-- ---------------------------------------------------------------------------
-- Abfragekosten: ohne Index, mit Index, mit Constraint
--
-- \timing on  -> psql zeigt vor jedem Ergebnis die Dauer an
-- ---------------------------------------------------------------------------

\timing on

-- Aktueller Stand
SELECT count(*) FROM kurs;

-- ---------------------------------------------------------------------------
-- 1) OHNE Index
-- ---------------------------------------------------------------------------

-- Ein einzelner Datensatz über den Schlüssel
EXPLAIN ANALYZE SELECT * FROM kurs WHERE id = 3999999;

-- Ein einzelner Datensatz über den Namen
EXPLAIN ANALYZE SELECT * FROM kurs WHERE name = 'Kurs Nr. 123456';

-- Beide sollten "Seq Scan on kurs" zeigen:
-- der Server liest ALLE 4 Mio. Zeilen durch (rows=4000000).

-- ---------------------------------------------------------------------------
-- 2) Index anlegen und Statistik aktualisieren
-- ---------------------------------------------------------------------------

CREATE INDEX idx_kurs_id ON kurs (id);

ANALYZE kurs;

-- ---------------------------------------------------------------------------
-- 3) MIT Index: dieselbe Abfrage noch einmal
-- ---------------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM kurs WHERE id = 3999999;
-- Erwartung: "Index Scan using idx_kurs_id" statt "Seq Scan"

-- Der Namensfilter hat nichts vom Index auf id und bleibt Seq Scan:
EXPLAIN ANALYZE SELECT * FROM kurs WHERE name = 'Kurs Nr. 123456';

-- ---------------------------------------------------------------------------
-- 4) Variante: Primary Key (Constraint) statt einfachem Index
--
-- Erst den einfachen Index wegwerfen, sonst vergleicht man Äpfel mit Birnen:
--   DROP INDEX idx_kurs_id;
-- Der Primary Key legt selbst einen Index an (Name: kurs_pkey).
-- Geht nur, wenn es keine doppelten id-Werte gibt.
-- ---------------------------------------------------------------------------

-- DROP INDEX idx_kurs_id;
-- ALTER TABLE kurs ADD CONSTRAINT kurs_pkey PRIMARY KEY (id);
-- ANALYZE kurs;
-- EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM kurs WHERE id = 3999999;

-- ---------------------------------------------------------------------------
-- 5) Platzverbrauch
-- ---------------------------------------------------------------------------

\dt+ kurs

SELECT pg_size_pretty(pg_total_relation_size('kurs'))  AS gesamt,
       pg_size_pretty(pg_relation_size('kurs'))       AS tabelle,
       pg_size_pretty(pg_indexes_size('kurs'))        AS indizes;
