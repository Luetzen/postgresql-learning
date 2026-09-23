# 18 — Testdaten erzeugen: Werte statt Zähler

Teil 4 füllt die Tabelle `kurs` mit 4 Mio. Zeilen und benutzt dafür genau einen
Trick: `generate_series(1, 4000000)` liefert die Zahlen 1 bis 4.000.000, die
landen dann in der Tabelle. Das ist der schnellste Weg zu **vielen** Zeilen —
aber jede Zeile ist ein Zähler, und in `name` steht dieselbe Zeichenkette mit
einer anderen Zahl.

Für Teil 5 bis 17 reicht das. Sobald es aber darum geht, **wie die Werte
verteilt sind** — wenige verschiedene gegen viele verschiedene, sortiert gegen
gemischt — braucht man Werte, die nicht einfach hochzählen. Dafür ist dieses
Dokument da: der Werkzeugkasten, mit dem man sich Testdaten so baut, wie man sie
für die nächste Frage braucht.

Auf der Tafel stand der Fall aus der Schulung:

```sql
CREATE TABLE adresse (stadt integer, plz integer, strasse integer);

INSERT INTO adresse
SELECT i / 10000, i / 100, i
FROM generate_series(1, 1000000) AS g(i);
```

Dieselben zwei Zeilen als Datei:
[`sql/06_adresse.sql`](../sql/06_adresse.sql) — dort steht zusätzlich die
Text-Variante.

> **Zu den Zahlen:** hier steht kein einziger Messwert. Wie lange ein `INSERT`
> dauert, wie groß die Tabelle wird und welchen Plan der Planer wählt, hängt an
> deinem Rechner — das wird gemessen (Teil 16), nicht abgeschrieben. Was hier
> steht, ist Arithmetik und Dokumentation.

---

## 18.0 Der Werkzeugkasten

| Werkzeug | erzeugt | offizielle Doku |
|----------|---------|-----------------|
| `generate_series(a, b [, s])` | ganze Zahlen, auch Zeitstempel | [functions-srf](https://www.postgresql.org/docs/18/functions-srf.html) |
| `random()`, `random(a, b)`, `random_normal()` | Zufallszahlen | [functions-math](https://www.postgresql.org/docs/18/functions-math.html) |
| `/` (ganzzahlig), `%` (Modulo) | gleichmäßig verteilte Werte aus dem Zähler | [functions-math](https://www.postgresql.org/docs/18/functions-math.html) |
| `ARRAY[…]` + Index | Werte aus einer festen Liste | [functions-array](https://www.postgresql.org/docs/18/functions-array.html) |
| `md5()`, `substr()`, `repeat()`, `lpad()` | Text, aus dem Zähler abgeleitet | [functions-string](https://www.postgresql.org/docs/18/functions-string.html) |
| `gen_random_uuid()`, `uuidv4()`, `uuidv7()` | UUIDs | [functions-uuid](https://www.postgresql.org/docs/18/functions-uuid.html) |
| `CREATE TABLE … AS SELECT` | Tabelle direkt aus einer Abfrage | [sql-createtableas](https://www.postgresql.org/docs/18/sql-createtableas.html) |
| `pgbench -i` | fertige Testdatenbank in Standardform | [pgbench](https://www.postgresql.org/docs/18/pgbench.html) |
| `COPY … FROM` / `\copy` | Daten aus einer CSV-Datei | [sql-copy](https://www.postgresql.org/docs/18/sql-copy.html) |

Die Regel dahinter: **erzeugt wird im Server.** Ein `INSERT … SELECT` mit einer
Serie schickt nicht eine Million Zeilen über die Leitung, sondern eine
Anweisung — das ist der Unterschied zu einer Schleife im Skript (Teil 4, Weg B).

---

## 18.1 `generate_series`: mehr als hochzählen

Die Serie kann Schrittweite, und sie kann Zeit:

```sql
-- Schrittweite: 0, 2, 4, … 20
SELECT * FROM generate_series(0, 20, 2);

-- Zeitstempel statt Zahlen: jede Stunde eines Tages
SELECT * FROM generate_series('2026-01-01 00:00'::timestamp,
                              '2026-01-01 23:00'::timestamp,
                              interval '1 hour');

-- ganze Kalendertage
SELECT * FROM generate_series('2026-01-01'::timestamp,
                              '2026-12-31'::timestamp,
                              interval '1 day');
```

Und man kann zwei Serien **kreuzen** — daraus wird eine Tabelle mit allen
Kombinationen:

```sql
-- 100 Städte × 100 PLZ = 10.000 Paare, in einer Anweisung
SELECT s.nr AS stadt, p.nr AS plz
FROM generate_series(1, 100) AS s(nr)
CROSS JOIN generate_series(1, 100) AS p(nr);
```

Solche gekreuzten Serien sind der Vorrat, aus dem 18.5 und 18.6 dann schöpfen —
und genau das macht [`sql/05_join_schema.sql`](../sql/05_join_schema.sql)
(„kleine Seite × große Seite", Teil 17).

---

## 18.2 `random()` und seine Verwandten

| Aufruf | Ergebnis |
|--------|----------|
| `random()` | `double precision`, `0.0 <= x < 1.0` |
| `random(1, 10000)` | ganze Zahl, `1 <= x <= 10000` (ab PostgreSQL 16) |
| `random_normal(1.75, 0.1)` | Normalverteilung um 1.75 mit Streuung 0.1 |
| `setseed(0.42)` | legt den Zufallskeim der Sitzung fest, ohne Rückgabe |

Aus dem alten `random()` macht man so eine ganze Zahl:

```sql
SELECT 1 + floor(random() * 100)::int;    -- 1 .. 100
```

Das `floor(…)::int` ist kein Zierrat: `random()` liefert einen Komma-Wert, und
in einer `integer`-Spalte wird der **gerundet**, nicht abgeschnitten. Prüf es
selbst: `SELECT 1.9::int, 1.4::int;`. Wer die Häufigkeiten später als gleichmäßig
annimmt, rechnet sonst mit einer Verteilung, die nicht in der Tabelle steht.

Drei Dinge, die man wissen muss, bevor man `random()` in Testdaten benutzt:

- **Es ist nicht wiederholbar.** Zwei Läufe ergeben zwei verschiedene Tabellen,
  und damit sind zwei Messungen nicht mehr vergleichbar. `setseed(…)` in
  derselben Sitzung macht die Folge wiederholbar — danach liefert dieselbe
  Anweisung dieselben Werte.
- **Es ist `volatile`.** In `SELECT random() FROM generate_series(…)` wird es
  pro erzeugter Zeile ausgewertet. Steht es aber als `(SELECT random())` da,
  kann der Planer daraus eine einmalige Auswertung machen — dann haben alle
  Zeilen denselben Wert. Mit `EXPLAIN` nachsehen (Teil 16).
- **In einem Index-Ausdruck ist es verboten.** `CREATE INDEX … ON t
  (floor(random()*10))` scheitert mit „functions in index expression must be
  marked IMMUTABLE" — ein Index würde ja gespeicherte Werte liefern, das
  Ergebnis wäre falsch.

---

## 18.3 Gleichmäßig statt gewürfelt: den Zähler umrechnen

Das Beispiel von der Tafel kommt ganz ohne `random()` aus:

```sql
i / 10000      -- 0 … 99          100 verschiedene Werte
i / 100        -- 0 … 9999        10.000
i              -- 1 … 1000000     in jeder Zeile anders
```

`/` ist bei `integer` eine **ganzzahlige Division**: der Rest fällt weg. Die drei
Spalten haben also drei verschiedene Grade an Vielfalt — `stadt` kennt nur 100
Werte, `plz` 10.000, `strasse` jeden Wert genau einmal. Das ist genau der
Unterschied, an dem ein Index-Scan sich entscheidet (Teil 5, Teil 11), und der
Grund, warum die Tabelle so gebaut wurde.

Aber Achtung: `i / 10000` ist **monoton**. Alle Zeilen mit Stadt 0 liegen
hintereinander, dann alle mit Stadt 1 und so weiter. Wer dieselben Werte
*gemischt* haben will, nimmt den Rest statt des Quotienten:

```sql
1 + (i % 100)      -- 1,2,…,100,1,2,…   dieselben 100 Städte
1 + (i % 10000)    -- dieselben 10.000 PLZ
i                  -- bleibt eindeutig
```

Beide Fassungen haben dieselbe Anzahl verschiedener Werte — nur die
Reihenfolge unterscheidet sich. Der Unterschied steht in `pg_stats.correlation`
(18.10): bei der ersten Fassung liegen die Werte in derselben Reihenfolge wie
die Zeilen auf der Platte, bei der zweiten nicht. Genau daran hängt, ob ein
Index-Scan dieselben Seiten immer wieder trifft oder über die ganze Tabelle
streut.

Der Vorteil von Rechnen statt Würfeln ist, dass die **Häufigkeiten exakt** sind:
jeder der 100 Städte-Werte kommt gleich oft vor. Bei `random()` gilt das nur
*näherungsweise* — das ist nicht falsch, aber es bedeutet, dass die Statistik,
die der Planer nach einem `ANALYZE` liest, bei jedem Lauf ein bisschen anders
aussieht.

---

## 18.4 Werte aus einer Liste

Wenn die Werte „ausgesucht" aussehen sollen, nimmt man ein Feld:

```sql
SELECT (ARRAY['Köln', 'Essen', 'Bochum', 'Dortmund'])[1 + (i % 4)]
FROM generate_series(0, 7) AS g(i);
```

⚠️ Der Index eines Feldes beginnt bei **1**, nicht bei 0. `[i % 4]` greift bei
`i = 0` auf Element 0 zu, und das ist kein Fehler, sondern **NULL** — die Zeile
bekommt still keine Stadt. Prüf es einmal selbst:
`SELECT (ARRAY['a','b'])[0], (ARRAY['a','b'])[1];`

---

## 18.5 Zwei Spalten, die zusammenpassen

Zwei unabhängig ausgewürfelte Spalten erzeugen auch unmögliche Zeilen: „Essen /
50667". Wenn die Spalten zusammen Sinn ergeben sollen, braucht man einen Vorrat,
in dem sie als **Paar** stehen:

```sql
CREATE TEMP TABLE vorrat (nr integer, stadt text, plz text);

INSERT INTO vorrat VALUES
    (1, 'Köln',     '50667'),
    (2, 'Essen',    '45127'),
    (3, 'Bochum',   '44787'),
    (4, 'Dortmund', '44135');

INSERT INTO adresse_text (stadt, plz, strasse)
SELECT v.stadt, v.plz, 'Strasse ' || (1 + (i % 900))
FROM generate_series(1, 1000000) AS g(i)
JOIN vorrat v ON v.nr = 1 + (i % 4);
```

Der Schlüssel `1 + (i % 4)` läuft im Kreis über die Vorratszeilen; weil Stadt und
PLZ darin zusammen stehen, passen sie auch in `adresse_text` zusammen (die
Tabelle kommt aus [`sql/06_adresse.sql`](../sql/06_adresse.sql)). Mit vier Werten
hat man vier verschiedene Städte — dieselbe Konstruktion mit
`generate_series(1, 100)` als Vorrat steht in der Datei.

`CREATE TEMP TABLE` heißt: die Tabelle verschwindet mit dem Ende der Sitzung.
Für einen Vorrat, den man nur zum Füllen braucht, ist das genau richtig.

---

## 18.6 Text erzeugen, wenn es nur Text sein muss

```sql
SELECT md5(i::text)                      -- 32 Hexzeichen
     , substr(md5(i::text), 1, 8)        -- kurz
     , repeat('x', 1 + (i % 40))         -- unterschiedlich lang
     , upper(substr(md5(i::text), 1, 6)) -- Großbuchstaben
FROM generate_series(1, 5) AS g(i);
```

`md5(i::text)` ist **deterministisch**: dieselbe Zahl ergibt denselben Text, in
jedem Lauf. Das ist für Testdaten oft besser als `random()`, weil sich die
Tabelle wiederholen lässt.

Und für die PLZ gibt es `lpad()` — es füllt mit einem Zeichen auf:

```sql
SELECT lpad('107', 5, '0');    -- '00107'
```

Das ist der Punkt, an dem eine PLZ aufhört, eine Zahl zu sein (18.12).

---

## 18.7 Deterministisch „zufällig": `md5()` als Hash

Oft will man beides: Werte, die *nicht* mit dem Zähler laufen (wie `i % 100`),
aber bei jedem Lauf **dieselben**. Dafür nimmt man den Hash des Zählers:

```sql
SELECT (('x' || substr(md5(i::text), 1, 8))::bit(32)::bigint % 10000)::int
FROM generate_series(1, 5) AS g(i);
```

Was hier passiert, Schritt für Schritt:

1. `md5(i::text)` → 32 Hexziffern, also 128 Bit.
2. `substr(…, 1, 8)` → die ersten 8 Hexziffern, also 32 Bit.
3. `'x' || …` → daraus wird ein Bit-String-Literal in Hex-Schreibweise.
4. `::bit(32)::bigint` → eine Zahl zwischen 0 und 4294967295.
5. `% 10000` → in den gewünschten Bereich gebracht.

Der Umweg über `bigint` ist Absicht: `bit(32)::integer` scheitert bei Werten über
2³¹−1. Wer direkt einen `integer` will, nimmt sieben Hexziffern
(28 Bit, `substr(…, 1, 7)`) — dann passt es immer.

Solche Werte sind innerhalb der Tabelle praktisch unkorreliert mit dem Zähler,
also über alle Seiten verteilt — genau die Gegenprobe zu 18.3.

---

## 18.8 UUIDs als Schlüssel

```sql
SELECT gen_random_uuid();    -- seit PostgreSQL 13 eingebaut, kein Zusatzmodul
SELECT uuidv4();             -- dasselbe, der neue Name
SELECT uuidv7();             -- ab PostgreSQL 18: mit Zeitstempel
```

Wichtig ist nicht die Funktion, sondern die **Reihenfolge**: `uuidv7()` enthält
die Zeit und sortiert sich deshalb ungefähr wie eine Nummer, die hochzählt —
neue Zeilen landen am Ende des Index. `uuidv4()` würfelt dagegen quer über den
ganzen Wertebereich, und ein Index über so eine Spalte arbeitet entsprechend
anders. Das ist derselbe Unterschied wie in 18.3, nur auf einem anderen Typ: der
Testfall für „verteilter Schlüssel gegen wachsenden Schlüssel".

Doku: [UUID Functions](https://www.postgresql.org/docs/18/functions-uuid.html)

---

## 18.9 Wenn es fertig sein soll: `pgbench` und CSV

Nicht jeder Testdatensatz muss aus einer eigenen Abfrage kommen.

**`pgbench`** bringt einen eigenen Generator mit. `-i` legt seine Tabellen an
und füllt sie, `-s` (scale factor) bestimmt die Menge:

```bash
docker compose exec db pgbench -i -s 10 -U kurs kurs
```

⚠️ `-i` löscht und erstellt dabei die Tabellen `pgbench_accounts`,
`pgbench_branches`, `pgbench_history` und `pgbench_tellers`. Das ist ein
eigenes, in sich stimmiges Schema — brauchbar, um einen Server unter Last zu
sehen, nicht als Ersatz für `kurs`. Wie viele Zeilen ein Skalierungsfaktor
ergibt, steht in der [pgbench-Doku](https://www.postgresql.org/docs/18/pgbench.html).

**CSV** laden ist der Weg von außen:

```sql
COPY adresse FROM '/sql/adresse.csv' WITH (FORMAT csv, HEADER true);
```

Ein Pfad, den der Server nicht sieht, lässt sich nicht laden — hier läuft auch
`psql` im Container, also gilt für `\copy` dasselbe (das Repo hängt `./sql`
nach `/sql` hinein, siehe `compose.yaml`). Ein Generator auf dem Rechner, der
CSV nach `sql/` schreibt, passt also gut zusammen. Für Testdaten ohne Server
gibt es auch Werkzeuge außerhalb von PostgreSQL (Faker-Bibliotheken, Mockaroo
& Co.) — die erzeugen CSV, und der Weg von dort in die Datenbank ist genau
dieser `COPY`.

---

## 18.10 Nachsehen, was man erzeugt hat

Erst zählen, dann `ANALYZE` — **ohne** `ANALYZE` arbeitet der Planer mit
Vorgabewerten, und jeder Plan wäre eine Aussage über die Vorgaben, nicht über
die Daten (Teil 5):

```sql
SELECT count(*) FROM adresse;
SELECT count(DISTINCT stadt), count(DISTINCT plz), count(DISTINCT strasse)
FROM adresse;

ANALYZE adresse;
```

Was der Planer danach glaubt, steht in `pg_stats`
([view-pg-stats](https://www.postgresql.org/docs/18/view-pg-stats.html)):

```sql
SELECT attname, n_distinct, correlation, most_common_vals, histogram_bounds
FROM pg_stats
WHERE schemaname = 'public' AND tablename = 'adresse'
ORDER BY attname;
```

- **`n_distinct`** ist die geschätzte Zahl verschiedener Werte. Ein **negativer**
  Wert heißt nicht „minus so viele", sondern *Anteil der Zeilen*: `-1` bedeutet
  „jede Zeile verschieden".
- **`correlation`** sagt, ob die Werte in derselben Reihenfolge liegen wie die
  Zeilen auf der Platte — die Antwort auf die Frage aus 18.3.
- **`most_common_vals`** ist bei den Text-Spalten der Vorrat aus 18.5. Die
  Statistik kennt ihn, weil sie die häufigsten Werte einzeln mitschreibt.

Und wenn man nur mal hineinsehen will — nicht die ersten, sondern zehn beliebige
Zeilen:

```sql
SELECT * FROM adresse TABLESAMPLE SYSTEM (1) LIMIT 10;
```

`ORDER BY random() LIMIT 10` tut das nicht: das sortiert die ganze Tabelle.
Doku: [TABLESAMPLE](https://www.postgresql.org/docs/18/sql-select.html#SQL-FROM)

---

## 18.11 Aufräumen

```sql
TRUNCATE adresse;              -- leer, Tabelle bleibt
DELETE FROM adresse;           -- dasselbe, nur Zeile für Zeile (langsamer)
DROP TABLE adresse;            -- Tabelle weg
```

Wie in Teil 4: ohne `TRUNCATE` oder `DROP` davor verdoppelt ein zweites `INSERT`
die Zeilen — die Zählungen stimmen dann nicht mehr.

---

## 18.12 Fragen an dich selbst

Das Beispiel von der Tafel hat drei `integer`-Spalten, die `stadt`, `plz` und
`strasse` heißen. Zwei davon sind Zahlen, die gar keine sind:

- Was ändert sich, wenn in `stadt` und `strasse` **Text** steht — für den Plan,
  für die Größe der Tabelle, für das, was man mit der Spalte machen kann? In
  `sql/06_adresse.sql` steht die Text-Variante; vergleich sie einmal.
- Eine **PLZ ist keine Zahl**: `01896` fängt mit einer Null an, und `WHERE plz
  LIKE '01%'` geht auf `integer` gar nicht. Spricht etwas für `text` — und was
  spricht für `integer`?
- Was ist der Unterschied zwischen den beiden `INSERT`s in `sql/06_adresse.sql`
  in `pg_stats.correlation` — und was macht der Planer daraus? (Beides mal mit
  einem Index auf `stadt` ausprobieren, Teil 5.)
- Warum stehen in `adresse` genau 100 verschiedene Städte, wenn man
  `generate_series(1, 1000000)` benutzt? Ändere die Division und sag vorher,
  welche Zahl herauskommt.

---

## Doku dazu

- [`generate_series`](https://www.postgresql.org/docs/18/functions-srf.html)
- [Mathematik: `random()`, `random(a,b)`, `random_normal()`, `setseed()`](https://www.postgresql.org/docs/18/functions-math.html)
- [Felder (`ARRAY`)](https://www.postgresql.org/docs/18/functions-array.html)
- [Textfunktionen: `md5()`, `substr()`, `repeat()`, `lpad()`](https://www.postgresql.org/docs/18/functions-string.html)
- [UUIDs: `gen_random_uuid()`, `uuidv4()`, `uuidv7()`](https://www.postgresql.org/docs/18/functions-uuid.html)
- [`CREATE TABLE … AS`](https://www.postgresql.org/docs/18/sql-createtableas.html)
- [`COPY`](https://www.postgresql.org/docs/18/sql-copy.html)
- [`pgbench`](https://www.postgresql.org/docs/18/pgbench.html)
- [`pg_stats`](https://www.postgresql.org/docs/18/view-pg-stats.html)
