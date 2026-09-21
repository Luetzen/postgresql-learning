# 2 — PostgreSQL im Docker-Container, und sich damit verbinden

Ziel: ein laufender PostgreSQL 18.6, mit dem man sich verbinden kann — und zwar
so, dass man die Datenbank *von außen* und *von innen* erreichen kann.

Die Datei [`compose.yaml`](../compose.yaml) liegt fertig im Repo.

---

## 2.1 Container starten

```bash
docker compose up -d
```

Kontrolle:

```bash
docker compose ps
docker compose logs db | tail -20
```

Im Log muss am Ende so etwas stehen:

```
database system is ready to accept connections
```

Das Image-Einstiegs-Skript legt beim ersten Start automatisch an:

- Benutzer `kurs`
- Datenbank `kurs` (das ist **nicht** die Standard-Datenbank `postgres`, sondern
  eine eigene Übungsdatenbank)
- das Passwort `kurs` (nur für die lokale Übung, niemals für etwas Echtes)

---

## 2.2 Verbinden — Weg 1: von außen auf den Port

`compose.yaml` veröffentlicht Port 5432. Damit kann ein `psql` **auf dem eigenen
Rechner** (falls vorhanden) direkt verbinden:

```bash
psql -h localhost -p 5432 -U kurs -d kurs
```

Passwort: `kurs`

Vorteil: man kann jedes beliebige Werkzeug benutzen (DBeaver, IntelliJ, …).
Nachteil: `psql` muss lokal installiert sein.

---

## 2.3 Verbinden — Weg 2: in den Container hinein

Kein lokales `psql` nötig — der Client steckt schon im Image:

```bash
docker compose exec db psql -U kurs -d kurs
```

Das ist der bequemste Weg und wird ab hier benutzt.

Variante, wenn man eine Weile drinbleiben und mehrere Befehle tippen will:

```bash
docker compose exec db bash
psql -U kurs -d kurs
```

---

## 2.4 Die wichtigsten `psql`-Befehle

Zum Ausprobieren — das sind die, die man ständig braucht:

```sql
\?          -- Hilfe zu allen Backslash-Befehlen
\h          -- Hilfe zu SQL-Befehlen, z.B. \h CREATE TABLE
\l          -- alle Datenbanken auflisten
\c kurs     -- zur Datenbank "kurs" wechseln
\dt         -- alle Tabellen auflisten
\d kurs     -- Struktur der Tabelle "kurs"
\di         -- alle Indizes auflisten
\timing on  -- vor jedem Befehl die Dauer anzeigen
\x          -- Ausgabe breit/untereinander umschalten (bei vielen Spalten)
\i /sql/03_abfragen.sql   -- eine Datei ausführen
\q          -- beenden
```

Merksatz: **`\`-Befehle sind `psql`-Befehle, kein SQL.** Sie funktionieren nur
in `psql`.

---

## 2.5 Warum diese zwei Wege wichtig sind

- **Standard-Datenbank vs. eigene Datenbank:** Nach dem Start gibt es immer die
  Datenbank `postgres`. Sie ist für Verwaltungskram da — Serverbenutzer, Rechte,
  Systemkataloge. Die eigene Kurs-Datenbank ist etwas anderes und wird als
  Nächstes angelegt.
- **Von außen verbinden** ist das, was eine Anwendung (Spring Boot, ein Tool,
  ein Skript) später macht. `-h localhost -p 5432 -U kurs -d kurs` — mehr ist
  eine Datenbankverbindung nicht.
- **Von innen verbinden** ist das, was man beim Lernen und Debuggen macht.

---

## 2.6 Stoppen und Löschen

```bash
docker compose stop        # Container anhalten, Daten bleiben
docker compose start       # wieder starten
docker compose down        # Container löschen, Daten bleiben (Named Volume)
docker compose down -v     # Container UND Daten löschen -- alles neu
```

Wichtig zu wissen: `down` allein löscht die **Daten nicht**. Sie liegen im
Named Volume `pgdata`. Erst `-v` wirft sie weg.

```bash
docker volume ls | grep postgresql-learning
```
