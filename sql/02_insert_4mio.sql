-- ---------------------------------------------------------------------------
-- 4.000.000 Datensätze in EINEM Befehl
--
-- generate_series() erzeugt die Zahlen 1..4000000 direkt im Server,
-- ohne dass Daten über das Netzwerk geschickt werden müssen.
-- Das ist der schnellste Weg für viele Testdaten.
--
-- Tabelle vorher leeren, damit die Zählung stimmt:
--   TRUNCATE kurs;
-- ---------------------------------------------------------------------------

INSERT INTO kurs (id, name)
SELECT nr, 'Kurs Nr. ' || nr
FROM generate_series(1, 4000000) AS s(nr);

-- Kontrolle
SELECT count(*) FROM kurs;
