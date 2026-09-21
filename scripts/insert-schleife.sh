#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 40 × 100.000 = 4.000.000 Datensätze
#
# Immer derselbe Befehl, immer dieselbe SQL-Datei — nur der Offset ändert sich.
# Genau wie in der Schulung: ein Command aus einer Datei, in Schleife.
#
# Voraussetzung: der Container läuft (docker compose up -d)
# Aufruf:        ./scripts/insert-schleife.sh
# ---------------------------------------------------------------------------
set -euo pipefail

ROWS=100000
BLOCKS=40

for ((i = 0; i < BLOCKS; i++)); do
    offset=$((i * ROWS))
    echo "-> Block $((i + 1))/$BLOCKS  (offset $offset)"
    docker compose exec -T db psql -U kurs -d kurs \
        -v offset="$offset" \
        -f /sql/02b_insert_100k_block.sql
done

echo "-> Fertig. Kontrolle:"
docker compose exec -T db psql -U kurs -d kurs -c "SELECT count(*) FROM kurs;"
