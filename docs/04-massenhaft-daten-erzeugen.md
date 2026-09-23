# 4 — 4.000.000 Datensätze erzeugen

Ziel: die Tabelle `kurs` in wenigen Minuten mit 4 Millionen Zeilen füllen.

Vorbereitung — Tabelle muss leer sein, sonst zählt man doppelt:

```bash
docker compose exec db psql -U kurs -d kurs -c "TRUNCATE kurs;"
```

Es gibt zwei Wege. **Weg A** macht es in einem Befehl, **Weg B** ist der aus der
Schulung: derselbe Befehl, in einer Schleife, immer wieder.

> Hier geht es um die **Menge**. Wenn die Werte nicht nur hochzählen sollen —
> wenige verschiedene gegen viele, sortiert gegen gemischt —, dann weiter mit
> [Teil 18](18-testdaten-erzeugen.md).

---

## Weg A — ein Befehl, 4 Mio. Zeilen

```sql
\timing on

INSERT INTO kurs (id, name)
SELECT nr, 'Kurs Nr. ' || nr
FROM generate_series(1, 4000000) AS s(nr);
```

Als Datei: [`sql/02_insert_4mio.sql`](../sql/02_insert_4mio.sql)

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/02_insert_4mio.sql
```

`generate_series(1, 4000000)` erzeugt die Zahlen 1 bis 4.000.000 **direkt im
Server**. Es müssen also keine 4 Mio. Zeilen über die Leitung geschickt werden —
das ist der schnellste Weg für Testdaten.

Kontrolle:

```sql
SELECT count(*) FROM kurs;
SELECT * FROM kurs ORDER BY id DESC LIMIT 5;
```

---

## Weg B — derselbe Befehl, 40-mal (der Weg aus der Schulung)

Hier wird **eine** SQL-Datei immer wieder ausgeführt, jeweils mit einem anderen
Startwert. In der Datei steht nur ein `INSERT` — 100.000 Zeilen pro Aufruf,
40 Aufrufe, 4.000.000 Zeilen.

Die Datei [`sql/02b_insert_100k_block.sql`](../sql/02b_insert_100k_block.sql):

```sql
INSERT INTO kurs (id, name)
SELECT :offset + nr, 'Kurs Nr. ' || (:offset + nr)
FROM generate_series(1, 100000) AS s(nr);
```

`:offset` ist eine **psql-Variable**. Sie wird beim Aufruf mit `-v offset=...`
gesetzt. Deshalb ist es *derselbe* Befehl mit *derselben* Datei.

Von Hand, die ersten drei Blöcke:

```bash
docker compose exec -T db psql -U kurs -d kurs -v offset=0      -f /sql/02b_insert_100k_block.sql
docker compose exec -T db psql -U kurs -d kurs -v offset=100000 -f /sql/02b_insert_100k_block.sql
docker compose exec -T db psql -U kurs -d kurs -v offset=200000 -f /sql/02b_insert_100k_block.sql
```

Immer weiter, in 100.000er-Schritten, bis 3.900.000.

Oder automatisch — [`scripts/insert-schleife.sh`](../scripts/insert-schleife.sh):

```bash
./scripts/insert-schleife.sh
```

Das Skript ist genau diese Schleife:

```bash
for ((i = 0; i < 40; i++)); do
    offset=$((i * 100000))
    docker compose exec -T db psql -U kurs -d kurs \
        -v offset="$offset" -f /sql/02b_insert_100k_block.sql
done
```

---

## Zwischendurch nachsehen (während es läuft)

Zweites Terminal aufmachen:

```bash
docker compose exec db psql -U kurs -d kurs -c "SELECT count(*) FROM kurs;"
```

Interessante Frage nebenbei: *warum* wird das mit jeder Zeile ein bisschen
langsamer? Notiere die Zeit des ersten und des letzten Blocks.

---

## Kontrolle am Ende

```sql
SELECT count(*)            FROM kurs;                       -- 4000000
SELECT min(id), max(id)    FROM kurs;                       -- 1, 4000000
SELECT count(DISTINCT id)  FROM kurs;                       -- 4000000, keine Dubletten
```

Auch die Zeit aus Teil A kann man sich noch einmal ansehen — das schaut man sich
am besten im Log des Containers an bzw. mit `\timing on` direkt beim Ausführen.

---

## Aufräumen

```sql
TRUNCATE kurs;     -- schnell, macht die Tabelle leer
```

`TRUNCATE` ist deutlich schneller als `DELETE FROM kurs`, weil es die Tabelle als
Ganzes neu aufsetzt statt Zeile für Zeile zu löschen.
