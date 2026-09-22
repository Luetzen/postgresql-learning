-- ---------------------------------------------------------------------------
-- Übungstabelle für Teil 7: Transaktionen, Sperren, Isolationsstufen
--
-- Bewusst MIT Primary Key und NOT NULL. Hier geht es nicht um den
-- Indexvergleich (das war Teil 5 mit "kurs"), sondern darum, wie sich zwei
-- Sitzungen verhalten, die gleichzeitig dieselben Zeilen anfassen.
--
-- Kann immer wieder ausgeführt werden: Tabelle wird neu angelegt und mit dem
-- Ausgangszustand gefüllt.
--
--   docker compose exec -T db psql -U kurs -d kurs -f /sql/04_konto.sql
--
-- Hinweis: Hat eine zweite Sitzung gerade eine offene Transaktion auf "konto",
-- wartet das DROP TABLE, bis diese beendet ist. Zwischen zwei Versuchen genügt
-- deshalb ein UPDATE (siehe 7.0).
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS konto;

CREATE TABLE konto (
    id     bigint PRIMARY KEY,
    name   text           NOT NULL,
    betrag numeric(15,2)  NOT NULL
);

INSERT INTO konto (id, name, betrag) VALUES
    (1, 'laurenz', 10000),
    (2, 'sven',    10000);

-- Kontrolle: zwei Zeilen, Summe 20000
SELECT * FROM konto;
SELECT sum(betrag) AS summe FROM konto;
