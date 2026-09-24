# 20 — Wiederherstellung: ganzer Server, ein Zeitpunkt, einzelne Objekte

„Recovery" heißt in PostgreSQL nicht ein Verfahren, sondern mehrere. Wer sie
verwechselt, plant die falsche Sicherung — und merkt es erst, wenn es weh tut.

Deshalb steht hier zuerst die Frage **„welcher Unfall war es?"**, danach die
Werkzeuge und erst dann die Übung.

Die drei Doku-Kapitel, um die es geht:

- https://www.postgresql.org/docs/18/backup-dump.html (logische Sicherung)
- https://www.postgresql.org/docs/18/app-pgbasebackup.html (physische Sicherung)
- https://www.postgresql.org/docs/18/continuous-archiving.html (WAL-Archiv, PITR)

Und die Einstellungen, um die es geht:
https://www.postgresql.org/docs/18/recovery-config.html und
https://www.postgresql.org/docs/18/runtime-config-wal.html

> **Zwei Umgebungen, dieselben Befehle.** Der Kurs arbeitet auf PostgreSQL **19**
> — dort heißt das Datenverzeichnis `19/data` und die Sicherung liegt als
> `backup/` daneben (dieselben Kapitel in der Doku: `/docs/19/…`). Dieses Repo
> läuft auf `postgres:18.6`, siehe [`compose.yaml`](../compose.yaml). Die
> Handgriffe sind identisch, nur Pfade und Versionsnummer unterscheiden sich.
> Deinen eigenen Pfad zeigt `SHOW data_directory;`.

---

## 20.0 Welcher Unfall — welches Werkzeug

| Unfall | Rettung |
|--------|---------|
| `DELETE`/`UPDATE` ohne `WHERE`, falscher Wert in einer Tabelle | logischer Dump, ggf. nur die eine Tabelle (20.2) |
| `DROP TABLE`, `DROP SCHEMA`, `TRUNCATE` | logischer Dump (20.2) |
| Datenbank komplett gelöscht, Rolle/Passwort weg | `pg_dump`/`pg_dumpall` (20.1), Rollen aus `-g` |
| falsche Migration um 14:05 durchgelaufen | **PITR auf einen Zeitpunkt** (20.5, 20.6) |
| Platte defekt, PGDATA weg, Maschine weg | physische Sicherung + WAL-Archiv (20.3, 20.4) |
| Server abgestürzt, nichts gesichert | **Crash Recovery** — passiert von allein |

Die letzte Zeile ist der Punkt, an dem man versteht, warum PostgreSQL WAL
überhaupt schreibt: nach einem Absturz startet der Server und spielt das
Write-Ahead-Log nach, ohne dass jemand eingreift. Das ist **keine**
Wiederherstellung aus einer Sicherung, sondern das Normale. Alles andere in
diesem Dokument muss man vorher eingerichtet haben.

Merksatz: **Ohne WAL kommt man nur bis zum Ende der Sicherung zurück — ohne
Sicherung nützt auch das schönste WAL-Archiv nichts.** Beides gehört zusammen,
und beides muss man eingerichtet haben, *bevor* der Unfall passiert.

---

## 20.1 Logisch sichern: `pg_dump`

```bash
docker compose exec -u postgres -T db mkdir -p /var/lib/postgresql/backup
docker compose exec -u postgres -T db pg_dump -U kurs -d kurs -Fc -f /var/lib/postgresql/backup/kurs.dump
```

Die vier Formate und wann man welches nimmt:

| `-F` | Format | wofür |
|------|--------|-------|
| `p` (Vorgabe) | reines SQL-Skript | lesbar, mit `psql -f` einspielbar |
| `c` | `custom`, komprimiert | **der Alltagsfall**: mit `pg_restore` teilweise einspielbar |
| `d` | Verzeichnis | erlaubt `-j` (parallel) |
| `t` | `tar` | selten; kein `pg_restore -j` |

Was `pg_dump` **nicht** enthält — und was deshalb extra gesichert werden muss:

- **Rollen und deren Passwörter**: `pg_dumpall -r` (oder `-g` für alle globalen
  Objekte). Ohne diese Datei steht nach dem Einspielen ein Schema ohne die
  Benutzer da, die es benutzen sollen.
- **Tablespace-Definitionen**: die gehören zum Dateisystem, nicht in den Dump
  (siehe 20.7).

Zwei Eigenschaften, die man kennen muss:

- Der Dump läuft **in einer einzigen Transaktion** und sieht damit einen
  konsistenten Schnappschuss (Teil 12) — es wird also nicht mitten im Dump
  „weitergeschrieben". Beim parallelen Dump in ein Verzeichnis (`-Fd -j`) werden
  die Schnappschüsse der Arbeiter dafür synchronisiert.
- Andere Sitzungen dürfen währenddessen weiterarbeiten. Aber **DDL** während des
  Dumps ist eine schlechte Idee: ändert jemand die Tabelle, während sie gelesen
  wird, kann der Dump fehlschlagen oder unvollständig sein. Die Doku sagt dazu,
  dass man bei Schemaänderungen zur falschen Zeit einen Fehler bekommt und den
  Dump wiederholen muss.

Vorher nachsehen, wie groß das wird:

```sql
SELECT pg_size_pretty(pg_database_size('kurs'));
```

---

## 20.2 Einzelne Objekte zurückholen — das ist der häufigste Fall

Aus einem `custom`-Dump lässt sich **herausnehmen, was man braucht**. Das ist
genau dann wichtig, wenn in der Produktion eine Tabelle fehlt, aber die
Datenbank weiterläuft: man will nicht die ganze Datenbank überschreiben.

Zuerst das **Inhaltsverzeichnis** ansehen — es listet jedes Objekt im Dump:

```bash
docker compose exec -T db pg_restore -l /var/lib/postgresql/backup/kurs.dump
```

Das ist die Antwort auf „was steckt eigentlich in der Sicherung?" — und die
Liste ist bearbeitbar. Der Weg in der Doku:

```bash
# Liste in eine Datei schreiben, dort Zeilen löschen, Liste benutzen
docker compose exec -u postgres db bash -c "pg_restore -l /var/lib/postgresql/backup/kurs.dump > /var/lib/postgresql/backup/inhalt.txt"
docker compose exec -T db pg_restore -U kurs -L /var/lib/postgresql/backup/inhalt.txt -d kurs /var/lib/postgresql/backup/kurs.dump
```

Und die Kurzformen für eine einzelne Tabelle bzw. ein Schema:

```bash
docker compose exec -T db pg_restore -U kurs -d kurs -t konto  /var/lib/postgresql/backup/kurs.dump
docker compose exec -T db pg_restore -U kurs -d kurs -n public /var/lib/postgresql/backup/kurs.dump
```

Was dabei zu wissen ist:

- Was zu einer Tabelle **noch dazugehört** — Indizes, Constraints, Sequenz, ihr
  Eigentümer —, steht im Inhaltsverzeichnis aus `-l`. Nimm nicht an, dass nur
  die Tabelle kommt: vergleiche die Einträge vor und nach dem Filtern.
- Mit `--section=pre-data|data|post-data` zerlegt man das: Definition zuerst,
  Daten, dann Indizes und Constraints. Für „Tabelle ist noch da, nur der Inhalt
  ist falsch" ist `data` das Mittel der Wahl.
- Der Dump wurde mit **allen** Tabellen erzeugt (kein `-t` beim Sichern), sonst
  ist in der Sicherung nur die eine Tabelle drin. Wer einzelne Objekte retten
  will, muss sie also auch einzeln gesichert haben oder eine Vollsicherung
  haben.
- `pg_restore` bricht nicht beim ersten Fehler ab, sondern zählt die Fehler und
  meldet sie am Ende. Diese Zeile lesen — sonst hält man eine halbe
  Wiederherstellung für eine ganze. `-e` erzwingt Abbrechen beim ersten Fehler.

### Der sichere Weg, wenn das Objekt noch existiert

`pg_restore -t konto -d kurs` auf eine **vorhandene** Tabelle scheitert an
`already exists`. Wer dann `--clean --if-exists` benutzt, löscht erst die
Tabelle im Ziel — in der Produktion ein zweiter Unfall.

Besser: in eine **Auffang-Datenbank** einspielen und die Daten von dort
zurückholen:

```bash
docker compose exec -T db createdb -U kurs rettung
docker compose exec -T db pg_restore -U kurs -d rettung -t konto /var/lib/postgresql/backup/kurs.dump
```

Dann drüben arbeiten und die Tabelle hierher zurückholen:

```bash
docker compose exec db bash -c "pg_dump -U kurs -d rettung -t konto | psql -U kurs -d kurs"
```

Die Auffang-Datenbank ist auch der Ort, an dem man erst einmal **nachsieht**, ob
der alte Stand wirklich der ist, den man will — bevor man in der echten Datenbank
etwas anfasst.

---

## 20.3 Physisch sichern: `pg_basebackup`

Die logische Sicherung kennt nur Tabellen. Die physische kopiert **das
Datenverzeichnis** — PGDATA, alle Datenbanken, alle Kataloge, alle Rollen. Das
ist die Grundlage, auf der man danach WAL nachspielen kann.

Voraussetzungen prüfen, nicht raten:

```sql
SHOW wal_level;        -- Vorgabe ist replica — welcher Wert für Sicherung und Archiv nötig ist, steht in der Doku
SHOW max_wal_senders;  -- für -X stream; 0 hieße: keine WAL-Übertragung
SHOW data_directory;   -- was genau kopiert wird (Hinweis in compose.yaml)
```

```bash
docker compose exec -u postgres -T db pg_basebackup -U kurs -h /var/run/postgresql \
    -D /var/lib/postgresql/base -X stream -c fast -P
```

| Option | Zweck |
|--------|-------|
| `-D` | Zielverzeichnis — muss **leer oder nicht vorhanden** sein |
| `-X stream` | schickt das währenddessen anfallende WAL mit (`fetch` sammelt es erst am Ende ein und braucht dann, dass die Dateien im `pg_wal` der Quelle noch liegen — Stichwort `wal_keep_size`) |
| `-c fast` | erzwingt einen schnellen Checkpoint — verkürzt die Dauer der Sicherung |
| `-P` | Fortschritt anzeigen (sonst sieht man minutenlang nichts) |
| `-T alt=neu` | Pfad eines Tablespace umschreiben (20.7) |
| `-R` | schreibt `standby.signal` + `primary_conninfo` mit hinein |

`-R` ist hier **absichtlich nicht** dabei: damit entsteht ein Standby, keine
Sicherung, die man auf einen Zeitpunkt zurückspielt (20.6).

Prüfen, dass die Sicherung vollständig ist:

```bash
docker compose exec -T db pg_verifybackup /var/lib/postgresql/base
```

Das vergleicht jede Datei mit der Prüfsumme, die `pg_basebackup` in der Datei
`backup_manifest` mitgeschrieben hat. Wer sie nie laufen lässt, weiß bis zur
Wiederherstellung nicht, ob die Sicherung heil ist.

Zum Hineinsehen gibt es außerdem:

```bash
docker compose exec -T db pg_controldata /var/lib/postgresql/base
```

---

## 20.4 WAL archivieren

Ohne Archiv gibt es keine Wiederherstellung auf einen Zeitpunkt — nur den
Zustand „Ende der Sicherung". Der Server muss die abgeschlossenen WAL-Segmente
also wegschreiben, bevor er sie löscht.

Drei Dinge sind dafür zu setzen, und sie unterscheiden sich genau so, wie Teil 14
es beschreibt:

```sql
SHOW archive_mode;      -- context = postmaster  -> Neustart nötig
SHOW archive_command;   -- context = sighup      -> Reload genügt
SHOW wal_level;         -- context = postmaster  -> Neustart nötig
```

Woher die Werte kommen und was ein `context` bedeutet, steht in 14.3 — hier ist
es genau dasselbe Werkzeug:

```sql
SELECT name, setting, context, source, pending_restart
FROM pg_settings
WHERE name IN ('archive_mode', 'archive_command', 'archive_timeout', 'wal_level');
```

```sql
ALTER SYSTEM SET archive_mode = on;
ALTER SYSTEM SET archive_command = 'test ! -f /var/lib/postgresql/walarchiv/%f && cp %p /var/lib/postgresql/walarchiv/%f';
ALTER SYSTEM SET archive_timeout = '60s';
```

```bash
docker compose exec -u postgres -T db mkdir -p /var/lib/postgresql/walarchiv
docker compose restart db          # NICHT `down -v` — das löscht das Volume
```

In `archive_command` sind **Pfad und Dateiname zwei verschiedene Dinge** — das
ist der Platzhalter-Teil aus der Doku:

| Platzhalter | ersetzt durch |
|-------------|---------------|
| `%p` | den **Pfad** der zu archivierenden Datei (Verzeichnis und Name) |
| `%f` | nur den **Dateinamen** (`0000000100000000000000AB`) |

Deshalb das `test ! -f … && cp %p %f`: der Server darf denselben Aufruf
**mehrfach** losschicken (etwa wenn er beim ersten Mal fehlschlug), und ein
bereits vorhandenes Ziel darf dabei nicht noch einmal geschrieben werden. Und
deshalb muss `archive_command` **Erfolg als Rückgabewert 0 melden** — tut er das
nicht, gilt das Segment als nicht archiviert, der Aufruf kommt in Abständen
wieder und es wird weiter kein WAL aufgeräumt.

Zusehen, ob es läuft:

```sql
SELECT * FROM pg_stat_archiver;
SELECT pg_current_wal_lsn();
SELECT pg_switch_wal();           -- Segment sofort abschließen, damit es archiviert wird
```

```bash
docker compose exec -T db ls -l /var/lib/postgresql/walarchiv
```

`pg_stat_archiver` ist die Stelle, an der man einen kaputten Archivbefehl
erkennt: `failed_count` steigt, `last_failed_wal` benennt die Datei,
`last_failed_time` den Zeitpunkt. Was dann passiert, ist die wichtigste Warnung
des Themas: **Der Server kann sein WAL nicht mehr aufräumen und das Verzeichnis
`pg_wal` wächst an, bis die Platte voll ist.** Ein still fehlschlagendes Archiv
fällt nicht im Betrieb auf, sondern erst beim Speicherplatz.

Und: archiviert werden nur **abgeschlossene** Segmente. Deshalb `archive_timeout`
— sonst liegt das letzte WAL-Stück bei ruhigem Betrieb stundenlang ungeschrieben
herum und fehlt genau dann, wenn man es braucht.

---

## 20.5 „Bis zu diesem Punkt": die `recovery_target`-Parameter

Das ist der Kern der Wiederherstellung auf einen Zeitpunkt: Man spielt die
Sicherung ein, lässt WAL nachspielen — und sagt dem Server, **wann er anhalten
soll**.

| Parameter | Ziel ist … |
|-----------|------------|
| `recovery_target = 'immediate'` | der Moment, in dem die Sicherung endete, also der frühestmögliche konsistente Zustand |
| `recovery_target_name` | ein **Name**, den man vorher selbst gesetzt hat |
| `recovery_target_time` | ein Zeitstempel |
| `recovery_target_xid` | eine Transaktions-ID |
| `recovery_target_lsn` | eine Position im WAL |
| `recovery_target_inclusive` | ob direkt **hinter** dem Ziel (Vorgabe) oder direkt davor angehalten wird |
| `recovery_target_timeline` | aus welcher Zeitlinie (Vorgabe `latest`) |
| `recovery_target_action` | was danach passiert: `pause`, `promote`, `shutdown` |

Der Name entsteht im laufenden Betrieb — das ist der bequemste Anker, weil man
ihn **vor** einem Eingriff setzt:

```sql
SELECT pg_create_restore_point('vor_migration_17');
```

Der Rückgabewert ist eine LSN. Notiere ihn zusammen mit der Uhrzeit:

```sql
SELECT now(), pg_current_wal_lsn();
```

Zwei Details, die man leicht falsch annimmt:

- `recovery_target_action = 'pause'` ist die **Vorgabe** — der Server bleibt
  nach der Wiederherstellung stehen und beantwortet nur lesende Abfragen. Das
  ist keine Panne, sondern Absicht: Man soll nachsehen können, ob der Stand
  stimmt, und dann selbst weitermachen (`promote`) oder abbrechen. Dass in
  diesem Zustand überhaupt Abfragen möglich sind, ist Hot Standby zu verdanken
  (`hot_standby`).
- `inclusive` ist **nicht** für jedes Ziel gleich zu lesen. Die Doku beschreibt
  das bei den einzelnen Zieltypen unterschiedlich genau. Bevor du dich darauf
  verlässt, an welcher Seite des Ziels angehalten wird, lies die Stelle zu
  deinem Zieltyp auf der Seite `recovery-config.html` — bei einem `DELETE` in
  derselben Sekunde macht genau das den Unterschied.

---

## 20.6 Der Ablauf durchgespielt

Es gibt zwei Schauplätze für denselben Ablauf, und der Unterschied ist wichtig
genug, um ihn vorher zu kennen:

| | **in-place** (so läuft es im Kurs) | **zweite Instanz** (so läuft es hier im Repo) |
|---|---|---|
| PGDATA | wird überschrieben | bleibt unangetastet |
| Platzbedarf | Sicherung + PGDATA | Sicherung + zweite Kopie |
| Fehler wiederholbar | nur solange das Alte nicht gelöscht ist | beliebig oft |
| Verbindung | wie gewohnt (5432) | eigener Port (hier 5433) |
| wofür | der Einzelfall auf einer Maschine | Nachsehen, Heraussichern, Üben |

### Wie es in der Doku steht

1. Server stoppen.
2. Kaputtes PGDATA **wegräumen, nicht löschen** (umbenennen — es ist die letzte
   Chance).
3. Sicherung in ein leeres PGDATA einspielen.
4. `restore_command`, `recovery_target*` in `postgresql.conf` setzen und die
   Datei `recovery.signal` anlegen.
5. Server starten — er spielt WAL nach, bis das Ziel erreicht ist.
6. Prüfen, dann `promote` (oder stoppen und noch einmal anders aufsetzen).

Die `recovery.signal`-Datei ist dabei der Schalter: **existiert sie, wird
Wiederherstellung gemacht**; heißt sie `standby.signal`, wird ein Standby
daraus. Beides zusammen ergibt ein Standby, das zusätzlich bis zum Ziel spielt.
Seit PostgreSQL 12 stehen die Parameter in `postgresql.conf` — die frühere
`recovery.conf` gibt es nicht mehr.

### Der Ablauf aus dem Kurs — in-place

Die Kursumgebung arbeitet auf **PostgreSQL 19**, das Datenverzeichnis heißt
dort `19/data` und die Sicherung liegt als `backup/` daneben (Doku dazu unter
`/docs/19/…`). Der Ablauf ist genau der aus 20.5, nur ohne zweite Instanz:

```sql
-- 1. den Haltepunkt notieren, BEVOR etwas passiert
SELECT now(), pg_current_wal_lsn();
SELECT pg_create_restore_point('vor_dem_unfall');
```

```sql
-- 2. der Unfall
DROP TABLE test;
SELECT pg_switch_wal();      -- Segment abschließen, damit es ins Archiv geht
```

```bash
# 3. anhalten und den Stand zur Seite schaffen
pg_ctl stop
mv 19/data 19/data.kaputt      # im Kurs steht hier `rm -rf 19/data/`

# 4. die Sicherung an seine Stelle kopieren
cp -a backup 19/data           # das Ziel darf noch nicht existieren

# 5. Ziel setzen und den Schalter umlegen
vi 19/data/postgresql.conf     # restore_command, recovery_target_time, recovery_target_action
touch 19/data/recovery.signal

# 6. starten — und zwar mit Log, sonst siehst du nichts
pg_ctl start -l /var/lib/postgresql/restore.log
```

In die `postgresql.conf` gehört dabei genau das, was in 20.4 und 20.5 stand —
Archivpfad und Zeitstempel sind deine eigenen, den Zeitstempel am besten **samt
Offset**:

```
# dein Archiv aus 20.4 und dein Zeitpunkt aus Schritt 1
restore_command = 'cp /var/lib/postgresql/walarchiv/%f %p'
recovery_target_time = '2026-09-23 09:34:22.815568+00'
recovery_target_action = 'promote'
```

Zum Vergleichen: der Ablauf in der Doku steht unter
https://www.postgresql.org/docs/18/continuous-archiving.html im Abschnitt
„Recovering Using a Continuous Archive Backup" — dieselben sechs Schritte, nur
ohne die Dateinamen des Kurses.

### Was bei diesem Ablauf leicht schiefgeht

- **`rm -rf 19/data/` ist der riskanteste Befehl der ganzen Übung.** Im
  `pg_wal` des alten Verzeichnisses liegen Segmente, die vielleicht noch **nicht**
  im Archiv sind — die sind danach weg. Vorher prüfen: `SELECT * FROM
  pg_stat_archiver;` (steht `failed_count` auf 0?) und `pg_switch_wal()`
  ausführen. Umbenennen kostet nichts und ist derselbe Effekt.
- **Das Archiv muss den Zeitraum danach noch enthalten.** `restore_command`
  greift auf das Archiv zu, nicht auf die alte Instanz. Läuft `archive_command`
  nicht (oder hat es nie gelaufen), findet die Wiederherstellung nichts zu
  spielen und bricht mit „could not open file …" ab.
- **Eigentümer und Rechte nach dem Kopieren.** `cp -r` legt die Dateien dem
  Benutzer hin, der kopiert. Der Server startet nicht, wenn PGDATA nicht dem
  Datenbankbenutzer gehört und die Rechte nicht stimmen. `-a` statt `-r` und
  danach `ls -ld 19/data` / `whoami` — die Doku nennt die genauen Anforderungen
  an PGDATA.
- **Die `postgresql.auto.conf` überstimmt die Datei, die du gerade mit `vi`
  bearbeitest** (14.0). Wurde `archive_mode` oder `archive_command` vorher per
  `ALTER SYSTEM` gesetzt, liegen diese Zeilen jetzt in der Sicherung — und ein
  in `postgresql.conf` eingetragenes `archive_mode = off` wirkt dann **nicht**.
  Die Wiederherstellungs-Instanz würde also ins selbe Archiv schreiben wollen.
- **Wohin die Meldungen gehen.** Während der Wiederherstellung gibt es noch
  **keine SQL-Verbindung** — die Servermeldungen sind die **einzige**
  Fortschrittsanzeige („redo starts at …", „recovery stopping …"). Wo sie
  landen, hängt davon ab, wie du startest: mit `-l <datei>` weißt du es,
  sonst schreibt der Server dorthin, wohin `log_destination` / `logging_collector`
  zeigen (`SHOW log_directory;`). Vorher festlegen, sonst suchst du den
  Abbruchgrund später in mehreren Dateien.
- **Zeitstempel und Zeitzone.** Nimm den Wert aus `now()` komplett, mit
  Offset (`+00`) — dann ist eindeutig, welcher Zeitpunkt gemeint ist. Vergleiche
  `SHOW timezone;` und schau, welche Zeit das Log für sein Ziel nennt: eine
  Stunde daneben, und der `DROP TABLE` ist entweder noch drin oder schon wieder
  da.
- **Wann ist es fertig?** Nach `recovery_target_action` — `pause` bleibt stehen
  (lesbar), `promote` macht die Instanz schreibbar, `shutdown` stoppt sie. Bei
  `pause` geht es mit `SELECT pg_wal_replay_resume();` weiter.
- **Der Test ist nicht „der Server startet", sondern der Inhalt.** Ist `test`
  wieder da — und die Änderung *nach* dem Zielzeitpunkt weg? Genau dafür hast du
  in Schritt 1 gemessen und nicht geraten.
- **Aufräumen hinterher.** Sieh nach, ob die `recovery.signal` nach dem Lauf noch
  liegt, und nimm die Recovery-Zeilen wieder aus der Konfiguration, wenn du sie
  nicht behalten willst. Beim späteren normalen Start (ohne Signaldatei) sind sie
  wirkungslos — aber sie stehen dann in der nächsten Sicherung mit drin.

### Derselbe Ablauf, aber ohne die laufende Instanz anzufassen

Das ist die Variante, die dieses Repo benutzt — statt PGDATA zu überschreiben,
läuft die Wiederherstellung als **zweite Instanz** aus derselben Sicherung, mit
anderem Datenverzeichnis und anderem Port. Das ist der Grund, warum man im
Container nur eine Sicherung braucht und keine zweite Maschine.

Hinweise zur Umgebung, bevor du startest:

- Das Datenverzeichnis liegt laut [`compose.yaml`](../compose.yaml) im Volume
  `pgdata` unter `/var/lib/postgresql`. Schreib dort hinein
  (`/var/lib/postgresql/…`) — es ist **der einzige Ort, der einen
  Container-Neustart übersteht**. `./sql` ist read-only eingebunden, dorthin
  kann also nichts gesichert werden.
- Die Befehle unten, die **Dateien schreiben oder den Server steuern**, laufen
  mit `-u postgres`. `pg_ctl` und `initdb` verweigern die Arbeit als `root` —
  und Dateien, die `root` ins Datenverzeichnis legt, gehören später dem falschen
  Benutzer. Prüfe in der Shell mit `whoami`, wenn du unsicher bist.
- `pg_ctl`, `pg_basebackup` und `pg_waldump` liegen bei dieser Installation unter
  `/usr/lib/postgresql/18/bin` — falls ein Befehl „not found" ist, dort
  nachsehen und den Pfad setzen.

**1. Archiv und Sicherung anlegen** (20.4), dann:

```bash
docker compose exec -u postgres -T db mkdir -p /var/lib/postgresql/backup
docker compose exec -u postgres -T db pg_basebackup -U kurs -h /var/run/postgresql -D /var/lib/postgresql/base -X stream -c fast -P
docker compose exec -u postgres -T db pg_verifybackup /var/lib/postgresql/base
```

**2. Einen Haltepunkt setzen — bevor etwas passiert:**

```sql
SELECT pg_create_restore_point('vor_dem_unfall');
SELECT now(), pg_current_wal_lsn();
```

**3. Den Unfall bauen.** In der laufenden Instanz — zum Beispiel:

```sql
DROP TABLE kurs;
```

Danach das WAL-Segment abschließen, damit der Unfall sicher im Archiv landet:

```sql
SELECT pg_switch_wal();
SELECT archived_count, failed_count FROM pg_stat_archiver;
```

**4. Wiederherstellung vorbereiten.** In der Shell:

```bash
docker compose exec -u postgres -T db cp -a /var/lib/postgresql/base /var/lib/postgresql/restore
docker compose exec -u postgres db bash
```

Ab hier in dieser Shell. Die Kopie enthält **beide** Konfigurationsdateien —
und in der `postgresql.auto.conf` stehen noch `archive_mode = on` und der
`archive_command` aus 20.4. Das ist genau die Falle aus 14.0: die `.auto.conf`
wird **nach** der `postgresql.conf` gelesen und überstimmt sie. Wer jetzt in die
`postgresql.conf` schreibt, ändert nichts Wirksames.

Deshalb wird hier in die `.auto.conf` geschrieben — und dort gilt der spätere
Eintrag, die kopierten Zeilen stehen ja weiter oben:

```bash
echo "archive_mode = off" >> /var/lib/postgresql/restore/postgresql.auto.conf
echo "restore_command = 'cp /var/lib/postgresql/walarchiv/%f %p'" >> /var/lib/postgresql/restore/postgresql.auto.conf
echo "recovery_target_name = 'vor_dem_unfall'" >> /var/lib/postgresql/restore/postgresql.auto.conf
echo "recovery_target_action = 'pause'" >> /var/lib/postgresql/restore/postgresql.auto.conf
touch /var/lib/postgresql/restore/recovery.signal
```

`archive_mode = off` gehört dazu, damit diese Instanz nicht ins selbe Archiv
schreibt und dabei die WAL-Dateien der laufenden Instanz überschreibt.
Beim `cp -a` bleibt übrigens eine `standby.signal` liegen, falls du die Sicherung
mit `-R` erzeugt hast — dann ist es ein Standby und keine Wiederherstellung auf
einen Zeitpunkt. Sieh im Zweifel nach, welche Signaldateien da sind.

Hier stehen jetzt **beide** Platzhalter aus 20.4 spiegelverkehrt: `%f` ist der
Name im Archiv, `%p` der Zielpfad, an den PostgreSQL die Datei haben will. Die
Rollen sind gegenüber `archive_command` vertauscht — deshalb schreibt man sie
nicht aus dem Gedächtnis, sondern liest die Tabelle in der Doku.

**5. Starten und zusehen:**

```bash
pg_ctl -D /var/lib/postgresql/restore -l /var/lib/postgresql/restore.log -o "-p 5433" start
tail -f /var/lib/postgresql/restore.log
```

Im Log stehen die Zeilen, an denen man den Fortschritt erkennt: wo das
Nachspielen beginnt, wann der Zustand konsistent ist, welches WAL-Segment
gerade geholt wurde und mit welcher Zeile „recovery stopping …" das Ziel
erreicht wurde. Genau diese Zeilen sind später die Auskunft, **wie weit** die
Wiederherstellung gekommen ist.

**6. Prüfen.** Der Port 5433 ist nur **innerhalb** des Containers erreichbar —
also aus der laufenden Shell, nicht vom Host:

```bash
psql -U kurs -p 5433 -d kurs -c "SELECT pg_is_in_recovery(), pg_last_xact_replay_timestamp();"
psql -U kurs -p 5433 -d kurs -c "\dt"
```

```sql
-- Existiert die Tabelle wieder? Und der Stand von vor dem Unfall?
SELECT count(*) FROM kurs;
```

**7. Abschließen — oder hier stoppen und die Daten herausholen.** Solange die
Instanz pausiert, ist sie lesbar. Du kannst also genau das tun, was in 20.2
steht: das gebrauchte Objekt hier heraussichern und in die laufende Datenbank
zurückholen. Das ist der in der Praxis häufigste Weg bei einem einzelnen
`DROP TABLE` — **nicht** die ganze Instanz zurückdrehen.

```bash
pg_dump -U kurs -p 5433 -d kurs -t kurs | psql -U kurs -p 5432 -d kurs
```

Wenn die Richtung stimmt, mach die Wiederherstellung fertig:

```sql
SELECT pg_wal_replay_resume();     -- die pausierte Instanz läuft weiter und übernimmt
```

oder beende beide Instanzen und räume auf (20.9).

> **Erwartung, keine Zusage:** Ob die Zeilen nach dem Zurückholen wirklich
> dieselben sind wie vor dem `DROP TABLE`, steht nicht in diesem Dokument — das
> siehst du nur, wenn du vorher gezählt hast. Deshalb der Schritt mit `now()`
> und der LSN: ohne notierten Ausgangsstand ist jede Wiederherstellung
> unfalsifizierbar.

---

## 20.7 Wenn Tabellen in eigenen Tablespaces liegen — die „Pfade"

Ein Tablespace ist **ein Pfad**, den der Server sich merkt. Das hat Folgen für
jede Sicherung:

- Beim Sichern mit `pg_basebackup -T altpfad=neupfad` landen die Tabellen in der
  Sicherung unter einem anderen Pfad. Ohne `-T` stehen in der Sicherung dieselben
  absoluten Pfade wie auf dem Quellsystem.
- Beim Wiederherstellen auf einer anderen Maschine muss es diese Pfade also
  geben — oder man muss sie umbiegen. Wie das im Einzelnen läuft, steht im
  Tablespace-Kapitel der Doku
  (https://www.postgresql.org/docs/18/manage-ag-tablespaces.html) und bei den
  Recovery-Einstellungen; verlass dich dabei nicht auf dieses Dokument.

Selbst nachsehen lohnt sich, denn die Frage „wo liegen meine Daten
physikalisch?" beantwortet der Katalog:

```sql
SELECT spcname, pg_tablespace_location(oid) FROM pg_tablespace;
SELECT relname, reltablespace FROM pg_class WHERE relkind = 'r' AND reltablespace <> 0;
SHOW data_directory;
```

Im Kurs-Container gibt es keine eigenen Tablespaces — der Punkt betrifft nur die
Übertragung auf eine echte Umgebung. Genau deshalb steht er hier: eine Sicherung,
die auf dem Quellsystem perfekt funktioniert, scheitert beim Einspielen an einem
Pfad, den es dort nicht gibt.

---

## 20.8 Was das Archiv nicht kann

- **Einzelne Objekte aus einer physischen Sicherung herausnehmen, geht nicht.**
  Die Sicherung ist ein Datenverzeichnis — man kann nicht „Tabelle `konto` aus
  `base`" extrahieren. Der Weg führt über eine **zweite Instanz** aus dieser
  Sicherung (20.6) und dann `pg_dump` von dort. Deshalb bleibt der logische Dump
  (20.1) auch dann nützlich, wenn es PITR gibt: er ist die „kleine Zange", die
  körperliche Sicherung ist die „große".
- **Nur komplette Segmente.** Das WAL-Stück, das gerade offen ist, liegt noch im
  `pg_wal` der Instanz und ist nicht im Archiv. Beim Neustart wird es dort
  abgeschlossen und dann nachgereicht — deshalb funktioniert `pg_switch_wal()`
  (20.4). Für die Crash Recovery nach einem Absturz braucht man es ohnehin aus
  `pg_wal`, nicht aus dem Archiv. Geht aber die **Platte** verloren, ist genau
  dieses Stück weg — ein Argument für ein kurzes `archive_timeout`.
- **Das Archiv ist nicht die Sicherung.** Es sind Änderungen, die auf eine
  Sicherung angewendet werden müssen. Beides getrennt aufbewahren — sonst ist der
  eine Defekt immer auch der Verlust des anderen.
- **Aufbewahrung ist eine Entscheidung, kein Automatismus.** `archive_timeout`
  bestimmt die Auflösung, die Aufbewahrungsdauer der WAL-Dateien und der
  Sicherungen bestimmst du. Danach richtet sich, **wie weit** man zurückkann
  (`recovery_target_timeline = 'latest'` hilft nur, solange es die Zeitlinie
  noch gibt).

---

## 20.9 Aufräumen

Der Unfall aus Schritt 3 steht in der laufenden Instanz noch da — die Tabelle
`kurs` ist dort weg. Neu aufbauen:

```sql
\i /sql/01_schema.sql
```

Die 4 Mio. Zeilen kommen mit `/sql/02_insert_4mio.sql` zurück (dauert, siehe
Teil 4) — oder man nimmt bewusst nur einen Block aus
`/sql/02b_insert_100k_block.sql`.

```bash
docker compose exec -u postgres -T db pg_ctl -D /var/lib/postgresql/restore stop
docker compose exec -u postgres -T db rm -rf /var/lib/postgresql/restore /var/lib/postgresql/restore.log
```

Die Archivierung wieder abschalten, sonst schreibt der Container bei jedem
Segment in ein Verzeichnis, um das sich niemand mehr kümmert:

```sql
ALTER SYSTEM RESET archive_command;
ALTER SYSTEM RESET archive_timeout;
ALTER SYSTEM SET archive_mode = off;
```

```bash
docker compose restart db
```

`ALTER SYSTEM RESET ALL` nimmt alles auf einmal zurück — vorsichtiger Umgang gilt
hier wie in 14.2, es gibt keinen Papierkorb.
