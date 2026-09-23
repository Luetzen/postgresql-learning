# 17 — Nested Loop, Hash, Merge: welche Verbindungsmethode wann

Jede Verbindung zweier Tabellen führt PostgreSQL mit **genau einer** von drei
Methoden aus, und jede hat einen eigenen Namen im Plan:

| im Plan | Methode |
|---------|---------|
| `Nested Loop` | Schleife über die eine Seite, Suche in der anderen |
| `Hash Join` | eine Seite in eine Hash-Tabelle bauen, die andere dagegen probieren |
| `Merge Join` | beide Seiten sortiert, dann in einem Durchgang zusammenführen |

Teil 16 hat gezeigt, wie man einen Plan *liest*. Hier geht es um die Wahl:
**wann ist welche Methode die richtige** — und woran man erkennt, dass der Planer
anders entschieden hat als man selbst.

Auf der Tafel stehen die drei als Spalten und die Fragen als Zeilen: *wie arbeitet
sie*, *wofür passt sie*, *was macht ein Index*. 17.0 ist das als Matrix, 17.0b die
Tafel selbst, 17.1 bis 17.4 füllen sie aus, und 17.5 bis 17.6 zeigen, wie man jede
Methode selbst erzwingt und nachmisst.

> **Zu den Zahlen:** hier steht kein einziger Messwert. Zeilen, Zeiten und Blöcke
> hängen an deinem Rechner, deinen Daten und deinem `work_mem` — die werden
> gemessen, nicht abgeschrieben (16.8b).

---

## 17.0 Die Matrix

| Frage | `Nested Loop` | `Hash Join` | `Merge Join` |
|-------|---------------|-------------|--------------|
| **Wie?** | für *jede* Zeile der äußeren Seite die innere Seite abfragen | eine Seite komplett in eine Hash-Tabelle bauen, die andere Zeile für Zeile dagegen probieren | beide sortierten Seiten nebeneinander herlaufen lassen, wie zwei sortierte Stapel |
| **Welche Bedingung?** | jede — auch `<`, `<>` | nur Gleichheit (`=`) | nur Gleichheit („merge-fähige" Operatoren) |
| **Index?** | **hilft**: ein Index auf der inneren Join-Spalte erspart das Durchsuchen | **nutzlos**: beide Seiten werden ganz gelesen | **kann das Sortieren sparen**, wenn er die Reihenfolge liefert |
| **Gut wenn …** | eine Seite klein ist, oder `LIMIT` früh abbricht | beide Seiten groß sind und keine Sortierung vorhanden ist | beide Seiten schon sortiert sind oder das Ergebnis sortiert gebraucht wird |
| **Schlecht wenn …** | beide Seiten groß sind und kein Index existiert | zu wenig `work_mem` (dann `Batches > 1`) | eine `Sort`-Stufe eingeschoben werden muss |
| **Speicher** | kaum | `work_mem` pro Hash-Knoten (16.6) | `work_mem` pro `Sort`-Knoten |
| **Erste Zeile kommt** | sofort | erst nach dem Aufbau | erst nach dem Sortieren |
| **Ergebnis sortiert?** | wie die äußere Seite | nein | ja, nach der Join-Spalte |
| **Woran im Plan** | innerer Knoten mit `loops > 1` | Kind-Knoten `Hash` mit `Buckets`/`Batches` | ein oder zwei `Sort`-Kinder — oder gar keine |

Und „wann man was macht" als Liste — mit der Warnung darunter:

1. **Kleine Seite außen, Index innen, oder ein `LIMIT`** → `Nested Loop`.
2. **Zwei große Seiten, nur `=`, kein Index, genug `work_mem`** → `Hash Join`.
3. **Zwei große Seiten, beide schon sortiert (Index auf der Join-Spalte)** → kann
   ein `Merge Join` billiger sein als ein `Hash Join`.
4. **Keine Gleichheit in der Bedingung** → es bleibt nur der `Nested Loop`.

> Das ist keine Regel, nach der man Abfragen *schreibt*. Der Planer entscheidet
> über `cost` (16.2) aus den Schätzungen der Statistik, und deshalb kann dieselbe
> Abfrage auf zwei Rechnern zwei verschiedene Methoden bekommen. Die Liste sagt,
> was du erwartest — der Plan sagt, was er gewählt hat. Und entschieden wird über
> **Schätzungen**: ein `ANALYZE` (Teil 5) oder bessere Statistik (`CREATE
> STATISTICS`, 16.4b) ändert nicht nur die Kosten, sondern manchmal die Methode.

---

## 17.0b Die Tafel, Zeile für Zeile

Damit die Matrix oben und die Tafel dieselbe Sprache sprechen — hier die drei
Zeilen der Tafel wörtlich, samt der einen leeren Zelle:

| Zeile | `Nested Loop` | `Hash` | `Merge` |
|-------|---------------|--------|---------|
| **wie?** | *(auf der Tafel offen — das füllt 17.1)* | Seq scan erste Tab → Hash, Seq scan zweite Tab → probe Hash | sortiere beide Tab. nach Join-Bed. → merge |
| **gut für?** | wenige Ergebniszeilen, eine Tabelle klein | größere Tabellen (Hash ≤ RAM) | sehr große Tabellen, Ergebnis soll sortiert sein |
| **Index?** | auf der Join-Bed. auf der inneren Tab. | *(leer)* | auf der Join-Bed. auf beiden Tab. |

Drei Stellen, an denen die Tafel mehr sagt als die Matrix:

- **„sortiere beide Tab. nach Join-Bed.“** — sortiert wird nach der
  **Join-Bedingung**, also nach der Spalte aus dem `ON`. Steht die im Index,
  entfällt das Sortieren (17.3, `Merge Cond:`).
- **„Hash ≤ RAM“** — der Speicher, der einem Hash-Knoten zusteht, ist `work_mem`
  (Teil 14). Passt die Hash-Tabelle nicht hinein, landet sie in temporären
  Dateien: `Batches > 1` (16.6, und die Übung 17.6b).
- **Die leere Zelle bei `Hash` / `Index`** ist keine Lücke im Skript: ein Hash Join
  liest beide Seiten vollständig, ein Index kann daran nichts ändern. Deshalb steht
  in der Matrix „nutzlos“ — und deshalb ist die Zelle auf der Tafel leer.

---

## 17.1 `Nested Loop`

Die einfachste Methode und die einzige, die mit beliebigen Bedingungen
funktioniert:

```
Nested Loop
  ->  <äußere Seite>          wenige Zeilen
  ->  <innere Seite>          wird pro äußerer Zeile neu durchlaufen
```

Für **jede** Zeile der äußeren Seite wird die innere Seite abgefragt. Zwei Fälle:

- **Mit Index** auf der Join-Spalte der inneren Seite: pro Zeile ein `Index Scan`
  — das ist der klassische, sehr schnelle Fall für einzelne Zeilen (Teil 5).
- **Ohne Index**: die innere Seite wird vollständig gelesen, und zwar *für jede*
  äußere Zeile. Die Arbeit ist dann das **Produkt** beider Zeilenzahlen. Steht auf
  der inneren Seite ein `Materialize`-Knoten, hat der Planer sie einmal gelesen und
  hält sie im Speicher, damit die Wiederholungen nicht erneut auf die Tabelle
  gehen (siehe `enable_material`, 16.8).

Der Preis steht an zwei Stellen im Plan: `loops` am inneren Knoten zählt die
Durchläufe, also die Zahl der äußeren Zeilen, und ein Knoten mit vielen `loops`
ist trotz winziger Zeit *pro* Durchlauf der teuerste im Plan — die
Multiplikationsfalle aus 16.3.

Was gut daran ist: die erste Ergebniszeile kommt sofort. Mit einem `LIMIT` bricht
die Abfrage deshalb extrem früh ab, während `Hash Join` und `Merge Join` erst
einmal fertig aufbauen müssten.

Eine Bedingung, die der Index nicht beantworten kann, wird nicht zum `Index Cond`,
sondern zum `Join Filter:` — und was daran scheitert, steht als
`Rows Removed by …` dahinter (16.4c).

Der Index gehört auf die **innere** Seite (so steht es auch in der Index-Zeile der
Tafel). Einer auf der äußeren Seite nützt hier nichts: die wird ohnehin nur einmal
gelesen, und für sie gibt es keine „nächste Suche“.

**Wann ihn der Planer wählt:** wenige Ergebniszeilen, eine kleine (äußere) Seite,
Index auf der inneren Join-Spalte, oder ein `LIMIT`, das früh genug greift.

---

## 17.2 `Hash Join`

Zwei Phasen:

1. **Build** — eine Seite vollständig lesen und in eine Hash-Tabelle legen. Das
   ist der Knoten `Hash` im Plan.
2. **Probe** — die andere Seite Zeile für Zeile durch die Hash-Tabelle schicken.

Genau das steht auf der Tafel: *Seq Scan erste Tabelle → Hash*, *Seq Scan zweite
Tabelle → probe Hash*. Welche Seite gebaut wird, entscheidet der Planer, und
üblich ist die **kleinere** — sie muss in den Speicher passen. Deshalb *kann* die
`Hash`-Seite im Plan eine ganz andere Tabelle sein, als du in `FROM` zuerst
geschrieben hast (17.5).

Eigenschaften:

- **Nur `=`,** keine Bereichsbedingungen: eine Hash-Tabelle kennt keine Ordnung.
- **Liest beide Seiten genau einmal, ganz** — und braucht dafür **keinen Index**.
  Das ist der Fall, in dem ein Hash Join den Nested Loop schlägt: zwei große
  Tabellen, kein Index, kein `LIMIT`.
- **Kostet Speicher.** Die Hash-Tabelle soll in `work_mem` passen — auf der Tafel
  steht dafür kurz *Hash ≤ RAM*. Passt sie nicht, zerlegt der Planer sie in
  `Batches` und schreibt sie in temporäre Dateien; im Plan stehen dann
  `Batches > 1`, `Disk Usage` und `Buffers: temp read/written` (16.6, `work_mem`
  in Teil 14).
- **Anfangsträgheit:** bis der `Hash`-Knoten fertig ist, kommt keine Zeile heraus.
- **Die Reihenfolge des Ergebnisses ist beliebig** — ein Hash kennt keine Ordnung.
- Die Gleichheit auf der Hash-Spalte steht als `Hash Cond:`, alles Übrige als
  `Join Filter:`.

**Wann ihn der Planer wählt:** beide Seiten groß, nur Gleichheit, kein Index und
keine Sortierung vorhanden — der Standardfall bei größeren Auswertungen.

---

## 17.3 `Merge Join`

Beide Seiten werden **nach der Join-Bedingung sortiert** und dann gleichzeitig
durchlaufen — wie zwei sortierte Kartenstapel, bei denen man immer nur die
obersten Karten vergleicht und weiterrückt:

```
Merge Join                      Merge Cond: (a.id = b.id)
  ->  <Seite A, sortiert>
  ->  <Seite B, sortiert>
```

Sortiert wird nicht extra, wenn die Reihenfolge schon da ist:

- Ein `Index Scan` auf der Join-Spalte liefert sie geschenkt (ein btree-Index ist
  sortiert), und
- ein `Sort`-Knoten im Plan heißt: sie fehlte.

Hier zählt **beide** Seiten: die Index-Zeile der Tafel sagt es genau so — *auf der
Join-Bed. auf beiden Tab.* Ein Index auf nur einer Seite spart nur eines der zwei
`Sort`.

Eigenschaften:

- **Nur Gleichheit** — genauer: Operatoren aus einer Sortier-Operatorklasse.
- **Liest jede Seite genau einmal**, braucht keinen Index, aber die Sortierarbeit.
- Ein `Sort` ist nicht billig: er braucht `work_mem` und schreibt darüber hinaus
  auf die Platte (`Buffers: temp`). Ein `Merge Join` mit zwei `Sort`-Kindern ist
  deshalb oft **teurer** als ein `Hash Join` auf denselben Zeilen — der baut nur
  *eine* Seite auf.
- Dafür kommt das Ergebnis **sortiert nach der Join-Spalte** heraus. Braucht die
  Abfrage diese Ordnung sowieso, ist das geschenkt.

**Wann ihn der Planer wählt:** zwei **sehr große**, bereits sortierte Seiten (Index
auf beiden Join-Spalten) — oder wenn das Ergebnis sowieso sortiert gebraucht wird.

---

## 17.4 Warum bei „keine Gleichheit" nur ein Weg übrig bleibt

Hash und Merge brauchen beide `=`. Sobald die Bedingung eine andere ist:

```sql
SELECT a.id, b.id FROM thema a JOIN thema b ON a.id < b.id;
```

bleibt nur der `Nested Loop`. Die Bedingung ist keine Suchbedingung für einen
Index, sondern ein `Join Filter`, das Zeile für Zeile geprüft wird. Im Plan steht
dann `Nested Loop` mit `Join Filter:` in der Kindzeile und einer Zahl hinter
`Rows Removed by Join Filter` (16.4c).

Was daraus folgt: eine Abfrage wie `… ON a.name <> b.name` oder
`… ON a.datum < b.datum` ist keine Frage des Optimierens, sondern eine
Kostenfrage — und der Preis ist das Produkt der Zeilenzahlen.

---

## 17.5 Den Planer fragen — und ihn überstimmen

Fragen kostet nichts:

```sql
EXPLAIN SELECT … ;      -- ohne ANALYZE: nur die Wahl, ohne Ausführung
```

Überstimmen mit genau drei Schaltern aus 16.8:

```sql
SET enable_hashjoin = off;  SET enable_mergejoin = off;   -- nur noch Nested Loop
SET enable_nestloop = off;  SET enable_mergejoin = off;   -- nur noch Hash Join
SET enable_nestloop = off;  SET enable_hashjoin  = off;   -- nur noch Merge Join
RESET ALL;
```

Zur Erinnerung (16.8): `off` **verbietet nichts**, es macht die Methode nur
teuer. Sind alle drei aus, wählt er trotzdem eine — die billigste der verbotenen.
Und `enable_sort = off` nimmt einem `Merge Join` die Möglichkeit, seine
Sortierung herzustellen; wer es genau wissen will, schaltet auch das ab und
schaut, was übrig bleibt.

Warum die Seiten dabei so oft wandern: bei **inneren** Joins darf der Planer die
Reihenfolge frei tauschen (bis `join_collapse_limit`) — unabhängig davon, wie man
sie in `FROM` aufgeschrieben hat.

Referenz: https://www.postgresql.org/docs/18/explicit-joins.html

---

## 17.6 Der Übungsaufbau

Die Tabellen kommen aus `sql/05_join_schema.sql`: `thema` mit 8 Zeilen,
`kurs_thema` mit 4 Mio. Zeilen — absichtlich **ohne** Index.

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/05_join_schema.sql
```

```sql
ANALYZE thema, kurs_thema;      -- ohne Statistik plant er schlecht (Teil 5)
\d thema
\d kurs_thema
```

### 17.6a Kleine gegen große Seite

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT t.bezeichnung, count(*)
FROM thema t
JOIN kurs_thema kt ON kt.thema_id = t.id
GROUP BY t.bezeichnung
ORDER BY t.bezeichnung;
```

Ansehen: Welche Seite ist der `Hash`-Knoten (also die gebaute), welche die
probende? Steht bei `Batches` eine 1? Oder ist es doch ein `Nested Loop`
geworden?

Jetzt dieselbe Abfrage, aber alle Alternativen verboten:

```sql
SET enable_hashjoin = off;
SET enable_mergejoin = off;
EXPLAIN (ANALYZE, BUFFERS) /* dieselbe Abfrage */ ;
RESET ALL;
```

Erwartung: ein `Nested Loop` — der hier die große Tabelle für jede der 8
`thema`-Zeilen einmal liest. Er dauert deutlich länger; das ist die Lektion, und
`loops` verrät, warum.

Und nun der Index auf der Join-Spalte:

```sql
CREATE INDEX idx_kurs_thema_thema ON kurs_thema (thema_id);
ANALYZE kurs_thema;

EXPLAIN (ANALYZE, BUFFERS) /* dieselbe Abfrage */ ;
```

Jetzt sind zwei Methoden plötzlich billiger als vorher: ein `Nested Loop`, der per
`Index Scan` in die große Tabelle greift, oder ein `Merge Join`, weil der Index
die `thema_id` schon sortiert liefert. Welche es wird, entscheiden die
Statistiken — notiere, was bei dir steht.

### 17.6b Große gegen große Seite

Das ist die schwerste Abfrage in diesem Teil:

```sql
SHOW work_mem;

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
FROM kurs_thema a
JOIN kurs_thema b ON a.kurs_id = b.kurs_id;
```

Ansehen: Wie groß ist die Hash-Tabelle laut `Memory Usage`, und steht bei
`Batches` mehr als 1? Dann hat sie nicht in `work_mem` gepasst und wurde in
temporäre Dateien ausgelagert (`Buffers: temp read/written`). Diesen Plan einmal
mit einem größeren `work_mem` wiederholen:

```sql
SET work_mem = '64MB';
EXPLAIN (ANALYZE, BUFFERS) /* dieselbe Abfrage */ ;
RESET work_mem;
```

Fällt `Batches` damit auf 1? Und wie verhalten sich die Zeiten der beiden Läufe?
(16.8b: mehrere Läufe, nicht einen.)

Für den Vergleich mit `Merge Join`: der Index auf `kurs_id` liefert die
Sortierung, die der Merge Join braucht.

```sql
CREATE INDEX idx_kurs_thema_kurs ON kurs_thema (kurs_id);
ANALYZE kurs_thema;

SET enable_hashjoin = off;
SET enable_nestloop = off;
EXPLAIN (ANALYZE, BUFFERS) /* dieselbe Abfrage */ ;
RESET ALL;
```

Erwartung: `Merge Join` **ohne** `Sort`-Kinder, weil beide Seiten den Index
benutzen. Zur Kontrolle den Index wieder wegwerfen und noch einmal dasselbe —
jetzt stehen zwei `Sort`-Knoten im Plan.

### 17.6c Keine Gleichheit — es gibt keine Wahl

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.id, b.id
FROM thema a
JOIN thema b ON a.id < b.id;
```

Hier hilft kein `SET`: `Hash Join` und `Merge Join` können `<` nicht. Der Plan
ist ein `Nested Loop` mit `Join Filter` — und `Rows Removed by Join Filter` zeigt,
wie oft die Prüfung umsonst war.

### 17.6d Drei Tabellen — der Join ist ein Baum

Ein Join verbindet immer nur **zwei** Seiten (16.1, Regel 2). Drei Tabellen sind
deshalb **zwei** Join-Knoten übereinander. Dafür braucht man `kurs` aus Teil 3/4
mit seinen 4 Mio. Zeilen:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT k.id, k.name, t.bezeichnung
FROM kurs k
JOIN kurs_thema kt ON kt.kurs_id = k.id
JOIN thema t       ON t.id = kt.thema_id
WHERE k.id <= 1000;
```

Ansehen: Welcher Join-Knoten sitzt unter welchem, und welcher ist die Wurzel?
Steht die Tabelle aus der ersten `FROM`-Zeile auch in der innersten Verzweigung —
oder hat der Planer die Reihenfolge getauscht (17.5)? Und welche Methode hat jeder
der beiden Knoten bekommen? Der `WHERE`-Filter ist nur da, damit die Ausgabe klein
bleibt; das Join-Muster ist dasselbe wie ohne ihn. Was du siehst, hängt davon ab,
welche Indizes aus 17.6a und 17.6b noch stehen — genau das ist der Punkt.

### 17.6e Aufräumen

```sql
DROP INDEX IF EXISTS idx_kurs_thema_thema;
DROP INDEX IF EXISTS idx_kurs_thema_kurs;
DROP TABLE IF EXISTS kurs_thema, thema;
```

Wer die große Tabelle lieber kleiner hätte: in `sql/05_join_schema.sql` steht die
Obergrenze zweimal in den beiden `INSERT`s.

---

## 17.7 Was hier noch fehlt

Bewusst offengelassen, kommt nach und nach dazu:

- **`Memoize`** — ein Zwischenspeicher auf der inneren Seite eines `Nested Loop`
  (seit PostgreSQL 14): derselbe Suchwert wird nicht zweimal gesucht. Erklärt
  manchen Nested Loop, der sonst unsinnig aussähe.
- **Semi- und Anti-Joins** — `Hash Semi Join`, `Merge Anti Join`: das sind `IN`,
  `EXISTS` und `NOT IN`.
- **Parallele Joins** — `Parallel Hash Join` mit `Gather`-Knoten (Teil 16).
- **Die Suche nach der Join-Reihenfolge** bei vielen Tabellen:
  `join_collapse_limit`, `geqo_threshold`.
- **`Hash Cond` gegen `Join Filter`** — warum ein Prädikat im Plan wandert.

Referenz: https://www.postgresql.org/docs/18/planner-optimizer.html

---

## Was in `06-kurs-notizen.md` gehört

- Welche Methode hat der Planer in 17.6a gewählt — und welche Seite war der
  `Hash`-Knoten?
- Der erzwungene `Nested Loop` in 17.6a: wie viele `loops` hatte der innere
  Knoten, und wie viel Zeit ergibt `actual time` × `loops`?
- Hat sich die Methode geändert, nachdem `CREATE INDEX` + `ANALYZE` gelaufen sind?
- `Batches` in 17.6b mit dem Vorgabe-`work_mem` gegen 64 MB: wo bleibt der
  Unterschied — in den Zeiten oder nur in den temporären Blöcken?
- `Merge Join` erzwungen: standen `Sort`-Knoten im Plan, obwohl der Index auf
  `kurs_id` existierte — vorher und nachher?
- Wie viele Zeilen standen in 17.6c hinter `Rows Removed by Join Filter`?
- Beim Drei-Tabellen-Join in 17.6d: welcher Join-Knoten saß unter welchem, welche
  Methode hatte jeder — und hat der Planer die `FROM`-Reihenfolge getauscht?
- Sind mit allen drei Methoden verboten trotzdem Pläne herausgekommen — und zu
  welchem `cost`?
