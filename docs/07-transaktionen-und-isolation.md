# 7 — Transaktionen, Sperren und Isolationsstufen

Teil 5 war **Geschwindigkeit**: ein Benutzer, eine Abfrage, ein Plan. Hier geht
es um **Korrektheit**, sobald zwei gleichzeitig arbeiten — und um die Frage, die
in Teil 5 nicht vorkam: *was passiert, wenn sich zwei Sitzungen in die Quere
kommen?*

Der Aufhänger ist eine Überweisung. Sie besteht aus **zwei** Befehlen:

```sql
UPDATE konto SET betrag = betrag - 100 WHERE id = 1;
UPDATE konto SET betrag = betrag + 100 WHERE id = 2;
```

Zwischen diesen beiden Zeilen ist die Bank um 100 € falsch. Das ist kein Bug,
das ist der Normalzustand zwischen zwei Befehlen — und genau dafür gibt es
Transaktionen, Sperren und Isolationsstufen.

Übungstabelle: [`sql/04_konto.sql`](../sql/04_konto.sql)

---

## 7.0 Vorbereitung: die Tabelle `konto`

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/04_konto.sql
```

Die Tabelle ist absichtlich anders als `kurs` aus Teil 3:

| Spalte | Typ | Warum |
|--------|-----|-------|
| `id` | `bigint PRIMARY KEY` | Eindeutigkeit **erzwungen** — zwei Konten mit derselben Nummer darf es nicht geben |
| `name` | `text NOT NULL` | ein Konto ohne Inhaber ist kein Konto |
| `betrag` | `numeric(15,2)` | Geld in `numeric`, **nicht** `float`: `0.1` ist als Gleitkommazahl nicht exakt darstellbar |

Ausgangszustand: zwei Konten mit je 10000, Summe 20000.

> `PRIMARY KEY` legt automatisch einen Index an. Diese Tabelle eignet sich
> deshalb **nicht** für den Vergleich aus Teil 5 — dafür ist `kurs` da. Hier ist
> der Index nicht das Thema, sondern die *Garantie* (siehe 5.3).

**Zurücksetzen zwischen zwei Versuchen** — nicht neu anlegen, nur die Beträge
zurückdrehen:

```sql
UPDATE konto SET betrag = 10000;
SELECT sum(betrag) FROM konto;   -- 20000
```

Ein `UPDATE` ohne `WHERE` trifft alle Zeilen. Hier ist das gewollt — und genau
die Falle aus 7.2.

**Zwei Sitzungen braucht man ab 7.5.** Zweites Fenster (Shell auf dem eigenen
Rechner), dort dieselbe Verbindung:

```bash
docker compose exec db psql -U kurs -d kurs
```

Nicht zwei Prompts innerhalb *einer* `psql`-Sitzung: eine Sperre kann nur eine
**andere** Sitzung blockieren (siehe 7.5).

Nützliche Einstellung für dieses Kapitel — zeigt zu jedem Fehler den SQLSTATE:

```sql
\set VERBOSITY verbose
```

---

## 7.1 Vier Prompts, vier Zustände

Der Prompt ist keine Dekoration. Er sagt, in welchem Zustand die Sitzung ist:

| Prompt | Bedeutung |
|--------|-----------|
| `kurs=#` | keine Transaktion offen — jeder Befehl wird sofort bestätigt |
| `kurs=*#` | eine Transaktion läuft, noch nicht abgeschlossen |
| `kurs=!#` | eine Transaktion läuft, ist aber **abgebrochen** |
| `kurs-#` | psql wartet auf das abschließende `;` |
| `kurs-*#` | beides gleichzeitig: Zeilenpuffer offen *und* Transaktion läuft |

Zum Ausprobieren:

```sql
BEGIN;
SELECT 1 / 0;
SELECT 42;      -- ERROR: current transaction is aborted, commands ignored ...
ROLLBACK;
SELECT 42;      -- geht wieder
```

Nach einem Fehler nimmt die Transaktion **keinen** Befehl mehr an — auch keinen
harmlosen `SELECT`. Aus diesem Zustand führen nur `ROLLBACK` oder `COMMIT`.

Und ein `COMMIT` in diesem Zustand wird als **`ROLLBACK`** gemeldet:

```sql
BEGIN;
SELECT 1 / 0;
COMMIT;         -- psql antwortet: ROLLBACK
```

Die Doku zu `COMMIT` beschreibt das ausdrücklich: war die Transaktion
abgebrochen, wirkt ein `COMMIT` wie ein `ROLLBACK`. Der Server weigert sich,
einen halbfertigen Zustand festzuschreiben. Das ist die gewünschte Antwort,
keine Fehlfunktion.

Zwei weitere Rückmeldungen, die man zu lesen lernen muss:

```sql
COMMIT;         -- WARNING: there is no transaction in progress
ROLLBACK;       -- WARNING: there is no transaction in progress
```

Das heißt: *ich habe deinen Befehl gesehen, aber es lief nichts.* Immer wenn
diese Warnung kommt, stimmt das eigene Bild von der Sitzung nicht.

---

## 7.2 Ohne `BEGIN` ist jeder Befehl schon eine Transaktion

Ausgangszustand herstellen und die Summe notieren:

```sql
UPDATE konto SET betrag = 10000;
SELECT sum(betrag) FROM konto;
```

Jetzt **eine** Hälfte der Überweisung — und bewusst **kein** `BEGIN`:

```sql
UPDATE konto SET betrag = betrag - 100 WHERE id = 1;
SELECT * FROM konto;
SELECT sum(betrag) FROM konto;
```

Die Summe ist jetzt um 100 zu niedrig, und zwar **endgültig**. Ohne `BEGIN` ist
jeder einzelne Befehl seine eigene Transaktion und wird beim Absenden sofort
bestätigt (*autocommit*).

> Das ist der Grund, warum die Summe nach mehreren Versuchen nicht mehr 20000
> ist: jede halbe Überweisung, die irgendwann ohne `BEGIN` abgesetzt wurde, hat
> eine dauerhafte Spur hinterlassen. Die Summe ist nicht „kaputt", sondern die
> Summe aller committeten Schritte.

Und das ist auch die Erklärung für diese Warnung:

```sql
UPDATE konto SET betrag = betrag + 100 WHERE id = 2;
COMMIT;         -- WARNING: there is no transaction in progress
```

Das `UPDATE` war schon durch — das `COMMIT` hatte nichts mehr zu tun.

Die Anzahl der geänderten Zeilen steht in der Antwort des Servers:

```
UPDATE 1   -- eine Zeile geändert
UPDATE 2   -- zwei Zeilen
```

Diese Zahl ist die verlässlichste Auskunft darüber, wie viele Zeilen betroffen
waren — unabhängig davon, was man erwartet hatte.

---

## 7.3 Die Überweisung richtig: `BEGIN` … `COMMIT`

Erst zeigen lassen, was getroffen wird, dann schreiben:

```sql
SELECT * FROM konto WHERE id = 1;
```

```sql
BEGIN;

UPDATE konto SET betrag = betrag - 100 WHERE id = 1;
UPDATE konto SET betrag = betrag + 100 WHERE id = 2;

SELECT * FROM konto;
SELECT sum(betrag) FROM konto;

COMMIT;
SELECT sum(betrag) FROM konto;
```

Erwartung: die Summe ist **vorher und nachher dieselbe** (20000), die
Kontostände haben sich um 100 verschoben.

Und jetzt der Gegenversuch — genau dieselben Befehle, aber mit `ROLLBACK`
statt `COMMIT`:

```sql
BEGIN;
UPDATE konto SET betrag = betrag - 100 WHERE id = 1;
SELECT sum(betrag) FROM konto;   -- mitten in der Transaktion: 19900
ROLLBACK;
SELECT sum(betrag) FROM konto;   -- wieder 20000
```

Das ist der ganze Sinn der Sache: der falsche Zwischenstand **existiert**, aber
nur innerhalb der Transaktion. Nach außen war er nie da.

Wichtiger als das Erfolgserlebnis ist der Unterschied zum Abbruch: bei 7.2 war
der Zwischenstand echt und blieb. Deshalb steht in einem echten Überweisungs-
programm `BEGIN` vor der ersten Zeile und `COMMIT` nach der letzten — und
dazwischen nur diese beiden Befehle.

---

## 7.4 `SAVEPOINT` — der einzige Weg zurück aus einem Fehler

Ohne `SAVEPOINT` macht ein Fehler die ganze Transaktion unbrauchbar (siehe 7.1).
Mit `SAVEPOINT` gibt es einen Haltepunkt, zu dem man zurück kann:

```sql
BEGIN;

SAVEPOINT s1;
UPDATE konto SET betrag = betrag + 100 WHERE id = 2;
SELECT * FROM konto;                  -- das +100 ist da
SELECT 1 / 0;                         -- Fehler
ROLLBACK TO SAVEPOINT s1;
SELECT * FROM konto;                  -- das +100 ist wieder weg
COMMIT;
```

Die beiden `SELECT`-Zeilen sind der Punkt: davor sichtbar, danach verschwunden.
`ROLLBACK TO SAVEPOINT` macht aus dem `!#`-Prompt wieder ein `*#` — die
Transaktion läuft weiter, nur ein Teil davon ist verworfen.

Zur Kontrolle der Prompt:

```sql
BEGIN;
SAVEPOINT s1;
SELECT 1 / 0;
-- jetzt: kurs=!#
ROLLBACK TO SAVEPOINT s1;
-- jetzt: kurs=*#
COMMIT;
```

Ein `COMMIT` am Ende ist trotzdem nötig — der Savepoint ersetzt es nicht.

---

## 7.5 Zwei Sitzungen — erst prüfen, dann messen

**Vor** jedem Sperr-Experiment nachsehen, ob wirklich zwei Client-Sitzungen da
sind:

```sql
SELECT pid, backend_type, usename, datname, state
FROM pg_stat_activity
ORDER BY pid;
```

Wichtig ist die Spalte `backend_type`:

- `client backend` = eine echte Verbindung (also du bzw. dein zweites Fenster)
- alles andere (`checkpointer`, `walwriter`, `autovacuum launcher`, …) sind
  **Hintergrundprozesse** des Servers — keine Clients, und sie haben `usename`
  und `datname` leer

Erwartung: genau **zwei** Zeilen mit `backend_type = client backend` und
`datname = kurs`. Steht nur eine dort, ist das zweite Fenster nicht verbunden —
und jedes Sperr-Experiment danach ist wertlos, weil es niemanden gibt, der
blockiert werden könnte.

Der ältere Filter, der einen auf die falsche Spur schickt:

```sql
-- schließt die eigene Sitzung aus; zeigt die zweite also nur, wenn es sie gibt
SELECT pid, state, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE datname = 'kurs' AND pid <> pg_backend_pid();
```

---

## 7.6 Die Zeilensperre

**Fenster A:**

```sql
BEGIN;
UPDATE konto SET betrag = betrag + 100 WHERE id = 2;
-- NICHT committen, stehen lassen
```

**Fenster B:**

```sql
UPDATE konto SET betrag = 0 WHERE id = 2;    -- hängt
```

Kein Fehler, kein Abbruch: B **wartet**. Das `UPDATE` in A hat eine
**Zeilensperre** auf genau diese eine Zeile gesetzt. Sie gilt bis zum Ende der
Transaktion.

**Fenster C** (drittes Fenster) zeigt, worauf B wartet:

```sql
SELECT pid, backend_type, wait_event_type, wait_event, query
FROM pg_stat_activity
WHERE datname = 'kurs';
```

Erwartung: bei der wartenden Zeile steht `wait_event_type = Lock`. Das ist die
Antwort auf „warum hängt das?" — statt zu raten. Ein Blick in `pg_locks` zeigt
dasselbe auf Ebene der Sperrobjekte.

**Fenster A:**

```sql
COMMIT;
```

Jetzt läuft B von selbst weiter. Der Moment, in dem es *hängt* und dann
*plötzlich durchläuft*, ist der eigentliche Aha-Punkt.

Zwei Dinge, die man dabei lernt:

- Die Sperre liegt auf **einer Zeile**, nicht auf der Tabelle. Zwei Überweisungen
  auf *verschiedene* Konten behindern sich nicht. Das ist der Preis des
  Index-überflüssigen Nebeneffekts, der PostgreSQL brauchbar macht: Zeilensperren
  statt Tabellensperren.
- In **derselben** Sitzung blockiert man sich nie selbst: wer die Sperre schon
  hält, darf weiterarbeiten. `UPDATE 1` kommt sofort zurück. Zwei Sitzungen sind
  Pflicht, nicht Bequemlichkeit.

Eine Zeile lässt sich auch sperren, *ohne* sie zu ändern — nützlich, wenn man
erst rechnen und dann schreiben will:

```sql
BEGIN;
SELECT * FROM konto WHERE id = 2 FOR UPDATE;   -- sperrt, ändert nichts
-- rechnen, prüfen ...
UPDATE konto SET betrag = betrag - 100 WHERE id = 2;
COMMIT;
```

---

## 7.7 Verklemmung (Deadlock)

Wenn zwei Transaktionen dieselben Zeilen in **umgekehrter Reihenfolge** sperren,
kommt keine mehr voran: A hält Zeile 1 und will Zeile 2, B hält Zeile 2 und
will Zeile 1. PostgreSQL merkt das und bricht **eine** der beiden ab:

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
UPDATE konto SET betrag = betrag + 100 WHERE id = 1;   -- löst die Verklemmung aus
```

Erwartung: eine der beiden Sitzungen bekommt
`ERROR: deadlock detected`, die andere kann weiterarbeiten. Wie lange der Server
wartet, bevor er das merkt:

```sql
SHOW deadlock_timeout;
```

Die Lehre daraus ist praktisch: **in einer Überweisung immer in derselben
Reihenfolge sperren** (erst das kleinere `id`, dann das größere). Dann kann diese
Verklemmung nicht entstehen. Genau deshalb schreiben echte Systeme ihre
Buchungen nicht in der Reihenfolge, in der der Benutzer klickt.

Nach einem `deadlock detected` gilt dasselbe wie nach jedem anderen Fehler:
die betroffene Transaktion ist abgebrochen, `ROLLBACK` (oder `COMMIT`, siehe
7.1).

---

## 7.8 Isolationsstufen — was PostgreSQL wirklich macht

Welche Stufe gerade gilt:

```sql
SHOW transaction_isolation;          -- in dieser Transaktion
SHOW default_transaction_isolation;  -- Standard für neue Transaktionen
```

Der Standard ist `read committed`. Die vier Stufen der SQL-Norm und was
PostgreSQL daraus macht:

| Stufe | In PostgreSQL |
|-------|---------------|
| `READ UNCOMMITTED` | wird wie `READ COMMITTED` behandelt — „schmutziges Lesen" gibt es **nicht** |
| `READ COMMITTED` | Standard. Jede **Anweisung** sieht einen frischen Schnappschuss |
| `REPEATABLE READ` | Schnappschuss ab der ersten Anweisung; entspricht Snapshot-Isolation. Schreibkonflikte sind möglich (40001) |
| `SERIALIZABLE` | wie `REPEATABLE READ`, zusätzlich erkennt der Server Zyklen zwischen Transaktionen (40001) |

Interessant: PostgreSQL ist bei `REPEATABLE READ` **strenger** als die Norm
verlangt (auch Phantom-Zeilen wiederholen sich nicht), und es lässt
`READ UNCOMMITTED` gar nicht erst zu.

Stufe setzen — für eine einzelne Transaktion:

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- ...
COMMIT;
```

Oder nach `BEGIN`, aber **vor** der ersten Anweisung:

```sql
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

Für die ganze Sitzung:

```sql
SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL REPEATABLE READ;
```

Ein `SET TRANSACTION ISOLATION LEVEL` nach einer bereits ausgeführten Anweisung
wird abgelehnt — die Stufe steht für die Dauer der Transaktion fest.

Referenz: https://www.postgresql.org/docs/18/transaction-iso.html

---

## 7.8b Bevor es losgeht: in **einer** Sitzung passiert nichts davon

Die folgenden Versuche sind nur mit **zwei echten Sitzungen** zu machen. Das ist
keine Bequemlichkeit, sondern der Kern der Sache. Man kann leicht nachweisen,
dass es in einem Fenster nicht geht:

```sql
-- EIN Fenster, EINE Sitzung:
BEGIN;
SELECT sum(betrag) FROM konto;
UPDATE konto SET betrag = betrag + 100 WHERE id = 2;   -- eigene Änderung
SELECT sum(betrag) FROM konto;
COMMIT;
```

Man sieht die eigene Änderung sofort — das ist aber **kein veralteter Wert**,
sondern der eigene, noch nicht bestätigte Zustand. Es kommt kein Konflikt, keine
Sperre, kein `40001`. Und zwar aus zwei Gründen:

- **Man blockiert sich nicht selbst.** Wer eine Sperre schon hält, darf
  weiterarbeiten (siehe 7.6).
- **Es gibt keinen zweiten Schnappschuss.** Eine Transaktion, eine Sicht. Dass
  zwei Sichten auseinanderlaufen, geht erst mit zwei Sitzungen.

Wer in einem Fenster auf einen Konflikt wartet, wartet also auf etwas, das
nicht kommen kann. Deshalb die Prüfung vor jedem Versuch (dauert Sekunden):

```sql
SELECT pid, backend_type, usename, datname, state
FROM pg_stat_activity
WHERE backend_type = 'client backend'
ORDER BY pid;
```

Erwartung: **zwei** Zeilen mit `datname = kurs`. Steht nur eine dort, ist das
zweite Fenster nicht verbunden — dann ist der Versuch wertlos.

Daraus die zwei Regeln für alle folgenden Abschnitte:

- Beide Fenster in dieselbe Datenbank: `docker compose exec db psql -U kurs -d kurs`
- Eine Transaktion bleibt **offen**, während man im anderen Fenster arbeitet.
  Das Fenster mit der offenen Transaktion erkennt man am `*` im Prompt.

---

## 7.9 `READ COMMITTED`: die Zahl ändert sich unter den Händen

*Zwei Fenster, beide in `kurs` — siehe 7.8b. In einem Fenster ist diese Übung
nicht zu machen.*

**Fenster A:**

```sql
BEGIN;
SELECT sum(betrag) FROM konto;
```

**Fenster B:**

```sql
BEGIN;
UPDATE konto SET betrag = betrag + 100 WHERE id = 2;
COMMIT;
```

**Fenster A** — dieselbe Abfrage, noch in derselben Transaktion:

```sql
SELECT sum(betrag) FROM konto;
```

Zum Vergleich beide Fenster nebeneinander, ohne dass jemand etwas ändert:

| Fenster | Zustand | zeigt |
|---------|---------|-------|
| A | offene Transaktion, `READ COMMITTED` | die **neue** Summe |
| B | keine offene Transaktion | dieselbe neue Summe |

Erwartung: beide zeigen **dasselbe**. In `READ COMMITTED` gibt es keinen
veralteten Wert — jedes `SELECT` holt sich einen frischen Schnappschuss.

Und trotzdem hat sich die Summe **innerhalb von A** geändert: das nennt man
*non-repeatable read*, und in `READ COMMITTED` ist es erlaubt. Genau deshalb gibt
es die nächste Stufe — wer zweimal liest und zweimal dasselbe braucht, ist hier
falsch; wer immer den aktuellen Stand braucht, ist hier richtig.

`A` braucht danach kein `ROLLBACK` — gelesen wurde nichts geändert:

```sql
ROLLBACK;
```

Diese Stufe ist für die meisten Anwendungen richtig: kurz, nebenläufig,
vorhersehbar. Man muss nur wissen, dass zwei `SELECT` in einer Transaktion
nicht denselben Zustand sehen müssen.

---

## 7.10 `REPEATABLE READ`: stabil — und der erste Serialisierungsfehler

*Zwei Fenster, beide in `kurs` — siehe 7.8b.*

### a) Wiederholtes Lesen bleibt stabil

**Fenster A:**

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT sum(betrag) FROM konto;
```

**Fenster B:**

```sql
UPDATE konto SET betrag = betrag + 100 WHERE id = 2;
```

**Fenster A:**

```sql
SELECT sum(betrag) FROM konto;   -- derselbe Wert wie vorher
ROLLBACK;
```

Erwartung: die Summe ist **unverändert**. Der Schnappschuss steht fest.

Jetzt der Vergleich, um den es hier geht — beide Fenster **gleichzeitig**, ohne
dass jemand etwas ändert:

| Fenster | Zustand | zeigt |
|---------|---------|-------|
| A | offene Transaktion, `REPEATABLE READ` | die Summe von **vor** B's `UPDATE` |
| B | keine offene Transaktion | die Summe **nach** dem bestätigten `UPDATE` |

Zwei verschiedene Zahlen für dieselbe Frage, im selben Moment. Das ist der
**veraltete Wert**: A arbeitet auf einem Stand, den der Server längst überholt
hat. Sichtbar wird das nur so — mit zwei Sitzungen. In einem Fenster sieht man
immer nur eine der beiden Zahlen, und deshalb lässt sich der Fehler dort auch
nicht erzeugen.

### b) Schreiben auf eine inzwischen geänderte Zeile

**Fenster A:**

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
UPDATE konto SET betrag = betrag + 100 WHERE id = 1;
```

**Fenster B:**

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
UPDATE konto SET betrag = betrag + 100 WHERE id = 1;   -- hängt
```

**Fenster A:**

```sql
COMMIT;
```

**Fenster B** bekommt jetzt einen Fehler:

```
ERROR:  could not serialize access due to concurrent update
SQLSTATE: 40001
```

B ist damit abgebrochen — nur `ROLLBACK` hilft, danach von vorn.

Der Grund: B will eine Zeile schreiben, deren Stand in Wirklichkeit nicht mehr
der ist, den B gesehen hat. B's Bild ist **veraltet**, und darauf baut der Server
nicht auf — lieber ein Fehler als eine stillschweigend falsche Buchung.

**Der Vergleich mit `READ COMMITTED` ist der eigentliche Lerninhalt:** dort
würde dasselbe `UPDATE` in B **keinen** Fehler geben. In `READ COMMITTED` liest
die Anweisung die inzwischen bestätigte Zeile neu und rechnet auf ihr weiter —
beide `+100` landen nacheinander, ohne Fehler. In `REPEATABLE READ` verweigert
der Server das, weil der Schnappschuss von B nicht mehr stimmt.

Also: `REPEATABLE READ` macht Fehler **sichtbar**, statt sie stillschweigend
aufzulösen. Beides ist richtig — aber eine Anwendung, die auf dieser Stufe läuft,
*muss* mit Fehlern rechnen.

---

## 7.11 `SERIALIZABLE`: der Serialisierungsfehler und was man damit tut

*Zwei Fenster, beide in `kurs` — siehe 7.8b.*

Auf der strengsten Stufe prüft PostgreSQL zusätzlich, ob sich die Transaktionen
in einer Reihenfolge hätten ausführen lassen, die man auch nacheinander hätte
erreichen können. Wenn nicht, bricht es eine ab. Klassischer Fall: beide
Transaktionen **lesen** etwas und **schreiben** danach etwas, das von dem
Gelesenen abhängt.

**Fenster A:**

```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT sum(betrag) FROM konto;
UPDATE konto SET betrag = betrag + 1;
```

**Fenster B:**

```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT sum(betrag) FROM konto;
UPDATE konto SET betrag = betrag + 1;
```

**Fenster A:**

```sql
COMMIT;
```

**Fenster B:**

```sql
COMMIT;
```

Erwartung: **eine** der beiden Sitzungen bricht ab, mit

```
ERROR:  could not serialize access due to read/write dependencies among transactions
SQLSTATE: 40001
```

Hier ist die Ursache noch einen Schritt subtiler als in 7.10: es sind nicht die
geänderten *Zeilen*, sondern die **veralteten Werte**. Beide haben eine Summe
gelesen, die nach dem `COMMIT` der anderen nicht mehr stimmt — und beide haben
darauf aufgebaut. Man kann sich zwei Bankangestellte vorstellen, die beide
notiert haben „der Bestand reicht" und danach beide etwas davon wegnehmen.
Keiner hat für sich einen Fehler gemacht, aber zusammen ergibt das keinen
Ablauf, den es hätte geben dürfen.

Welcher der beiden Schritte den Fehler meldet (`UPDATE` oder `COMMIT`), hängt
davon ab, wie sich die beiden Sitzungen verschränkt haben. Deshalb ist die
wichtige Frage nicht „welche Meldung genau?", sondern: **was macht man damit?**

`40001` ist **kein Bug und kein Datenverlust** — es ist die Aufforderung, die
Transaktion zu wiederholen:

```text
wiederhole:
    BEGIN ISOLATION LEVEL SERIALIZABLE;
    ... alles lesen und schreiben ...
    COMMIT;
bei Fehler 40001:
    von vorn
```

Das ist der Preis der strengsten Stufe: man bekommt Korrektheit, aber die
Anwendung muss den Wiederholungsfall selbst behandeln. Ein Programm, das
`SERIALIZABLE` setzt und 40001 nicht abfängt, fällt gelegentlich einfach um —
und zwar umso häufiger, je mehr gleichzeitig läuft.

Fehlercodes nachschlagen kann man hier:
https://www.postgresql.org/docs/18/errcodes-appendix.html

---

## 7.12 Aufräumen

Kontostände zurücksetzen (schnell, ohne Tabellensperre):

```sql
UPDATE konto SET betrag = 10000;
SELECT sum(betrag) FROM konto;
```

Tabelle weg:

```sql
DROP TABLE konto;
```

Und grundsätzlich: eine offene Transaktion erkennt man am `*` im Prompt. Ein
`\q` beendet die Sitzung und rollt sie dabei zurück. Trotzdem ist es sauberer,
selbst `ROLLBACK` zu tippen — dann *weiß* man, was passiert ist.

---

## Was in `06-kurs-notizen.md` gehört

Die Zahlen sind auf dem jeweiligen Rechner zu messen, nicht hier
hineinzuschreiben. Dort die leeren Tabellen dafür:

- Ändert sich die Summe innerhalb / außerhalb einer Transaktion?
- Was passiert in `READ COMMITTED`, `REPEATABLE READ`, `SERIALIZABLE` bei
  gleichzeitigen Zugriffen — und welcher Fehlercode kommt?
- Wie lange hat es gedauert, bis ein wartendes `UPDATE` weiterlief?
