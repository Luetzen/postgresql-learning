-- ---------------------------------------------------------------------------
-- Kurs-Tabelle anlegen
--
-- Bewusst OHNE Primary Key und OHNE Index.
-- Genau darum geht es im Experiment: erst ohne, dann mit.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS kurs;

CREATE TABLE kurs (
    id   integer,
    name text
);

-- Kontrolle: Spalten, Typen, Indizes (hier: keine)
\d kurs
