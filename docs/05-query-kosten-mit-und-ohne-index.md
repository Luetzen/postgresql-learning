# 5 — Abfragen ohne Constraint, mit Index und mit Primary Key messen

Jetzt kommt der eigentliche Kursinhalt: **was kostet eine Abfrage?**

Es gibt drei Zustände, die man vergleichen will:

| Zustand | Was vorhanden ist | Erwartung |
|---------|-------------------|-----------|
| A | nichts (kein Index, kein Constraint) | der Server liest die *ganze* Tabelle |
| B | einfacher Index auf `id` | der Server springt direkt zur Zeile |
| C | Primary Key auf `id` | wie B, zusätzlich erzwungen die DB die Eindeutigkeit |

Verbindung:

```bash
docker compose exec db psql -U kurs -d kurs
```

---

## 5.0 Werkzeug: EXPLAIN ANALYZE und \timing

```sql
\timing on
```

`\timing on` lässt `psql` vor jedes Ergebnis die Dauer schreiben.

```sql
EXPLAIN SELECT ...;                    -- nur der Plan, nicht ausgeführt
EXPLAIN ANALYZE SELECT ...;            -- Plan UND echte Ausführung mit Zeiten
EXPLAIN (ANALYZE, BUFFERS) SELECT ...; -- zusätzlich: wie viele Datenblöcke gelesen
```

Die wichtigsten Zeilen in der Ausgabe:

- `Seq Scan on kurs` — **die ganze Tabelle wird gelesen**
- `Index Scan using ...` / `Index Only Scan` — es wird nur der Index benutzt
- `rows=` — geschätzte (ohne `ANALYZE`) bzw. tatsächliche Zeilenzahl
- `actual time=... rows=... loops=1` — echte Laufzeit
- `Execution Time:` — Gesamtzeit in Millisekunden

Diesen Vergleich macht man immer genau so: **erst ohne, dann mit** — und
vergleicht die Pläne.

---

## 5.1 Zustand A — ohne alles

Falls die Tabelle schon einen Index hat, wegwerfen:

```sql
DROP INDEX IF EXISTS idx_kurs_id;
```

Messen:

```sql
EXPLAIN ANALYZE SELECT * FROM kurs WHERE id = 3999999;
EXPLAIN ANALYZE SELECT * FROM kurs WHERE name = 'Kurs Nr. 123456';
```

Was man sieht: **`Seq Scan on kurs`**, `rows=4000000`. Die Abfrage ist trotzdem
schnell, weil die Tabelle nur ~200 MB groß ist und im Arbeitsspeicher liegt —
aber der Server hat alle 4 Mio. Zeilen gelesen, um eine einzige zu finden.

Sichtbar wird das an `Buffers`: `shared hit=` entspricht den gelesenen 8-kB-Blöcken.

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM kurs WHERE id = 3999999;
```

---

## 5.2 Zustand B — mit einfachem Index

```sql
CREATE INDEX idx_kurs_id ON kurs (id);

ANALYZE kurs;      -- Statistik aktualisieren, sonst plant der Server schlecht
```

Statistiken sind wichtig: der Planer entscheidet anhand dieser Zahlen, ob er den
Index benutzt. Ohne `ANALYZE` kann er sich vertun.

Dieselbe Abfrage noch einmal:

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM kurs WHERE id = 3999999;
```

Erwartung: **`Index Scan using idx_kurs_id on kurs`**, `rows=1`, und die Zahl der
gelesenen Blöcke fällt von ~25.000 auf wenige.

Jetzt noch einmal der Namensfilter:

```sql
EXPLAIN ANALYZE SELECT * FROM kurs WHERE name = 'Kurs Nr. 123456';
```

Erwartung: **immer noch `Seq Scan`**. Der Index liegt auf `id`, nicht auf `name`
— für den Namensfilter kann er nichts tun. Das ist die Lehre aus diesem Schritt:
*ein Index hilft nur der Abfrage, für die er gebaut ist.*

Zum Vergleich einen Index auf `name` anlegen:

```sql
CREATE INDEX idx_kurs_name ON kurs (name);
ANALYZE kurs;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM kurs WHERE name = 'Kurs Nr. 123456';
-- jetzt: Index Scan using idx_kurs_name
```

---

## 5.3 Zustand C — Primary Key statt einfachem Index

Ein Primary Key ist ein **Constraint**: er erzeugt erstens automatisch einen
eindeutigen Index und verhindert zweitens doppelte Werte (und `NULL`).

Erst den einfachen Index wegwerfen, sonst hat man zwei Indizes auf derselben
Spalte und weiß nicht, welcher benutzt wird:

```sql
DROP INDEX idx_kurs_id;
```

Dann:

```sql
ALTER TABLE kurs ADD CONSTRAINT kurs_pkey PRIMARY KEY (id);

ANALYZE kurs;

\d kurs
```

`\d kurs` zeigt jetzt:

```
Indexes:
    "kurs_pkey" PRIMARY KEY, btree (id)
```

Und messen:

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM kurs WHERE id = 3999999;
```

Der Plan sieht aus wie bei B (`Index Scan using kurs_pkey`) — der Unterschied
liegt nicht in der Geschwindigkeit, sondern in der **Garantie**: ab jetzt können
zwei Zeilen nicht dieselbe `id` haben. Einfach einmal ausprobieren:

```sql
INSERT INTO kurs (id, name) VALUES (42, 'doppelt');
-- FEHLER: duplicate key value violates unique constraint "kurs_pkey"
```

Das ist der Punkt von „Constraint" gegenüber „Index": der Index macht schnell,
der Constraint macht *richtig*.

---

## 5.4 Platzverbrauch

```sql
\dt+ kurs

SELECT pg_size_pretty(pg_total_relation_size('kurs')) AS gesamt,
       pg_size_pretty(pg_relation_size('kurs'))      AS tabelle,
       pg_size_pretty(pg_indexes_size('kurs'))       AS indizes;
```

Ein Index kostet Platz und verlangsamt jedes `INSERT` ein wenig, weil er
mitgepflegt werden muss. Dafür machen ihn Abfragen bezahlbar. Auch das ist ein
Index.

---

## 5.5 Warum die erste Version ohne Index so wichtig war

Man merkt sich das am besten über den Ablauf:

1. **Ohne Index** — funktioniert, ist nur langsam. Die Datenbank liest alles.
2. **Mit Index** — gleiche Abfrage, gleiches Ergebnis, viel weniger Arbeit.
   `EXPLAIN` zeigt den Unterschied schwarz auf weiß.
3. **Mit Constraint** — Geschwindigkeit plus eine Garantie über die Daten.

Das ist die Standard-Frage in jedem Datenbankgespräch: *„Hast du `EXPLAIN`
angeguckt?"* Ab jetzt kannst du das beantworten.

---

## 5.6 Alles zurück auf Anfang

```sql
DROP INDEX IF EXISTS idx_kurs_id;
DROP INDEX IF EXISTS idx_kurs_name;
ALTER TABLE kurs DROP CONSTRAINT IF EXISTS kurs_pkey;
```

Oder radikal die ganze Tabelle:

```sql
DROP TABLE kurs;
```

Danach `sql/01_schema.sql` ausführen und die Übung beginnt wieder bei null.
