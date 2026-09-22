# 10 — Warteereignisse: worauf wartet eine Sitzung wirklich?

In 7.6b und 9.4 haben wir die Frage „warum hängt das?" mit
`wait_event_type = Lock` beantwortet. Das war richtig — und es war **einer von
zehn** Typen. Wer nur nach `Lock` filtert, hält jede andere Warterei für „läuft
gerade".

Denn „hängt" hat viele Ursachen. Eine Sperre ist nur eine davon.

---

## 10.0 Die zwei Spalten

```sql
SELECT pid,
       state,
       wait_event_type,
       wait_event,
       left(query, 40) AS query
FROM pg_stat_activity
WHERE backend_type = 'client backend'
ORDER BY pid;
```

| Spalte | Bedeutung |
|--------|-----------|
| `wait_event_type` | die **Art** des Wartens — oder `NULL`, wenn nicht gewartet wird |
| `wait_event` | der **genaue Punkt** innerhalb dieser Art |
| `state` | `active`, `idle`, `idle in transaction`, … |

Wichtig und leicht zu verwechseln: **`state` und `wait_event` sind unabhängig.**
So steht es ausdrücklich in der Doku. Konkret heißt das:

- `state = 'active'` und `wait_event` ist **gesetzt** → die Abfrage läuft, hängt
  aber gerade irgendwo im System. Das ist der interessante Fall.
- `state = 'active'` und `wait_event` ist `NULL` → sie rechnet wirklich.
- `state = 'idle'` → sie wartet auf den nächsten Befehl des Clients.

---

## 10.1 Die zehn Typen

| Typ | was er bedeutet |
|-----|-----------------|
| `Activity` | der Prozess ist untätig — er wartet in seiner Hauptschleife auf Arbeit |
| `BufferPin` | eine Seite im Puffer soll **exklusiv** angefasst werden |
| `Client` | der Server wartet auf die Anwendung am anderen Ende der Verbindung |
| `Extension` | eine Erweiterung wartet (z. B. `postgres_fdw`) |
| `InjectionPoint` | Warten an einem Testpunkt (nur für Tests) |
| `IO` | eine I/O-Operation ist noch nicht fertig |
| `IPC` | der Prozess wartet auf einen **anderen Serverprozess** |
| `Lock` | eine **schwere** Sperre — `Lock` im Sinne von Teil 7 |
| `LWLock` | eine **leichte** Sperre auf einer Struktur im Shared Memory |
| `Timeout` | es läuft eine Wartezeit ab (z. B. `pg_sleep`) |

Die ersten beiden Spalten aus 7.6b (`Lock`, `transactionid`) sind also **ein**
Fall von zehn. Genau deshalb lohnt sich dieses Kapitel: eine Sitzung, die auf
eine Platte wartet (`IO`), sieht in einem `Lock`-Filter aus wie eine, die
arbeitet.

Referenz mit allen Werten: https://www.postgresql.org/docs/18/monitoring-stats.html
(Tabellen 27.4 bis 27.13)

---

## 10.2 Beschreibungen holen statt abtippen: `pg_wait_events`

Es gibt eine Sicht, in der zu jedem Warteereignis die Beschreibung steht. Man
muss die Doku-Tabellen also nicht abschreiben:

```sql
SELECT a.pid, a.wait_event_type, a.wait_event, w.description
FROM pg_stat_activity a
JOIN pg_wait_events w
  ON a.wait_event_type = w.type
 AND a.wait_event = w.name
WHERE a.wait_event IS NOT NULL
ORDER BY a.pid;
```

Erwartung: für jede wartende Sitzung eine Zeile mit dem Klartext — z. B.
„Waiting to acquire a lock on a relation" statt nur `relation`. Das ist der
schnellste Weg von einer PID zur Antwort.

---

## 10.3 Ein Fenster beobachtet das andere

Das ist die Technik, mit der man all das sieht. In **Fenster B** die Abfrage von
10.0 absetzen und dann wiederholen lassen:

```sql
\watch 2
```

`\watch` führt die letzte Abfrage alle zwei Sekunden erneut aus, bis man mit
Strg+C abbricht. In **Fenster A** läuft währenddessen das Experiment.

Und ein erstes, sehr bequemes Ziel: in Fenster A

```sql
SELECT pg_sleep(5);
```

In Fenster B ist dann zu sehen:

```
wait_event_type | wait_event
----------------+------------
Timeout         | PgSleep
```

`PgSleep` ist der dokumentierte Warteereignisname für einen `pg_sleep`-Aufruf.
Man sieht also **nicht** „active ohne Warten", sondern einen benannten Grund.
Dasselbe funktioniert mit dem `UPDATE` aus 7.6 (dort: `Lock` /
`transactionid`) und mit dem `BEGIN`, das offen bleibt (dort: `Client` /
`ClientRead`).

---

## 10.4 „page locks" — und was davon in `pg_locks` steht

Der Begriff bezeichnet drei verschiedene Dinge. Nur **eines** davon ist eine
Sperre im Lock-Manager.

| Begriff | was es wirklich ist | sichtbar als |
|---------|---------------------|--------------|
| **Page-Level Lock** (13.3.3) | eine Lese-/Schreibsperre auf einer Tabelle**seite** im Shared-Buffer-Pool | `wait_event_type = LWLock`, `wait_event = BufferContent` |
| **`page` als Lock-Typ** | eine schwere Sperre auf einer Seite einer Relation | `pg_locks.locktype = 'page'`, `wait_event_type = Lock`, `wait_event = page` |
| **Buffer-Pin** | **keine Sperre** — ein „diese Seite darf nicht verdrängt werden" | `wait_event_type = BufferPin`, `wait_event = BufferPin` |

Was die Doku zum ersten Punkt sagt:

> Zusätzlich zu Tabellen- und Zeilensperren werden Share/Exclusive-Sperren auf
> Seiten benutzt, um den Lese-/Schreibzugriff auf Tabellenseiten im
> Shared-Buffer-Pool zu steuern. Diese Sperren werden sofort wieder freigegeben,
> sobald eine Zeile gelesen oder geändert ist. Anwendungsentwickler müssen sich
> normalerweise nicht um Sperren auf Seiten kümmern; sie werden hier nur der
> Vollständigkeit halber erwähnt.

(Sinngemäß übersetzt aus https://www.postgresql.org/docs/18/explicit-locking.html,
Abschnitt 13.3.3)

Der letzte Satz ist die Antwort: **man muss sich nicht darum kümmern.** Sie sind
so kurz gehalten, dass man sie praktisch nie als Wartenden erwischt. Wenn doch
einmal `BufferContent` in `pg_stat_activity` steht, ist das die Bedeutung — nicht
das Signal, etwas umzubauen.

Und die Klarstellung, die den Begriff aus anderen Datenbanken mitbringt:
PostgreSQL hat **keine wählbare Sperrebene „Seite"** wie Oracle oder SQL Server.
Man kann nicht einstellen, dass „grob" oder „fein" gesperrt wird. Zeilen werden
als Zeilen gesperrt, Tabellen als Tabellen — und die Seiten im Puffer verwaltet
der Server selbst.

---

## 10.5 Warum Zeilensperren nicht in `pg_locks` stehen

Das hat uns in 7.6b schon einmal korrigiert. Die Doku sagt es zweimal, aus zwei
Richtungen:

- `pg_locks`: „Informationen über Zeilensperren liegen **auf der Platte**, nicht
  im Speicher, und deshalb erscheinen Zeilensperren normalerweise gar nicht in
  dieser Sicht. Wartet ein Prozess auf eine Zeilensperre, erscheint er
  stattdessen als wartend auf die **Transaktions-ID** des aktuellen Halters."
- Kapitel 13.3.2: „PostgreSQL merkt sich keine Informationen über geänderte
  Zeilen im Speicher, deshalb gibt es keine Obergrenze für die Anzahl gleichzeitig
  gesperrter Zeilen. Eine Zeilensperre kann jedoch einen Schreibzugriff auf die
  Platte auslösen — `SELECT FOR UPDATE` markiert die ausgewählten Zeilen als
  gesperrt und schreibt sie dadurch auf die Platte."

Beides beschreibt dasselbe: die Zeilensperre steckt im Zeilenkopf auf der Platte.
Deshalb ist `transactionid` in `pg_locks` der Stellvertreter, und deshalb
schreibt ein `SELECT … FOR UPDATE` Daten. Wer in `pg_locks` eine Zeile sucht,
sucht vergeblich.

---

## 10.6 Die Fälle, die man im Alltag sieht

**(a) `Timeout` / `PgSleep`** — siehe 10.3. Wartezeit, die man selbst gebaut hat.

**(b) `Lock` / `transactionid`** — die Zeilensperre aus 7.6. Der Wartende nennt
nicht die Zeile, sondern die Transaktion des Halters. Weiter mit
`pg_blocking_pids()` (7.6b).

**(c) `Lock` / `relation`** — eine **Tabellensperre**. Hier geht es nicht um eine
Zeile, sondern um die ganze Tabelle. Was welche Anweisung nimmt, steht im
Tabellenkopf von Kapitel 13.3.1.

**(d) `IPC` / `ExecuteGather`** — der Leiter einer **parallelen** Abfrage wartet
auf seine Worker. Dazu ein Blick, der sich lohnt: parallele Worker sind eigene
Zeilen in `pg_stat_activity` mit `backend_type = 'parallel worker'`, und die
Spalte `leader_pid` sagt, zu welcher Sitzung sie gehören. Bei dem Plan aus
Teil 5 (`Parallel Seq Scan`) ist das genau diese Situation — praktisch sieht man
sie nur, wenn die Abfrage lange genug läuft.

**(e) `Client` / `ClientRead`** — der Server wartet auf **die Anwendung**. Das ist
der Normalfall bei `state = 'idle'`. Wenn dort etwas hängt, liegt es nicht an der
Datenbank, sondern daran, dass der Client nicht weiterschickt.

**(f) `LWLock` / `BufferContent`** — die Seite aus 10.4. Dazu passt der Nachbar
`LWLock` / `BufferMapping` („eine Seite einem Puffer zuordnen") und
`LWLock` / `WALWrite` („WAL-Puffer auf die Platte schreiben"). Solche Wartezeiten
heißen: der Server wartet auf sich selbst bzw. auf die Platte — nicht auf deine
Sperrlogik.

**(g) `BufferPin`** — dazu der Doku-Satz, der es am besten erklärt:

> Warten auf einen Buffer-Pin kann sich lange hinziehen, wenn ein anderer Prozess
> einen offenen Cursor hält, der zuletzt aus genau diesem Puffer gelesen hat.

Das ist der Klassiker „ein Cursor blockiert `VACUUM`". Mit zwei Zeilen in `konto`
lässt sich das nicht sinnvoll nachstellen — merken, nicht üben.

**(h) `IO` / `DataFileRead`** — die Seite war nicht im Buffer-Cache und muss von
der Platte kommen. Ein `EXPLAIN (ANALYZE, BUFFERS)` aus Teil 5 zeigt dieselbe
Situation als `read=` statt `hit=`. Der zugehörige Zähler im Log des Containers
ist die zweite Quelle.

**(i) `Activity`** — und damit schließt sich der Kreis zu 7.5: die Zeilen mit
leerem `usename` und `datname` in `pg_stat_activity` sind die
Hintergrundprozesse des Servers. Sie stehen auf `Activity` und warten in ihrer
Hauptschleife — deshalb sehen sie aus wie wartende Clients, sind aber keine.
Ihre Art verrät `backend_type`: `checkpointer`, `walwriter`, `background writer`,
`autovacuum launcher`, … Kein Client, kein `datname`, kein Warten auf dich.

---

## 10.7 Was das fürs Suchen bedeutet

Wenn eine Sitzung „hängt", ist die erste Zeile immer dieselbe Frage: **welcher
`wait_event_type`?**

| Typ | wo man weitersucht |
|-----|--------------------|
| `Lock` | Teil 7/9 — `pg_blocking_pids()`, Sperrreihenfolge, `lock_timeout` |
| `LWLock`, `BufferPin`, `IO` | der Server selbst: Cache, Platte, Vakuum — nicht die eigene Sperrlogik |
| `Client` | die eigene Anwendung: sie schickt nicht weiter |
| `Timeout` | eine selbst gesetzte Wartezeit (`pg_sleep`, Verzögerungen) |
| `IPC` | eine andere Sitzung oder ein Worker derselben Abfrage |
| `Activity` | war niemand — das ist ein Hintergrundprozess |

Und die Regel aus der Doku, die man selten so deutlich liest: **solange keine
Verklemmung erkannt wird, wartet eine Transaktion unbegrenzt.** Ein Warten ist
also nie „zu kurz", um es anzusehen — es ist höchstens zu kurz, um es zu
erwischen.

---

## 10.8 Referenzen

- Warteereignisse: https://www.postgresql.org/docs/18/monitoring-stats.html
  (Tabellen 27.4–27.13) und die Sicht `pg_wait_events`
- Sperren allgemein: https://www.postgresql.org/docs/18/explicit-locking.html
  (13.3, mit 13.3.3 „Page-Level Locks")
- `pg_locks`: https://www.postgresql.org/docs/18/view-pg-locks.html

---

## Was in `06-kurs-notizen.md` gehört

- Welcher `wait_event_type` / `wait_event` steht bei dir, während `pg_sleep(5)`
  läuft?
- Dasselbe beim wartenden `UPDATE` aus 7.6 — und was steht bei der **haltenden**
  Sitzung?
- Was steht bei der Sitzung, die `BEGIN` gesagt hat und dann nichts tut?
- Welche `backend_type`-Zeilen haben bei dir keine `datname`, und auf welchem
  Warteereignis stehen sie?
