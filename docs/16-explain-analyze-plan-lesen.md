# 16 — Einen Ausführungsplan lesen: Schätzung, Wirklichkeit, `loops`, `Buffers`

Teil 5 hat den Plan benutzt, um eine einzige Frage zu beantworten: **wird der
Index benutzt oder nicht?** Das war ein Vergleich zweier Zustände. Hier geht es
darum, einen Plan zu *lesen* — was die Zahlen bedeuten, wo sie lügen, und welche
Zeile man zuerst anschaut.

Ein Plan ist keine Messung von Geschwindigkeit, sondern eine **Rechnung mit einer
Schätzung darin**. Wer das verwechselt, optimiert das Falsche.

---

## 16.0 Das Werkzeug in voller Länge

Bisher wurde `EXPLAIN ANALYZE` und `EXPLAIN (ANALYZE, BUFFERS)` benutzt. Die
Optionen lassen sich beliebig kombinieren:

```sql
EXPLAIN (ANALYZE, BUFFERS, SETTINGS) SELECT * FROM kurs WHERE id = 3999999;
```

| Option | was sie tut |
|--------|-------------|
| `ANALYZE` | führt die Abfrage **wirklich aus** und zeigt die gemessenen Werte |
| `BUFFERS` | zeigt, wie viele 8-kB-Blöcke gelesen wurden — und woher |
| `VERBOSE` | zeigt zusätzlich die Ausgabespalten jedes Knotens |
| `COSTS` | die `cost=`-Zahlen; abschaltbar mit `COSTS OFF` |
| `TIMING` | die `actual time=`-Werte; abschaltbar mit `TIMING OFF` |
| `SETTINGS` | welche Einstellungen vom Standard abweichen (Teil 14) |
| `SUMMARY` | die `Planning Time` / `Execution Time` am Ende |
| `FORMAT` | `TEXT` (Standard), `JSON`, `YAML`, `XML` für Werkzeuge |
| `WAL` | wie viel Write-Ahead-Log die Abfrage erzeugt (nur mit `ANALYZE`) |
| `MEMORY` | wie viel Speicher die **Planung** gebraucht hat |
| `SERIALIZE` | was das Umwandeln der Ausgabe in Text/Binär kostet |
| `GENERIC_PLAN` | einen Plan für Platzhalter (`$1`) statt für feste Werte |

Zwei Angaben kommen von selbst mit, auch wenn man sie nicht anfordert: die
Zusammenfassung (`Planning Time`, `Execution Time`) erscheint mit `ANALYZE`, und
**`BUFFERS` ebenfalls**. Die Doku sagt es ausdrücklich:

> Buffers information is automatically included when `ANALYZE` is used.

Wer `EXPLAIN (ANALYZE)` schreibt und trotzdem `Buffers:`-Zeilen sieht, hat also
nichts falsch gemacht.

Zwei Vorsichtsmaßnahmen, die man einmal verinnerlichen muss:

- **`ANALYZE` führt aus.** Bei `INSERT`, `UPDATE`, `DELETE` verändert das die
  Daten. Wenn man den Plan einer schreibenden Anweisung sehen will, wickelt man
  sie in eine Transaktion, die man zurückrollt:

  ```sql
  BEGIN;
  EXPLAIN (ANALYZE, BUFFERS) UPDATE kurs SET name = name WHERE id = 1;
  ROLLBACK;
  ```

- **`TIMING` kostet selbst Zeit.** Bei sehr schnellen Abfragen kann das Messen
  länger dauern als die Abfrage. Dann `TIMING OFF` — die Zeilenzahlen bleiben,
  die Zeiten fallen weg:

  ```sql
  EXPLAIN (ANALYZE, BUFFERS, TIMING OFF) SELECT * FROM pg_stats;
  ```

Referenz: https://www.postgresql.org/docs/18/using-explain.html

---

## 16.1 Den Baum lesen, nicht den Text

Die Ausgabe ist ein **Baum**, keine Liste. Die Einrückung ist die Struktur, und
sie steht auf dem Kopf: der Wurzelknoten steht **oben**, die Blätter stehen
**unten, tief eingerückt**. Gelesen wird von innen nach außen — die Kinder
liefern ihre Zeilen an den Elternknoten.

```
Knoten A                       <- das Endergebnis
  ->  Knoten B                 <- erstes Kind von A
        ->  Knoten C           <- erstes Kind von B (Blatt)
        ->  Knoten D           <- zweites Kind von B (Blatt)
  ->  Knoten E                 <- zweites Kind von A
```

Drei Regeln, mit denen man jeden Plan entschlüsseln kann:

1. **Jeder Knoten mit Kind beginnt mit `->`** — nur die Wurzel nicht.
2. **Ein Join hat immer zwei Kinder.** Stehen dort nur eins, ist die Ausgabe
   abgeschnitten (das passiert leicht, wenn man in der Konsole nach oben scrollt
   und den Anfang nicht sieht — oder wenn das Pager-Fenster zu klein war).
3. **Die Reihenfolge der Kinder ist bedeutsam.** Bei einem `Nested Loop` ist das
   erste Kind die *äußere* Seite und das zweite die *innere*, die pro Zeile neu
   durchlaufen wird. Genau daher kommt `loops` in 16.3.

---

## 16.2 `cost=0.00..202.95` — eine erfundene Einheit

```
(cost=159.24..202.95 rows=8 width=475)
```

- Die zwei Zahlen sind **Startkosten** und **Gesamtkosten** des Knotens. Die
  Startkosten sind das, was anfällt, *bevor* die erste Zeile herauskommt — bei
  einem `Sort` zum Beispiel das komplette Einsortieren.
- Die Einheit ist **willkürlich**. Die Doku legt eine Sequenz-Seite als 1.0
  zugrunde, aber das ist eine Konvention, keine Zeit. Kosten sind nur **innerhalb
  eines Plans** vergleichbar, nie zwischen zwei Rechnern.
- `rows=` ist die **geschätzte** Zeilenzahl, die dieser Knoten ausgibt.
- `width=` ist die geschätzte **durchschnittliche Zeilenbreite in Bytes**. Wenn
  hier ein absurd kleiner Wert steht, fehlt eine Statistik.

Ein Kostenvergleich zweier Pläne ist die Art, wie der Planer sich entscheidet —
siehe 16.8, wo man ihn mit `enable_*` überstimmt.

---

## 16.3 `loops=` — die Multiplikationsfalle

```
(actual time=0.392..7.465 rows=3636.00 loops=1)
```

- `actual time=a..b` — gemessene Zeit **in Millisekunden** bis zur ersten und bis
  zur letzten Zeile. Ausgabe eines Knotens: **`b × loops`**.
- `rows=` — die tatsächlich gelieferten Zeilen **pro Durchlauf**. Insgesamt also
  **`rows × loops`**.
- `loops=` — wie oft der Knoten ausgeführt wurde.

Das ist die Falle: **die Zeit eines Knotens ist die Zeit *pro* Durchlauf.** Steht
im inneren Teil eines `Nested Loop` ein Index Scan mit `loops=438`, dann ist die
Gesamtzeit dieses Knotens nicht die angezeigte Zahl, sondern das 438-fache. Wer
das übersieht, sucht den Engpass im falschen Knoten.

Umgekehrt ist es ein wertvoller Hinweis: **`loops=1` überall** heißt, dass kein
Knoten mehrfach durchlaufen wurde — die Joins arbeiten mit einem Aufbau (Hash),
statt pro Zeile nachzuschlagen. Genau das ist in den Plänen über
Systemkataloge der Normalfall, weil dort alles winzig ist.

Und die Gegenprobe: **wo `loops > 1` steht, ist das eine Warnung.** Ein Knoten,
der 420-mal ausgeführt wird, sieht mit seinen 0,001 ms harmlos aus und kostet in
Summe ein Vielfaches seiner Nachbarn. Wer nur die Millisekunden liest, übersieht
ihn.

Dafür gibt es einen eigenen Zähler:

- **`Index Searches:`** — wie viele Suchläufe im Index tatsächlich passiert sind.
  Normalerweise gleich `loops`. Sie können aber **größer** sein: bei `= ANY(array)`
  macht eine einzige Ausführung viele Suchläufe. Dann verrät dir `loops` allein
  nicht die Arbeit, die wirklich anfiel.

---

## 16.3b Wo die Zeit sitzt: `inclusive` gegen `exclusive`

Die Ausgabe nennt für jeden Knoten eine **Gesamtzeit, die seine Kinder
einschließt**. Im Wurzelknoten steht damit die Summe des ganzen Baums — und
nirgends steht, welcher Knoten **selbst** wie viel beigetragen hat. Das muss man
sich ausrechnen:

```
eigene Zeit(Knoten) = Zeit(Knoten) − Σ Zeit(seine direkten Kinder)
```

Rechne das einmal an einer eigenen Ausgabe nach. Es geht genau auf: die Summe der
eigenen Zeiten aller Knoten ist die Gesamtzeit des Plans. Und meistens ist die
eigene Zeit fast aller Knoten winzig, während **ein einziger** fast alles kostet.

Merke: **`actual time` eines Knotens ist nicht seine Arbeit, sondern seine Arbeit
plus die aller Knoten unter ihm.** Wer den Engpass sucht, indem er die längste
Zeile sucht, findet deshalb immer den Wurzelknoten — und der sammelt nur ein.

---

## 16.4 Schätzung gegen Wirklichkeit

Das ist die Zeile, an der man einen Plan zuerst prüft: **steht links und rechts
dasselbe?**

```
Seq Scan on pg_statistic s  (cost=0.00..34.15 rows=615 ...) (actual ... rows=438.00 ...)
                                ^^^^ Schätzung                   ^^^^ Wirklichkeit
```

- Weichen die Werte um einen Faktor in der Größenordnung 10 oder mehr ab, ist die
  Schätzung falsch — und der Planer hat auf dieser Grundlage entschieden.
- Häufigste Ursache: **die Statistik ist alt.** `ANALYZE tabelle;` (5.2) ist der
  erste Griff.
- Zweite Ursache: die Daten sind **korreliert** (z. B. Postleitzahl und Ort in
  derselben Tabelle). Hier hilft `CREATE STATISTICS` auf mehreren Spalten
  (`ndistinct`, `mcv`, `dependencies`) — durchgerechnet in
  [Teil 19](19-schaetzung-und-parallele-plaene.md).
- Dritte Ursache: die Tabelle ist zu klein oder zu eigenartig für
  Durchschnittswerte. **Systemkataloge sind genau so ein Fall** — die
  Verteilung in `pg_class` oder `pg_attribute` ist nicht wie in Anwendungsdaten,
  und der Planer daneben zu liegen ist dort normal, aber harmlos.
- Vierte Ursache: es ist überhaupt keine **Spalte**, sondern ein **Ausdruck**
  (`WHERE sin(id) < 1`). Dann gibt es nichts zu analysieren, und der Planer nimmt
  einen Vorgabewert — siehe 16.4b.

Wichtig: eine schlechte Schätzung ist **kein Fehler an sich**. Sie wird erst zum
Problem, wenn sie zu einem schlechten Plan führt.

---

## 16.4b Ausdrücke: wenn der Planer gar nichts weiß

Eine vierte Ursache für eine falsche Schätzung, und die interessanteste:
**über einen Ausdruck gibt es keine Statistik.** Ein Histogramm gibt es pro
*Spalte*. Steht in der `WHERE`-Klausel `sin(id)`, gibt es dazu keine Spalte — der
Planer greift zu einem **fest verdrahteten Vorgabewert**:

| Bedingung | Vorgabewert | im Quellcode |
|-----------|-------------|--------------|
| Gleichheit (`=`) | 0,5 % | `DEFAULT_EQ_SEL` |
| Ungleichheit (`<`, `>`) | 1/3 | `DEFAULT_INEQ_SEL` |

Nachprüfen lässt sich das durch Nachrechnen: die geschätzte Zeilenzahl ist die
Zeilenzahl der Tabelle mal dem Vorgabewert. Zwei Dinge folgen daraus sofort:

- **`<` und `>` bekommen denselben Schätzwert.** Der Planer weiß nicht, dass die
  beiden Bedingungen komplementär sind. Er sieht nur „Vergleich gegen einen
  Ausdruck, kein Histogramm" — zweimal.
- **`ANALYZE` hilft hier nicht.** Es kann nur Spalten messen.

Abhilfe schafft eine **Statistik auf dem Ausdruck**, seit PostgreSQL 14:

```sql
CREATE STATISTICS meine_stats ON (sin(id)) FROM test;
ANALYZE test;
```

Die Doku nennt das die Form für „univariate statistics for a single expression,
providing benefits similar to an expression index without the overhead of index
maintenance". Danach hat der Planer ein Histogramm über die *Werte des Ausdrucks*
und schätzt richtig.

Zwei Lehren aus diesem Experiment:

1. **Der `cost` ändert sich dadurch nicht zwangsläufig.** Ein `Seq Scan` muss alle
   Zeilen lesen; seine Kosten hängen davon ab, wie viele Zeilen er *liest*, nicht
   wie viele er *weitergibt*. Korrigiert sich nur die Ausgabemenge eines obersten
   Knotens, ändert sich am Plan gar nichts. Die bessere Schätzung wird erst dort
   wirksam, wo über ihr eine Entscheidung hängt.
2. **Erweiterte Statistiken greifen bei Joins nicht.** Die Doku: „Extended
   statistics are not currently used by the planner for selectivity estimations
   made for table joins." Sitzt die schlechte Schätzung in einer
   *Join*-Bedingung, hilft `CREATE STATISTICS` (noch) nicht.

Und die Wirkung des Objekts ist an den Katalog gebunden: es gilt **nur für diesen
Ausdruck**. Für `cos(id)` braucht es ein zweites. Es ist nichts weiter als eine
Stichprobe über die Werte dieses Ausdrucks, die `ANALYZE` gemessen hat — kein
Wissen über die Funktion.

Referenz: https://www.postgresql.org/docs/18/sql-createstatistics.html

---

## 16.4c Was weggeworfen wurde: `Rows Removed by …`

Zwei Zeilen, die nur erscheinen, wenn es etwas zu berichten gibt — und die
deshalb leicht übersehen werden:

- **`Rows Removed by Filter: N`** — der Filter hat N Zeilen aussortiert. Fehlt
  die Zeile, hat er **keine** aussortiert.
- **`Rows Removed by Join Filter: N`** — die Join-Bedingung passte, aber ein
  zusätzlicher Filter hat die Paarung danach verworfen.

Der zweite Fall ist der teure: er entsteht, wenn eine Bedingung **nicht als
Join-Schlüssel benutzt werden kann** — etwa ein Funktionsaufruf. Dann paart der
Server die Zeilen erst und ruft die Funktion danach für jede Paarung auf. Eine
solche Zeile im Plan ist ein Fingerzeig: hier wird Arbeit gemacht und gleich
wieder weggeworfen.

Und es lässt sich nachrechnen: `rows` + `Rows Removed by Join Filter` = Zahl der
Paarungen, die der Join überhaupt gebildet hat.

---

## 16.5 `Buffers:` — woraus gelesen wurde

```
Buffers: shared hit=111
```

Die drei Werte, die auftauchen können:

| Wert | Bedeutung |
|------|-----------|
| `hit` | der Block war schon im `shared_buffers` — kein Plattenzugriff |
| `read` | der Block musste gelesen werden (aus dem Dateisystem) |
| `dirtied` | ein Block wurde verändert |
| `written` | ein Block musste geschrieben werden |

Zwei Dinge, die man daraus lernt:

- **`hit` gegen `read` verrät, ob du warm oder kalt gemessen hast.** Denselben
  Befehl zweimal hintereinander: der zweite Lauf hat andere `Buffers`. Wer
  Laufzeiten vergleicht, muss das wissen (Teil 5).
- **Die Zahlen eines Knotens schließen seine Kinder mit ein** — wie bei den
  Zeiten. Man darf sie also **nicht addieren**. Rechne es einmal an einer eigenen
  Ausgabe nach: die Zahl der Wurzel muss der Summe ihrer Kinder entsprechen, und
  die eines Kindes wieder der Summe von dessen Kindern. Wenn das nicht aufgeht,
  hast du einen Knoten übersehen.

---

## 16.5b CPU gegen I/O — die wichtigste Unterscheidung

`Buffers` sagt, **wie viel** gelesen wurde. Ob das lange gedauert hat, sagt es
nicht. Dafür braucht man `track_io_timing` (Teil 14) — dann steht neben den
Blöcken eine zweite Zeile:

```
I/O Timings: shared read=…
```

Damit lässt sich eine Abfrage einordnen. Steht dort ein Wert, der neben der
`Execution Time` verschwindet, ist die Abfrage **CPU-gebunden** — dann helfen
weder eine schnellere Platte noch mehr `shared_buffers` noch ein Index. Steht
dort fast die ganze Zeit, ist sie **I/O-gebunden** — dann hilft genau das. Die
häufigste Fehldiagnose in der Praxis ist, eine CPU-gebundene Abfrage mit
I/O-Mitteln kurieren zu wollen.

Zwei Fallen dabei:

- **`shared read` heißt nicht „von der Platte".** Es heißt nur „war nicht im
  `shared_buffers`". Der Block kann aus dem Cache des Betriebssystems gekommen
  sein — das ist ein **zweiter Cache**, den dir `BUFFERS` nicht zeigt. Rechne die
  gelesene Menge durch die I/O-Zeit: kommt eine Zahl heraus, die keine Platte
  schafft, kam es aus dem OS-Cache.
- **`I/O Timings` misst nur die Wartezeit im Leseaufruf**, nicht das Kopieren in
  den `shared_buffers`. Es ist also nicht „die I/O hat X gekostet", sondern „auf
  die Platte haben wir X gewartet".

---

## 16.6 `Hash`: `Buckets`, `Batches`, `Memory Usage`

Ein `Hash`-Knoten baut eine Tabelle im Arbeitsspeicher auf. Drei Angaben dazu:

```
Buckets: 4096 (originally 2048)  Batches: 1 (originally 1)  Memory Usage: 650kB
```

- **`Batches`** ist der wichtigste Wert. `Batches: 1` heißt: alles passte in
  `work_mem`, es wurde nichts auf die Platte geschrieben. **`Batches > 1` heißt:
  es musste ausgelagert werden** — dann wird die Arbeit in mehreren Durchgängen
  gemacht und es entstehen temporäre Dateien. Das ist der klassische Grund, ein
  `Hash Join` plötzlich langsam wird, und der Anlass, `work_mem` hochzusetzen
  (Teil 14).
- **`originally N`** zeigt, wie der Wert beim Start war. Ein `Hash` wächst, wenn
  mehr Zeilen kommen als geschätzt — `Buckets: 4096 (originally 2048)` ist also
  ein sichtbares Zeichen dafür, dass die Schätzung zu niedrig war (16.4).
- **`Memory Usage`** ist der tatsächlich belegte Speicher. Ist er deutlich größer
  als `work_mem`, war irgendetwas falsch.

Ob überhaupt ausgelagert wurde, sieht man auch global:

```sql
SELECT datname, temp_files, temp_bytes FROM pg_stat_database WHERE datname = current_database();
```

---

## 16.7 `Seq Scan` ist nicht automatisch schlecht

Bisher (Teil 5) war `Seq Scan` immer das, was weg sollte. Hier ist das
Gegenteil wichtig: **bei kleinen Tabellen ist ein `Seq Scan` der richtige Plan.**

In einem Plan über `pg_class`, `pg_attribute` oder `pg_statistic` steht fast
immer `Seq Scan`. Das ist kein Problem, sondern eine Entscheidung: die Tabellen
haben wenige Seiten, ein Index würde mehr kosten als das Lesen der ganzen
Tabelle. Genau deshalb entscheidet der Planer über `cost` (16.2) und nicht über
die Frage „Index da oder nicht".

Ein schöner, immer reproduzierbarer Fall — die Abfrage hinter `pg_stats`:

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM pg_stats;
```

Diese Abfrage verbindet `pg_statistic`, `pg_attribute` und `pg_class`. Ihre
Spuren im Plan: ein `Join Filter` mit `has_column_privilege(c.oid, a.attnum,
'select'::text)` und ein `Filter: (NOT attisdropped)` auf `pg_attribute`. Beide
gehören zur Definition der View — man sieht also **das Innere einer System-View**,
kein Anwendungsproblem. Zur Kontrolle:

```sql
\d+ pg_stats
```

Lektion: **bevor man einen Plan optimiert, muss man wissen, was die Abfrage
eigentlich tut.** Ein `Seq Scan` auf einem Katalog ist normal.

---

## 16.8 Den Planer überstimmen

Der Planer wählt, was `cost` sagt. Will man wissen, **welche Wahl** er getroffen
hat, schaltet man die Alternativen ab und sieht, was passiert:

```sql
SET enable_seqscan = off;    -- zwingt zum Index, wenn möglich
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM kurs WHERE name = 'Kurs Nr. 123456';
RESET enable_seqscan;
```

Die Schalter für das Thema hier: `enable_seqscan`, `enable_indexscan`,
`enable_indexonlyscan` (5.0), `enable_bitmapscan`, `enable_nestloop`,
`enable_hashjoin`, `enable_mergejoin`, `enable_sort` (15.5), `enable_material`.

Vorsicht beim Lesen: `enable_seqscan = off` verbietet den Seq Scan nicht, es
macht ihn nur künstlich teuer. Wenn es keine Alternative gibt, bleibt er trotzdem
stehen — und ist dann am hohen `cost` erkennbar.

Referenz: https://www.postgresql.org/docs/18/runtime-config-query.html

---

## 16.8b Eine Änderung bewerten, ohne sich zu täuschen

Derselbe Befehl mehrfach hintereinander liefert **unterschiedliche** Zeiten.
Nicht im Sinne von Rundung, sondern in der Größenordnung von Prozenten bis zu
einem Viertel — je nachdem, was sonst noch auf dem Rechner passiert und wie warm
die Caches sind.

Was daraus folgt:

- **Nie eine Änderung mit *einem* Lauf pro Seite bewerten.** Wer vorher einmal
  und nachher einmal misst, misst die Streuung.
- **Wenn Zeiten das Ziel sind: mehrere Läufe** und den Mittelwert oder Median
  vergleichen — nicht den schönsten Wert.
- **Vergleiche notfalls etwas anderes als die Zeit.** Mit `TIMING OFF` bleiben
  die Zeilenzahlen und die Blöcke übrig, und die sind viel stabiler als
  Millisekunden.
- **Nur eine Sache auf einmal ändern.** Zwei Läufe, die sich in der Abfrage *und*
  im Cache-Zustand unterscheiden, sind kein Vergleich — egal wie ähnlich die
  Zahlen aussehen.

---

## 16.8c Fremde Werkzeuge — und was du damit wegschickst

Die Ausgabe von `EXPLAIN` kann man in Web-Dienste einwerfen, die den Plan
graphisch aufbereiten (z. B. <https://explain.depesz.com/> oder
<https://explain.dalibo.com/>).
Was sie leisten: sie rechnen die Dinge aus, die in der Textausgabe fehlen — vor
allem **`exclusive` gegen `inclusive`** (16.3b) und den **Faktor zwischen
Schätzung und Wirklichkeit** (16.4). Die Farben sind nur eine Visualisierung
dieser Zahlen; **neue Informationen über den Plan liefert das nicht.**

Zwei Dinge, die man dabei wissen muss:

- **Der Plan wird hochgeladen.** Auf dem fremden Server liegen damit
  Tabellennamen, Spaltennamen, Indexnamen und unter Umständen die Werte aus
  Filterbedingungen. Für ein Lernprojekt ist das harmlos — für die Pläne einer
  Produktionsdatenbank ist es das nicht.
- **Alles, was das Werkzeug zeigt, kannst du selbst ausrechnen** — und dann hat es
deinen Rechner nie verlassen. Für einen Plan ohne Auslagerungen genügen die
drei Rechnungen aus 16.3b, 16.4c und die Vorgabewerte aus 16.4b.

Wer es lieber lokal hat: `EXPLAIN (ANALYZE, FORMAT JSON)` liefert die Daten in
einer Form, die auch eigenständige Plan-Betrachter lesen können.

---

## 16.9 Was hier noch fehlt

Bewusst offengelassen, kommt nach und nach dazu:

- **`auto_explain`** — Pläne langsam gewordener Abfragen automatisch ins Log
  schreiben, statt sie einzeln nachzustellen.
- **`pg_stat_statements`** — welche Abfrage kostet über alle Ausführungen hinweg
  am meisten? Das ist die Frage *vor* dem Plan.
- **`log_min_duration_statement`** — ab wann ist eine Abfrage einen Log-Eintrag
  wert? (Teil 14)
- **Plan-Regression mit `EXPLAIN (FORMAT JSON)`** in einem Skript.
- **Parallele Pläne** — `Gather`, geplante gegen gestartete Worker, und wem die
  Zahlen in so einem Knoten gehören: [Teil 19](19-schaetzung-und-parallele-plaene.md).

(`track_io_timing` steht nicht mehr hier — es wird jetzt in 16.5b benutzt.)

Referenz: https://www.postgresql.org/docs/18/monitoring-stats.html
