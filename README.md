# PostgreSQL lernen

Lernprojekt rund um PostgreSQL 18.6 — alles selbst nachbauen, nichts nur lesen.

Der Ablauf, den wir hier abbilden:

1. PostgreSQL **aus dem Quellcode installieren** (nur zum Verstehen, was da eigentlich passiert)
2. PostgreSQL in einen **Docker-Container** packen und sich damit **verbinden**
3. Die Datenbank `kurs` anlegen mit einer Tabelle `kurs (id, name)`
4. **4.000.000 Datensätze** einfügen — immer derselbe Befehl, aus einer Datei heraus
5. Messen: Was kostet eine Abfrage **ohne** Index, was kostet sie **mit** Index/Constraint?
6. **Zwei Sitzungen gleichzeitig**: Transaktionen, Sperren und Isolationsstufen
7. **Timeouts**: Anweisung, Transaktion und Sperre zeitlich begrenzen
8. **Verklemmungen**: im Log finden, protokollieren, mit `NOWAIT`/`SKIP LOCKED` vermeiden
9. **Warteereignisse**: worauf eine Sitzung wirklich wartet — und was „page locks" sind
10. **Indizes im Betrieb**: `CONCURRENTLY`, `INVALID`, `REINDEX`
11. **MVCC**: Zeilenversionen, `xmin`/`xmax` und warum alte Werte noch sichtbar sind
12. **VACUUM**: tote Zeilen, Bloat und warum eine offene Transaktion aufhält
13. **Konfiguration**: wo Einstellungen stehen und wann sie wirken

Alles, was hier als Befehl steht, ist Copy-Paste-fähig.

---

## Voraussetzungen

- **Docker** mit Docker Compose (Teil 2–5)
- Für Teil 1: Linux oder WSL2 mit Build-Werkzeugen (`build-essential`, `bison`, `flex`, …)
- `psql` muss **nicht** auf dem Rechner installiert sein — der Client kommt aus dem Container

Kurz prüfen:

```bash
docker --version
docker compose version
```

---

## Lernpfad

| # | Datei | Inhalt |
|---|-------|--------|
| 1 | [docs/01-installation-aus-dem-quellcode.md](docs/01-installation-aus-dem-quellcode.md) | Quellcode holen, `configure`, `make`, Server starten |
| 2 | [docs/02-docker-container-und-verbindung.md](docs/02-docker-container-und-verbindung.md) | Container starten, verbinden, `psql`-Grundlagen |
| 3 | [docs/03-kurstabelle-anlegen.md](docs/03-kurstabelle-anlegen.md) | Datenbank `kurs` + Tabelle mit `id` und `name` |
| 4 | [docs/04-massenhaft-daten-erzeugen.md](docs/04-massenhaft-daten-erzeugen.md) | 4 Mio. Datensätze, zwei Wege |
| 5 | [docs/05-query-kosten-mit-und-ohne-index.md](docs/05-query-kosten-mit-und-ohne-index.md) | `EXPLAIN ANALYZE`, Index, Primary Key |
| 6 | [docs/06-kurs-notizen.md](docs/06-kurs-notizen.md) | Platz für die weiteren Kursinhalte |
| 7 | [docs/07-transaktionen-und-isolation.md](docs/07-transaktionen-und-isolation.md) | `konto`, zwei Sitzungen, Sperren, Serialisierungsfehler (40001) |
| 8 | [docs/08-timeouts.md](docs/08-timeouts.md) | `statement_timeout`, `lock_timeout`, `idle_in_transaction_session_timeout`, `transaction_timeout` |
| 9 | [docs/09-verklemmungen.md](docs/09-verklemmungen.md) | Deadlocks im Serverlog, `log_lock_waits`, `NOWAIT`, `SKIP LOCKED`, `40P01` |
| 10 | [docs/10-warteereignisse.md](docs/10-warteereignisse.md) | `wait_event_type`, `pg_wait_events`, „page locks", Buffer-Pin |
| 11 | [docs/11-indizes-im-betrieb.md](docs/11-indizes-im-betrieb.md) | `CREATE INDEX CONCURRENTLY`, `INVALID`, `REINDEX` |
| 12 | [docs/12-mvcc.md](docs/12-mvcc.md) | `ctid`, `xmin`, `xmax`, Schnappschüsse, `pg_xact_status` |
| 13 | [docs/13-vacuum-und-tote-zeilen.md](docs/13-vacuum-und-tote-zeilen.md) | `VACUUM`, tote Zeilen, Bloat, autovacuum |
| 14 | [docs/14-konfiguration.md](docs/14-konfiguration.md) | `postgresql.conf`, `ALTER SYSTEM`, `pg_settings`, Reload oder Neustart |
| 15 | [docs/15-repack.md](docs/15-repack.md) | `REPACK` (ab PostgreSQL 19): Neuschreiben, `CONCURRENTLY`, `USING INDEX` |
| 16 | [docs/16-explain-analyze-plan-lesen.md](docs/16-explain-analyze-plan-lesen.md) | Plan lesen: `cost`, `rows` gegen `actual`, `loops`, `Buffers`, `Batches` |
| 17 | [docs/17-join-methoden.md](docs/17-join-methoden.md) | Nested Loop, Hash Join, Merge Join: wann welche, und was der Index daran ändert |
| 18 | [docs/18-testdaten-erzeugen.md](docs/18-testdaten-erzeugen.md) | Testdaten mit Variation: `random()`, Modulo, `ARRAY`, `md5()`, UUIDs, `pgbench` |
| 19 | [docs/19-schaetzung-und-parallele-plaene.md](docs/19-schaetzung-und-parallele-plaene.md) | Falsche Schätzung bei korrelierten Spalten, `CREATE STATISTICS`, `Gather` und Worker |
| 20 | [docs/20-sicherung-und-wiederherstellung.md](docs/20-sicherung-und-wiederherstellung.md) | `pg_dump`/`pg_restore` für einzelne Objekte, `pg_basebackup`, WAL-Archiv, PITR mit `recovery_target*` |
| 21 | [docs/21-streaming-replikation.md](docs/21-streaming-replikation.md) | Standby aufsetzen (`pg_basebackup -R`), `pg_stat_replication`, `pg_stat_wal_receiver`, synchron/asynchron, `pg_promote` |
| 22 | [docs/22-logische-replikation.md](docs/22-logische-replikation.md) | `wal_level = logical`, Publication/Subscription, `REPLICA IDENTITY`, `test_decoding`, `pg_stat_subscription` |
| 23 | [docs/23-wal-und-haltbarkeit.md](docs/23-wal-und-haltbarkeit.md) | Der `# WRITE-AHEAD LOG`-Block: `wal_level`, `fsync`, `synchronous_commit`, `wal_sync_method`, `full_page_writes`, `wal_log_hints`, `wal_compression` |
| 24 | [docs/24-rollen-und-rechte.md](docs/24-rollen-und-rechte.md) | `CREATE ROLE`/`CREATE USER`, die Rollenattribute, `GRANT`/`REVOKE`, `pg_hba.conf`, Mitgliedschaft und `SET ROLE`, vordefinierte Rollen |
| 25 | [docs/25-verbindungen-von-aussen.md](docs/25-verbindungen-von-aussen.md) | `listen_addresses`, Port, `pg_hba.conf` für fremde Hosts, `pg_isready`, `\conninfo`, `client_addr` |
| 26 | [docs/26-tls-verschluesselte-verbindungen.md](docs/26-tls-verschluesselte-verbindungen.md) | `ssl = on`, Zertifikat und Schlüssel mit `openssl`, Rechte, `pg_stat_ssl`, `sslmode`, `hostssl` |
| 27 | [docs/27-eigentuemer-und-acl.md](docs/27-eigentuemer-und-acl.md) | Eigentümer versus Recht, `ALTER … OWNER TO`, `REASSIGN OWNED`/`DROP OWNED`, ACL-Zeichen lesen, `WITH GRANT OPTION`, Gruppen als Eigentümer |
| 28 | [docs/28-rechte-gezielt-setzen.md](docs/28-rechte-gezielt-setzen.md) | Eigenes Schema, `GRANT USAGE`, `ALTER DEFAULT PRIVILEGES` (Zeile für Zeile), Read-only-Rolle, `\ddp`, Sequenzen als eigene Zeile |
| 29 | [docs/29-upgrade.md](docs/29-upgrade.md) | Major gegen Minor, `pg_upgrade` (`--check`, `--link`/`--copy`), Dump-Weg, logische Replikation als Brücke, `ANALYZE` nach dem Umzug |

---

## Schnellstart (Teil 2 bis 5)

```bash
docker compose up -d                         # PostgreSQL 18.6 starten
docker compose exec db psql -U kurs -d kurs  # verbinden, interaktiv
```

Und dann in `psql`:

```sql
\i /sql/01_schema.sql          -- Tabelle anlegen
\timing on                     -- Zeitmessung einschalten
\i /sql/02_insert_4mio.sql     -- 4 Mio. Datensätze
\i /sql/03_abfragen.sql        -- ohne Index / mit Index messen
```

Aufräumen (löscht auch die Daten!):

```bash
docker compose down -v
```

---

## Schnellstart (Teil 7 — Transaktionen)

Voraussetzung: die Tabelle aus Teil 3 existiert nicht zwingend, `konto` wird
separat angelegt.

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/04_konto.sql
```

Und dann in `psql` (für 7.5 und folgende ein **zweites** Fenster mit derselben
Verbindung öffnen):

```sql
\set VERBOSITY verbose          -- Fehler mit SQLSTATE anzeigen
BEGIN;
UPDATE konto SET betrag = betrag - 100 WHERE id = 1;
UPDATE konto SET betrag = betrag + 100 WHERE id = 2;
SELECT sum(betrag) FROM konto;
COMMIT;
```

Ganze Übungen: [docs/07-transaktionen-und-isolation.md](docs/07-transaktionen-und-isolation.md)

---

## Schnellstart (Teil 8 — Timeouts)

```sql
SHOW statement_timeout;                  -- Vorgabe: 0 = aus
SET statement_timeout = '2s';
SELECT pg_sleep(5);                      -- ERROR: canceling statement due to statement timeout
RESET statement_timeout;
```

Alle Timeouts: [docs/08-timeouts.md](docs/08-timeouts.md)

---

## Schnellstart (Teil 9 — Verklemmungen)

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/04_konto.sql    # konto aus Teil 7
```

Und dann in `psql` — zwei Fenster, **vorher** in beiden:

```sql
SET deadlock_timeout = '10s';
```

Deadlock auslösen wie in 7.7, danach im Log nachsehen:

```bash
docker compose logs db | tail -40
```

Ganze Übungen: [docs/09-verklemmungen.md](docs/09-verklemmungen.md)

---

## Schnellstart (Teil 10 — Warteereignisse)

Zwei Fenster. In B beobachten:

```sql
SELECT pid, state, wait_event_type, wait_event, left(query, 40) AS query
FROM pg_stat_activity
WHERE backend_type = 'client backend';
\watch 2
```

In A etwas tun, das wartet:

```sql
SELECT pg_sleep(5);
```

Erwartung in B: `Timeout` / `PgSleep`. Alle Übungen:
[docs/10-warteereignisse.md](docs/10-warteereignisse.md)

---

## Schnellstart (Teil 11 — Indizes im Betrieb)

```sql
\d kurs
CREATE INDEX CONCURRENTLY idx_kurs_cc ON kurs (id);
-- nach ein paar Sekunden Strg+C: "canceling statement due to user request"
\d kurs                                    -- jetzt: INVALID
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM kurs WHERE id = 3999999;   -- Seq Scan
DROP INDEX idx_kurs_cc;
```

Alle Einzelheiten: [docs/11-indizes-im-betrieb.md](docs/11-indizes-im-betrieb.md)

---

## Schnellstart (Teil 12/13 — MVCC und VACUUM)

```sql
SELECT ctid, xmin, xmax, * FROM konto;          -- Zeilenversionen ansehen
SELECT pg_current_xact_id();                    -- eigene Transaktions-ID

-- in einer Transaktion ändern und nicht bestätigen:
BEGIN;
UPDATE konto SET betrag = betrag + 100 WHERE id = 1;
-- in einem zweiten Fenster: SELECT ctid, xmin, xmax FROM konto;  -> altes xmax, alter Wert
ROLLBACK;

VACUUM VERBOSE konto;                           -- was aufgeräumt wird
```

Alle Einzelheiten: [docs/12-mvcc.md](docs/12-mvcc.md) und
[docs/13-vacuum-und-tote-zeilen.md](docs/13-vacuum-und-tote-zeilen.md)

---

## Schnellstart (Teil 14 — Konfiguration)

```sql
SHOW config_file;

SELECT name, setting, unit, context, source, pending_restart
FROM pg_settings
WHERE name LIKE 'autovacuum%'
ORDER BY name;

ALTER SYSTEM SET autovacuum_naptime = '30s';
SELECT pg_reload_conf();
SHOW autovacuum_naptime;

ALTER SYSTEM RESET autovacuum_naptime;
SELECT pg_reload_conf();
```

Alle Einzelheiten: [docs/14-konfiguration.md](docs/14-konfiguration.md)

---

## Schnellstart (Teil 17 — Join-Methoden)

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/05_join_schema.sql
```

Und dann in `psql`:

```sql
ANALYZE thema, kurs_thema;

EXPLAIN (ANALYZE, BUFFERS)
SELECT t.bezeichnung, count(*)
FROM thema t
JOIN kurs_thema kt ON kt.thema_id = t.id
GROUP BY t.bezeichnung;

-- dieselbe Abfrage, aber ohne Wahlmöglichkeit für den Planer:
SET enable_hashjoin = off;
SET enable_mergejoin = off;
EXPLAIN (ANALYZE, BUFFERS) SELECT t.bezeichnung, count(*) FROM thema t JOIN kurs_thema kt ON kt.thema_id = t.id GROUP BY t.bezeichnung;
RESET ALL;
```

Alle Übungen: [docs/17-join-methoden.md](docs/17-join-methoden.md)

---

## Schnellstart (Teil 18 — Testdaten mit Variation)

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/06_adresse.sql
```

Und dann in `psql` — dieselben Werte, einmal in Blöcken, einmal gemischt:

```sql
SELECT count(*) FROM adresse;
SELECT count(DISTINCT stadt), count(DISTINCT plz), count(DISTINCT strasse) FROM adresse;

ANALYZE adresse;
SELECT attname, n_distinct, correlation FROM pg_stats
WHERE tablename = 'adresse' ORDER BY attname;
```

Alle Werkzeuge: [docs/18-testdaten-erzeugen.md](docs/18-testdaten-erzeugen.md)

---

## Schnellstart (Teil 19 — Schätzung und parallele Pläne)

Voraussetzung: `adresse` aus Teil 18.

```sql
ANALYZE adresse;

EXPLAIN (ANALYZE) SELECT * FROM adresse WHERE stadt = 1 AND plz = 100;
EXPLAIN (ANALYZE) SELECT * FROM adresse WHERE stadt = 1;          -- zum Vergleich

CREATE STATISTICS adresse_stadt_plz (dependencies, ndistinct)
    ON stadt, plz FROM adresse;
ANALYZE adresse;

EXPLAIN (ANALYZE) SELECT * FROM adresse WHERE stadt = 1 AND plz = 100;
```

Alle Einzelheiten: [docs/19-schaetzung-und-parallele-plaene.md](docs/19-schaetzung-und-parallele-plaene.md)

---

## Schnellstart (Teil 20 — Sicherung und Wiederherstellung)

Erst die logische Sicherung — daraus lassen sich **einzelne Objekte** zurückholen:

```bash
docker compose exec -u postgres -T db mkdir -p /var/lib/postgresql/backup
docker compose exec -u postgres -T db pg_dump -U kurs -d kurs -Fc -f /var/lib/postgresql/backup/kurs.dump
docker compose exec -T db pg_restore -l /var/lib/postgresql/backup/kurs.dump
```

Für den Zeitpunkt davor braucht es WAL-Archivierung und eine Grundsicherung:

```sql
ALTER SYSTEM SET archive_mode = on;
ALTER SYSTEM SET archive_command = 'test ! -f /var/lib/postgresql/walarchiv/%f && cp %p /var/lib/postgresql/walarchiv/%f';
ALTER SYSTEM SET archive_timeout = '60s';
```

```bash
docker compose exec -u postgres -T db mkdir -p /var/lib/postgresql/walarchiv
docker compose restart db
```

```bash
docker compose exec -u postgres -T db pg_basebackup -U kurs -h /var/run/postgresql -D /var/lib/postgresql/base -X stream -c fast -P
```

Den Rest — Haltepunkt setzen, Unfall, zweite Instanz auf Port 5433,
`recovery_target_name`, Log lesen, prüfen, auflösen — Schritt für Schritt:
[docs/20-sicherung-und-wiederherstellung.md](docs/20-sicherung-und-wiederherstellung.md)

---

## Schnellstart (Teil 21 — Streaming-Replikation)

Voraussetzung: `wal_level = replica` (Vorgabe), `max_wal_senders > 0`. Die
Standby läuft als **zweite Instanz im selben Container**, Ausgangspunkt ist die
Grundsicherung aus Teil 20 — diesmal aber **mit `-R`**:

```bash
docker compose exec -u postgres -T db mkdir -p /var/lib/postgresql/standby
docker compose exec -u postgres -T db pg_basebackup -U kurs -h /var/run/postgresql \
    -D /var/lib/postgresql/standby -X stream -c fast -P -R
```

```bash
docker compose exec -u postgres db bash
pg_ctl -D /var/lib/postgresql/standby -l /var/lib/postgresql/standby.log -o "-p 5433" start
```

Und dann auf beiden Instanzen nachsehen:

```sql
-- Primary (5432):
SELECT application_name, state, sent_lsn, replay_lsn, replay_lag, sync_state
FROM pg_stat_replication;

-- Standby (5433):
SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn();
SELECT status, sender_host, slot_name FROM pg_stat_wal_receiver;
```

Alle Einzelheiten: [docs/21-streaming-replikation.md](docs/21-streaming-replikation.md)

---

## Schnellstart (Teil 22 — Logische Replikation)

Voraussetzung ist `wal_level = logical` (Neustart, kein Reload) — und eine
**zweite** Datenbank daneben, denn auf sich selbst kann man nicht abonnieren:

```sql
-- einmalig in der Konfiguration:
ALTER SYSTEM SET wal_level = 'logical';
```

```bash
docker compose restart db
docker compose exec -T db psql -U kurs -d postgres -c "CREATE DATABASE kurs_abo;"
docker compose exec -T db psql -U kurs -d kurs     -f /sql/04_konto.sql
docker compose exec -T db psql -U kurs -d kurs_abo -f /sql/04_konto.sql
```

Dann auf der Quelle veröffentlichen, auf dem Ziel abonnieren:

```sql
-- Quelle (kurs):
CREATE PUBLICATION pub_konto FOR TABLE konto;

-- Ziel (kurs_abo): erst leeren — sonst kollidiert die Startkopie mit den
-- Zeilen aus 04_konto.sql
TRUNCATE konto;
CREATE SUBSCRIPTION sub_konto
    CONNECTION 'host=/var/run/postgresql port=5432 dbname=kurs user=kurs'
    PUBLICATION pub_konto;
```

Und auf beiden Seiten nachsehen:

```sql
-- Quelle: was ist veröffentlicht, welcher Slot liest?
SELECT * FROM pg_publication_tables WHERE pubname = 'pub_konto';
SELECT slot_name, active, confirmed_flush_lsn, wal_status FROM pg_replication_slots;

-- Ziel: läuft der Abonnent?
SELECT subname, received_lsn, last_msg_receipt_time FROM pg_stat_subscription;
```

Alle Einzelheiten: [docs/22-logische-replikation.md](docs/22-logische-replikation.md)

---

## Schnellstart (Teil 23 — Der WAL-Block)

Voraussetzung: die Tabelle `konto` aus Teil 7 — in die Beispiele unten wird
geschrieben:

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/04_konto.sql
```

Zuerst lesen, was auf **diesem** Server gilt — `context` sagt, ob eine Änderung
Neustart, Reload oder nur eine Sitzung braucht:

```sql
SELECT name, setting, unit, context, vartype, source, pending_restart
FROM pg_settings
WHERE name IN ('wal_level', 'fsync', 'synchronous_commit', 'wal_sync_method',
               'full_page_writes', 'wal_log_hints', 'wal_compression')
ORDER BY name;
```

Dann der Vergleich, den man messen muss: 500 Zeilen mit und ohne Warten auf die
Platte (`\timing on` vorher):

```sql
INSERT INTO konto (id, betrag) SELECT 9000 + g, g FROM generate_series(1, 500) AS g;

SET synchronous_commit = off;
INSERT INTO konto (id, betrag) SELECT 9500 + g, g FROM generate_series(1, 500) AS g;
RESET synchronous_commit;
```

Und die Rechnung für `full_page_writes` — ein Checkpoint setzt den Ausgangspunkt,
ab dem ganze Seiten mitgeloggt werden:

```sql
CHECKPOINT;
SELECT wal_fpi, wal_bytes FROM pg_stat_wal;      -- vorher notieren
UPDATE konto SET betrag = betrag + 1;
SELECT pg_switch_wal();
SELECT wal_fpi, wal_bytes FROM pg_stat_wal;      -- nachher vergleichen
```

Alle sieben Schalter, ihre Vorgaben und das Aufräumen:
[docs/23-wal-und-haltbarkeit.md](docs/23-wal-und-haltbarkeit.md)

---

## Schnellstart (Teil 24 — Rollen und Rechte)

Voraussetzung: die Tabelle `konto` aus Teil 7 (wie im vorigen Abschnitt):

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/04_konto.sql
```

Wer bist du, und was darfst du? Erst nachsehen, nichts ändern:

```sql
\du+                                    -- Rollen mit Attributen und Mitgliedschaften
\h CREATE ROLE                          -- was an einer Rolle einstellbar ist
SELECT current_user, session_user;
```

Dann eine Rolle anlegen und mit `SET ROLE` die Welt aus ihrer Sicht ansehen — jedes
fehlende Recht hat eine eigene Meldung:

```sql
CREATE ROLE sepp LOGIN PASSWORD 'geheim';
SET ROLE sepp;
SELECT count(*) FROM konto;             -- permission denied for table konto
RESET ROLE;

GRANT CONNECT ON DATABASE kurs TO sepp;
GRANT USAGE   ON SCHEMA  public TO sepp;
GRANT SELECT  ON TABLE   konto  TO sepp;
```

Rechte lieber an eine Rolle ohne `LOGIN` hängen und Personen zu Mitgliedern machen:

```sql
CREATE ROLE accounting NOLOGIN;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO accounting;
GRANT accounting TO sepp;
\dp konto
\drg                                   -- wer ist Mitglied von was, mit welchen Optionen
```

Und was der Server von Haus aus erlaubt, sieht man an der `pg_hba.conf`, deren Pfad
`SHOW hba_file;` nennt — dazu die Anmeldung selbst:

```sql
SHOW hba_file;
SHOW password_encryption;
\conninfo
```

Attribute, alle Rechte-Ebenen, vordefinierte Rollen und das Aufräumen (inklusive
`DROP OWNED` / `REASSIGN OWNED`):
[docs/24-rollen-und-rechte.md](docs/24-rollen-und-rechte.md)

---

## Schnellstart (Teil 25 — Verbindungen von außen)

Zuerst ohne Netz, nur am Server — hört er überhaupt, und auf welcher Adresse?

```sql
SHOW listen_addresses;
SHOW port;
SELECT name, setting, context, source, pending_restart
FROM pg_settings WHERE name IN ('listen_addresses', 'port') ORDER BY name;
```

```bash
ss -ltn                       # 127.0.0.1:5432 oder *:5432?
```

Dann die Frage, ob man überhaupt bis zum Server kommt — **ohne** Anmeldung:

```bash
pg_isready -h kurs-00 -p 5432
```

Und erst danach die `pg_hba.conf`, deren Pfad `SHOW hba_file;` nennt: eine
`host`-Zeile für den fremden Client, Reihenfolge von oben nach unten.

```ini
# TYPE   DATABASE  USER  ADDRESS       METHOD
host     kurs      sepp  10.0.0.5/32   scram-sha-256
```

```sql
SELECT pg_reload_conf();      -- hier reicht der Reload, kein Neustart
```

Achtung, die häufigste Falle: die Zeile wirkt nur für Adressen, die nicht schon von
oben erwischt werden. `-h 127.0.0.1`, `-h localhost` und der Socket sind **nicht**
„von außen" — dort gilt weiter die `trust`-Zeile (25.3a).

Vom Client aus, und die Gegenprobe, wie die Sitzung angekommen ist:

```bash
psql -h kurs-00 -p 5432 -U sepp -d kurs
```

```sql
\conninfo
SELECT current_user, inet_server_addr(), inet_server_port();
```

Die drei Tore, `pg_isready` als Suchwerkzeug und das Aufräumen:
[docs/25-verbindungen-von-aussen.md](docs/25-verbindungen-von-aussen.md)

---

## Schnellstart (Teil 26 — TLS)

Erst nachsehen, was gilt — `ssl` ist reloadbar, hier ist also **kein** Neustart nötig:

```sql
SHOW ssl;
SHOW ssl_cert_file;
SHOW ssl_key_file;
SELECT name, setting, context, source, pending_restart
FROM pg_settings WHERE name IN ('ssl', 'ssl_cert_file', 'ssl_key_file') ORDER BY name;
```

Zertifikat und Schlüssel erzeugen — **im Datenverzeichnis**, als `postgres` (im
Container: `docker compose exec -u postgres db bash`, dort heißt der Superuser `kurs`):

```bash
openssl req -new -x509 -days 365 -nodes -text -out server.crt \
  -keyout server.key -subj "/CN=kurs-00"
chmod og-rwx server.key
```

Ein anderer Ort als das Datenverzeichnis geht über `ssl_cert_file` und
`ssl_key_file` — samt der Frage, wem die Dateien gehören müssen und welche Rechte
sie brauchen (26.3a).

```ini
# postgresql.conf
ssl = on
```

```sql
SELECT pg_reload_conf();
SHOW ssl;
```

Der Nachweis, dass es diese Sitzung wirklich betrifft:

```text
\conninfo
```

```sql
SELECT a.usename, a.client_addr, s.ssl, s.version, s.cipher, s.client_dn
FROM pg_stat_activity a LEFT JOIN pg_stat_ssl s USING (pid);
```

Und auf der Client-Seite der Modus — die Vorgabe `prefer` ist keine Empfehlung:

```bash
psql "host=kurs-00 dbname=kurs user=sepp sslmode=require"
```

Die drei Angriffe, `sslmode` in allen sechs Werten, `hostssl` und das Aufräumen:
[docs/26-tls-verschluesselte-verbindungen.md](docs/26-tls-verschluesselte-verbindungen.md)

---

## Schnellstart (Teil 27 — Eigentümer und Rechte)

Zwei Fragen, zwei Befehle — `\dt` zeigt den Eigentümer, **nicht** die Rechte:

```text
\dt
\dp tabelle
```

Ein Objekt gehört einer Rolle, und das ist kein Recht, sondern eine Zugehörigkeit:

```sql
ALTER TABLE tabelle OWNER TO accounting;
```

Deshalb hängt eine Rolle an ihren Objekten — die `DETAIL`-Zeile nennt das Objekt:

```sql
DROP ROLE sepp;
-- ERROR: role "sepp" cannot be dropped because some objects depend on it
-- DETAIL: owner of table tabelle
```

Aufräumen in der Reihenfolge aus Abschnitt 21.4 — **in jeder Datenbank**:

```sql
REASSIGN OWNED BY sepp TO accounting;
DROP OWNED    BY sepp;
DROP ROLE sepp;
```

Die Zeichenketten in der Spalte `Access privileges` (`=c/postgres`,
`accounting=c/postgres`) lesen: Empfänger `=` Rechte `/` Geber, leeres Feld vor
dem `=` heißt `PUBLIC`, ein `*` heißt `WITH GRANT OPTION`. Ungefiltert aus dem
Katalog nachsehen:

```sql
SELECT datname, datacl FROM pg_database ORDER BY datname;
SELECT grantor, grantee, privilege_type, is_grantable
FROM aclexplode((SELECT datacl FROM pg_database WHERE datname = current_database()));
```

Und die Regel, die den ganzen Abschnitt abkürzt: **Objekte gehören Rollen ohne
`LOGIN`, Personen sind nur Mitglieder.**

Der komplette Durchlauf als Skript — Rollen, Übungstabelle, alle Abschnitte,
Aufräumen am Ende — steht in [sql/07_rechte.sql](sql/07_rechte.sql).

Die Besitz-Regel, Tabelle 5.1/5.2, `WITH GRANT OPTION` und die Aufgaben:
[docs/27-eigentuemer-und-acl.md](docs/27-eigentuemer-und-acl.md)

---

## Schnellstart (Teil 28 — Rechte gezielt setzen)

Ein neues Schema ist von Haus aus zu; die drei Stufen der Reihe nach:

```sql
CREATE SCHEMA IF NOT EXISTS myapp;

GRANT CONNECT ON DATABASE kurs TO readonly;    -- 1. in die Datenbank
GRANT USAGE   ON SCHEMA   myapp TO readonly;   -- 2. das Schema benutzen
```

Und dann die zwei Hälften, die man verwechselt — **jetzt** gegen **künftig**:

```sql
-- was schon da ist (Momentaufnahme)
GRANT SELECT ON ALL TABLES IN SCHEMA myapp TO readonly;

-- was danach entsteht (Vorlage) — die Rolle heißt in diesem Container `kurs`
ALTER DEFAULT PRIVILEGES FOR ROLE kurs IN SCHEMA myapp
    GRANT SELECT ON TABLES TO readonly;
```

Nachsehen — Vorgaberechte sieht man nur hier:

```text
\ddp
\dn+ myapp
\dp
```

Den Beweis, dass die Vorlage greift, liefert eine neue Tabelle: anlegen, `\dp`
— die Spalte ist **nicht** leer.

`FOR ROLE` (wer legt die Tabellen wirklich an), `IN SCHEMA`, die Sequenzen als
eigene Zeile und die Verbindung zu `DROP ROLE`:
[docs/28-rechte-gezielt-setzen.md](docs/28-rechte-gezielt-setzen.md)

---

## Schnellstart (Teil 29 — Upgrade)

Zuerst die Frage, die den Aufwand entscheidet — **Major** (18 → 19, Format ändert
sich) oder **Minor** (18.6 → 18.7, nur neue Binärdateien)?

```sql
SELECT version();
```

Nur der Major-Sprung braucht den Umzug. Der Standardweg (`pg_upgrade`) in Kurzform
— beide Binärsätze müssen **gleichzeitig** vorhanden sein:

```bash
# alte Instanz stoppen, leeren Ziel-Cluster mit der NEUEN Version anlegen
docker compose exec -u postgres -T db pg_ctl -D /var/lib/postgresql/18/docker stop
docker compose exec -u postgres -T db /usr/lib/postgresql/19/bin/initdb -D /var/lib/postgresql/19/data

# erst trocken prüfen, dann umziehen (--link schnell, --copy konservativ)
docker compose exec -u postgres -T db /usr/lib/postgresql/19/bin/pg_upgrade \
    -b /usr/lib/postgresql/18/bin -B /usr/lib/postgresql/19/bin \
    -d /var/lib/postgresql/18/docker -D /var/lib/postgresql/19/data --check
docker compose exec -u postgres -T db /usr/lib/postgresql/19/bin/pg_upgrade \
    -b /usr/lib/postgresql/18/bin -B /usr/lib/postgresql/19/bin \
    -d /var/lib/postgresql/18/docker -D /var/lib/postgresql/19/data --link --jobs 4
```

Starten und die Statistik neu erzeugen (gehört zum Upgrade, nicht zum Feinschliff):

```bash
docker compose exec -u postgres -T db pg_ctl -D /var/lib/postgresql/19/data -o "-p 5433" start
docker compose exec -u postgres -T db vacuumdb -p 5433 --all --analyze-in-stages
```

Die Inventur vorher (Erweiterungen, Tablespaces, offene Transaktionen), die
Alternative über Dump, die Replikations-Brücke und die `--link`-Falle Schritt für
Schritt: [docs/29-upgrade.md](docs/29-upgrade.md)

---

## Struktur

```
postgresql-learning/
├── compose.yaml                 # PostgreSQL 18.6 im Container
├── docs/                        # Die Anleitung, Schritt für Schritt
├── sql/                         # Fertige SQL-Dateien zum Ausführen
│   ├── 01_schema.sql
│   ├── 02_insert_4mio.sql
│   ├── 02b_insert_100k_block.sql
│   ├── 03_abfragen.sql
│   ├── 04_konto.sql
│   ├── 05_join_schema.sql
│   ├── 06_adresse.sql
│   └── 07_rechte.sql
└── scripts/
    └── insert-schleife.sh       # 40 × derselbe INSERT-Befehl
```

---

## Version

- PostgreSQL **18.6** — Release 2026-08-13, aktuell stabil (Stand: 21.09.2026)
- Docker-Image: `postgres:18.6`
- Quellcode: https://ftp.postgresql.org/pub/source/v18.6/postgresql-18.6.tar.bz2
