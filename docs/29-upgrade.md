# 29 — Upgrade: eine Major-Version weiter

In Teil 20 wanderten **Daten** aus einer Sicherung zurück. Hier geht es um etwas
anderes: die **Software** wird getauscht. Bei einem *Major*-Sprung muss dabei
zugleich das **Datenverzeichnis** umziehen — es hat sein eigenes Format, und der
neue Server versteht das alte nicht mehr.

Beides wird leicht verwechselt, weil beide mit „Sicherung" und „Wiederherstellung"
zu tun haben. Deshalb der Satz vorweg: **ein Upgrade ist kein Restore.** Aber es
braucht fast immer die Werkzeuge aus Teil 20.

Und der zweite Satz, der den Aufwand entscheidet: **ein Major-Upgrade und ein
Minor-Update sind zwei verschiedene Dinge.** Nur das erste braucht dieses Kapitel.

Die Beispiele hier gehen von **18.6 auf 19**, weil das der Kurs-Sprung ist.
Ersetz die Zahlen, und es ist jeder Major-Sprung.

Die Doku-Kapitel, um die es geht:

- https://www.postgresql.org/docs/18/upgrading.html (der Überblick über die Wege)
- https://www.postgresql.org/docs/18/pgupgrade.html (das Werkzeug Weg A)
- https://www.postgresql.org/docs/18/app-pg-dumpall.html (globale Objekte, Weg B)
- https://www.postgresql.org/docs/18/logical-replication.html (die Brücke, Weg C)
- https://www.postgresql.org/support/versioning/ (Major gegen Minor)

> **Zwei Umgebungen, dieselben Befehle.** Der Kurs arbeitet auf PostgreSQL **19**
> — dort heißt das Datenverzeichnis `19/data` (dieselben Kapitel in der Doku:
> `/docs/19/…`). Dieses Repo läuft auf `postgres:18.6`, siehe
> [`compose.yaml`](../compose.yaml). In diesem Kapitel ist das **kein Nebensatz,
> sondern das Thema**: du brauchst beide Versionen **gleichzeitig** auf einer
> Maschine. Ob 19 bei dir schon fertig oder noch Beta ist, ändert keinen Schritt —
> nur, woher du die Binärdateien nimmst. Deinen eigenen Pfad zeigt
> `SHOW data_directory;`.

---

## 29.0 Major oder Minor — die Frage, die den Aufwand entscheidet

PostgreSQL nummeriert `MAJOR.MINOR`. Die **erste** Zahl ist die Major-Version
(etwa jährlich, mit Formatänderung), die **zweite** ist die Minor-Version
(Fehlerbehebungen, gleiches Format).

| Wechsel | Beispiel | Format des Datenverzeichnisses | was man macht |
|---------|----------|-------------------------------|---------------|
| **Major** | 18.6 → 19.x | ändert sich | `pg_upgrade` **oder** Dump **oder** Replikation (29.3–29.5) |
| **Minor** | 18.6 → 18.7 | bleibt | neue Binärdateien installieren, **Neustart** |

Nachsehen, wo man steht:

```sql
SELECT version();
SHOW server_version;
```

Der Fehler, den man hier macht: „18.6 auf 19" für dasselbe halten wie „18.6 auf
18.7". Beim Minor-Update tauschst du nur das Programm. Beim Major-Sprung **weigert
sich** der neue Server, das alte Verzeichnis zu öffnen — warum, steht in 29.1.

---

## 29.1 Warum 19 nicht einfach auf das 18-Verzeichnis startet

Das Datenverzeichnis trägt seine Version mit sich. Zwei Stellen zeigen sie:

- die Datei `PG_VERSION` im Datenverzeichnis,
- der **Catalog Version** in `pg_controldata`.

```bash
# den Pfad zuerst holen: SHOW data_directory;  → z. B. /var/lib/postgresql/18/docker
docker compose exec -u postgres -T db cat /var/lib/postgresql/18/docker/PG_VERSION
docker compose exec -u postgres -T db pg_controldata -D /var/lib/postgresql/18/docker
```

Startest du die neuen Binärdateien auf den alten Dateien, bricht der Start ab —
die Katalogtabellen sind anders aufgebaut als erwartet. Die Meldung dreht sich
um **incompatible** bzw. darum, dass das Verzeichnis von einer **anderen Version**
angelegt wurde. Das ist kein Rechte- und kein Konfigurationsfehler: es ist der
Hinweis, dass hier ein Upgrade fehlt.

Deshalb gibt es überhaupt die drei Wege in 29.3 bis 29.5. Alle drei haben dasselbe
Ziel: die **Daten** in ein **neu angelegtes** Verzeichnis der neuen Version zu
bringen.

---

## 29.2 Vorher: was im alten Cluster steht, das mit muss

Nicht die Tabellen sind der schwierige Teil — die kommen mit. Schwierig ist, was
**neben** den Tabellen hängt. Diese Abfragen sind die Inventur (auf der **alten**
Instanz):

```sql
SELECT * FROM pg_extension;                                   -- 1. Erweiterungen

SELECT spcname, pg_tablespace_location(oid) FROM pg_tablespace;  -- 2. Tablespaces

SELECT gid, prepared FROM pg_prepared_xacts;                  -- 3. muss leer sein

SELECT count(*) FROM pg_largeobject_metadata;                 -- 4. Large Objects
```

Was die vier Zeilen bedeuten:

| Zeile | warum sie zählt |
|-------|-----------------|
| Erweiterungen | jede muss im **neuen** Cluster installiert sein (die `.so`-Dateien), sonst bricht `pg_upgrade` ab |
| Tablespaces | liegen außerhalb von PGDATA; ihre **Pfade** müssen im neuen Cluster dieselben sein |
| `pg_prepared_xacts` | offene Two-Phase-Transaktionen blockieren das Upgrade — vorher auflösen (`ROLLBACK PREPARED`) |
| Large Objects | zählen als Daten, nicht als Tabelle: sie kommen mit, wenn man sie nicht vergisst |

Und zwei Dinge, die keine Abfrage zeigen:

- **`UNLOGGED`-Tabellen verlieren ihre Daten.** Das ist ihre Definition (Teil 23),
  aber beim Upgrade ist es eine Überraschung, wenn man sie nicht auf dem Zettel hat.
- **Statistiken wandern nicht mit.** Der Planer startet im neuen Cluster blind —
  deshalb gehört ans Ende **jedes** Weges ein `ANALYZE` (29.6).

Hinweis zum Umfang: der trockene Lauf `pg_upgrade --check` (29.3) prüft einen
Großteil davon selbst. Die Inventur hier ist dafür da, dass du die Antworten
**kennst**, bevor ein Skript sie dir vorhält.

---

## 29.2a Die drei Wege und ihr Ausfall

Bevor du dich für einen entscheidest: die drei Wege unterscheiden sich **vor
allem darin, womit der Ausfall wächst**. Das ist die Frage, die bei einer großen
Datenbank alles entscheidet.

| Weg | Werkzeug | Ausfall wächst mit … | Platz | nimmt mit |
|-----|----------|----------------------|-------|-----------|
| **A** | `pg_upgrade` | der **Zahl der Objekte** (mit `--link`), sonst der Datenmenge (`--copy`) | `--link`: nichts, `--copy`: Clustergröße | alles Dateibasierte |
| **B** | `pg_dump` + Restore | der **Datenmenge** | eine leere Instanz | nur, was `pg_dump` kennt |
| **C** | logische Replikation | **gar nichts** — beide laufen ja weiter | eine zweite Instanz | DML, aber kein DDL |

Der Merksatz dazu: **`--link` ist schnell, weil es nichts kopiert — es zeigt nur
um.** Deshalb hängt der Ausfall dort an der Zahl der Objekte (Tabellen, Indizes,
Sequenzen) und nicht an den Gigabyte. Wer „große DB, kleines Fenster“ hat, landet
deshalb fast immer bei **A mit `--link`** oder bei **C**. `--clone` (29.3) ist
derselbe Trick, nur ohne die `--link`-Falle.

Und die Gegenprobe: **B** wächst wie `--copy` mit der Datenmenge — dafür ist es
der einzige Weg, dem ein mehrfacher Versionsabstand egal ist (29.4).

---

## 29.3 Weg A: `pg_upgrade` — dieselben Dateien, neue Binärdateien

Das ist der Standardweg auf einer normalen Installation. Die Idee in Worten: der
alte Cluster wird **gestoppt** (nichts schreibt mehr); **daneben** legt man mit
den neuen Binärdateien einen **leeren** Cluster an; `pg_upgrade` bringt die Daten
vom alten in den neuen, indem es die Dateien **verlinkt oder kopiert**; danach
startet die neue Instanz.

Voraussetzung, die man nicht wegdiskutieren kann: **beide Binärsätze liegen
gleichzeitig auf der Maschine.** Genau dafür gibt es `-b` (alt) und `-B` (neu).

```bash
# 1) alte Instanz sauber stoppen — kein laufender Schreiber
docker compose exec -u postgres -T db pg_ctl -D /var/lib/postgresql/18/docker stop

# 2) leeren Ziel-Cluster mit den NEUEN Binärdateien anlegen
docker compose exec -u postgres -T db /usr/lib/postgresql/19/bin/initdb -D /var/lib/postgresql/19/data

# 3) trockener Lauf: prüfen, nichts ändern
docker compose exec -u postgres -T db /usr/lib/postgresql/19/bin/pg_upgrade \
    -b /usr/lib/postgresql/18/bin -B /usr/lib/postgresql/19/bin \
    -d /var/lib/postgresql/18/docker -D /var/lib/postgresql/19/data \
    --check
```

Erst wenn `--check` sauber durchläuft, der echte Lauf:

```bash
docker compose exec -u postgres -T db /usr/lib/postgresql/19/bin/pg_upgrade \
    -b /usr/lib/postgresql/18/bin -B /usr/lib/postgresql/19/bin \
    -d /var/lib/postgresql/18/docker -D /var/lib/postgresql/19/data \
    --link --jobs 4
```

Die Schalter, die den Weg bestimmen:

| Schalter | was er tut | Preis |
|----------|------------|-------|
| `--check` | prüft nur, verändert nichts | keiner — immer zuerst |
| `--copy` (**Vorgabe**) | kopiert die Dateien | braucht **Platz** in Höhe des Clusters; der alte Cluster bleibt als Sicherung intakt |
| `--link` | verlinkt die Dateien (Hardlinks) | schnell und platzsparend — aber der **alte Cluster ist danach tot**, weil beide dieselben Dateien teilen |
| `--clone` | klont die Dateien im Dateisystem (Reflink / Copy-on-Write) | so schnell wie `--link`, **aber** der alte Cluster bleibt heil — nur auf Dateisystemen, die es können (btrfs, XFS mit reflink); nicht jede `pg_upgrade`-Version kennt den Schalter, sieh in `--help` nach |
| `--jobs` | parallelisiert das Übertragen | mehr Last während des Laufs |

> **`--link` ist die Falle.** Es ist der schnellste Weg und sieht harmlos aus —
> aber danach darfst du den alten Cluster **nicht mehr starten**. Wer den alten
> Stand als Sicherung behalten will, nimmt `--copy` **oder** hat vorher ein
> Backup (Teil 20) — beides gehört zusammen. Wer beides will, schnell **und**
> einen heilen alten Cluster, nimmt `--clone`, wenn das Dateisystem es hergibt:
> derselbe Trick wie `--link`, nur ohne die Falle.

Dann die Konfiguration — **das ist der Restore-Teil, den man vergisst.** `initdb`
legt im neuen Cluster **Vorgabe**-Dateien an. Deine Einstellungen aus Teil 14
liegen aber im alten Datenverzeichnis und kommen nicht mit:

```bash
# die drei Dateien aus dem alten Datenverzeichnis hinüberbringen
docker compose exec -u postgres -T db cp /var/lib/postgresql/18/docker/postgresql.conf /var/lib/postgresql/19/data/postgresql.conf
docker compose exec -u postgres -T db cp /var/lib/postgresql/18/docker/pg_hba.conf       /var/lib/postgresql/19/data/pg_hba.conf
docker compose exec -u postgres -T db cp /var/lib/postgresql/18/docker/pg_ident.conf     /var/lib/postgresql/19/data/pg_ident.conf
```

Zwei Dinge dazu:

- **Eine alte `postgresql.conf` in eine neue Version zu kopieren, meldet sich.**
  Parameter, die die neue Version entfernt hat, stehen nach dem Start im Log.
  Deshalb: starten, Log lesen — nicht „läuft ja“ annehmen.
- **`postgresql.auto.conf` nicht mitkopieren.** Darin stehen die `ALTER SYSTEM`-Werte
  (Teil 14), und die Datei verwaltet der Server selbst — setz die Werte im neuen
  Cluster neu, statt die Datei zu überschreiben.

Danach die neue Instanz starten und die Statistik neu erzeugen:

```bash
docker compose exec -u postgres -T db pg_ctl -D /var/lib/postgresql/19/data -o "-p 5433" start

# pg_upgrade hinterlässt einen Hinweis bzw. ein kleines Skript im Arbeitsverzeichnis:
#   analyze_new_cluster.sh   bzw.   vacuumdb --all --analyze-in-stages
docker compose exec -u postgres -T db vacuumdb -p 5433 --all --analyze-in-stages
```

`pg_upgrade` kopiert **keine** Statistiken und wärmt keinen Cache. Der
`analyze`-Schritt ist deshalb kein Feinschliff, sondern Teil des Upgrades: ohne
ihn plant der Server im neuen Cluster mit Schätzungen, die er sich gerade eben
ausgedacht hat (Teil 19).

Zum Schluss — und **erst** wenn du geprüft hast — das Aufräumskript des alten
Clusters. Bis dahin liegen die alten Dateien noch da.

> **Woher die zweite Binärversion kommt, ist eine Umgebungsfrage.** In diesem
> Container liegen nur die 18.6-Binärdateien unter `/usr/lib/postgresql/18/bin`.
> Für den echten Sprung brauchst du die 19-Binärdateien daneben — aus einem
> `postgres:19`-Image oder aus den Paketen deiner Distribution (PGDG-Repository).
> `pg_upgrade` ist das egal: es will nur, dass **beide** erreichbar sind und
> `-b`/`-B` dorthin zeigen.

---

## 29.4 Weg B: Dump und in eine neue Instanz einspielen

Dieser Weg braucht **kein** Nebeneinander der Binärsätze: er transportiert die
Daten als Text. Er ist der langsamste und der mit dem längsten Ausfall — dafür
versteht er jeden Versionsabstand, auch über mehrere Major-Versionen hinweg.

Er benutzt genau die Werkzeuge aus 20.1 — nur mit dem Ziel „neue Instanz"
statt „Auffang-Datenbank".

**1. Globale Objekte und den Dump ziehen** (auf der **alten** Instanz, Port 5432):

```bash
docker compose exec -u postgres -T db pg_dumpall -g > /var/lib/postgresql/backup/globals.sql
docker compose exec -u postgres -T db pg_dump -U kurs -d kurs -Fc -f /var/lib/postgresql/backup/kurs.dump
```

Die `-g`-Datei ist die, die man vergisst: **Rollen samt Passwörtern und die
Tablespace-Definitionen** stehen nicht im normalen Dump (20.1). Fehlt sie, steht
im neuen Cluster ein Schema ohne die Benutzer, die es benutzen sollen.

**2. Eine neue Instanz aufsetzen** — dasselbe Muster wie in 20.6 und 21.2: ein
eigenes Datenverzeichnis, ein eigener Port, damit die alte Instanz noch läuft:

```bash
# mit den NEUEN Binärdateien, deshalb der volle Pfad
docker compose exec -u postgres -T db /usr/lib/postgresql/19/bin/initdb -D /var/lib/postgresql/19/data
docker compose exec -u postgres -T db pg_ctl -D /var/lib/postgresql/19/data -l /var/lib/postgresql/19.log -o "-p 5433" start
```

**3. Einspielen** (in die **neue** Instanz, Port 5433):

```bash
docker compose exec -u postgres -T db psql -p 5433 -U postgres -d postgres -f /var/lib/postgresql/backup/globals.sql
docker compose exec -T db pg_restore -p 5433 -U kurs -d kurs /var/lib/postgresql/backup/kurs.dump
```

Und dann, was bei jedem Weg ans Ende gehört: `ANALYZE` (29.6).

Was dieser Weg mitnimmt — und was nicht:

| | Weg A (`pg_upgrade`) | Weg B (Dump) |
|---|---|---|
| Binärdateien | **beide** nötig | nur die neue |
| Ausfall | nur der Umzug | Dump + Restore |
| Platz | wie gewählt (`--copy`/`--link`/`--clone`) | eine leere Instanz |
| nimmt mit | alles Dateibasierte, inkl. Statistiken | nur, was `pg_dump` kennt |
| Versionsabstand | benachbart (18 → 19) | beliebig |

---

## 29.5 Weg C: logische Replikation als Brücke

Beide Wege oben haben einen Moment, in dem **nichts** läuft. Wer den Ausfall gegen
fast null drücken will, lässt **beide** Versionen zugleich laufen und spiegelt die
Daten hinüber — dann wird umgeschaltet. Das ist die logische Replikation aus
Teil 22: auf der alten Instanz eine `PUBLICATION`, auf der neuen eine
`SUBSCRIPTION`.

Der Preis, den man kennen muss: die Brücke überträgt **DML, nicht DDL**. Ein
`ALTER TABLE` muss drüben selbst passieren, sonst bricht die Subscription ab. Und
Sequenzen synchronisiert sie nicht von allein — den letzten Wert holt man vor dem
Umschalten ausdrücklich herüber. Das sind genau die Punkte, an denen man auf
diesem Weg umschaltet.

Dieses Kapitel baut die Brücke nicht neu auf — sie steht schon in
[docs/22-logische-replikation.md](22-logische-replikation.md) und in 20.2 als
Rückweg einzelner Objekte.

---

## 29.6 Die Reihenfolge, die auf allen Wegen gleich ist

| Phase | was passiert | Anschluss |
|-------|--------------|-----------|
| **vorher** | Backup ziehen, Inventur (29.2), `--check`, Zielversion installieren | Teil 20, 29.1, 29.2 |
| **während** | alte Instanz stoppen, neuen Cluster `initdb`en, Daten umziehen (A/B/C) | 29.3, 29.4, 29.5 |
| **nachher** | starten, `ANALYZE`, Erweiterungen prüfen (`\dx`), ggf. `REINDEX`, erst dann umschalten | 29.6 unten |
| **zuletzt** | alten Cluster löschen — **wenn** du die Sicherung hast | 29.8 |

Der „nachher"-Block ist der, den man überspringt, weil die Instanz ja schon
antwortet. Die drei Handgriffe darin:

```sql
\dx                                   -- sind alle Erweiterungen da? (29.2)
```

```bash
docker compose exec -u postgres -T db vacuumdb -p 5433 --all --analyze-in-stages
```

- **`ANALYZE`**: ohne Statistik ist der Planer schlecht (Teil 19).
- **`REINDEX`**: wenn das Betriebssystem oder die Locale der neuen Maschine eine
  andere ist, können Indexschüssel für Text anders sortieren als gespeichert.
  Das ist der Grund, warum die Doku vor „anderer Locale" ausdrücklich warnt.
- **Umschalten**: erst wenn `\dx` vollständig ist und der neue Cluster geantwortet
  hat, zeigt man die Clients auf den neuen Port. Vorher zeigt man sie **nicht**
  dorthin — ein halb bespielter Server ist schlimmer als ein alter.

---

## 29.7 Was schiefgeht

| Symptom | wahrscheinliche Ursache | wo nachsehen |
|---------|-------------------------|--------------|
| Start bricht ab: Datenverzeichnis „incompatible" | die neue Version zeigt auf das **alte** Verzeichnis | 29.1, `pg_controldata`, `PG_VERSION` |
| `pg_upgrade` bricht bei „required libraries" ab | eine Erweiterung ist im neuen Cluster nicht installiert | `pg_extension` (29.2), `\dx` |
| „Prepared transactions are present" | offene Two-Phase-Transaktionen | `pg_prepared_xacts` (29.2), `ROLLBACK PREPARED` |
| „could not access … tablespace" | Tablespace-Pfad im neuen Cluster anders | `pg_tablespace` (29.2) |
| Alter Cluster startet nach dem Upgrade nicht mehr | `--link` benutzt — die Dateien sind geteilt | 29.3 (und dein Backup aus Teil 20) |
| Pläne sind nach dem Upgrade schlechter | Statistik fehlt | `vacuumdb --analyze-in-stages` (29.6) |
| Text-Indizes sortieren anders / Fehler mit „collation" | neue Maschine hat eine andere OS-Locale | Doku `upgrading.html`, `REINDEX` (29.6) |
| Nach dem Dump-Weg fehlen Rollen | `pg_dumpall -g` vergessen | 20.1, 29.4 |
| Daten einer `UNLOGGED`-Tabelle sind weg | das ist ihre Definition | Teil 23, 29.2 |

Der Merksatz über dieser Tabelle: **die Fehler stecken nicht im Upgrade-Befehl,
sondern in dem, was ringsum hängt** — Erweiterungen, Tablespaces, offene
Transaktionen, Locale. Der Umzug der Tabellen ist der einfache Teil.

---

## 29.8 Aufräumen

Erst die **neue** Instanz stoppen — die **alte** bleibt vorerst, sie ist deine
Rückversicherung, solange du sie nicht mit `--link` entwertet hast:

```bash
docker compose exec -u postgres -T db pg_ctl -D /var/lib/postgresql/19/data stop
```

Dann den Platz des Übungs-Clusters zurückholen, **nachdem** du geprüft hast:

```bash
docker compose exec -u postgres -T db rm -rf /var/lib/postgresql/19 /var/lib/postgresql/19.log
```

Ein `docker compose down -v` löscht wie immer das ganze Volume und damit **auch
die Original-Daten** aus 18 (Teil 2) — als Aufräumbefehl ist das zu grob.

> **Keine Zahlen in diesem Dokument.** Wie lange ein Upgrade läuft und wie viel
> Platz `--copy` braucht, hängt an der Größe deines Clusters und an der Platte —
> nicht an PostgreSQL. Miss es selbst (`\timing on`, und die Größe wie in 20.1
> über `pg_size_pretty(pg_database_size(…))`) und trag es in
> [docs/06-kurs-notizen.md](06-kurs-notizen.md) ein. Hier steht absichtlich
> nichts.
