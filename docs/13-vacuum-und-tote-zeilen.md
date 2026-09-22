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
(`autovacuum_freeze_max_age`). Für dieses Projekt ist das reine Theorie; wenn du
tiefer willst, ist das ein eigenes Dokument.

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

---

## Was in `06-kurs-notizen.md` gehört

- `n_dead_tup` vor und nach `VACUUM` (nach 13.0)
- Was `VACUUM VERBOSE konto;` gemeldet hat: wie viele tote Zeilenversionen, in
  wie vielen Seiten?
- Wie viele tote Zeilen waren **„cannot be removed yet"**, solange Fenster A offen
  war — und wie viele danach?
- `pg_relation_size('kurs')` vor dem `UPDATE`, nach dem `UPDATE`, nach `VACUUM`,
  nach `VACUUM FULL`
- Wann hat autovacuum bei dir zugeschlagen (`last_autovacuum`)?
