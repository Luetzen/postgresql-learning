# 14 — Konfiguration: wo Einstellungen stehen und wann sie wirken

Jede Einstellung in PostgreSQL hat **einen Ort** und **einen Zeitpunkt**. Wer das
verwechselt, ändert etwas und wundert sich, dass nichts passiert — oder dass es
nach dem nächsten Neustart wieder weg ist.

In 8.1 haben wir das für die Timeouts schon benutzt. Hier steht das Ganze an einer
Stelle, mit Autovacuum als Beispiel — denn dort ist es besonders praktisch, weil
fast alle Werte **ohne Neustart** wirksam werden.

---

## 14.0 Die Kette: wer gewinnt

Wenn eine Einstellung mehrere Werte hat, gilt der **spätere** in dieser Liste:

| Stufe | wo | gilt |
|-------|-----|------|
| Vorgabe | eingebaut | immer, wenn nichts anderes gesetzt ist |
| `postgresql.conf` | in der Datenverzeichnis-Konfiguration | für den Server |
| `postgresql.auto.conf` | daneben, geschrieben von `ALTER SYSTEM` | **überstimmt** `postgresql.conf` |
| `ALTER DATABASE … SET` | im Katalog | für eine Datenbank |
| `ALTER ROLE … SET` | im Katalog | für eine Rolle — überstimmt die Datenbank |
| `SET` / `SET LOCAL` | in der Sitzung | für die Sitzung bzw. Transaktion (8.1) |

Dazu kommen noch Werte von der Kommandozeile und aus Umgebungsvariablen
(`PGOPTIONS`, in 8.1 vorgestellt).

Der praktisch wichtigste Punkt: **`ALTER SYSTEM` ist keine Ergänzung, sondern
überstimmt die Datei.** Wer in `postgresql.conf` etwas ändert und vorher einmal
`ALTER SYSTEM` benutzt hat, ändert möglicherweise nichts Wirksames.

---

## 14.1 Wo die Datei liegt

```sql
SHOW config_file;
SHOW hba_file;
```

Im Container liegt sie im Datenverzeichnis (siehe den Hinweis in
[`compose.yaml`](../compose.yaml)) — und das ist ein Docker-Volume, **kein**
eingebundener Ordner. Von außen kommt man also nicht einfach dran, und im Image
ist auch kein Editor dabei.

Deshalb: für den Alltag ist `ALTER SYSTEM` der bequemere Weg. Die Datei direkt zu
bearbeiten lohnt nur, wenn man ohnehin einen Editor und Zugriff auf das
Datenverzeichnis hat.

---

## 14.2 Drei Wege, etwas zu ändern

```sql
-- 1. für die Sitzung: sofort wirksam, beim Verbindungsende weg
SET work_mem = '64MB';

-- 2. für den Server, ohne Editor: landet in postgresql.auto.conf
ALTER SYSTEM SET autovacuum_naptime = '30s';
SELECT pg_reload_conf();          -- Konfiguration neu einlesen

-- 3. direkt in postgresql.conf: Datei bearbeiten, dann neu einlesen
```

Zu jedem Zeitpunkt prüfbar:

```sql
SHOW autovacuum_naptime;
```

Und rückgängig machen:

```sql
ALTER SYSTEM RESET autovacuum_naptime;
SELECT pg_reload_conf();
```

`ALTER SYSTEM RESET ALL` nimmt alle so gesetzten Werte zurück —
vorsichtig verwenden, es gibt keinen Papierkorb.

---

## 14.3 Wann es wirkt: `pg_settings` fragen

Das ist die Antwort auf „warum ist dieser Wert so, und was passiert, wenn ich ihn
ändere?":

```sql
SELECT name, setting, unit, context, source, sourcefile, pending_restart
FROM pg_settings
WHERE name LIKE 'autovacuum%'
ORDER BY name;
```

Die drei Spalten, auf die es ankommt:

| Spalte | Bedeutung |
|--------|-----------|
| `setting` | der Wert, der gerade gilt |
| `context` | **wann** eine Änderung greift (siehe unten) |
| `source` | **woher** der aktuelle Wert kommt — `default`, `configuration file`, `database`, `role`, `session`, `environment variable`, `command line` |
| `pending_restart` | `true`, wenn der Wert in der Datei schon geändert ist, aber erst nach einem Neustart gilt |

`source` ist die Spalte, die man bei „das ist doch gesetzt!" aufruft: sie sagt,
ob der Wert wirklich aus der Datei kommt oder noch die Vorgabe ist.

### Alle Parameter — die ungefilterte Liste

Ohne `WHERE` listet dieselbe Sicht **jeden** Parameter der Installation:

```sql
SELECT name, setting, unit FROM pg_settings ORDER BY name;
```

Das ist eine lange Liste — und ohne Ordnung kaum zu lesen. Die Spalte, die sie
lesbar macht, sieht man sich deshalb am besten zuerst gruppiert an:

```sql
SELECT category, count(*) FROM pg_settings GROUP BY category ORDER BY category;
```

`category` ist die Einteilung, in der die Doku die Parameter führt („Autovacuum",
„Client Connection Defaults", „Write-Ahead Log" …). Damit findest du die Gruppe,
in der ein Parameter steckt, und siehst sie dann gezielt an:

```sql
SELECT name, setting, unit, context
FROM pg_settings
WHERE category LIKE 'Write-Ahead Log%'      -- Untergruppen wie „… / Archiving" mit
ORDER BY name;
```

Zwei Dinge, die man beim Blick in die volle Liste mitnimmt:

- **`name`/`setting` sind nicht alles.** Die zwei Spalten sind die halbe Antwort;
  erst `context` (14.4), `source` (oben) und `pending_restart` machen daraus eine
  Antwort auf „warum ist das so, und was passiert, wenn ich es ändere?".
- **Die Liste ist versionsabhängig.** Zwischen zwei Major-Versionen kommen
  Parameter dazu und fallen weg — ein Grund mehr, vor einem Upgrade in die
  Release Notes zu sehen (Teil 29).

---

## 14.4 `context`: Reload oder Neustart?

| `context` | was nötig ist |
|-----------|---------------|
| `internal` | gar nicht änderbar |
| `postmaster` | **Neustart** des Servers |
| `sighup` | Datei ändern oder `ALTER SYSTEM`, dann neu einlesen (`pg_reload_conf()`) |
| `superuser` | `SET`, nur für die Sitzung; Superuser nötig |
| `user` | `SET`, nur für die Sitzung |

Klassische Beispiele:

- `shared_buffers` → `postmaster`, Neustart.
- `autovacuum_max_workers` → Neustart. (Wie viele Arbeiter laufen dürfen, kann
  man nicht im Betrieb umstellen.)
- `autovacuum_naptime`, `autovacuum_vacuum_scale_factor`, `work_mem` → `sighup`
  bzw. `user`, also ohne Neustart machbar.

Im Container ist ein Neustart harmlos:

```bash
docker compose restart db
```

In einer echten Umgebung ist es das nicht — deshalb lohnt der Blick in
`context`, **bevor** man etwas ändert.

---

## 14.5 Lieber klein als global

Nicht jede Anpassung gehört in die Serverkonfiguration. Oft ist die richtige
Antwort „nur für diese Datenbank" oder „nur für diese Tabelle":

```sql
-- für eine Datenbank / Rolle (siehe 8.1)
ALTER DATABASE kurs SET statement_timeout = '5s';
ALTER ROLE kurs SET statement_timeout = '2s';
```

Und für Autovacuum gibt es **Tabellen-Parameter**, die kein Serverneustart
brauchen und nur eine Tabelle betreffen:

```sql
ALTER TABLE kurs SET (autovacuum_vacuum_scale_factor = 0.05,
                      autovacuum_vacuum_threshold = 100);

-- nachsehen
SELECT relname, reloptions FROM pg_class WHERE relname = 'kurs';

-- wieder wegnehmen
ALTER TABLE kurs RESET (autovacuum_vacuum_scale_factor,
                        autovacuum_vacuum_threshold);
```

Das ist meistens die bessere Idee als der große Hebel: eine einzelne
vielgeänderte Tabelle bekommt eigene Schwellen, der Rest bleibt bei den Vorgaben.

---

## 14.6 Autovacuum konkret

Die Schalter, die man wirklich anfasst:

```sql
SHOW autovacuum;                        -- Hauptschalter
SHOW autovacuum_naptime;                -- wie oft nachgesehen wird
SHOW autovacuum_vacuum_threshold;       -- ab wie vielen toten Zeilen
SHOW autovacuum_vacuum_scale_factor;    -- plus Anteil der Tabellengröße
SHOW autovacuum_max_workers;            -- Neustart nötig!
SHOW autovacuum_freeze_max_age;         -- ab wann aggressiv (13.7)
```

Zwei Warnungen:

- **`autovacuum = off` ist fast immer ein Fehler.** Man gewinnt etwas Ruhe und
  bezahlt mit wachsenden Tabellen bis hin zum Transaktionszähler-Problem (13.7).
- **Werte global hochsetzen ist selten die Lösung.** Wenn eine Tabelle zu spät
  aufgeräumt wird, liegt es meistens an langen Transaktionen (13.5) — und die
  bekommt man nicht über die Konfiguration weg.

---

## 14.7 Übung

Eine Einstellung ändern, prüfen, zurücknehmen:

```sql
SHOW autovacuum_naptime;

ALTER SYSTEM SET autovacuum_naptime = '30s';
SELECT pg_reload_conf();

SHOW autovacuum_naptime;
SELECT setting, unit, context, source, pending_restart
FROM pg_settings WHERE name = 'autovacuum_naptime';
```

Erwartung: der neue Wert steht da, `source` ist nicht mehr `default`, und
`pending_restart` bleibt `false` — ein Reload hat gereicht.

Und dasselbe für einen Parameter, der einen Neustart braucht:

```sql
SELECT name, setting, context, pending_restart
FROM pg_settings WHERE name = 'autovacuum_max_workers';
```

Dann in der Sitzung etwas ändern (was **nicht** in die Datei geht):

```sql
SET work_mem = '64MB';
SHOW work_mem;
SELECT source FROM pg_settings WHERE name = 'work_mem';
```

`source` sagt jetzt `session` — und dass es beim nächsten Verbinden weg ist.

---

## 14.8 Aufräumen

```sql
ALTER SYSTEM RESET autovacuum_naptime;
SELECT pg_reload_conf();
SHOW autovacuum_naptime;
```

Kontrolle, dass nichts hängen geblieben ist:

```sql
SELECT name, setting, source
FROM pg_settings
WHERE source NOT IN ('default', 'configuration file')
ORDER BY name;
```

Das ist die Abfrage, die man nach jedem Experiment laufen lässt: sie zeigt genau
das, was man selbst verstellt hat.
