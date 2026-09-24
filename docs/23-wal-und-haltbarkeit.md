# 23 — WAL und Haltbarkeit: die Schalter aus dem `# WRITE-AHEAD LOG`-Block

In Teil 20 war das WAL ein **Archiv**, in Teil 21 eine **Leitung**, in Teil 22 ein
**Inhalt** — aber jedes Mal war es einfach da. Hier geht es um die Frage davor:
**Was schreibt der Server überhaupt ins WAL, und wann sagt er „fertig"?**

Die Antwort steht in einem Block der `postgresql.conf`, der genauso heißt wie die
Sache: `# WRITE-AHEAD LOG`, Unterabschnitt `# - Settings -`. Sieben Zeilen, die
man überliest, weil davor überall ein `#` steht:

```ini
wal_level = replica            # minimal, replica, or logical
                               # (change requires restart)
fsync = on                     # flush data to disk for crash safety
                               # (turning this off can cause
                               #  unrecoverable data corruption)
synchronous_commit = on        # synchronization level
wal_sync_method = fsync        # the default is the first option
                               # supported by the operating system
full_page_writes = on          # recover from partial page writes
wal_log_hints = off            # also do full page writes of non-critical updates
                               # (change requires restart)
wal_compression = off          # enables compression of full-page writes
```

Zwei Dinge fallen an diesem Ausschnitt sofort auf — und beide sind der Einstieg in
das Thema:

- **Das `#` am Zeilenanfang ist kein Kommentar über den Wert, sondern eine
  Aussage:** „hier steht der Vorgabewert, gesetzt ist nichts". Die Werte rechts
  gelten trotzdem — sie sind eingebaut.
- **`synchronous_commit` ist die einzige Zeile *ohne* `#`.** Sie ist also bewusst
  gesetzt. Auf welchen Wert? Auf den, der auch die Vorgabe wäre. Wer das tut,
  dokumentiert eine Absicht, ohne etwas zu verändern — und genau darauf kommt es
  in diesem Teil an: **die Vorgaben sind schon sicher; die interessanten Fragen
  sind, wann man davon abweicht und was man dabei bezahlt.**

Die Doku-Kapitel, um die es geht:

- https://www.postgresql.org/docs/18/runtime-config-wal.html — der ganze Block,
  Einstellung für Einstellung, jeweils mit Vorgabe und `context`
- https://www.postgresql.org/docs/18/wal-reliability.html — der Abschnitt
  „Reliability", in dem `fsync`, `full_page_writes` und `wal_sync_method`
  zusammen erklärt werden
- https://www.postgresql.org/docs/18/wal-internals.html — was ein
  WAL-Datensatz und eine „Full Page Image" (FPI) sind
- https://www.postgresql.org/docs/18/runtime-config-replication.html —
  `synchronous_commit` und `synchronous_standby_names` (die Brücke zu Teil 21)
- https://www.postgresql.org/docs/18/monitoring-stats.html — `pg_stat_wal`
- https://www.postgresql.org/docs/18/app-initdb.html — Data Checksums, die
  Alternative zu `wal_log_hints`

> **Zwei Umgebungen, dieselben Befehle.** Der Kurs arbeitet auf PostgreSQL **19**
> (in der Doku: `/docs/19/…`). Dieses Repo läuft auf `postgres:18.6`, siehe
> [`compose.yaml`](../compose.yaml). Die Handgriffe sind identisch. Bei
> `wal_compression` unterscheiden sich die **erlaubten Werte** zwischen den
> Versionen — was deine Installation akzeptiert, sagt `pg_settings` (23.9), nicht
> dieses Dokument.

---

## 23.0 Zwei Fragen, die man nicht verwechseln darf

Der Grund, warum dieser Block so verwirrend ist: er beantwortet **zwei**
verschiedene Fragen, und die Antworten sehen ähnlich aus.

| Frage | Wovon hängt die Antwort ab | Teil |
|-------|---------------------------|------|
| „Übersteht meine Änderung einen **Absturz des Servers**?" | `fsync`, `full_page_writes`, `synchronous_commit` | hier |
| „Überlebt meine Datenbank, wenn die **Maschine** oder das **Verzeichnis** weg ist?" | Grundsicherung, WAL-Archiv, Standby | 20 und 21 |

Und innerhalb der ersten Frage gibt es noch eine zweite Trennung, die im
Betrieb **die** wichtige ist:

| Schalter aus | Was passiert bei einem Absturz |
|--------------|-------------------------------|
| `synchronous_commit = off` | die **letzten Transaktionen** sind weg — die Datenbank ist danach aber **in sich stimmig** |
| `fsync = off` | die Datenbank kann **beschädigt** sein — nicht nur Daten fehlen, sondern die Dateien passen nicht mehr zusammen |

Die erste Zeile ist eine **Entscheidung** („diese letzten Sekunden sind mir
gleichgültig"), die zweite ist ein **Risiko ohne Gegenwert**. Deshalb steht in der
Konfigurationsdatei selbst der Kommentar `turning this off can cause unrecoverable
data corruption` — und deshalb ist der Rest dieses Dokuments um diese zwei Zeilen
herum gebaut.

---

## 23.1 Der Block Zeile für Zeile

| Einstellung | Vorgabe | entscheidet | braucht |
|-------------|---------|-------------|---------|
| `wal_level` | `replica` | **was** überhaupt ins WAL kommt | Neustart |
| `fsync` | `on` | ob der Server den Schreibvorgang bis auf die Platte erzwingt | Reload |
| `synchronous_commit` | `on` | worauf ein `COMMIT` **wartet**, bevor es „ok" sagt | nichts — auch sitzungsweise |
| `wal_sync_method` | `fdatasync` (Linux) | **wie** das Erzwingen aussieht (welcher Systemaufruf) | Reload |
| `full_page_writes` | `on` | ob nach einem Absturz ganze Seiten mitgeloggt werden | Reload |
| `wal_log_hints` | `off` | ob auch reine Hinweis-Bits ganze Seiten erzeugen | **Neustart** |
| `wal_compression` | `off` | ob diese ganzen Seiten komprimiert werden | Reload |

Die Spalte „braucht" ist **nicht** die Wahrheit für jede Version und Plattform —
sie ist die Angabe, die in der Doku steht. Die Spalte, die es für *dein* System
verbindlich sagt, heißt `context` und steht in `pg_settings` (23.9). Genau
hierfür gibt es Teil 14.4: **erst nachsehen, dann ändern.**

Und das `(change requires restart)` in der Konfigurationsdatei ist derselbe
Hinweis, nur von Hand hineingeschrieben. Suche die zwei Stellen im Ausschnitt
oben — es sind genau die beiden, bei denen in der Tabelle „Neustart" steht.

---

## 23.2 `wal_level` — was überhaupt ins WAL kommt

Drei Stufen, von wenig nach viel:

| Wert | was im WAL landet | wofür es reicht |
|------|-------------------|-----------------|
| `minimal` | so wenig wie möglich, um nach einem Absturz wieder konsistent zu sein | der Server selbst |
| `replica` | zusätzlich alles, was eine **zweite Instanz** braucht (Vorgabe) | Teil 20 und 21 — Archiv, `pg_basebackup`, Standby |
| `logical` | zusätzlich die Informationen, um **Zeilenänderungen** zu lesen | Teil 22 — Publication/Subscription, `pg_rewind`-Slot-Lesen |

Die Richtung ist wichtig: mehr Stufe = **mehr WAL** (Platz, Schreiblast), aber
**nicht** mehr Sicherheit für die eigene Datenbank. `minimal` ist nicht unsicher,
es ist nur zu wenig für die anderen.

```sql
SHOW wal_level;
```

Auswirkung, die man im Betrieb direkt merkt: mit `wal_level = minimal` sagt
`pg_basebackup` nicht „mach ich nicht" — es gibt einen Weg, aber die
Replikation kann nach einem Neustart nicht einfach aufsetzen, und ein Standby
startet nicht. Wenn in Teil 21 „`wal_level` is insufficient" im Log stand, war
das hier die Ursache.

Und die Kurs-Falle, die in Teil 22 schon stand: **`logical` ist die einzige
Änderung an diesem Block, die ohne Neustart nicht gilt.** Ein `pg_reload_conf()`
hilft hier nicht.

---

## 23.3 `fsync` — der Schalter, den man nicht ausschaltet

`fsync = on` bedeutet: wenn der Server sagt „das WAL ist geschrieben", dann hat er
das Betriebssystem angewiesen, es wirklich auf das Gerät zu schreiben — statt es
im Schreib-Cache liegen zu lassen und es ihm zu *sagen*.

Der Unterschied wird genau einmal sichtbar: **bei einem Stromausfall.** Ohne
`fsync` meldet der Server ein `COMMIT` als bestätigt, die Daten liegen aber noch
irgendwo im Puffer. Danach steht die Datenbank nicht „auf einem alten Stand" —
sie kann an Stellen stehen, die es nie gab (mittendrin geschriebene Seiten,
verlorene WAL-Sätze). Deshalb heißt es in der Konfigurationsdatei
`unrecoverable data corruption`: **`fsync = off` ist nicht die „schnelle"
Version von `synchronous_commit = off`, es ist eine andere Kategorie.**

Im Übungscontainer ist ein Neustart billig — `fsync = off` in einer echten
Umgebung ist dagegen eine Wette auf die Hardware, die man nicht gewinnt.

Nachsehen, wie deine Installation es hält:

```sql
SHOW fsync;

SELECT name, setting, context, source
FROM pg_settings WHERE name = 'fsync';
```

`source` ist hier die interessante Spalte (Teil 14.3): steht dort `default`,
dann ist es die Vorgabe — und in der Konfigurationsdatei würde man den Wert
deshalb gar nicht sehen, weil die Zeile auskommentiert ist.

---

## 23.4 `synchronous_commit` — was ein `COMMIT` verspricht

Das ist der einzige Schalter aus dem Block, den man **gefahrlos sitzungsweise**
und für einzelne Vorgänge ändern darf. Er sagt nicht, *ob* geschrieben wird,
sondern **worauf gewartet wird, bis das `COMMIT` zurückkommt.**

| Wert | das `COMMIT` wartet auf | Verlust bei Absturz/Ausfall |
|------|------------------------|------------------------------|
| `off` | gar nicht — das WAL darf noch im Speicher liegen | die letzten Transaktionen |
| `local` | das lokale WAL ist durchgeschrieben | nichts, solange die lokale Platte lebt |
| `remote_write` | zusätzlich: eine Standby hat es **geschrieben** (nicht unbedingt auf Platte) | nichts beim Ausfall der Primary — die Standby hat es |
| `remote_apply` | zusätzlich: eine Standby hat es **nachgespielt** | nichts — und die Standby *zeigt* es auch schon |
| `on` (Vorgabe) | zusätzlich: eine Standby hat es auf Platte durchgeschrieben | nichts |

Zwei Konsequenzen, die man sich merken kann:

- Die unteren drei Zeilen setzen **`synchronous_standby_names`** voraus. Ist das
  leer (die Vorgabe), dann sind `local`, `remote_write`, `remote_apply` und `on`
  im Effekt dasselbe. Es wartet immer nur die lokale Platte.
- `off` ist der Schalter, mit dem man einen großen Import schnell macht: er
  verliert im Absturzfall **Arbeit**, aber nicht **Stimmigkeit**. Wenn der Inhalt
  ohnehin aus einer Datei kommt, die man erneut einspielen kann, ist das eine
  vertretbare Entscheidung.

```sql
SHOW synchronous_commit;

SET synchronous_commit = off;   -- nur diese Sitzung
SHOW synchronous_commit;
SELECT source FROM pg_settings WHERE name = 'synchronous_commit';

RESET synchronous_commit;       -- zurück zur Vorgabe
```

Und im Fenster daneben beobachten, wie lange ein `COMMIT` dauert — mit
`\timing on`. Der Vergleich „`on` gegen `off`" ist die erste eigene Messung in
23.11.

Die Verbindung zu Teil 21.7 ist genau hier: `synchronous_commit` ist die eine
Hälfte, `synchronous_standby_names` die andere. Ohne die zweite Hälfte gibt es
keine Standby, auf die man warten könnte.

---

## 23.5 `wal_sync_method` — wie „auf die Platte" aussieht

`fsync = on` sagt *dass* erzwungen wird. `wal_sync_method` sagt, *mit welchem
Aufruf*. Die Konfigurationsdatei zählt die Kandidaten selbst auf:

| Wert | was er tut |
|------|-----------|
| `open_datasync` | Datei beim Öffnen für direkte, ungepufferte Schreibzugriffe markieren |
| `fdatasync` | nur die **Daten** der Datei durchschreiben, nicht ihre Metadaten |
| `fsync` | Daten **und** Metadaten durchschreiben |
| `fsync_writethrough` | wie `fsync`, aber bis durch den Schreib-Cache des Geräts hindurch |
| `open_sync` | wie `open_datasync`, aber auch für Metadaten-Schreibzugriffe |

Die Vorgabe ist **der erste Eintrag der Liste, den die Plattform unterstützt** —
mit der Ausnahme, dass auf **Linux und FreeBSD `fdatasync`** die Vorgabe ist.
Auf welcher Plattform du bist, siehst du in der Ausgabe von:

```sql
SHOW wal_sync_method;
```

Das ist bewusst ein Schalter, an dem man **nichts tut, solange es funktioniert**:
welcher Aufruf schneller und welcher auf einem bestimmten Dateisystem überhaupt
korrekt ist, hängt an der Hardware und nicht an PostgreSQL. Nützlich ist die
Einstellung vor allem als Erklärung dafür, dass „auf die Platte schreiben" auf
verschiedenen Maschinen verschieden teuer ist — was man in 23.11 misst, ohne die
Einstellung überhaupt anzufassen.

---

## 23.6 `full_page_writes` — der Schutz gegen halb geschriebene Seiten

Hier steckt die interessanteste Idee des ganzen Blocks. Eine „Seite" in
PostgreSQL ist `BLCKSZ` groß (typisch 8 kB). Eine 8-kB-Seite landet aber nicht
in einem Rutsch auf dem Gerät: sie kann in Sektoren zerlegt werden, und wenn der
Strom **mittendrin** ausgeht, steht auf der Platte **halb die alte, halb die neue
Version** — eine Seite, die es nie gab. Man nennt das *torn page*, und sie ist
nicht durch Wiederholen des WAL zu reparieren, weil die Seite selbst kaputt ist.

`full_page_writes = on` löst das mit einem Trick:

> **Die erste Änderung an einer Seite nach dem letzten Checkpoint wird als
> vollständige Seitenkopie ins WAL geschrieben** — nicht als Änderung.

Damit kann die Wiederherstellung eine halb geschriebene Seite **komplett
ersetzen** statt sie fortzusetzen. Der Preis: das WAL wird größer, und zwar nach
jedem Checkpoint aufs Neue — genau einmal pro Seite, die zwischendurch angefasst
wird.

Das ist der Punkt, an dem man `full_page_writes = off` wirklich versteht: es ist
**nur dann** riskant, wenn es zu einem **unsauberen Abschalten** kommt, und
**nur dann** gefährlich, wenn das Dateisystem oder das Gerät keine ganzen Seiten
atomar schreibt. Es ist also kein Schalter für den laufenden Betrieb — es ist eine
Versicherung für den einen Absturz.

Und der Kommentar in der Konfigurationsdatei („also do full page writes of
non-critical updates") führt direkt zum nächsten Schalter: dieselbe Mechanik,
nur für Änderungen, die man sonst **nicht** mitloggen würde.

---

## 23.7 `wal_log_hints` — was `pg_rewind` zum Zurückholen braucht

PostgreSQL ändert beim Lesen gelegentlich „Hinweis-Bits" auf einer Seite — kleine
Merker im Kopf der Zeile, ohne dass sich für den Anwender etwas ändert. Diese
Änderungen gehen normalerweise **nicht** durchs WAL. Steht `wal_log_hints = on`,
erzeugt auch so eine Änderung eine ganze Seitenkopie, wie in 23.6.

Wofür das gut ist, hat man in Teil 21.6 gesehen: wenn aus einer Standby die neue
Primary wird, muss die **alte** (die inzwischen weitergeschrieben hat) wieder
anschließen können. Das Werkzeug dafür heißt `pg_rewind`, und es kann nur dann
arbeiten, wenn die Seiten, die es zurücksetzen muss, auch im WAL stehen. Deshalb:

- `wal_log_hints = off` (Vorgabe) ist **in Ordnung**, solange man kein
  `pg_rewind` braucht — also solange man beim Ausfall die alte Primary wegwirft.
- Wer ein Failover mit Rückkehr der alten Primary plant, macht es entweder hier
  an (`on`, **mit Neustart**), oder er hat die Datenbank schon mit
  **Data Checksums** angelegt (`initdb`, siehe der Link in der Einstiegsliste) —
  dann reichen die Prüfsummen aus, um dieselbe Frage zu beantworten.

Der Unterschied zu `full_page_writes` in einem Satz: das eine schützt die
**Wiederherstellung**, das andere die **Rückkehr einer alten Instanz**.

---

## 23.8 `wal_compression` — die ganzen Seiten kleiner machen

`wal_compression` komprimiert genau die Daten, die 23.6 und 23.7 gerade **größer**
gemacht haben: die vollständigen Seitenkopien. Man tauscht also CPU gegen
WAL-Volumen. Auf einem System, dessen Platte der Engpass ist, gewinnt man; auf
einem, dessen CPU der Engpass ist, verliert man.

Wichtig für den Kurs, weil sich hier die Versionen unterscheiden: was der
Parameter als Wert akzeptiert, ist nicht überall dasselbe. Die älteren Fassungen
kennen nur `off`/`on`, die neueren zusätzlich Namen für das Verfahren (in der
Doku zu `runtime-config-wal` steht die Liste für die jeweilige Version). Was
**deine** Installation erlaubt, sagt sie dir selbst:

```sql
SELECT name, setting, vartype, enumvals
FROM pg_settings WHERE name = 'wal_compression';
```

`enumvals` ist die Antwort auf „welche Werte gehen hier?" — und `vartype`
verrät, ob es überhaupt eine Auswahlliste ist oder ein einfacher An/Aus-Wert.

Was du in jedem Fall messen kannst, ist die Wirkung: die Zahl der geschriebenen
Seitenkopien steht in `pg_stat_wal` (23.9), die Größe des WAL in `pg_wal_lsn_diff`.

---

## 23.9 Nachsehen: `pg_settings`, `pg_stat_wal`, LSN

Der Block ist mit einer einzigen Abfrage zu überblicken — dieselbe Form wie in
14.3, hier auf die sieben Namen eingeschränkt:

```sql
SELECT name, setting, unit, context, vartype, source, pending_restart
FROM pg_settings
WHERE name IN ('wal_level', 'fsync', 'synchronous_commit', 'wal_sync_method',
               'full_page_writes', 'wal_log_hints', 'wal_compression')
ORDER BY name;
```

Die vier Spalten, die man liest:

| Spalte | Frage, die sie beantwortet |
|--------|----------------------------|
| `setting` | was **jetzt** gilt |
| `context` | **wann** eine Änderung greift (14.4): Neustart, Reload oder nur Sitzung |
| `source` | **woher** der Wert kommt — `default` heißt: die `#`-Zeile im Bild gilt |
| `pending_restart` | `true` = in der Datei steht schon etwas anderes, es greift erst nach dem Neustart |

Und die Zahlen zum WAL selbst:

```sql
SELECT * FROM pg_stat_wal;
```

Zwei Spalten daraus sind für hier gemacht:

- **`wal_fpi`** — wie viele **vollständige Seitenkopien** geschrieben wurden. Das
  ist die direkte Rechnung für `full_page_writes` (23.6) und `wal_log_hints`
  (23.7).
- **`wal_bytes`** — wie viel WAL insgesamt entstanden ist.

Die LSN als Maßband für einen Versuch:

```sql
SELECT pg_current_wal_lsn();

-- ... etwas tun ...

SELECT pg_current_wal_lsn(),
       pg_wal_lsn_diff(pg_current_wal_lsn(), 'HIER_DIE_ERSTE_LSN');
```

`pg_wal_lsn_diff` rechnet zwei LSNs in Bytes um; ohne es sind die Zahlen
unlesbar. `pg_switch_wal()` aus 20.4/21.3 schließt ein Segment ab — nützlich, um
im Verzeichnis zu sehen, dass wirklich etwas entstanden ist.

---

## 23.10 Übung: drei Versuche, drei Beobachtungen

Alles hier läuft in einer Sitzung und wird hinterher aufgeräumt (23.12). Nichts
davon braucht einen Neustart. Voraussetzung ist die Tabelle `konto` aus Teil 7 —
in die Versuche wird geschrieben:

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/04_konto.sql
```

**Versuch 1 — was ein `COMMIT` wartet.** Zwei Fenster, in beiden `\timing on`.
In Fenster A ein paar hundert Male etwas schreiben, einmal mit Vorgabe und einmal
mit `off`:

```sql
\timing on
INSERT INTO konto (id, betrag) SELECT 9000 + g, g FROM generate_series(1, 500) AS g;
```

```sql
SET synchronous_commit = off;
INSERT INTO konto (id, betrag) SELECT 9500 + g, g FROM generate_series(1, 500) AS g;
RESET synchronous_commit;
```

Vergleiche die beiden Zeiten. **Trag beide in `06-kurs-notizen.md` ein** — wie
groß der Unterschied ist, hängt an deiner Platte, nicht an PostgreSQL, und steht
deshalb nirgends in diesem Dokument.

**Versuch 2 — wie viele ganze Seiten geschrieben werden.** Ein Checkpoint setzt
den Ausgangspunkt, ab dem `full_page_writes` wieder zuschlägt:

```sql
CHECKPOINT;
SELECT wal_fpi, wal_bytes FROM pg_stat_wal;      -- Ausgangswert notieren

UPDATE konto SET betrag = betrag + 1;            -- viele Zeilen ändern
SELECT pg_switch_wal();

SELECT wal_fpi, wal_bytes FROM pg_stat_wal;      -- zweiter Wert
```

Die **Differenz** in `wal_fpi` ist die Anzahl der vollständigen Seitenkopien, die
dieser `UPDATE` gekostet hat. Vergleiche den Versuch mit einem `UPDATE`, das nur
**eine** Zeile trifft — und schau, ob die Differenz kleiner wird. Warum wohl?

**Versuch 3 — dieselbe Änderung, aber mit Kompression.** Nur wenn `enumvals` in
23.9 einen Kompressionswert erlaubt:

```sql
ALTER SYSTEM SET wal_compression = 'lz4';        -- Wert aus enumvals nehmen!
SELECT pg_reload_conf();

SELECT name, setting, pending_restart
FROM pg_settings WHERE name = 'wal_compression';
```

Dann Versuch 2 wiederholen und die `wal_bytes`-Differenz vergleichen.
`pending_restart = true` bedeutet hier, dass dieser Parameter einen Neustart
braucht — dann:

```bash
docker compose restart db
```

Zusatzfrage für `06-kurs-notizen.md`: ändert sich `wal_fpi` durch die
Kompression, oder nur `wal_bytes`? Die Antwort sagt, **was** komprimiert wird.

---

## 23.11 Was zwischen „sicher" und „schnell" schiefgeht

| Beobachtung | wahrscheinliche Ursache | wo nachsehen |
|-------------|------------------------|--------------|
| `wal_level` geändert, wirkt nicht | Reload reicht nicht — Neustart nötig | `pending_restart` in `pg_settings` |
| `pg_basebackup`/Standby scheitert mit „`wal_level` is insufficient" | `wal_level = minimal` | `SHOW wal_level;`, 23.2 und 21.8 |
| logische Replikation startet nicht | `wal_level` noch nicht `logical` (und/oder kein Neustart) | `SHOW wal_level;` (Teil 22) |
| `pg_wal` wächst und wächst, nichts läuft | ein Slot oder ein hängendes Archiv hält WAL zurück — **nicht** dieser Block | `pg_replication_slots`, `pg_stat_archiver` (21.7, 22.8) |
| Platte voll nach großen Änderungen | genau der Effekt von 23.6: viele `wal_fpi` | `pg_stat_wal`, `pg_wal_lsn_diff` (23.9) |
| ein `COMMIT` „hängt" plötzlich Sekunden | `synchronous_standby_names` gesetzt und die Standby ist weg | `pg_stat_replication` (21.7) |
| Datenbank nach einem Absturz beschädigt | irgendwo steht `fsync = off` | `pg_settings` (23.3) |
| Änderung an `wal_sync_method` hat nichts gebracht | der Wert ist gar nicht aktiv | `source` in `pg_settings` (14.3) |

Der Merksatz über der Tabelle: **drei der Zeilen sind Betriebsprobleme**
(Slot, Archiv, Standby), **und nur vier betreffen diesen Block**. Wenn `pg_wal`
wächst, ist die Ursache fast nie ein WAL-Schalter, sondern etwas, das den WAL
nicht abholt.

---

## 23.12 Aufräumen

Erst die Sitzungswerte, dann die Server-Werte:

```sql
RESET synchronous_commit;

ALTER SYSTEM RESET wal_compression;      -- nur, wenn du ihn gesetzt hast
SELECT pg_reload_conf();
```

Und die Kontrolle, die nach jedem Experiment gehört (dieselbe wie in 14.8):

```sql
SELECT name, setting, source, pending_restart
FROM pg_settings
WHERE source NOT IN ('default', 'configuration file')
ORDER BY name;
```

Steht hier noch etwas, das du nicht mehr willst: `ALTER SYSTEM RESET <name>;`
gefolgt von `SELECT pg_reload_conf();` — und wenn `pending_restart` `true` bleibt,
hilft nur `docker compose restart db`.

Die Zeilen aus Versuch 1 und 2 wieder wegräumen:

```sql
DELETE FROM konto WHERE id > 9000;
```

Und ein letzter Blick, ob der Server wieder auf Vorgabe steht:

```sql
SELECT name, setting, source
FROM pg_settings
WHERE name IN ('wal_level', 'fsync', 'synchronous_commit', 'wal_sync_method',
               'full_page_writes', 'wal_log_hints', 'wal_compression')
ORDER BY name;
```
