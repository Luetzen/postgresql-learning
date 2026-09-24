# 11 — Indizes anlegen, ohne den Betrieb anzuhalten

In Teil 5 ging es darum, was ein Index **bringt**: `EXPLAIN`, `Seq Scan` gegen
`Index Scan`, der Platzverbrauch. Hier geht es um die Frage davor — **wie legt
man einen Index an, wenn die Tabelle gerade benutzt wird?** — und um den Zustand,
der dabei entstehen kann: `INVALID`.

Voraussetzung: die Tabelle `kurs` aus Teil 3/4 mit ihren 4 Mio. Zeilen. Genau
richtig, um einen Index-Build notfalls abzubrechen.

```sql
SELECT count(*) FROM kurs;
\d kurs
```

Für die Übungen in 11.6 sollte `kurs` **keinen** Index auf `id` haben. Falls aus
Teil 5 noch einer übrig ist:

```sql
DROP INDEX IF EXISTS idx_kurs_id;
DROP INDEX IF EXISTS idx_kurs_name;
```

---

## 11.1 Zwei Arten zu bauen

| | `CREATE INDEX` | `CREATE INDEX CONCURRENTLY` |
|---|---|---|
| Tabellensperre | `SHARE` (7.6c) | `SHARE UPDATE EXCLUSIVE` |
| Einfügen/Ändern/Löschen | **blockiert**, bis der Build fertig ist | läuft weiter |
| Lesen | läuft weiter | läuft weiter |
| Tabellenscans | einer | **zwei** |
| Dauer | kürzer | deutlich länger |
| im Transaktionsblock | ja | **nein** |

Die Doku sagt zum normalen Weg:

> Normalerweise sperrt PostgreSQL die zu indizierende Tabelle gegen Schreibzugriffe
> und führt den gesamten Index-Build mit einem einzigen Scan der Tabelle durch.
> Andere Transaktionen können die Tabelle weiterhin lesen, aber wenn sie Zeilen
> einfügen, ändern oder löschen wollen, blockieren sie, bis der Index-Build fertig
> ist.

Und zum zweiten Weg:

> … muss PostgreSQL zwei Scans der Tabelle durchführen und zusätzlich warten, dass
> alle existierenden Transaktionen, die den Index ändern oder benutzen könnten,
> beendet sind. Damit ist diese Methode mehr Arbeit als ein normaler Index-Build
> und dauert deutlich länger.

Der Tausch ist also klar: **Stillstand gegen Zeit.** In Produktion nimmt man die
zweite Variante, wenn Schreibzugriffe weiterlaufen müssen — und bezahlt mit zwei
Tabellenscans und längerer Laufzeit.

Referenz: https://www.postgresql.org/docs/18/sql-createindex.html

---

## 11.2 Warum ein Concurrent-Build hängen kann

Die Doku beschreibt die Phasen sehr genau, und daraus erklärt sich das, was man
in der Praxis beobachtet: dass so ein Build **wartet**, obwohl er nichts mit
Sperren zu tun zu haben scheint.

> Bei einem Concurrent-Index-Build wird der Index in einer Transaktion als
> „invalid" in die Systemkataloge eingetragen, dann finden in zwei weiteren
> Transaktionen zwei Tabellenscans statt. Vor jedem Scan muss der Build warten,
> dass existierende Transaktionen, die die Tabelle geändert haben, beendet sind.
> Nach dem zweiten Scan muss er warten, dass alle Transaktionen mit einem
> Schnappschuss von **vor** dem zweiten Scan beendet sind … Dann kann der Index
> als „valid" markiert werden.

Der letzte Teil ist der unangenehme: es genügt eine einzige Sitzung, die `BEGIN`
gesagt hat und dann nichts tut (7.6b, `idle in transaction`), um einen Build
aufzuhalten — dieselbe Sitzung, die in 8.3 vom
`idle_in_transaction_session_timeout` abgeräumt wird.

Und noch eine Feinheit aus der Doku:

> Selbst dann ist der Index möglicherweise nicht sofort für Abfragen nutzbar: im
> schlimmsten Fall kann er nicht benutzt werden, solange Transaktionen existieren,
> die vor dem Start des Index-Builds begonnen haben.

Was gerade läuft, sieht man live:

```sql
SELECT * FROM pg_stat_progress_create_index;
```

Die Ansicht ist genau für diesen einen Vorgang da. Sieh sie dir während eines
Builds selbst an und lies, in welchem Schritt er steckt und auf wen er wartet.

Warum eine alte Transaktion so teuer ist — sie hält nicht nur den Build auf,
sondern auch das Aufräumen toter Zeilen —, steht in Teil 12 und 13.

---

## 11.3 `INVALID` — ein Index, den es nicht gibt

Wenn beim Scannen etwas schiefgeht — ein Deadlock, eine verletzte
Eindeutigkeit, oder ein `Strg+C` von Hand —, dann bricht der Befehl ab und
**lässt den Index stehen**:

> Wenn beim Scannen der Tabelle ein Problem auftritt, etwa ein Deadlock oder eine
> Verletzung der Eindeutigkeit in einem Unique-Index, schlägt `CREATE INDEX` fehl,
> lässt aber einen „invalid" Index zurück. Dieser Index wird für Abfragen
> **ignoriert**, weil er unvollständig sein könnte; er verbraucht trotzdem weiter
> **Update-Overhead**.

`psql` zeigt das im `\d`:

```
Indexes:
    "idx" btree (col) INVALID
```

Zwei Folgen, die zusammen ärgerlich sind:

- **Er wird nicht benutzt.** Der Planer ignoriert ihn — er kann unvollständig
  sein. Das ist die *zweite* Erklärung für „der Index ist da, wird aber nicht
  benutzt" (die erste war die leere Tabelle in Teil 5).
- **Er kostet trotzdem.** Jedes `INSERT` und `UPDATE` muss ihn mitpflegen, und
  er belegt Platz:

```sql
SELECT pg_size_pretty(pg_indexes_size('kurs')) AS indizes;
```

Und eine Falle speziell für `UNIQUE`:

> Wenn ein Fehler im zweiten Scan auftritt, setzt der „invalid" Index seine
> Eindeutigkeitsprüfung danach weiter durch.

Man hat dann einen Index, der nichts beschleunigt, aber Einfügungen abweist.

**Alle** invaliden Indizes einer Datenbank findet man so:

```sql
SELECT n.nspname AS schema,
       t.relname AS tabelle,
       c.relname AS index,
       i.indisvalid,
       i.indisready
FROM pg_index i
JOIN pg_class     c ON c.oid = i.indexrelid
JOIN pg_class     t ON t.oid = i.indrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE NOT i.indisvalid;
```

`indisvalid` ist das `INVALID` aus der `\d`-Ausgabe. Ein Index kann außerdem
`indisready = false` sein — dann ist er noch nicht einmal für neue Zeilen in
Betrieb.

---

## 11.4 Reparieren

Die Doku ist da eindeutig:

> Die empfohlene Wiederherstellung ist, den Index zu löschen und
> `CREATE INDEX CONCURRENTLY` erneut zu versuchen. (Eine andere Möglichkeit ist,
> den Index mit `REINDEX INDEX CONCURRENTLY` neu zu bauen.)

Also entweder:

```sql
DROP INDEX idx_kurs_cc;
CREATE INDEX CONCURRENTLY idx_kurs_cc ON kurs (id);
```

oder, wenn der Name bleiben soll:

```sql
REINDEX INDEX CONCURRENTLY idx_kurs_cc;
```

`REINDEX` allein (ohne `CONCURRENTLY`) ginge auch, sperrt aber — nach 7.6c wäre
das `SHARE` bzw. mehr. Für eine benutzte Tabelle nimmt man die Concurrent-Variante.

---

## 11.5 Regeln und Randfälle

- **`CONCURRENTLY` läuft nicht in einem Transaktionsblock.** Der Versuch endet
  mit einem Fehler. In `psql` ist das kein Problem, weil jede Anweisung einzeln
  bestätigt wird (7.2) — innerhalb eines `BEGIN` geht es nicht.
- **Nur ein Concurrent-Build pro Tabelle gleichzeitig.** Reguläre Builds dürfen
  sich dagegen parallel auf derselben Tabelle abspielen.
- **Während eines Builds ist keine Schemaänderung an der Tabelle erlaubt.**
- **Neue Ausdrucks-Indizes brauchen ein `ANALYZE`** (oder man wartet auf
  autovacuum), sonst hat der Planer keine Statistik dazu — siehe 5.2.
- **`ONLY` auf einer partitionierten Tabelle markiert den Index absichtlich als
  `INVALID`**; `ALTER INDEX … ATTACH PARTITION` macht ihn gültig, sobald alle
  Partitionen passende Indizes haben. Ein `INVALID` kann also auch gewollt sein.
- **Der Build kann parallel laufen** (B-tree, GIN, BRIN). `maintenance_work_mem`
  ist der Speicher für die ganze Operation, nicht je Worker.

---

## 11.6 Übung: einen `INVALID`-Index erzeugen und wieder loswerden

Ausgangslage prüfen:

```sql
\d kurs
```

Erwartung: nur `kurs_pkey` (falls aus Teil 5 vorhanden) oder gar kein Index.

Jetzt einen Concurrent-Build starten — und abbrechen:

```sql
CREATE INDEX CONCURRENTLY idx_kurs_cc ON kurs (id);
```

Nach ein paar Sekunden **Strg+C**:

```
ERROR:  canceling statement due to user request
```

Genau das ist der „Fehler beim Scannen" aus 11.3. Also nachsehen:

```sql
\d kurs
```

Erwartung: `"idx_kurs_cc" btree (id) INVALID`.

Und jetzt der Beweis, dass er ignoriert wird — dieselbe Abfrage wie in 5.2:

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM kurs WHERE id = 3999999;
```

Erwartung: **`Seq Scan`**, obwohl ein Index auf `id` existiert. Vergleiche mit
5.2, wo nach `CREATE INDEX` + `ANALYZE` ein `Index Scan` erschien. Der
Unterschied ist genau ein Wort in den Katalogen.

Zurück auf den Stand von vorher:

```sql
DROP INDEX idx_kurs_cc;
```

Fragen für `06-kurs-notizen.md`: wie lange lief der Build, bevor du abgebrochen
hast? Wie groß war der invalide Index (`pg_indexes_size`)? Und was passiert,
wenn du `REINDEX INDEX CONCURRENTLY` statt `DROP` + neu benutzt?

---

## 11.7 Aufräumen

```sql
-- falls noch etwas liegt:
DROP INDEX IF EXISTS idx_kurs_cc;
DROP INDEX IF EXISTS idx_kurs_id;
DROP INDEX IF EXISTS idx_kurs_name;
```

Und kontrollieren:

```sql
SELECT c.relname, i.indisvalid
FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_class t ON t.oid = i.indrelid
WHERE t.relname = 'kurs';
```
