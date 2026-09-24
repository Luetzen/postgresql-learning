# 13 — Tote Zeilen, VACUUM und Bloat

Teil 12 hat gezeigt, dass ein `UPDATE` eine **neue Zeilenversion** schreibt und die
alte stehen lässt — und dass ein `ROLLBACK` sogar eine tote Version hinterlässt.
Diese toten Versionen sammeln sich. `VACUUM` ist der Dienst, der sie einsammelt.

Die Doku sagt es am Anfang von `VACUUM` sehr nüchtern:

> `VACUUM` gewinnt den Speicher zurück, den tote Zeilen belegen. Im normalen
> PostgreSQL-Betrieb werden Zeilen, die gelöscht oder durch ein Update obsolet
> geworden sind, nicht physisch aus ihrer Tabelle entfernt; sie bleiben vorhanden,
> bis ein `VACUUM` läuft. Deshalb ist es nötig, regelmäßig zu vacuumen,
> insbesondere bei häufig aktualisierten Tabellen.

Ohne `VACUUM` wächst jede viel geänderte Tabelle monoton. Das ist kein Fehler,
sondern der Preis für 12.

Voraussetzung: `konto` aus Teil 7 und `kurs` aus Teil 3/4.

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/04_konto.sql
```

---

## 13.0 Erst tote Zeilen erzeugen

Mit zwei Zeilen sieht man zu wenig. Also viele Änderungen — jede davon macht eine
Version tot:

```sql
DO $$
BEGIN
    FOR i IN 1..1000 LOOP
        UPDATE konto SET betrag = betrag + 1 WHERE id = 1;
    END LOOP;
END $$;
```

Und die Zahlen dazu:

```sql
SELECT relname, n_live_tup, n_dead_tup, n_tup_upd, last_vacuum, last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'konto';
```

Erwartung: `n_live_tup` = 2 (die sichtbaren Zeilen), aber `n_dead_tup` in der
Größenordnung der 1000 Änderungen — obwohl die Tabelle logisch nur eine Zeile
geändert hat.

Referenz: https://www.postgresql.org/docs/18/monitoring-stats.html

---

## 13.1 Was `VACUUM` tut — und was nicht

```sql
VACUUM konto;
```

Das ist die ganze Anweisung. Ohne Tabellennamen würde sie die **ganze Datenbank**
durchgehen (`VACUUM;`) — genau das, was du vorhin getippt hast.

Und ein wichtiger Hinweis aus der Doku: **`VACUUM` kann nicht in einem
Transaktionsblock laufen.** Der Prompt muss also `kurs=#` sein, nicht `kurs=*#`
(siehe 7.1).

| | `VACUUM` | `VACUUM FULL` |
|---|---|---|
| Platz | wird **zur Wiederverwendung** freigegeben | Tabelle wird neu geschrieben, Platz geht **ans Dateisystem zurück** |
| Sperre | keine exklusive — läuft neben Lesen und Schreiben | `ACCESS EXCLUSIVE` (7.6c), blockiert alles |
| Dauer | kurz | viel länger |
| Extra-Platz | nein | **ja** — eine zweite Kopie der Tabelle während des Laufs |

Der erste Punkt ist der, der überrascht: **ein normales `VACUUM` macht die Tabelle
nicht kleiner.** Der Platz wird innerhalb der Tabelle wiederverwendbar — die Datei
bleibt gleich groß. Eine Ausnahme nennt die Doku ausdrücklich: leere Seiten am
**Ende** der Tabelle werden abgeschnitten (Option `TRUNCATE`, standardmäßig an).
In der Mitte gibt es nichts zurück.

Und `VACUUM` ist nicht faul: es überspringt Seiten, die laut *Visibility Map*
ohnehin für alle sichtbar sind. Diese Karte ist auch der Grund, warum ein offener
Cursor die Aufräumarbeit behindern kann — siehe 10.6 (g).

---

## 13.1b Die `VERBOSE`-Ausgabe lesen

Das ist der einzige Ort, an dem man sieht, **was** `VACUUM` getan hat. Die Form ist
immer dieselbe (hier mit `N` statt Zahlen — deine stehen in
`06-kurs-notizen.md`):

```text
INFO:  vacuuming "kurs.public.konto"
INFO:  finished vacuuming "kurs.public.konto": index scans: N
pages: N removed, N remain, N scanned (…% of total), N eagerly scanned
tuples: N removed, N remain, N are dead but not yet removable
removable cutoff: N, which was N XIDs old when operation ended
new relfrozenxid: N, which is N XIDs ahead of previous value
frozen: N pages from table (…% of total) had N tuples frozen
visibility map: N pages set all-visible, N pages set all-frozen (N were all-visible)
index scan not needed: N pages from table (…% of total) had N dead item identifiers removed
avg read rate: … MB/s, avg write rate: … MB/s
buffer usage: N hits, N reads, N dirtied
WAL usage: N records, N full page images, N bytes, N buffers full
system usage: CPU: user: … s, system: … s, elapsed: … s
```

| Zeile | was sie sagt |
|-------|--------------|
| `tuples: … removed` | wie viele **tote Zeilenversionen** weggeräumt wurden — die Zahl aus 13.0 |
| `tuples: … remain` | wie viele lebende Zeilen danach dastehen |
| `… are dead but not yet removable` | **der wichtigste Wert:** tote Versionen, die noch **nicht** weggeräumt werden durften. Steht hier eine Zahl größer null, hält jemand einen Schnappschuss (13.4) |
| `removable cutoff` | bis zu welcher Transaktions-ID aufgeräumt werden durfte. „0 XIDs old" heißt: nichts hat aufgehalten |
| `new relfrozenxid` | der Stand für das Einfrieren (13.7) — er wandert mit jedem Lauf nach vorn |
| `pages: … removed` | leere Seiten am **Ende**, die abgeschnitten wurden (die `TRUNCATE`-Option aus 13.1) |
| `pages: … scanned (…%)` | wie viel wirklich gelesen wurde. Weniger als 100 % heißt: die Sichtbarkeitskarte hat Seiten übersprungen |
| `visibility map: … set all-visible` | wie viele Seiten **jetzt für alle sichtbar** sind. Ab dann kann `VACUUM` sie künftig überspringen — und `Index Only Scan`s werden möglich (5.3) |
| `frozen: … had … tuples frozen` | wie viele Zeilen eingefroren wurden. Bei einer kleinen, jungen Tabelle fast immer `0` |
| `index scans` / `index scan not needed` | ob Indexe mit aufgeräumt werden mussten |
| `buffer usage` | `hits` = lag im Cache, `reads` = kam von der Platte, `dirtied` = geänderte Puffer |
| `WAL usage` | **Aufräumen kostet Schreibzugriffe** — auch Wegräumen muss protokolliert werden |
| `system usage` | CPU-Zeit und Dauer des Vorgangs |

Drei Dinge, die daran überraschen:

- **Es erscheint mehr als eine Tabelle.** Unter `konto` taucht eine zweite auf:
  `pg_toast_…`. Das ist die TOAST-Tabelle, die jede Tabelle für übergroße Werte
  bekommt. Bleibt sie leer, waren alle Werte kurz genug.
- **`all-visible` ist ein Nebeneffekt, den man haben will.** Ist eine Seite für
  alle sichtbar, kann sie übersprungen werden — und ein `Index Only Scan` wird
  möglich.
- **`0 are dead but not yet removable` ist die gute Nachricht.** Genau diese
  Zeile wird ungleich null, sobald in einem anderen Fenster eine Transaktion
  offen steht — der Versuch dazu steht in 13.4.

---

## 13.2 Drei Dinge, die man trennt

| Anweisung | was sie tut |
|-----------|-------------|
| `VACUUM` | tote Zeilen wegräumen |
| `ANALYZE` | **Statistik** für den Planer sammeln (5.2, 11.5) |
| `VACUUM FREEZE` | aggressives Einfrieren (siehe 13.6) |

Wichtig: `VACUUM` sammelt **keine** Spaltenstatistik. Histogramme und häufigste
Werte kommen von `ANALYZE`. Deshalb schreibt die Doku `VACUUM ANALYZE` als
„handliche Kombination für routinemäßige Wartung" — und in der Übung aus 5.2 war
das `ANALYZE` nach dem `CREATE INDEX` genau deshalb nötig.

Vollständig sieht das so aus:

```sql
VACUUM (VERBOSE, ANALYZE) konto;
```

`VERBOSE` gibt einen ausführlichen Bericht auf `INFO`-Ebene — **das ist das
Kommando, mit dem man sieht, was passiert ist:**

```sql
VACUUM VERBOSE konto;
```

Erwartung: eine `INFO`-Zeile mit der Anzahl **entfernter toter Zeilenversionen**
und der betroffenen Seiten. Vergleiche das mit `n_dead_tup` aus 13.0.

Und ein Detail, das zu deiner `test`-Tabelle von vorhin passt: bei **GIN-Indizes**
erledigt `VACUUM` zusätzlich die aufgeschobenen Index-Einträge (`fastupdate`, die
„pending list").

---

## 13.3 VACUUM im laufenden Betrieb

- **Nicht im Transaktionsblock** (siehe 13.1).
- Man braucht das `MAINTAIN`-Recht auf der Tabelle — oder ist Eigentümer der
  Datenbank, dann darf man alles darin vacuumen.
- Es nimmt `SHARE UPDATE EXCLUSIVE` auf die Tabelle (7.6c). Deshalb kann `VACUUM`
  auch **warten** — wenn jemand eine kollidierende Sperre hält, etwa mit einer
  offenen Schemaänderung.
- `VACUUM (SKIP_LOCKED)` überspringt Tabellen, die gerade nicht sofort gesperrt
  werden können, statt zu warten.
- Es kostet **I/O**, und das kann andere Sitzungen bremsen. Dafür gibt es die
  kostenbasierte Verzögerung (`autovacuum_vacuum_cost_delay` und Verwandte).
- Den Fortschritt sieht man live: `pg_stat_progress_vacuum` für `VACUUM`,
  `pg_stat_progress_cluster` für `VACUUM FULL`.
- Und man muss es selten von Hand machen: **autovacuum** (13.5).

---

## 13.4 Warum eine offene Transaktion das Aufräumen verhindert

Das ist der praktisch wichtigste Abschnitt — und die Verbindung zu 12.7.

Eine tote Zeilenversion darf erst weggeräumt werden, wenn **kein Schnappschuss**
sie mehr sehen könnte. Eine Sitzung, die `BEGIN` gesagt hat und dann nichts tut,
hält so einen Schnappschuss offen. Also steht die Arbeit still.

**Fenster A:**

```sql
BEGIN;
SELECT * FROM konto;
-- offen lassen
```

**Fenster B:** erst die Änderungen aus 13.0, dann

```sql
VACUUM VERBOSE konto;
```

Erwartung: im Bericht steht jetzt eine Zahl toter Zeilenversionen, die **„cannot
be removed yet"** sind — nicht weggeräumt werden können. In A dann `COMMIT;` (oder
`ROLLBACK;`), und:

```sql
VACUUM VERBOSE konto;
```

Jetzt ist der Müll weg. Dieselbe Mechanik wie in 7.6b (Blockieren), 8.3
(`idle_in_transaction_session_timeout`) und 11.2 (ein Concurrent-Index-Build
wartet auf alte Schnappschüsse) — nur diesmal trifft es nicht eine Abfrage,
sondern die Hygiene der Tabelle.

---

## 13.5 Autovacuum

Autovacuum macht dasselbe, nur von allein. Es entscheidet anhand von Schwellen,
ob eine Tabelle „schmutzig genug" ist:

```sql
SHOW autovacuum_vacuum_threshold;      -- zusätzliche tote Zeilen
SHOW autovacuum_vacuum_scale_factor;   -- plus Anteil der Tabellengröße
SHOW autovacuum_naptime;               -- wie oft nachgesehen wird
```

Ob es zugeschlagen hat, steht in `pg_stat_user_tables` in `last_autovacuum` und
`autovacuum_count`. Bei einer Zwei-Zeilen-Tabelle passiert lange nichts — die
Schwelle ist deutlich höher als das, was unsere Experimente erzeugen.

### Es rettet dich nicht vor einer offenen Transaktion

Das ist der Punkt, den man beim ersten Kontakt übersieht: **Autovacuum hat genau
dieselbe Grenze wie ein `VACUUM` von Hand.** Kann eine tote Zeilenversion noch von
einem Schnappschuss gesehen werden, darf sie nicht weggeräumt werden — und
automatisch wird das nicht besser. Ein „vergessener" `BEGIN` von irgendwo in der
Anwendung bremst also die automatische Aufräumarbeit genauso aus wie einen
manuellen Lauf.

Sichtbar ist das an drei Stellen:

```sql
-- läuft gerade jemand?
SELECT pid, backend_type, state, left(query, 50) AS query
FROM pg_stat_activity
WHERE backend_type = 'autovacuum worker';
```

Der `backend_type` ist derselbe, den du in 7.5 und 10.6 schon gesehen hast.
Weiter:

```sql
SELECT * FROM pg_stat_progress_vacuum;                 -- was er gerade tut
SELECT relname, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables WHERE relname = 'konto';       -- ob er drankam
```

Steht der `n_dead_tup` hoch und `last_autovacuum` ist alt, arbeitet niemand — oder
jemand arbeitet erfolgreich dagegen an.

### Zwei verschiedene „geht nicht"

Das lohnt sich zu trennen, weil die Ursachen verschieden sind:

| Symptom | Ursache | Abhilfe |
|---------|---------|---------|
| `VACUUM` **wartet** | jemand hält eine kollidierende Tabellensperre (7.6c) | `SKIP_LOCKED`, oder die Sperre beenden |
| „… dead but **not yet removable**" im Bericht | ein **Schnappschuss** könnte die alten Versionen noch sehen (13.4) | die offene Transaktion beenden |

Im ersten Fall tut `VACUUM` gar nichts, im zweiten Fall tut er alles, was er darf —
und lässt den Rest liegen. Das ist der Unterschied zwischen „blockiert" und
„darf nicht".

### Wann es trotzdem schiefgeht

Autovacuum ist Schadensbegrenzung, kein Ersatz für kurze Transaktionen (7.6b,
8.3). Wenn dauerhaft etwas den Schnappschuss-Horizont festhält, wächst die
Tabelle — und irgendwann kommt die Notbremse für den Transaktionszähler
(13.7): Autovacuum wird dann aggressiv (`autovacuum_freeze_max_age`) und darf
sogar die Index-Aufräumung überspringen, um rechtzeitig fertig zu werden.

Zwei typische Fußangeln:

- **Autovacuum pro Tabelle abschalten.** `ALTER TABLE … SET (autovacuum_enabled =
  false)` gibt es wirklich, und es ist fast immer ein Fehler.
- **Eine lange lesende Transaktion.** Ein `SELECT` hält keine Zeilensperre
  (7.6c) — aber einen Schnappschuss. Man merkt nichts, bis die Tabelle groß ist.

Die eigentliche Antwort bleibt deshalb dieselbe wie in 7.6b: **Transaktionen
beenden.** Aufräumen kann immer nur so viel tun, wie die Schnappschüsse zulassen.

Die Schalter selbst — welche es gibt, welche davon einen Neustart brauchen und wie
man sie **pro Tabelle** statt global setzt — stehen in Teil 14.

---

## 13.6 Bloat: messen statt glauben

Die Größe der Tabelle bekommt man so:

```sql
SELECT pg_size_pretty(pg_relation_size('konto'))     AS tabelle,
       pg_size_pretty(pg_total_relation_size('konto')) AS gesamt;
```

Und der Effekt, den man einmal gesehen haben sollte, an der großen Tabelle:

```sql
-- vorher
SELECT pg_size_pretty(pg_relation_size('kurs')) AS vorher;

-- 4 Mio. Zeilen „ändern", ohne den Inhalt zu ändern
UPDATE kurs SET name = name;

-- nachher: etwa das Doppelte
SELECT pg_size_pretty(pg_relation_size('kurs')) AS nach_a_update,
       (SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'kurs') AS tot;

VACUUM kurs;
-- Größe bleibt gleich, die toten Zeilen sind weg

VACUUM FULL kurs;
-- jetzt ist die Datei wieder klein
```

Das ist die ganze Lektion in vier Zeilen: **`UPDATE kurs SET name = name;` ändert
nichts am Inhalt — und verdoppelt trotzdem die Tabelle.** Ein `VACUUM` macht den
Platz wieder nutzbar, ein `VACUUM FULL` gibt ihn zurück.

Dauer und Größen gehören in `06-kurs-notizen.md`, nicht hierher.

---

## 13.7 Freeze und Wraparound (kurz)

`xid` ist 32 Bit und läuft alle 4 Milliarden Transaktionen über (5.6). Damit das
kein Problem wird, markiert `VACUUM` sehr alte Zeilen als eingefroren — sie gelten
dann als „immer sichtbar" und müssen nicht mehr mitgezählt werden.

```sql
SELECT datname, age(datfrozenxid) AS alter
FROM pg_database
ORDER BY alter DESC;
```

`age()` sagt, wie viele Transaktionen seit dem ältesten nicht eingefrorenen
Xid vergangen sind. Autovacuum wird aggressiv, wenn das zu groß wird
(`autovacuum_freeze_max_age`).

Und es ist **keine** Theorie: in einem `VACUUM VERBOSE`-Bericht kann
`frozen: … had … tuples frozen` stehen — Zeilen, die in diesem Lauf eingefroren
wurden. Die Vorgabe `vacuum_freeze_min_age` liegt bei vielen Millionen
Transaktionen, deshalb passiert das bei einer kleinen Übungstabelle normalerweise
nicht. Wer es trotzdem sieht, hat `VACUUM FREEZE` benutzt oder den Parameter
gesenkt:

```sql
SHOW vacuum_freeze_min_age;
```

Ist eine Seite eingefroren, steht im Bericht auch `all-frozen`. Das ist der
Endzustand: eine solche Seite muss nie wieder angefasst werden.

---

## 13.8 Aufräumen

```sql
VACUUM (FULL, ANALYZE) konto;
DROP TABLE konto;      -- oder die Datei neu ausführen
```

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/04_konto.sql
```

Für `kurs` reicht es, den Zustand aus Teil 5 wiederherzustellen:

```sql
VACUUM FULL kurs;
ANALYZE kurs;
```
