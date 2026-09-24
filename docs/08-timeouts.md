# 8 — Timeouts: Anweisung, Transaktion, Sperre

Ohne Timeout kennt der Server nur zwei Zustände: fertig oder hängt. Genau das
war die Situation in Teil 7 — die wartende Sitzung in 7.6 wartet *beliebig lange*,
und eine offene Transaktion, die nichts tut, hält ihre Sperren bis zum
Verbindungsende.

Timeouts sind die serverseitige Antwort darauf: man legt vorher fest, wie lange
etwas dauern darf, und der Server beendet es danach selbst.

Fünf Einstellungen, drei Ebenen — und eine, die nicht dazugehört.

---

## 8.0 Die Timeouts im Überblick

| Einstellung | Vorgabe | begrenzt | Wirkung |
|-------------|---------|----------|---------|
| `statement_timeout` | `0` (aus) | **eine Anweisung**, vom Eintreffen bis zum Ergebnis | Anweisung bricht ab |
| `lock_timeout` | `0` (aus) | nur das **Warten auf eine Sperre** | Anweisung bricht ab |
| `idle_in_transaction_session_timeout` | `0` (aus) | eine **offene Transaktion, die nichts tut** | Sitzung wird beendet |
| `idle_session_timeout` | `0` (aus) | eine offene **Verbindung** ohne Arbeit | Sitzung wird beendet |
| `transaction_timeout` | `0` (aus) | die **ganze Transaktion**, über alle Anweisungen hinweg | Sitzung wird beendet |
| `deadlock_timeout` | `1s` | **nichts** — nur die Wartezeit, bevor nach einer Verklemmung gesucht wird | kein Abbruch (siehe 7.7) |

Drei Dinge, die man daran typischerweise falsch versteht:

- **`0` heißt aus, nicht „sofort".** Die Vorgabe ist überall „kein Timeout".
- **`deadlock_timeout` gehört nicht in diese Reihe.** Es bricht nichts ab, es
  legt nur fest, wie lange gewartet wird, *bevor* geprüft wird, ob sich zwei
  Transaktionen gegenseitig blockieren. Deshalb steht es schon in 7.7 und nicht
  hier — und der Betriebsteil dazu in Teil 9.
- **Welche Meldung kommt, hängt davon ab, wie tief der Abbruch geht.** Eine
  Anweisung bricht mit `ERROR` ab, die Verbindung bleibt. Eine Sitzung bricht mit
  `FATAL` ab, die Verbindung ist weg:

| Timeout | Meldung | Verbindung |
|---------|---------|------------|
| `statement_timeout` | `ERROR: canceling statement due to statement timeout` | bleibt |
| `lock_timeout` | `ERROR: canceling statement due to lock timeout` | bleibt |
| `idle_in_transaction_session_timeout` | `FATAL: terminating connection due to idle-in-transaction timeout` | **weg** |
| `idle_session_timeout`, `transaction_timeout` | `FATAL: terminating connection due to …` | **weg** |

Werte schreibt man als Zahl (Millisekunden) oder mit Einheit:

```sql
SET statement_timeout = 2000;       -- Millisekunden
SET statement_timeout = '2s';       -- dasselbe, lesbarer
SET statement_timeout = '500ms';
```

Referenz: https://www.postgresql.org/docs/18/runtime-config-client.html

---

## 8.1 Wo man sie setzt — und wie man sie wieder loswird

Aktuelle Werte ansehen:

```sql
SHOW statement_timeout;
SHOW lock_timeout;
SHOW idle_in_transaction_session_timeout;
SHOW idle_session_timeout;
SHOW transaction_timeout;
```

Für die laufende **Sitzung** (bis die Verbindung endet):

```sql
SET statement_timeout = '2s';
```

Nur für die laufende **Transaktion**:

```sql
BEGIN;
SET LOCAL statement_timeout = '2s';
-- ...
COMMIT;
```

Wichtig: `SET LOCAL` funktioniert **nur** innerhalb einer Transaktion. Davor kommt
eine Warnung, und die Einstellung wirkt nicht.

Zurück auf die Vorgabe:

```sql
RESET statement_timeout;      -- Sitzung: zurück auf den Standardwert
SET statement_timeout = 0;    -- ausdrücklich: kein Timeout
```

Für den **Server**, eine **Datenbank** oder eine **Rolle** dauerhaft:

```sql
ALTER DATABASE kurs SET statement_timeout = '5s';
ALTER ROLE kurs SET statement_timeout = '2s';
```

Eine Einstellung an der Rolle hat Vorrang vor der an der Datenbank; ein `SET` in
der Sitzung hat Vorrang vor beiden. Wo die Konfigurationsdatei liegt:

```sql
SHOW config_file;
```

Die vollständige Kette — Vorgabe, `postgresql.conf`, `postgresql.auto.conf`,
Datenbank, Rolle, Sitzung — und wann eine Änderung einen **Neustart** braucht,
steht in Teil 14.

Und der Weg über die Kommandozeile — die Werte kommen dann schon mit der
Verbindung, ohne `SET` im `psql`:

```bash
docker compose exec -T db env PGOPTIONS='-c statement_timeout=2s' \
    psql -U kurs -d kurs -c "SELECT pg_sleep(5);"
```

---

## 8.2 `statement_timeout` — die einzelne Anweisung

```sql
SHOW statement_timeout;
SET statement_timeout = '2s';
SELECT pg_sleep(5);
```

Erwartung:

```
ERROR:  canceling statement due to statement timeout
```

Die Anweisung stirbt, die Verbindung bleibt. `pg_sleep(5)` ist dabei nur ein
bequemer Langläufer — der Server arbeitet wirklich fünf Sekunden und wird nach
zwei abgebrochen.

Was ein zweites Fenster in dieser Zeit sieht (`Timeout` / `PgSleep`), steht in
Teil 10, 10.3.

Gut zu wissen:

- Es gilt für **jede** Anweisung dieser Sitzung, nicht nur für die nächste. Wer es
  einmal setzt und nicht zurücksetzt, wundert sich später.
- Innerhalb einer Transaktion hinterlässt der Abbruch einen **abgebrochenen**
  Zustand: der Prompt wird `!#`, alles Weitere wird verweigert (siehe 7.1). Der
  Timeout ist also derselbe Fehler wie jeder andere — nur selbst gewollt.
- `RESET statement_timeout;` nicht vergessen, es ist keine dauerhafte Änderung.

Was `statement_timeout` **nicht** kann: eine ganze Transaktion aus vielen
schnellen Anweisungen begrenzen. Dafür gibt es `transaction_timeout` (siehe 8.5).

Eine Frage zum Selbstprüfen, statt sie zu glauben: **zählt die Zeit mit, in der
eine Anweisung auf eine Sperre wartet?** Die Situation aus 7.6 herstellen (Fenster
A hält die Zeilensperre), in Fenster B `SET statement_timeout = '2s';` setzen und
das `UPDATE` absetzen. Was passiert?

---

## 8.3 `idle_in_transaction_session_timeout` — die offene Transaktion

Das ist die serverseitige Antwort auf den Fall aus 7.6b
(`state = 'idle in transaction'`): `BEGIN` gesagt, etwas geändert, dann nichts
mehr.

**Fenster A:**

```sql
BEGIN;
UPDATE konto SET betrag = betrag + 100 WHERE id = 2;
-- ab hier: nichts mehr tun, einfach warten
```

Nach dem eingestellten Wert beendet der Server die Sitzung selbst:

```
FATAL:  terminating connection due to idle-in-transaction timeout
server closed the connection unexpectedly
        This probably means the server terminated abnormally
        before or while processing the request.
The connection to the server was lost.  Attempting reset: Succeeded.
```

Drei Dinge daran sind wichtig:

- **`FATAL` statt `ERROR`:** nicht die Anweisung ist gescheitert, sondern die
  **Sitzung** ist weg. Der Server hat entschieden, mit dieser Verbindung nicht
  weiterzurechnen.
- **Die Transaktion ist zurückgerollt.** Das `+100` ist verschwunden, wie bei
  `ROLLBACK`.
- **`psql` verbindet sich automatisch neu** („Attempting reset: Succeeded") und
  man landet wieder bei `kurs=#`. Der Vorgang sieht deshalb harmlos aus. Ein
  Blick auf die Daten zeigt, was wirklich passiert ist:

```sql
SELECT * FROM konto;
```

Das ist genau die Sitzung, die in 7.6b alle anderen warten ließ — nur diesmal
räumt der Server selbst auf, ohne dass jemand nachsehen muss.

Zu vergleichen mit den Werkzeugen aus 7.6b: `pg_cancel_backend()` bricht die
**Anweisung** ab (wie `statement_timeout`), `pg_terminate_backend()` beendet die
**Sitzung** (wie `idle_in_transaction_session_timeout`).

---

## 8.4 `lock_timeout` — nur das Warten auf eine Sperre

Wieder die Situation aus 7.6: Fenster A hält die Zeilensperre, Fenster B wartet.

**Fenster B:**

```sql
SHOW lock_timeout;
SET lock_timeout = '2s';
UPDATE konto SET betrag = 0 WHERE id = 2;
```

Erwartung:

```
ERROR:  canceling statement due to lock timeout
```

Statt beliebig zu warten, gibt B nach zwei Sekunden auf. Die Anweisung ist
abgebrochen, die Verbindung steht weiter — B kann es später erneut versuchen.

Das ist das Muster für Anwendungen: **kurz warten, Fehler bekommen, wiederholen**
statt unbegrenzt zu blockieren. Ein `lock_timeout` im Sekundenbereich ist deshalb
in vielen Systemen besser als keiner: ein Request, der mit einem Fehler
zurückkommt, ist billiger als einer, der hängt.

Und das ist auch die Waffe vor einer Schemaänderung. Ein `ALTER TABLE` wartet
sonst hinter der nächsten offenen Transaktion — und blockiert dahinter *alle*
folgenden Zugriffe auf dieselbe Tabelle:

```sql
SET lock_timeout = '2s';
ALTER TABLE konto ADD COLUMN notiz text;
RESET lock_timeout;
```

Kommt der Fehler, hat man nichts verloren — aber auch nichts kaputtgemacht.

Wichtig ist die Grenze: `lock_timeout` beendet das *Warten*, nicht die *Ursache*.
Eine Verklemmung löst er nur zufällig auf — dafür ist die Deadlock-Erkennung da,
und für die Vermeidung gibt es `NOWAIT` und `SKIP LOCKED` (Teil 9, 9.9).

Warum es ihn überhaupt braucht, sagt die Doku in Kapitel 13.3.4 sehr direkt:

> Solange keine Verklemmung erkannt wird, wartet eine Transaktion auf die
> Freigabe kollidierender Sperren **unbegrenzt**. Das bedeutet, dass es eine
> schlechte Idee ist, Transaktionen lange offen zu halten (etwa während man auf
> eine Benutzereingabe wartet).

Ohne `lock_timeout` gibt es also keinen Fehler, den man behandeln könnte, nur
Warten — und genau das ist 7.6 in Reinform.

---

## 8.5 `idle_session_timeout` und `transaction_timeout`

Diese beiden schließen die letzten Lücken.

**`idle_session_timeout`** — die Verbindung ist offen und tut gar nichts, nicht
einmal innerhalb einer Transaktion:

```sql
BEGIN;
COMMIT;
-- ab hier: nichts mehr tun — keine Transaktion, keine Anweisung
```

Nach dem Zeitlimit meldet der Server
`FATAL: terminating connection due to idle-session timeout`, und die Verbindung
ist weg. Vorgabe: aus. Für einen Verbindungspool ist das die Einstellung, die
vergessene Clients wegräumt, ohne dass jemand sie suchen muss.

**`transaction_timeout`** — die ganze Transaktion, über alle Anweisungen hinweg:

```sql
SET transaction_timeout = '5s';
BEGIN;
SELECT 1;
SELECT pg_sleep(2);
SELECT pg_sleep(2);
-- die Transaktion ist jetzt älter als 5 s
```

Erwartung: die Transaktion wird beendet, obwohl **keine einzelne Anweisung** zu
lange gebraucht hat. Genau das kann `statement_timeout` nicht. Die genaue Meldung
sieht man beim Ablauf selbst — sie ist `FATAL`, die Sitzung wird also beendet,
wie bei `idle_session_timeout`.

Laut Doku überstimmt `transaction_timeout` die beiden anderen, wenn es kürzer ist
als sie.

Warum das nützlich ist: eine hängende Transaktion hält Schnappschüsse und Sperren.
`statement_timeout` hilft nicht dagegen, wenn tausend kurze Anweisungen dieselbe
Transaktion am Leben halten.

---

## 8.6 Was setzt man in der Praxis worauf?

Keine Regel ohne Messen — ein zu kurzes Timeout macht aus einer langsamen, aber
korrekten Abfrage einen Fehler. Als Anhaltspunkte:

| Umgebung | sinnvoll |
|----------|----------|
| Anfrage aus einer Anwendung (Web/API) | `statement_timeout` (wenige Sekunden), `idle_in_transaction_session_timeout` als Netz |
| Verbindungspool | `idle_in_transaction_session_timeout` + `idle_session_timeout` |
| Bericht/Export, der länger dauern darf | `SET LOCAL` in genau dieser Transaktion statt global hochsetzen |
| Schemaänderung | `lock_timeout` davor, danach `RESET` |
| Ein Werkzeug, das gerade hängt | erst `pg_stat_activity` und `pg_blocking_pids()` (Teil 7), der Timeout ist die Notbremse |

Der Merksatz: **Timeouts sind keine Optimierung, sie sind eine Fehlergrenze.**
Sie machen ein Problem nicht schneller — sie machen es *sichtbar*, als Fehler
statt als Hänger.

---

## 8.7 Aufräumen

```sql
RESET statement_timeout;
RESET lock_timeout;
RESET idle_in_transaction_session_timeout;
RESET idle_session_timeout;
RESET transaction_timeout;
```

Und zur Kontrolle, was in dieser Sitzung alles verstellt wurde:

```sql
SHOW ALL;
```

`SHOW ALL` listet jede Einstellung mit ihrem aktuellen Wert.
