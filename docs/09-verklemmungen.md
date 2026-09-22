# 9 — Verklemmungen: erkennen, protokollieren, vermeiden

In 7.7 ging es um das Phänomen: zwei Transaktionen sperren dieselben Zeilen in
umgekehrter Reihenfolge, keine kommt voran, und nach `deadlock_timeout` bricht
der Server eine von beiden ab.

Hier geht es um das Drumherum — die Fragen, die im Betrieb auftauchen:

- Wie finde ich eine Verklemmung wieder, wenn sie nachts um drei passiert ist?
- Wie protokolliere ich Wartezeiten, die *keine* Verklemmung sind?
- Wie verhindert man Verklemmungen, statt sie zu behandeln?
- Und warum ist ein Timeout dabei nur die Notbremse?

Voraussetzung: die Tabelle `konto` aus Teil 7 — [`sql/04_konto.sql`](../sql/04_konto.sql)

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/04_konto.sql
```

---

## 9.0 Kurz: der Ablauf, den man auslösen muss

Ausführlich in 7.7, hier die Kurzfassung — **vorher** in beiden Fenstern:

```sql
SET deadlock_timeout = '10s';
```

**Fenster A:**

```sql
BEGIN;
UPDATE konto SET betrag = betrag - 100 WHERE id = 1;
```

**Fenster B:**

```sql
BEGIN;
UPDATE konto SET betrag = betrag - 100 WHERE id = 2;
```

**Fenster A:**

```sql
UPDATE konto SET betrag = betrag + 100 WHERE id = 2;   -- hängt
```

**Fenster B:**

```sql
UPDATE konto SET betrag = betrag + 100 WHERE id = 1;   -- schließt den Kreis
```

Jetzt hält A die Zeile 1 und will die Zeile 2, B hält die Zeile 2 und will die
Zeile 1. Ein **Zyklus** — und genau den erkennt der Server.

Vorher noch die zwei Fenster prüfen (7.8b):

```sql
SELECT pid, backend_type, usename, datname
FROM pg_stat_activity
WHERE backend_type = 'client backend';
```

Erwartung: zwei Zeilen mit `datname = kurs`.

---

## 9.1 Was der Client sieht

Erwartung (die Zahlen sind deine, die `…` sind Platzhalter):

```
ERROR:  deadlock detected
DETAIL:  Process … waits for ShareLock on transaction …; blocked by process ….
         Process … waits for ShareLock on transaction …; blocked by process ….
HINT:  See server log for query details.
CONTEXT:  while locking tuple … in relation "konto"
```

Drei Teile, die man lesen können muss:

| Teil | was er sagt |
|------|-------------|
| `ERROR: deadlock detected` | die Verklemmung wurde erkannt und diese Transaktion ist das Opfer |
| `DETAIL` | **der Zyklus**: zwei Zeilen, die aufeinander verweisen |
| `HINT: See server log for query details.` | die *Abfragen* stehen nicht hier, sondern im Serverlog |

Der `DETAIL` ist der Beweis. Wenn dort zwei PIDs stehen, die sich gegenseitig
blockieren, ist es kein „hängt halt", sondern eine Verklemmung — dieselbe
Information, die man in 7.7 mit `pg_blocking_pids()` von Hand sichtbar gemacht
hat.

Den Fehlercode sieht man mit:

```sql
\set VERBOSITY verbose
```

```sql
BEGIN;
-- ... Verklemmung auslösen ...
```

Erwartung: `SQLSTATE: 40P01`. Den Code braucht man, wenn eine Anwendung
entscheiden soll, ob ein Fehler wiederholbar ist (siehe 9.8) — nicht den
Meldungstext, denn der ist übersetzt und nicht stabil.

Und wie jeder Fehler in einer Transaktion hinterlässt ein Deadlock ein
abgebrochenes `!#` (7.1). Es hilft nur `ROLLBACK`.

---

## 9.2 Das Serverlog — dort stehen die Abfragen

Der Deadlock landet von alleine im Log: `log_min_messages` steht standardmäßig
auf `warning`, und `ERROR` ist lauter als das.

```bash
docker compose logs db | tail -40
```

Und wenn man nach einem Vorfall von gestern sucht:

```bash
docker compose logs db --since 24h | grep -i -A5 deadlock
```

Der Zugang zu diesem Log ist derselbe wie in Teil 2 — das Image schreibt nach
`stderr`, und Docker sammelt das auf. Nachsehen, wo die Meldungen hingehen:

```sql
SHOW log_destination;
SHOW log_min_messages;
SHOW logging_collector;
```

**Was genau im Log steht, hängt an den Einstellungen** — lies es einmal selbst
durch, das ist der Zweck dieses Abschnitts. Der `HINT` im Client verweist nicht
ohne Grund dorthin: bei einer Anwendung, die nachts hängt, ist das Log oft der
einzige Ort, an dem der Vorgang noch nachvollziehbar ist. Der Client hat den
Fehler längst protokolliert und weggeworfen.

Wer mehr Kontext will, stellt das *Statement-Logging* dazu — bewusst sparsam,
denn jede Anweisung mitzuschreiben kostet Platz und Zeit:

```sql
SHOW log_statement;                 -- Vorgabe: none
SHOW log_min_duration_statement;    -- Vorgabe: -1 (aus)
```

---

## 9.3 `log_lock_waits` — auch die Wartezeiten ohne Verklemmung

Nicht jede Wartezeit ist eine Verklemmung. Die Situation aus 7.6 (A hält die
Zeilensperre, B wartet) ist völlig normal — nur dauert sie manchmal zu lange.
Dafür gibt es eine eigene Protokollierung:

```sql
SHOW log_lock_waits;
SET log_lock_waits = on;
```

Jetzt die Situation aus 7.6 herstellen (Fenster A: `BEGIN; UPDATE …;` stehen
lassen, Fenster B: `UPDATE …` darauf warten lassen) und danach ins Log sehen:

```bash
docker compose logs db | tail -20
```

Erwartung: eine `LOG`-Zeile der Form

```
LOG:  process … still waiting for ShareLock on transaction … after … ms
```

Das ist der Punkt, an dem **`deadlock_timeout` zum zweiten Mal auftaucht**: es
ist nicht nur die Wartezeit vor der Verklemmungsprüfung, sondern auch die
Schwelle, ab der eine Wartezeit protokolliert wird. Bei der Vorgabe von 1 s
bekommt man also alle Wartezeiten über einer Sekunde ins Log — ohne dass man zum
Zeitpunkt des Hängens ein `pg_stat_activity` offen haben musste.

Wenn dein Benutzer für diese Einstellung nicht berechtigt ist, kommt hier ein
Fehler — dann setzt man sie serverseitig. `log_lock_waits` ist per Reload
änderbar, ein Neustart ist nicht nötig:

```sql
ALTER SYSTEM SET log_lock_waits = on;
SELECT pg_reload_conf();
-- später:
ALTER SYSTEM RESET log_lock_waits;
SELECT pg_reload_conf();
```

`ALTER SYSTEM` schreibt nicht in die Hauptdatei, sondern nach
`postgresql.auto.conf` — nachsehen kann man beides:

```sql
SHOW config_file;
SHOW hba_file;
```

---

## 9.4 Den Wartegraph von Hand nachlesen

Wenn man gerade live davor sitzt, braucht man das Log nicht — die Abfrage aus
7.6b reicht:

```sql
SELECT a.pid,
       pg_blocking_pids(a.pid) AS blockiert_von,
       a.wait_event,
       left(a.query, 40) AS query
FROM pg_stat_activity a
WHERE datname = 'kurs'
  AND cardinality(pg_blocking_pids(a.pid)) > 0;
```

Bei einer Verklemmung zeigt sie **zwei** Zeilen, deren `blockiert_von`-Werte
aufeinander verweisen. Das ist derselbe Zyklus wie im `DETAIL` des Fehlers und
im Log — nur eben live, bevor der Server eine der beiden abbricht.

Detaillierter wird es mit `pg_locks`: dort steht, welcher **Art** das Sperrobjekt
ist (Tabelle, Transaktions-ID, Recht zum Erweitern einer Relation …). Zeilensperren
stehen dort **nicht** — sie liegen auf der Platte und nicht im Speicher; der
Wartende erscheint stattdessen als Warten auf die Transaktions-ID des Halters.
Siehe 7.6b.

---

## 9.5 Vermeiden (1): eine feste Sperrreihenfolge

Die Ursache ist immer dieselbe: **zwei Stellen fassen dieselben Zeilen in
unterschiedlicher Reihenfolge an.** Also legt man eine Reihenfolge fest.

Die einfachste Form ist eine `SELECT … FOR UPDATE` mit `ORDER BY` — sie sperrt
die Zeilen in der Reihenfolge, in der sie geliefert werden:

```sql
BEGIN;
SELECT id FROM konto WHERE id IN (1, 2) ORDER BY id FOR UPDATE;
-- jetzt sind beide Zeilen gesperrt, und zwar in einer festen Reihenfolge
UPDATE konto SET betrag = betrag - 100 WHERE id = 1;
UPDATE konto SET betrag = betrag + 100 WHERE id = 2;
COMMIT;
```

Wichtig: `UPDATE` selbst kennt **kein** `ORDER BY`. Wer sich darauf verlassen will,
muss vorher sperren — oder die Anweisungen selbst sortiert absenden.

Genau hier entstehen die Verklemmungen in echten Anwendungen: eine
Buchungsroutine läuft in der Reihenfolge der Klicks, eine andere in der
Reihenfolge der Datenbank. Sobald zwei Reihenfolgen auf dieselben Zeilen
treffen, ist es eine Frage der Zeit bis zum `40P01`.

---

## 9.6 Vermeiden (2): `NOWAIT` und `SKIP LOCKED`

Man kann auch aufhören, über Reihenfolgen nachzudenken, und stattdessen sagen:
**„wenn es nicht sofort geht, will ich es gar nicht"**.

**Fenster A:**

```sql
BEGIN;
UPDATE konto SET betrag = betrag + 100 WHERE id = 2;   -- hält die Sperre
```

**Fenster B:**

```sql
BEGIN;
SELECT * FROM konto WHERE id = 2 FOR UPDATE NOWAIT;
```

Erwartung: sofort ein Fehler, kein Warten:

```
ERROR:  could not obtain lock on row in relation "konto"
SQLSTATE: 55P03
```

Anders als beim `lock_timeout` wartet B nicht einmal eine Sekunde. Das ist das
Muster für Anfragen, die lieber schnell scheitern als langsam.

Und die zweite Variante, mit der ganze Worker-Pools sich gegenseitig nie
blockieren:

**Fenster B:**

```sql
BEGIN;
SELECT * FROM konto ORDER BY id FOR UPDATE SKIP LOCKED;
```

Erwartung: B bekommt alle Zeilen **außer** der gesperrten — keinen Fehler,
kein Warten. Ohne `SKIP LOCKED` würde dieselbe Anweisung hängen.

Das ist das Muster hinter jeder Job-Queue auf PostgreSQL: mehrere Worker holen
sich jeweils die nächste freie Aufgabe, statt aufeinander zu warten. Die Form ist
immer dieselbe — hier auf `konto` gezeigt, in echt auf einer Tabelle mit
Statusspalte:

```sql
BEGIN;
SELECT id FROM auftrag
WHERE status = 'offen'
ORDER BY id
LIMIT 1
FOR UPDATE SKIP LOCKED;
-- ... bearbeiten ...
UPDATE auftrag SET status = 'fertig' WHERE id = <die geholte id>;
COMMIT;
```

`NOWAIT` und `SKIP LOCKED` gibt es auch für `FOR SHARE` und für `LOCK TABLE`.
Beide sind ausdrückliche Erklärungen: *ich will diese Sperre nicht abwarten.*

---

## 9.7 Vermeiden (3): kurz und klein halten

Je länger eine Transaktion läuft, desto länger hält sie ihre Sperren — und desto
größer wird die Fläche, auf der sich zwei Transaktionen überschneiden können.

- **Nichts Langsames in eine Transaktion legen.** Kein HTTP-Aufruf, kein
  Dateizugriff, keine Benutzereingabe, kein Warten. Genau das ist der Fall
  `idle in transaction` aus 7.6b.
- **Eine Anweisung ist schon eine Transaktion** (7.2). Wenn ein Vorgang nicht
  aus mehreren Schritten bestehen *muss*, braucht er auch kein `BEGIN`.
- **`LOCK TABLE` vermeiden.** Es sperrt die ganze Tabelle statt einzelner Zeilen
  und ist damit eine Einladung für Verklemmungen.
- **Vor DDL ein Zeitlimit setzen** (`lock_timeout`, siehe 8.4). Sonst wartet ein
  `ALTER TABLE` hinter einer offenen Transaktion und blockiert dahinter alles
  Weitere.
- **Fremdschlüssel sperren mit.** Ein `UPDATE` auf eine Elternzeile nimmt eine
  Sperre auf die Kindzeilen — dadurch entstehen Verklemmungen zwischen Tabellen,
  die man gar nicht gleichzeitig angefasst hat. Wenn zwei Vorgänge Eltern- und
  Kindzeilen in unterschiedlicher Reihenfolge anfassen, gilt derselbe Rat wie in
  9.5.

---

## 9.8 `40P01` ist vorübergehend — also wiederholen

Ein Deadlock sagt nichts über die Daten aus. Er sagt: *diese beiden Vorgänge
hätten so nicht gleichzeitig laufen dürfen.* Beim nächsten Versuch ist die andere
Transaktion durch, der Kreis entsteht nicht neu.

Dasselbe Muster wie bei `40001` in 7.11:

```text
wiederhole (höchstens n mal):
    BEGIN;
    ... alles lesen und schreiben ...
    COMMIT;
bei Fehler 40P01 oder 40001:
    von vorn
```

Drei Dinge, die dazugehören:

- **Die ganze Transaktion wiederholen**, nicht die einzelne Anweisung. Nach dem
  Fehler ist sie abgebrochen (`!#`), alles Vorherige ist weg.
- **Begrenzen.** Eine feste Anzahl Versuche, dann ein echter Fehler. Sonst wird
  aus einer Verklemmung eine Endlosschleife.
- **Wiederholen ist die Sicherung, nicht die Reparatur.** Wenn derselbe Vorgang
  regelmäßig `40P01` bekommt, ist die Sperrreihenfolge das Problem (9.5) — und
  die bekommt man mit `log_lock_waits` (9.3) und dem Log (9.2) zu sehen.

---

## 9.9 Timeouts sind die Notbremse, nicht die Lösung

Jetzt schließt sich der Kreis zu Teil 8 — und das ist der Punkt, an dem sich
`lock_timeout` und Deadlock-Erkennung unterscheiden:

| | `lock_timeout` | Deadlock-Erkennung |
|---|---|---|
| greift wann | nach der eingestellten Zeit | wenn ein **Kreis** entsteht |
| Abbruch | die wartende Anweisung gibt auf | der Server bricht eine Transaktion ab |
| Meldung | `ERROR: canceling statement due to lock timeout` | `ERROR: deadlock detected` (`40P01`) |
| Ursache | unbekannt — es hat nur lange gedauert | benannt — zwei Zeilen zeigen den Kreis |

Ein `lock_timeout` kann das Warten beenden, aber er sagt nichts über die Ursache:
er trifft auch die völlig normale Wartezeit aus 7.6. Die Deadlock-Erkennung ist
die ehrlichere Rückmeldung — sie benennt den Zyklus und lässt sich wiederholen
(9.8).

Und die Einstellung, die den Unterschied macht, ist `deadlock_timeout`:

- Im Betrieb ist die Vorgabe (1 s) in Ordnung.
- Hochsetzen (7.7) ist ein **Debug-Werkzeug**, um den Kreis zu beobachten, bevor
  der Server ihn auflöst.
- Als „Timeout" im Sinne von Teil 8 ist es **nicht** zu gebrauchen — es bricht
  nichts ab, es legt nur fest, wann geprüft wird.

---

## 9.10 Aufräumen

```sql
RESET log_lock_waits;
SET deadlock_timeout = '1s';
```

Im Log nichts hinterlassen:

```sql
ALTER SYSTEM RESET log_lock_waits;
SELECT pg_reload_conf();
```

Und Kontrolle, ob in der Sitzung noch etwas verstellt ist:

```sql
SHOW ALL;
```

---

## Was in `06-kurs-notizen.md` gehört

- Wie sieht die Log-Zeile bei einem Deadlock bei dir aus — steht die **Abfrage**
  darin oder nur der Wartegraph?
- Wie lange hat es gedauert, bis der Server die Verklemmung erkannt hat
  (`deadlock_timeout`-Wert und gemessene Zeit)?
- Kommt bei `log_lock_waits` eine Zeile, und nach welcher Wartezeit?
- Was gibt `SELECT * FROM konto … FOR UPDATE SKIP LOCKED` zurück, während die
  andere Sitzung eine Zeile hält?
