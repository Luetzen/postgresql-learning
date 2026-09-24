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
│   └── 06_adresse.sql
└── scripts/
    └── insert-schleife.sh       # 40 × derselbe INSERT-Befehl
```

---

## Version

- PostgreSQL **18.6** — Release 2026-08-13, aktuell stabil (Stand: 21.09.2026)
- Docker-Image: `postgres:18.6`
- Quellcode: https://ftp.postgresql.org/pub/source/v18.6/postgresql-18.6.tar.bz2
