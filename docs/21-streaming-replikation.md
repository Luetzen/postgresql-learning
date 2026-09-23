# 21 — Streaming-Replikation: Primary, Standby, WAL sender

In Teil 20 wanderte das WAL als **abgeschlossene Dateien** ins Archiv — davon
spielt man *nachträglich* auf einen Zeitpunkt zurück. Hier geht es um den
*anderen* Weg: eine zweite Instanz bekommt den WAL **live über die Verbindung**
und spielt ihn fortlaufend nach. Das nennt man **Streaming-Replikation**, die
zweite Instanz heißt **Standby**.

Die beiden Wege schließen sich nicht aus — sie sind zwei Verbraucher desselben
Logs. Teil 20 sagt „bis hierher zurück", Teil 21 sagt „dieser zweite Server ist
immer aktuell".

Die Doku-Kapitel, um die es geht:

- https://www.postgresql.org/docs/18/warm-standby.html (Log-Shipping / Standby)
- https://www.postgresql.org/docs/18/runtime-config-replication.html (die
  `*_replication`-Einstellungen)
- https://www.postgresql.org/docs/18/monitoring-stats.html (die beiden Sichten
  `pg_stat_replication` und `pg_stat_wal_receiver`)
- https://www.postgresql.org/docs/18/app-pgbasebackup.html (das `-R`, das du in
  20.3 bewusst weggelassen hast)

> **Zwei Umgebungen, dieselben Befehle.** Der Kurs arbeitet auf PostgreSQL **19**
> — dort heißt das Datenverzeichnis `19/data` (dieselben Kapitel in der Doku:
> `/docs/19/…`). Dieses Repo läuft auf `postgres:18.6`, siehe
> [`compose.yaml`](../compose.yaml). Die Handgriffe sind identisch, nur Pfade und
> Versionsnummer unterscheiden sich. Deinen eigenen Pfad zeigt
> `SHOW data_directory;`.

---

## 21.0 Die Skizze in Worten

Auf dem Bild stehen zwei Bereiche, getrennt durch eine senkrechte Linie: links
die **Primary**, rechts die **Standby**. Darunter die gemeinsame Ebene: das
**WAL**. Und zwischen den Bereichen die beiden Kästen, die den Transport machen.

| In der Skizze | In PostgreSQL | wo du es nachsiehst |
|---------------|---------------|---------------------|
| Primary (Zylinder) | die laufende Instanz, ihr Datenverzeichnis | `SHOW data_directory;` |
| Standby (Zylinder) | eine zweite Instanz mit **Kopie** des Datenverzeichnisses | `pg_is_in_recovery()` → `t` |
| WAL sender | ein Backend auf der Primary, das WAL verschickt | `pg_stat_activity`, `backend_type = 'walsender'` |
| WAL receiver | der Prozess auf der Standby, der WAL entgegennimmt | `pg_stat_wal_receiver` |
| WAL (in der Mitte) | das Write-Ahead-Log — hier der **Kanal**, nicht das Archiv | `pg_current_wal_lsn()`, `pg_switch_wal()` |
| die beiden „bac"-Kästchen | die Grundsicherung und die Kopie, die woanders liegt | Teil 20 (20.1, 20.3) |

Zwei Dinge, die man leicht verwechselt:

- **`wal sender`/`wal receiver` sind Prozesse, keine Dateien.** In Teil 20 waren
  es Dateien in einem Verzeichnis, hier ist es eine Verbindung zwischen zwei
  Servern.
- **Die Standby wächst nicht aus dem Nichts.** Sie fängt mit einer *physischen
  Kopie* an (21.1) und holt danach nur noch das, was sich seither geändert hat.

---

## 21.1 Womit eine Standby anfängt: die Grundsicherung

Bevor eine Standby streamen kann, braucht sie einen Ausgangspunkt — eine
Kopie des Datenverzeichnisses der Primary. Genau das ist `pg_basebackup` aus
20.3. Der Unterschied zu Teil 20 ist **ein Schalter**:

```bash
docker compose exec -u postgres -T db pg_basebackup -U kurs -h /var/run/postgresql \
    -D /var/lib/postgresql/base -X stream -c fast -P
```

Ohne `-R` entsteht eine **Sicherung** (ein Datenverzeichnis zum Zurückspielen,
20.6). Mit `-R` entsteht ein **Standby** — `pg_basebackup` legt dann im Ziel
zwei Dinge an, die den Unterschied machen:

- `standby.signal` — die Datei, die sagt „ich bin ein Standby". Fehlt sie,
  streamt die Instanz nicht, und `pg_is_in_recovery()` bleibt `f`.
- einen Eintrag `primary_conninfo` in der `postgresql.auto.conf` — die
  Verbindungsangabe zur Primary, inklusive der Rolle, mit der man sich anmeldet.

Der Merksatz dazu steht sinngemäß in der Doku: **die Signaldatei entscheidet,
was für eine Instanz es ist** — nicht ein Kommandozeilenargument beim Start. Sie
kann jederzeit umbenannt werden, und beim nächsten Start ist es etwas anderes.

Sieh selbst nach, was `-R` in das Verzeichnis schreibt — die Datei ist kurz und
lesbar:

```bash
docker compose exec -u postgres -T db cat /var/lib/postgresql/base/standby.signal
docker compose exec -u postgres -T db tail -5 /var/lib/postgresql/base/postgresql.auto.conf
```

---

## 21.2 Die Standby aufsetzen

Dieses Repo braucht dafür keine zweite Maschine: die Standby läuft als
**zweite Instanz im selben Container**, mit eigenem Datenverzeichnis und eigenem
Port — genau das Muster aus 20.6.

Hinweise zur Umgebung, bevor du startest:

- Geschrieben wird ins Volume `pgdata` unter `/var/lib/postgresql` — das ist der
  einzige Ort, der einen `docker compose down` übersteht. `./sql` ist read-only.
- Befehle, die Dateien schreiben oder den Server steuern, laufen mit
  `-u postgres`. `pg_ctl` und `initdb` verweigern die Arbeit als `root`.
- `pg_ctl`, `pg_basebackup` und `pg_waldump` liegen unter
  `/usr/lib/postgresql/18/bin` — falls ein Befehl „not found" ist, dort nachsehen.

**1. Vorher prüfen, ob die Primary überhaupt verschicken darf** (in `psql` auf
Port 5432):

```sql
SHOW wal_level;         -- 'replica' oder 'logical' — 'minimal' reicht nicht
SHOW max_wal_senders;   -- muss größer als 0 sein
SHOW hot_standby;       -- 'on' = die Standby darf lesend antworten
```

**2. Die Grundsicherung ziehen — diesmal mit `-R`:**

```bash
docker compose exec -u postgres -T db mkdir -p /var/lib/postgresql/standby
docker compose exec -u postgres -T db pg_basebackup -U kurs -h /var/run/postgresql \
    -D /var/lib/postgresql/standby -X stream -c fast -P -R
```

**3. Starten — anderer Port, sonst kollidiert es mit der laufenden Instanz:**

```bash
docker compose exec -u postgres db bash
```

Ab hier in dieser Shell:

```bash
pg_ctl -D /var/lib/postgresql/standby -l /var/lib/postgresql/standby.log -o "-p 5433" start
tail -f /var/lib/postgresql/standby.log
```

Im Log steht der Beginn des Streamens — die Zeile, in der die Standby meldet,
welches WAL-Segment sie woher holt. Genau diese Zeile ist die Auskunft, ob es
funktioniert hat. Kommt statt dessen eine Fehlermeldung über `wal_level`, die
`pg_hba.conf` oder ein bereits vergebenes WAL-Segment, ist das der Hinweis aus
21.8.

---

## 21.3 Zusehen: die beiden Sichten

Replikation ist unsichtbar, bis man sie abfragt. Es sind **zwei** Abfragen auf
**zwei** Instanzen:

Auf der **Primary** (Port 5432) — wer hört zu, und wie weit ist jeder?

```sql
SELECT application_name, client_addr, state,
       sent_lsn, write_lsn, flush_lsn, replay_lsn,
       write_lag, flush_lag, replay_lag, sync_state
FROM pg_stat_replication;
```

Auf der **Standby** (Port 5433, in der Shell) — wo stehe ich?

```bash
psql -U kurs -p 5433 -d kurs
```

```sql
SELECT status, sender_host, sender_port, slot_name,
       written_lsn, flushed_lsn, latest_end_lsn, last_msg_receipt_time
FROM pg_stat_wal_receiver;

SELECT pg_is_in_recovery(),
       pg_last_wal_receive_lsn(),
       pg_last_wal_replay_lsn(),
       pg_last_xact_replay_timestamp();
```

Und dann etwas ändern und beobachten, wie es durchkommt. Auf der Primary:

```sql
CREATE TABLE streaming_probe (id int, notiz text);
INSERT INTO streaming_probe VALUES (1, 'kommt das an?');
SELECT pg_switch_wal();     -- Segment abschließen (wie in 20.4)
```

Auf der Standby:

```sql
SELECT * FROM streaming_probe;
SELECT pg_last_xact_replay_timestamp();
```

Der Unterschied zwischen **empfangen** und **nachgespielt** (`receive_lsn` gegen
`replay_lsn`) ist der Punkt, an dem man begreift, dass beides zwei Schritte sind:
erst ankommen, dann anwenden. Zwischen beiden liegt das Fenster, in dem die
Standby etwas *weiß*, was sie noch nicht *zeigt*.

> **Keine Zahlen in diesem Dokument.** Wie groß die Lücken im Betrieb sind und
> wie schnell das durchläuft, steht nirgends hier — das misst du auf deinem
> Rechner und trägst es in `06-kurs-notizen.md` ein.

---

## 21.4 Lesen ja, schreiben nein — Hot Standby

Eine Standby ist **read-only**. Nicht aus Vorsicht, sondern weil sonst zwei
Instanzen dieselbe Zeile verschieden ändern könnten. Probier es:

```sql
-- auf der Standby:
CREATE TABLE probier (id int);
-- ERROR: cannot execute CREATE TABLE in a read-only transaction

BEGIN;
UPDATE streaming_probe SET notiz = 'geht nicht' WHERE id = 1;
-- ERROR: cannot execute UPDATE in a read-only transaction
ROLLBACK;
```

Dass man auf einer Standby überhaupt **lesen** darf, ist eine eigene
Einstellung — `hot_standby` (21.2, Schritt 1). Steht sie auf `off`, nimmt die
Standby die Verbindung gar nicht erst an, statt Fehler zu werfen.

---

## 21.5 Nachspielen anhalten und wieder freigeben

Man kann das Anwenden des WAL auf der Standby **anhalten**, ohne den Empfang zu
stoppen. Das ist der Zustand, in dem man kontrolliert „bis hierher" nachsehen
kann — dieselbe Idee wie `recovery_target_action = 'pause'` aus 20.5.

```sql
-- auf der Standby:
SELECT pg_wal_replay_pause();
```

Jetzt auf der Primary ein `replay_lag` beobachten, das **wächst**, während
`sent_lsn` weiterläuft — die Standby nimmt also weiter an, wendet aber nicht an.
Wieder freigeben:

```sql
-- auf der Standby:
SELECT pg_wal_replay_resume();
```

Der Anschluss an Teil 20 ist genau hier: `pg_wal_replay_pause()` ist derselbe
Heuhaufen, in dem man nachsieht, ob der Stand *vor* dem Unfall der richtige war.

---

## 21.6 Wenn aus der Standby die Primary wird: `pg_promote`

Eine Standby lässt sich zur Primary **befördern**. Danach ist sie kein Standby
mehr und nimmt Schreibzugriffe an — sie spielt nicht mehr nach, sie schreibt
jetzt selbst WAL:

```sql
-- auf der Standby:
SELECT pg_promote();
SELECT pg_is_in_recovery();    -- jetzt: f
```

Das ist der Kern dessen, was man „Failover" nennt. Im Betrieb gehört dazu mehr
als ein Befehl — wer entscheidet, wann befördert wird, und was mit der alten
Primary passiert (sie darf **nicht** einfach zurückkommen). Das ist ein eigenes
Thema und steht nicht in diesem Dokument.

---

## 21.7 Synchron oder asynchron

- **asynchron** (die Vorgabe): die Primary bestätigt ein `COMMIT`, sobald sie
  selbst fertig ist. Die Standby hinkt dann ein Stück hinterher — bei einem
  Ausfall der Primary sind die letzten Transaktionen weg.
- **synchron**: die Primary wartet mit der Bestätigung, bis die Standby den WAL
  geschrieben hat. Damit geht bei einem Ausfall nichts verloren — der Preis ist,
  dass jedes `COMMIT` auf die Standby **wartet**.

Die Stellschrauben:

```sql
-- auf der Primary:
SHOW synchronous_commit;
SHOW synchronous_standby_names;    -- leer = asynchron
```

Soll eine bestimmte Standby als synchron gelten, muss ihr `application_name`
dem Eintrag in `synchronous_standby_names` entsprechen — den Namen siehst du in
`pg_stat_replication` (21.3). Wie man ihn setzt und was `ANY` / `FIRST` in
`synchronous_standby_names` bedeuten, steht in der Doku zu
`runtime-config-replication`; probier es und sieh im dritten Fenster zu, wie
lange ein `COMMIT` dann dauert.

Für den Übungsbetrieb noch etwas, das man sonst vergisst: die Primary darf den
WAL **nicht wegwerfen**, bevor die Standby ihn geholt hat. Ein frisch
aufgesetztes Standby ohne Slot fällt genau daran um (21.8). Gegenmittel:

```sql
-- auf der Primary, damit Platz reserviert bleibt:
SELECT * FROM pg_create_physical_replication_slot('standby1');
```

```sql
-- auf der Standby, in der postgresql.auto.conf, dann Neustart:
-- primary_slot_name = 'standby1'
```

---

## 21.8 Was zwischen Primary und Standby schiefgeht

| Symptom | wahrscheinliche Ursache | wo nachsehen |
|---------|-------------------------|--------------|
| `pg_stat_wal_receiver` ist leer | die Standby ist gar kein Standby (`standby.signal` fehlt) | `pg_is_in_recovery()`, `ls …/standby.signal` |
| Standby startet nicht | derselbe Port wie die Primary | Log der Standby (`-o "-p 5433"`) |
| „no pg_hba.conf entry for replication" | der Primary fehlt eine `replication`-Zeile für die Standby | die `pg_hba.conf` der Primary (`SHOW hba_file;`) und das **Log der Standby** |
| „`wal_level` is insufficient" | die Primary loggt zu wenig | `SHOW wal_level;` (21.2) |
| „requested WAL segment … has already been removed" | die Primary hat den WAL recycelt, den die Standby noch brauchte | `pg_wal` auf der Primary, und die Zeile im Standby-Log — Abhilfe über 21.7 |
| Schreiben auf der Standby | das ist **kein** Fehler, das ist Hot Standby | 21.4 |
| `sync_state` bleibt `async`, obwohl ein Name gesetzt ist | Name in `synchronous_standby_names` ≠ `application_name` | `pg_stat_replication`, 21.7 |

Der wichtigste Punkt der ganzen Liste: **die Meldung steht im Log der
Standby, nicht in dem der Primary.** Die Primary merkt nur, dass sich jemand
*nicht* verbunden hat (`pg_stat_replication` bleibt leer) — warum, sagt sie
nicht.

---

## 21.9 Der Unterschied zu Teil 20 — auf einen Blick

| | Archiv (Teil 20) | Streaming (Teil 21) |
|---|------------------|---------------------|
| Transport | fertige Dateien in ein Verzeichnis | live über die Verbindung |
| wer zieht | die wiederherstellende Instanz (`restore_command`) | die Standby wird **geschickt** (`wal sender`) |
| Ergebnis | Instanz steht still, spielt bis zu einem Ziel | Instanz läuft weiter, immer aktuell |
| Rolle der Standby | keine — es ist ein Vorgang | dauerhaft |
| gemeinsame Basis | `pg_basebackup` als Ausgangspunkt | `pg_basebackup` als Ausgangspunkt |

Beides braucht **dieselbe** Grundsicherung und **dasselbe** WAL. Deshalb steht
in 20.3 der Satz, warum `-R` dort fehlt: mit `-R` wäre aus der Sicherung ein
Standby geworden — und ein Standby ist genau das, was man *nicht* auf einen
alten Zeitpunkt zurückspielen will.

---

## 21.10 Aufräumen

Erst die Standby stoppen (sie läuft im selben Container wie die Primary):

```bash
docker compose exec -u postgres -T db pg_ctl -D /var/lib/postgresql/standby stop
```

Hast du sie in 21.6 befördert, ist sie jetzt eine Primary — stoppen kann man sie
trotzdem so; sie ist nur keine Standby mehr.

Den Platz zurückholen, und den Slot nicht vergessen:

```sql
-- auf der Primary, falls du einen Slot angelegt hast:
SELECT pg_drop_replication_slot('standby1');
```

```bash
docker compose exec -u postgres -T db rm -rf /var/lib/postgresql/standby /var/lib/postgresql/standby.log
docker compose exec -T db psql -U kurs -d kurs -c "DROP TABLE IF EXISTS streaming_probe;"
```

Ein Slot, den niemand mehr benutzt, hält WAL **für immer** zurück und lässt
`pg_wal` wachsen — deshalb gehört er ausdrücklich aufgeräumt.

---

## Was in `06-kurs-notizen.md` gehört

- `SHOW wal_level;`, `SHOW max_wal_senders;`, `SHOW hot_standby;` auf dieser
  Installation — was steht dort?
- Erste Log-Zeile des Streamens auf der Standby: welches Segment, welcher
  Sender?
- `state` und `sync_state` in `pg_stat_replication` im Normalbetrieb
- Wie weit laufen `sent_lsn` und `replay_lsn` in Sekunden auseinander (bei
  Ruhe und unter Last)?
- Was passiert mit `replay_lag` in `pg_stat_replication`, solange
  `pg_wal_replay_pause()` aktiv ist?
- `application_name` der Standby in `pg_stat_replication` gegen den Eintrag in
  `synchronous_standby_names` — stimmen sie überein?
- Mit `synchronous_standby_names` gesetzt: wie lange dauert ein `COMMIT` dann?
- Das Log der Standby, wenn du bewusst einen falschen `primary_conninfo` /
  Port einträgst — steht dort, was schiefging?
- Was steht in `pg_stat_wal_receiver.slot_name`, und was macht `pg_wal` auf der
  Primary, wenn du den Slot bei laufender Standby löschst?
