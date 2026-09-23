-- ---------------------------------------------------------------------------
-- Übungstabellen für Teil 18: Werte erzeugen, die nicht nur Zähler sind
--
-- Zwei Tabellen mit ABSICHTLICH verschiedenartiger "Vielfalt":
--
--   adresse      drei integer-Spalten, aus dem Zähler gerechnet
--                stadt   -> 100 verschiedene Werte
--                plz     -> 10.000
--                strasse -> 1.000.000, also in jeder Zeile ein anderer
--                (die Werte liegen in Blöcken -> sortiert)
--
--   adresse_text wie man es "echt" füllen würde: Werte aus einem Vorrat,
--                Stadt und PLZ passen zusammen, Straße als Text
--                (dieselben 100 Städte, aber über die Tabelle verteilt)
--
-- Beide absichtlich OHNE Index — der Vergleich aus Teil 5 lässt sich damit
-- wiederholen, und die drei Spalten haben drei verschiedene Grade an Vielfalt.
--
-- Kann immer wieder ausgeführt werden: Tabellen werden neu angelegt.
--
--   docker compose exec -T db psql -U kurs -d kurs -f /sql/06_adresse.sql
--
-- Zum schnelleren Ausprobieren die Obergrenze in beiden INSERTs senken
-- (z. B. 100000) — die Zahl steht nur dort.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS adresse;
DROP TABLE IF EXISTS adresse_text;

CREATE TABLE adresse (
    stadt   integer,
    plz     integer,
    strasse integer
);

CREATE TABLE adresse_text (
    stadt   text,
    plz     text,
    strasse text
);

-- 1 Mio. Zeilen. Ganzzahlige Division schneidet ab, sie "rundet" nicht:
--   i / 10000  -> 0..99        100 verschiedene Werte
--   i / 100    -> 0..9999      10.000
--   i          -> 1..1000000   jede Zeile anders
INSERT INTO adresse (stadt, plz, strasse)
SELECT i / 10000, i / 100, i
FROM generate_series(1, 1000000) AS g(i);

-- Dieselben drei Grade an Vielfalt, aber über die ganze Tabelle verteilt
-- statt in Blöcken — die Variante, wenn es auf die Reihenfolge ankommt:
--
-- INSERT INTO adresse (stadt, plz, strasse)
-- SELECT 1 + (i % 100), 1 + (i % 10000), i
-- FROM generate_series(1, 1000000) AS g(i);

-- Ein Vorrat, aus dem die Zeilen auswählen. Weil Stadt und PLZ hier ZUSAMMEN
-- in einer Zeile stehen, passen sie später zusammen — zwei unabhängig
-- gewürfelte Spalten würden auch "Stadt 7 / PLZ 50667" erzeugen.
-- lpad() füllt mit Nullen auf: aus 107 wird '00107'.
CREATE TEMP TABLE stadt_plz AS
SELECT n                                  AS nr,
       'Stadt ' || n                       AS stadt,
       lpad((100 + n * 7)::text, 5, '0')   AS plz
FROM generate_series(1, 100) AS g(n);

-- dieselben 100 Städte, aber in jeder Zeile eine andere: der Auswahlschlüssel
-- 1 + (i % 100) läuft im Kreis, die Werte stehen also nicht in Blöcken
INSERT INTO adresse_text (stadt, plz, strasse)
SELECT s.stadt, s.plz, 'Strasse ' || (1 + (i % 900))
FROM generate_series(1, 1000000) AS g(i)
JOIN stadt_plz s ON s.nr = 1 + (i % 100);

-- Kontrolle: Zeilen und "wie viele verschiedene Werte je Spalte"
SELECT count(*) FROM adresse;
SELECT count(DISTINCT stadt), count(DISTINCT plz), count(DISTINCT strasse) FROM adresse;

SELECT count(*) FROM adresse_text;
SELECT count(DISTINCT stadt), count(DISTINCT plz), count(DISTINCT strasse) FROM adresse_text;

-- Ohne ANALYZE arbeitet der Planer mit Vorgabewerten (Teil 5)
ANALYZE adresse;
ANALYZE adresse_text;

-- Was der Planer jetzt glaubt
SELECT tablename, attname, n_distinct, correlation
FROM pg_stats
WHERE tablename IN ('adresse', 'adresse_text')
ORDER BY tablename, attname;

\d adresse
\d adresse_text
