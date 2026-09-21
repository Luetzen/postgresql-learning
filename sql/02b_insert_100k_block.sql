-- ---------------------------------------------------------------------------
-- EIN Block à 100.000 Datensätze
--
-- Diese Datei wird immer wieder mit demselben Aufruf ausgeführt,
-- nur :offset ändert sich. 40 Blöcke = 4.000.000 Datensätze.
--
-- Aufruf (von Hand):
--   docker compose exec -T db psql -U kurs -d kurs -v offset=0        -f /sql/02b_insert_100k_block.sql
--   docker compose exec -T db psql -U kurs -d kurs -v offset=100000   -f /sql/02b_insert_100k_block.sql
--   ...
--
-- Oder automatisch: scripts/insert-schleife.sh
-- ---------------------------------------------------------------------------

INSERT INTO kurs (id, name)
SELECT :offset + nr, 'Kurs Nr. ' || (:offset + nr)
FROM generate_series(1, 100000) AS s(nr);
