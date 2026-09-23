-- ---------------------------------------------------------------------------
-- Übungstabellen für Teil 17: Nested Loop, Hash Join, Merge Join
--
-- Zwei Tabellen, absichtlich OHNE Index — wie in Teil 5 kommt der Index erst
-- hinterher dazu, damit man den Unterschied der Pläne sieht.
--
--   thema      — winzig  (8 Zeilen)
--   kurs_thema — groß    (4 Mio. Zeilen), kurs_id ist eindeutig 1..4000000
--
-- Damit lassen sich alle drei Situationen stellen, die in Teil 17 gebraucht
-- werden:
--
--   thema × kurs_thema         kleine gegen große Seite
--   kurs_thema × kurs_thema    zwei große Seiten, Gleichheit auf kurs_id
--   thema × thema mit <        keine Gleichheit -> nur Nested Loop möglich
--
-- "kurs" aus Teil 3 wird hier nicht gebraucht. Wer es gefüllt hat, kann damit
-- zusätzlich einen Baum aus drei Tabellen bauen (kurs -> kurs_thema -> thema)
-- und die Join-Reihenfolge im Plan ansehen.
--
-- Kann immer wieder ausgeführt werden: Tabellen werden neu angelegt.
--
--   docker compose exec -T db psql -U kurs -d kurs -f /sql/05_join_schema.sql
--
-- Zum schnelleren Ausprobieren in beiden generate_series() die Obergrenze
-- senken (z. B. 400000) — die Zahl steht nur in den zwei INSERTs.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS kurs_thema;
DROP TABLE IF EXISTS thema;

CREATE TABLE thema (
    id          integer,
    bezeichnung text
);

CREATE TABLE kurs_thema (
    kurs_id  integer,
    thema_id integer
);

-- 8 Zeilen: die kleine Seite
INSERT INTO thema (id, bezeichnung)
SELECT nr, 'Thema ' || nr
FROM generate_series(1, 8) AS s(nr);

-- eine Zeile pro "Kurs": die große Seite
INSERT INTO kurs_thema (kurs_id, thema_id)
SELECT nr, 1 + (nr % 8)
FROM generate_series(1, 4000000) AS s(nr);

-- Kontrolle
SELECT count(*) FROM thema;
SELECT count(*) FROM kurs_thema;
\d thema
\d kurs_thema
