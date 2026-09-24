# 15 — REPACK: Tabelle neu schreiben statt `VACUUM FULL`

> **Ausblick — auf dem Kurs-Container nicht ausführbar.** `REPACK` gibt es erst
> ab PostgreSQL **19**. Der Container aus `compose.yaml` läuft auf
> `postgres:18.6`; dort endet `REPACK vactest;` mit einem Syntaxfehler. Für die
> Übungen unten brauchst du eine zweite Instanz mit 19.
>
> Die Doku-Seite liegt noch unter der Versionsnummer und wandert nach dem
> Release nach `/current/`:
> https://www.postgresql.org/docs/19/sql-repack.html

Teil 13 hat den Unterschied aufgeschrieben, um den es hier geht: `VACUUM` gibt
den Platz **innerhalb** der Datei zur Wiederverwendung frei, `VACUUM FULL`
schreibt die Tabelle neu und gibt ihn **ans Dateisystem** zurück (13.1). Das
Zweite ist ab 19 ein eigener Befehl.

Die Doku sagt es in zwei Sätzen:

> `REPACK` reclaims storage occupied by dead tuples. Unlike `VACUUM`, it does so
> by rewriting the entire contents of the table specified by `table_name` into a
> new disk file with no extra space (except for the space guaranteed by the
> `fillfactor` storage parameter), allowing unused space to be returned to the
> operating system.

`REPACK` ist damit **`VACUUM FULL` und `CLUSTER` in einer Anweisung**. Die
Optionen sind absichtlich dieselben wie bei `VACUUM` — `VERBOSE` und `ANALYZE`
gibt es dort schon (13.1b, 13.8). Wirklich neu ist allein `CONCURRENTLY` (15.4).

Die Syntax:

```
REPACK [ ( option [, ...] ) ] [ table_and_columns [ USING INDEX [ index_name ] ] ]
REPACK [ ( option [, ...] ) ] USING INDEX

option ist eines von:  VERBOSE, ANALYZE, CONCURRENTLY
```

---

## 15.0 Zwei gleiche Tabellen anlegen

Zum Vergleichen braucht es zwei Tabellen mit identischem Ausgangszustand — sonst
weiß man am Ende nicht, ob der Unterschied vom Befehl kommt oder von den Daten.

```sql
DROP TABLE IF EXISTS vactest;
DROP TABLE IF EXISTS vactest_full;

CREATE TABLE vactest      (id integer);
CREATE TABLE vactest_full (id integer);

INSERT INTO vactest      SELECT g FROM generate_series(1, 100000) AS g;
INSERT INTO vactest_full SELECT g FROM generate_series(1, 100000) AS g;

ANALYZE vactest;
ANALYZE vactest_full;
```

Messen — und zwar **beide** Zahlen, nicht nur die aus `\dt+`:

```sql
SELECT pg_size_pretty(pg_total_relation_size('vactest')) AS gesamt,
       pg_size_pretty(pg_table_size('vactest'))         AS tabelle,
       pg_size_pretty(pg_indexes_size('vactest'))       AS indizes;
```

Diese zwei Werte sind der **Ausgangswert**. Notiere sie, bevor du etwas
änderst — ohne ihn ist jede spätere Zahl bedeutungslos.

> **Falle:** die `Size`-Spalte von `\dt+` ist `pg_table_size` — also nur der
> Heap. Die Indizes sind dort **nicht** enthalten. Wenn du nur `\dt+` benutzt,
> siehst du die Hälfte des Effekts nicht. Die drei `pg_*_size`-Funktionen hast du
> schon in `sql/03_abfragen.sql` benutzt.

---

## 15.1 Aufblähen und messen

Ein `UPDATE` über alle Zeilen ist der schlimmste Fall: jede Zeile wird neu
geschrieben, die alte bleibt als tote Version liegen (12.0, 13.0).

```sql
UPDATE vactest      SET id = id + 1;
UPDATE vactest_full SET id = id + 1;
```

```sql
SELECT relname, n_live_tup, n_dead_tup
FROM pg_stat_user_tables
WHERE relname IN ('vactest', 'vactest_full');
```

Erwartung: `n_dead_tup` in der Größenordnung der 100.000 Änderungen, obwohl
logisch keine einzige Zeile dazugekommen ist — und `pg_total_relation_size`
größer als der Ausgangswert.

---

## 15.2 Neu schreiben: derselbe Schritt, zwei Befehle

```sql
REPACK (ANALYZE) vactest;
VACUUM (FULL, ANALYZE) vactest_full;
```

Beide schreiben die Tabelle in eine neue Datei und tauschen sie aus.

```sql
SELECT pg_size_pretty(pg_total_relation_size('vactest'))      AS repack,
       pg_size_pretty(pg_total_relation_size('vactest_full')) AS vacuum_full;
```

Erwartung: beide Werte fallen wieder auf den Ausgangswert zurück — **nicht
darunter**. Fällt das Ergebnis unter den Ausgangswert, war schon der
Ausgangswert aufgebläht; dann stimmt der Vergleich nicht und du fängst besser
mit frisch angelegten Tabellen neu an (oder nimmst eine Tabelle, auf der noch
nie gearbeitet wurde).

Das ist die ganze Lektion, dieselbe wie in 13.6, nur mit einem kürzeren Befehl.

---

## 15.3 `REPACK` ohne Tabellennamen

Wie bei `VACUUM` (13.1) lässt man den Namen weg und bekommt die ganze Datenbank:

```sql
REPACK;
```

Drei Regeln dazu aus der Doku:

- Es werden **alle Tabellen und materialisierten Views** bearbeitet, für die die
  eigene Rolle das Privileg `MAINTAIN` hat — ein Privileg, das erst mit
  PostgreSQL 17 kam.
- Die Anweisung **kann nicht in einem Transaktionsblock laufen**. Der Prompt
  muss also `kurs=#` sein, nicht `kurs=*#` (7.1).
- Diese Form **ist mit `CONCURRENTLY` nicht erlaubt**. Wer nebenläufig will,
  muss die Tabelle nennen.

`REPACK` wechselt für die Dauer des Laufs das `search_path` auf
`pg_catalog, pg_temp`. Das erklärt die Meldung, falls dir später jemand erzählt,
seine Tabellen seien „plötzlich nicht gefunden" worden.

---

## 15.4 `CONCURRENTLY` — der eigentliche Unterschied

`VACUUM FULL` und `REPACK` halten beide eine `ACCESS EXCLUSIVE`-Sperre (7.6c) —
und blockieren damit auch jedes `SELECT`. Genau das ändert `CONCURRENTLY`:

```sql
REPACK (CONCURRENTLY) vactest;
```

Die Doku erklärt den Mechanismus:

> Internally, `REPACK` copies the contents of the table (ignoring dead tuples)
> into a new file, sorted by the specified index, and also creates a new file for
> each index. Then it swaps the old and new files for the table and all the
> indexes, and deletes the old files. The `ACCESS EXCLUSIVE` lock is needed to
> make sure that the old files do not change during the processing because the
> changes would get lost due to the swap.
>
> With the `CONCURRENTLY` option, the `ACCESS EXCLUSIVE` lock is only acquired to
> swap the table and index files. The data changes that took place during the
> creation of the new table and index files are captured using logical decoding
> and applied before the `ACCESS EXCLUSIVE` lock is requested.

Kurz: die Arbeit läuft ohne Sperre, und nur der Dateitausch am Ende ist exklusiv.
Die Änderungen, die währenddessen passieren, werden über **logical decoding**
mitgeschnitten und unmittelbar vor dem Tausch nachgezogen (siehe Teil 10, dort
geht es um das Warten).

Was das praktisch bedeutet:

- Die Sperre ist „typically held only for the time needed to swap the files" —
  aber sie kann länger dauern, wenn währenddessen **viel** geändert wurde. Die
  Änderungen müssen ja noch verarbeitet werden, während die Sperre schon liegt.
- Es braucht dafür ein Replikationsslot. Reicht
  `max_repack_replication_slots` nicht aus, schlägt der Befehl fehl — die
  Einstellung gehört damit in die Sammlung aus Teil 14.
- `CONCURRENTLY` ordnet Zeilen nicht, die nach dem Start eingefügt wurden. Und
  es kann scheitern, wenn andere Transaktionen zwischendurch `DDL` auf der
  Tabelle machen.

Und die Voraussetzungen, unter denen es **gar nicht** geht:

| Bedingung | warum |
|-----------|-------|
| Tabelle ist `UNLOGGED` | kein Logical Decoding möglich |
| Tabelle ist partitioniert | wird nicht unterstützt |
| kein Primary Key / keine indexbasierte Replica Identity | Logical Decoding hat keinen Schlüssel, an dem es Änderungen festmachen kann |
| Systemkatalog oder TOAST-Tabelle | nicht erlaubt |
| Aufruf innerhalb eines Transaktionsblocks | nicht erlaubt |
| `max_repack_replication_slots` zu klein | kein Slot für den Lauf |

**Die wichtigste Warnung steht als Kasten in der Doku:**

> `REPACK` with the `CONCURRENTLY` option is not MVCC-safe, see Section 13.6.

Die Querverweisnummer „13.6" ist die Kapitelnummer der PostgreSQL-Doku, nicht
dieses Dokument 13. Der Satz ist trotzdem der Grund, warum man `CONCURRENTLY`
nicht blind einsetzt: es gibt einen Zustand, in dem ein gleichzeitiger Leser
etwas sieht, was MVCC sonst verhindern würde. Lies die Stelle in der Doku, bevor
du es produktiv benutzt.

Während ein `CONCURRENTLY`-Lauf läuft, ist er sichtbar:

```sql
SELECT * FROM pg_stat_progress_repack;
```

Das ist das Gegenstück zu `pg_stat_progress_cluster` aus 13.3.

---

## 15.5 `USING INDEX` — Clustering gratis dazu

```sql
REPACK (ANALYZE) vactest USING INDEX;
```

Mit `USING INDEX` werden die Zeilen in der Reihenfolge eines Index abgelegt —
das ist genau das, was `CLUSTER` tut. Ohne Indexnamen wird der Index genommen,
der per `ALTER TABLE ... CLUSTER ON` als Clustering-Index festgelegt wurde; ist
keiner festgelegt, gibt es einen Fehler. Zurücksetzen geht mit
`ALTER TABLE ... SET WITHOUT CLUSTER`.

Zwei Details, die man leicht falsch annimmt:

- **Clustering ist eine einmalige Sache.** Die Doku: „when the table is
  subsequently updated, the changes are not clustered". Nach den ersten
  `UPDATE`s ist die Ordnung wieder weg — deshalb der Hinweis, dass ein
  `fillfactor` unter 100% hilft, sie länger zu erhalten.
- Für den Index-Scan-Weg muss der Index ein **B-Tree** sein. Sonst nimmt
  `REPACK` einen Sequential Scan plus Sortierung.

Was zuletzt passiert, sagt die Doku ebenfalls: „It will attempt to choose the
method that will be faster, based on planner cost parameters and available
statistical information." Die Wahl ist also die des Planers — und genau dann
will man `EXPLAIN` lesen können (Teil 5, Teil 16).

---

## 15.6 Was es kostet, bevor du es startest

- **Plattenplatz.** „you need free space on disk at least equal to the sum of the
  table size and the index sizes" — und beim Sortier-Weg „as much as double the
  table size, plus the index sizes". Mit `SET enable_sort = off` kann man den
  zweiten Weg abschalten, wenn der Platz nicht reicht.
- **`maintenance_work_mem`** sollte vorher hochgesetzt werden: „It is advisable
  to set `maintenance_work_mem` to a reasonably large value (but not more than
  the amount of RAM you can dedicate to the `REPACK` operation)". Teil 14.
- **Sperre.** Ohne `CONCURRENTLY` blockiert alles, auch `SELECT`. In
  `pg_locks` zu sehen, siehe 7.6c und Teil 8.
- **Rechte.** Es braucht `MAINTAIN` auf der Tabelle.

---

## 15.7 Aufräumen

```sql
DROP TABLE vactest;
DROP TABLE vactest_full;
```
