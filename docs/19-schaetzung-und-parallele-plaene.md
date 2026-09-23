# 19 — Vom falschen Schätzwert zum parallelen Plan

Deine zwei Befehle auf `adresse` (Teil 18):

```sql
ANALYZE adresse;

EXPLAIN (ANALYZE) SELECT * FROM adresse WHERE stadt = 1 AND plz = 100;
```

Und die Antwort des Planers:

```
Gather  (cost=1000.00..12656.10 rows=1 width=12) (actual time=8.660..134.157 rows=100.00 loops=1)
  Workers Planned: 2
  Workers Launched: 2
  Buffers: shared hit=5406
  ->  Parallel Seq Scan on adresse  (cost=0.00..11656.00 rows=1 width=12) (actual time=78.760..118.702 rows=33.33 loops=1)
        Filter: ((stadt = 1) AND (plz = 100))
        Rows Removed by Filter: 333300
        Buffers: shared hit=5406
Planning:
  Buffers: shared hit=15
Planning Time: 0.283 ms
Execution Time: 134.218 ms
```

Teil 16 hat gezeigt, wie man so einen Plan *liest*. Hier steht, was in **diesem**
Plan steckt: eine Schätzung, die um den Faktor 100 daneben liegt, und ein
Knoten, der nicht nur Zahlen liefert, sondern eine eigene Rechnung hat.

> **Zu den Zahlen:** der Plan oben ist **deiner**, abgeschrieben von deinem
> Bildschirm. Alles andere in diesem Dokument ist Arithmetik oder Dokumentation —
> nichts davon ist gemessen, und nichts davon darfst du abschreiben.

---

## 19.0 Die Zeilen einzeln

| Zeile | was sie sagt |
|-------|--------------|
| `Gather` | der Knoten, der die Worker einsammelt — nicht der, der liest |
| `cost=1000.00..12656.10` | die erste Zahl ist **nicht** null: darin steckt der Preis fürs Parallelschalten (19.3) |
| `rows=1` | die **Schätzung** — hier steht der Fehler (19.1) |
| `actual … rows=100.00` | was tatsächlich herauskam: Faktor 100 daneben (16.4) |
| `width=12` | Zeilenbreite in Byte: drei `integer` à 4 Byte |
| `Workers Planned: 2` | wie viele Worker der Planer **einplanen wollte** |
| `Workers Launched: 2` | wie viele **wirklich gestartet** sind |
| `Buffers: shared hit=5406` | gelesen wurde aus dem Cache, nichts von der Platte |
| `-> Parallel Seq Scan on adresse` | die eigentliche Arbeit: die Tabelle wird durchgesehen, aufgeteilt auf die Prozesse |
| `Filter: ((stadt = 1) AND (plz = 100))` | was pro Zeile geprüft wird |
| `Rows Removed by Filter: 333300` | wie viele Zeilen der Filter **weggeworfen** hat (16.4c) |

Drei Zeilen darin sind eine eigene Erklärung wert — und sie hängen zusammen:
die Schätzung, der `Gather`, und die 333300.

---

## 19.1 `rows=1` gegen `rows=100` — die Annahme dahinter

Der Planer schätzt eine Bedingung über den **Anteil**, den sie übrig lässt:
`stadt = 1` betrifft eines von 100 möglichen Ergebnissen, `plz = 100` eines von
10.000. Diese zwei Anteile **multipliziert** er:

```
1/100  ×  1/10.000  =  1/1.000.000
1.000.000 Zeilen × 1/1.000.000  =  1  Zeile
```

Da steht die `1` aus dem Plan. Und die ist falsch — es sind 100 Zeilen. Prüf
zuerst, dass die **einzelen** Schätzungen tadellos sind:

```sql
EXPLAIN (ANALYZE) SELECT * FROM adresse WHERE stadt = 1;
```

Erwartung: `rows=10000` geschätzt, und auch tatsächlich 10.000 — weil deine
Daten durch Division entstanden sind (18.3) und damit **exakt** gleichmäßig
verteilt: 100 Städte, also ein Hundertstel von 1.000.000. Die Statistik ist hier
nicht ungenau. Sie ist genau richtig.

Falsch ist nur der **Schluss von zwei richtigen Zahlen auf die Kombination.** Der
Planer nimmt an, die beiden Bedingungen träfen **unabhängig** voneinander zu —
wie zwei Würfel. Bei deinen Daten stimmt das nicht, und man kann es nachrechnen:

```
plz   = i / 100      →  plz = 100  heißt  i zwischen 10000 und 10099
stadt = i / 10000    →  in diesem Bereich ist stadt IMMER 1
```

`plz = 100` legt `stadt = 1` also schon fest. Die zweite Bedingung fügt nichts
hinzu, und die echte Auswahl ist 1/10.000 → 100 Zeilen. Zwei Bedingungen, die in
Wahrheit **eine** sind.

Genau das ist der Fall, den 16.4 als zweite Ursache nennt — „die Daten sind
korreliert (z. B. Postleitzahl und Ort in derselben Tabelle)". Hier ist er
wörtlich eingetreten.

Und weil eine falsche Schätzung erst dann schlimm wird, wenn eine Entscheidung
daran hängt (16.4): **dieser** Plan war trotzdem in Ordnung. Ein `Seq Scan` über
1 Mio. Zeilen ist für ein Hundertstel der Tabelle eine vernünftige Antwort. Die
Schätzung wird dort gefährlich, wo sie zu einem `Nested Loop` führt, der mit
10.000 Zeilen gerechnet hätte und 1.000.000 bekommt (Teil 17).

---

## 19.2 Was dagegen hilft: eine Statistik über zwei Spalten

`ANALYZE` kann den Fall nicht reparieren: es misst **jede Spalte für sich**, und
beide Messungen sind ja richtig. Was fehlt, ist eine Messung über die
**Kombination**. Die gibt es als eigenes Objekt:

```sql
CREATE STATISTICS adresse_stadt_plz (dependencies, ndistinct)
    ON stadt, plz FROM adresse;

ANALYZE adresse;      -- jetzt wird sie gemessen
```

Zwei Arten von Wissen, und beide werden hier gebraucht:

| Art | was sie misst | wofür |
|-----|---------------|-------|
| `dependencies` | dass `plz` die `stadt` **festlegt** (funktionale Abhängigkeit) | die Schätzung der `WHERE`-Klausel aus 19.1 |
| `ndistinct` | wie viele **Kombinationen** es wirklich gibt, nicht wie viele es geben könnte | die Schätzung einer Gruppierung aus 19.4 |

Danach derselbe `EXPLAIN` wie oben. Zwei Dinge sind zu erwarten:

- **`rows` wandert auf ~100.** Nicht, weil die Spalten weniger verschieden
  wären, sondern weil der Planer jetzt weiß, dass die eine Bedingung die andere
  schon enthält.
- **Der `cost` steigt**, obwohl an der Arbeit selbst nichts anders wird. Ein
  `Seq Scan` bezahlt dafür, dass er Zeilen *liest*, nicht dafür, dass er welche
  *weitergibt* (16.4b, Lehre 1). Die bessere Schätzung wirkt erst dort, wo über
  ihr eine Entscheidung hängt.

Nachsehen kann man sich das Objekt in den Katalogen
([catalog-pg-statistic-ext](https://www.postgresql.org/docs/18/catalog-pg-statistic-ext.html)):

```sql
SELECT stxname, stxkind FROM pg_statistic_ext;

SELECT statistics_name, attnames, kinds, n_distinct
FROM pg_stats_ext
WHERE statistics_name = 'adresse_stadt_plz';
```

Drei Randbedingungen, die man kennen muss:

- Die Statistik sammelt **nichts** von selbst — erst das `ANALYZE` *nach* dem
  `CREATE STATISTICS` füllt sie.
- Sie wird nur benutzt, wenn die Abfrage **dieselben Spalten** in Bedingungen
  hat. Für `stadt` allein nützt sie nichts.
- In einer **Join**-Bedingung greift sie gar nicht (16.4b, Lehre 2, laut Doku).

Wegräumen und den Unterschied ansehen:

```sql
DROP STATISTICS adresse_stadt_plz;
ANALYZE adresse;      -- die Spaltenstatistik bleibt, die über die Kombination geht
```

Doku: [CREATE STATISTICS](https://www.postgresql.org/docs/18/sql-createstatistics.html)

---

## 19.3 Der `Gather` und wem die Zahlen darin gehören

### Warum überhaupt parallel?

Weil die Tabelle groß genug ist. Die Schwellen und Preise stehen als
Einstellungen da (Teil 14) — vier davon erklären diesen Plan komplett:

```sql
SHOW max_parallel_workers_per_gather;   -- wie viele Worker höchstens
SHOW parallel_setup_cost;               -- was das Parallelschalten kostet
SHOW parallel_tuple_cost;               -- was jede weitergegebene Zeile kostet
SHOW min_parallel_table_scan_size;      -- ab welcher Tabellengröße es sich lohnt
SHOW parallel_leader_participation;     -- scannt der Leader mit?

SELECT pg_size_pretty(pg_relation_size('adresse'));
```

`Workers Planned: 2` ist genau `max_parallel_workers_per_gather`. Und die erste
Kostenzahl des `Gather` — die `1000.00`, die nicht nach „nichts" aussieht —
rechnet sich aus dem Kind-Knoten darunter:

```
Gather              12656.10
Parallel Seq Scan - 11656.00
                  = 1000.10
```

Also `parallel_setup_cost` plus `parallel_tuple_cost` mal eine Zeile
(0,1 × 1 = 0,1). Verglichen mit `SHOW parallel_setup_cost;`: **dieselbe Zahl.**
Der Startpreis der Parallelität ist eine Einstellung, keine Messung.

### Die Zahlen im Knoten gehören einem Prozess

Und jetzt die Zeile, die am meisten Verwirrung stiftet:

```
rows=33.33            Rows Removed by Filter: 333300
```

Geschätzt bzw. gezählt wurden **100** Zeilen in der ganzen Tabelle — aber
`33.33`? Weil der `Parallel Seq Scan` **von mehreren Prozessen** ausgeführt
wird und jede Zahl in so einem Knoten der **Anteil eines einzelnen Prozesses**
ist. Nachrechnen lässt sich das mit deinen eigenen Zahlen:

```
33,33  +  333300  =  333333,33      was ein Prozess durchgesehen hat
333333,33 × 3     =  1000000        die Tabelle hat 1.000.000 Zeilen
```

Es sind **drei** Prozesse: zwei Worker (`Workers Launched: 2`) und der Leader,
der mitliest (`parallel_leader_participation`). Deshalb sind es Drittel und
nicht Hälften. Das ist die parallele Fassung der `loops`-Falle aus 16.3: `loops`
steht hier auf `1`, und trotzdem wurde dreimal gearbeitet. Die Gesamtzahl steht
allein in der `rows`-Zeile des `Gather` darüber.

### Die Blöcke nicht doppelt zählen

`Buffers: shared hit=5406` steht **zweimal** im Plan — am `Gather` und am
`Parallel Seq Scan`. Es sind nicht 10.812 Blöcke: die Zeile am `Gather` fasst
zusammen, was unter ihm gelesen wurde. Die Frage ist nicht „was steht wo",
sondern „welcher Knoten hat sie gelesen" — und das ist der `Seq Scan`.

### `Workers Planned` gegen `Workers Launched`

Geplant heißt entschieden, gestartet heißt passiert. Die beiden Zahlen gehen
auseinander, wenn gerade keine Worker mehr frei sind — probier es aus, indem du
in einem zweiten Fenster Sitzungen laufen lässt, die selbst parallel arbeiten.
Das ist die Stelle, an der `max_parallel_workers` und `max_worker_processes`
zuschlagen, nicht der Planer.

### Und zum Vergleich: einmal ohne

```sql
SET max_parallel_workers_per_gather = 0;

EXPLAIN (ANALYZE) SELECT * FROM adresse WHERE stadt = 1 AND plz = 100;

RESET max_parallel_workers_per_gather;
```

Dann bleiben `Gather`, `Workers …` und die Drittel-Zahlen weg, und derselbe
`Seq Scan` steht allein da. Zwei Dinge dabei beachten:

- Nach 16.8b ist **ein** Lauf pro Seite kein Vergleich. Mehrere Läufe, oder
  `TIMING OFF` und die Blöcke vergleichen — die sind stabiler als Millisekunden.
- Die geschätzte `rows` bleibt dieselbe. Die Parallelität ändert die Schätzung
  nicht, nur den Weg.

Wer sortierte Ausgabe aus Workern braucht, bekommt statt `Gather` ein
`Gather Merge`; `Gather` selbst sagt über die Reihenfolge nichts zu.

Doku: [Using EXPLAIN](https://www.postgresql.org/docs/18/using-explain.html)
und die Parallel-Einstellungen in
[runtime-config-query](https://www.postgresql.org/docs/18/runtime-config-query.html)

---

## 19.4 Dein nächster Befehl: `GROUP BY stadt, plz`

```sql
EXPLAIN (ANALYZE) SELECT * FROM adresse GROUP BY stadt, plz;
```

Dazu drei Dinge.

**Erstens wird der Befehl so nicht laufen.** `SELECT *` verlangt `strasse`, und
`strasse` steht nicht in der `GROUP BY`-Klausel — es gibt eine
`GROUP BY`-Verletzung, nicht etwa ein Ergebnis mit doppelten Zeilen. Was ist
`strasse` in einer Zeile, die 100 Zeilen zusammenfasst? Genau die Frage stellt
der Server.

**Zweitens lohnt der Vergleich mit 19.1.** Mit `stadt, plz, count(*)` gruppiert
der Server nach zwei Spalten, und der Planer schätzt die Zahl der **Gruppen** aus
denselben `n_distinct`-Werten, wieder multipliziert: 100 × 10.000 — gedeckelt
auf die Zeilen, die hineingehen. Sieh nach, was bei dir dasteht und was
tatsächlich herauskommt. Der Fehler ist derselbe wie oben, nur eine Etage höher:
die Werte sind nicht unabhängig, sondern `plz` bestimmt `stadt`.

Das ist die Stelle, an der `ndistinct` aus 19.2 gebraucht wird — sag vorher, wie
viele Gruppen es sein müssen, und rechne es aus den beiden `n_distinct`-Werten
*rückwärts*. Wenn beides zusammenpasst, hast du das Modell verstanden.

**Drittens: schau auf den Knoten.** Ein `HashAggregate` mit einer `Memory
Usage`-Zeile (16.6) ist der Normalfall. Ob die Gruppentabelle in `work_mem`
passt oder ob sie auf die Platte ausgelagert wird, steht in derselben Zeile —
und die Zahl der Gruppen, die der Planer *erwartet*, entscheidet mit, wie groß
er den Speicher ansetzt.

---

## 19.5 Was hier gemessen gehört

In [`06-kurs-notizen.md`](06-kurs-notizen.md) steht dafür eine eigene Tabelle.
Die Fragen dazu:

- `stadt = 1` allein gegen `stadt = 1 AND plz = 100`: geschätzte Zeilen und
  Ausführungszeit — wie groß ist der Abstand jeweils?
- Dasselbe noch einmal nach `CREATE STATISTICS … (dependencies)` — was ändert
  sich an `rows`, was an `cost`, was an der Zeit?
- `SELECT stadt, plz, count(*) … GROUP BY stadt, plz`: geschätzte gegen
  tatsächliche Gruppenzahl, vor und nach `ndistinct`?
- Mit `max_parallel_workers_per_gather = 0`: wie stark ändert sich die Zeit —
  und wie stark streut sie über fünf Läufe?

---

## 19.6 Fragen an dich selbst

- Warum schätzt der Planer `stadt = 1` allein richtig und `stadt = 1 AND plz =
  100` um Faktor 100 falsch, obwohl beide Spalten eine einwandfreie Statistik
  haben?
- Warum ändert `CREATE STATISTICS` den `cost`, aber oft nicht den Plan?
- Deine Daten sind durch Division entstanden. Was wäre, wenn in `plz` und
  `stadt` unabhängige Zufallszahlen stünden (18.2) — wäre die Multiplikation dann
  richtig?
- Warum sind es drei Prozesse und nicht zwei? Welche Einstellung entscheidet
  das, und wie viele Zahlen würdest du im Knoten erwarten, wenn sie aus wäre?
- In welchem Fall wird aus dieser Schätzung ein wirklich schlechter Plan? Baue
  ihn mit einer zweiten Tabelle und einem `Nested Loop` (Teil 17).

---

## Doku dazu

- [`EXPLAIN` und seine Optionen](https://www.postgresql.org/docs/18/sql-explain.html)
- [Using EXPLAIN](https://www.postgresql.org/docs/18/using-explain.html)
- [`CREATE STATISTICS`](https://www.postgresql.org/docs/18/sql-createstatistics.html)
- [`pg_statistic_ext`](https://www.postgresql.org/docs/18/catalog-pg-statistic-ext.html)
- [Parallel-Abfrage: die Einstellungen](https://www.postgresql.org/docs/18/runtime-config-query.html)
