# PostgreSQL lernen

Lernprojekt rund um PostgreSQL 18.6 — alles selbst nachbauen, nichts nur lesen.

Der Ablauf, den wir hier abbilden:

1. PostgreSQL **aus dem Quellcode installieren** (nur zum Verstehen, was da eigentlich passiert)
2. PostgreSQL in einen **Docker-Container** packen und sich damit **verbinden**
3. Die Datenbank `kurs` anlegen mit einer Tabelle `kurs (id, name)`
4. **4.000.000 Datensätze** einfügen — immer derselbe Befehl, aus einer Datei heraus
5. Messen: Was kostet eine Abfrage **ohne** Index, was kostet sie **mit** Index/Constraint?

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

## Struktur

```
postgresql-learning/
├── compose.yaml                 # PostgreSQL 18.6 im Container
├── docs/                        # Die Anleitung, Schritt für Schritt
├── sql/                         # Fertige SQL-Dateien zum Ausführen
│   ├── 01_schema.sql
│   ├── 02_insert_4mio.sql
│   ├── 02b_insert_100k_block.sql
│   └── 03_abfragen.sql
└── scripts/
    └── insert-schleife.sh       # 40 × derselbe INSERT-Befehl
```

---

## Version

- PostgreSQL **18.6** — Release 2026-08-13, aktuell stabil (Stand: 21.09.2026)
- Docker-Image: `postgres:18.6`
- Quellcode: https://ftp.postgresql.org/pub/source/v18.6/postgresql-18.6.tar.bz2
