# 3 — Die Kurs-Tabelle anlegen

Die Tabelle heißt `kurs` und hat genau zwei Spalten: `id` und `name`.

Bewusst **ohne** Primary Key und **ohne** Index. Genau darum geht es später im
Experiment: erst ohne, dann mit.

---

## 3.1 Verbinden

```bash
docker compose exec db psql -U kurs -d kurs
```

## 3.2 Die Tabelle

```sql
CREATE TABLE kurs (
    id   integer,
    name text
);
```

Fertig ist die Datei [`sql/01_schema.sql`](../sql/01_schema.sql), die man auch
so ausführen kann:

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/01_schema.sql
```

(`-T` schaltet das Terminal ab — nötig, wenn man `docker compose exec` in einem
Skript benutzt.)

## 3.3 Kontrollieren

```sql
\dt          -- tabelle taucht auf
\d kurs      -- spalten und typen
```

Die Ausgabe zeigt:

```
 Column |  Type   | Collation | Nullable | Default
--------+---------+-----------+----------+---------
 id     | integer |           |          |
 name   | text    |           |          |
```

Genau das ist gewollt: keine Einschränkung, kein Index, kein `NOT NULL`.

Die letzten Zeilen der Ausgabe sind der wichtige Teil:

```
Indexes:
    "..." PRIMARY KEY, ...
```

Fehlt hier etwas, gibt es auch keinen Index — und die Datenbank muss bei jeder
Suche die ganze Tabelle durchlesen. Das messen wir in Teil 5.

## 3.4 Warum `integer` und warum `text`?

- `integer` = 4 Byte, reicht bis 2.147.483.647. Für `id` völlig aus und spart
  Platz gegenüber `bigint`.
- `text` ist in PostgreSQL die normale Zeichenkette ohne Längenlimit.
  `varchar(50)` bräuchte man nur, wenn man eine Länge erzwingen *will* — ein
  Längenlimit ist in PostgreSQL kein Geschwindigkeitsvorteil.

## 3.5 Erste Zeile von Hand

```sql
INSERT INTO kurs (id, name) VALUES (1, 'Mein erster Kurs');

SELECT * FROM kurs;
```

## 3.6 Tabelle neu anfangen

```sql
DROP TABLE kurs;
```

Oder: die Datei `01_schema.sql` enthält oben `DROP TABLE IF EXISTS kurs;` — sie
kann also immer wieder ausgeführt werden und macht die Tabelle frisch.
