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
│   └── 04_konto.sql
└── scripts/
    └── insert-schleife.sh       # 40 × derselbe INSERT-Befehl
```

---

## Version

- PostgreSQL **18.6** — Release 2026-08-13, aktuell stabil (Stand: 21.09.2026)
- Docker-Image: `postgres:18.6`
- Quellcode: https://ftp.postgresql.org/pub/source/v18.6/postgresql-18.6.tar.bz2
