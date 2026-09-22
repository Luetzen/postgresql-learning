# 12 — MVCC: Zeilenversionen, `xmin`/`xmax` und alte Werte

In Teil 7 ging es um die Frage „wer darf gleichzeitig was?" — mit Sperren. Die
Antwort von PostgreSQL ist aber fast immer: **niemand muss warten, weil es die
Zeile mehrfach gibt.** Das ist MVCC (*multiversion concurrency control*), und die
Systemspalten `xmin`, `xmax` und `ctid` sind der Weg, es mit eigenen Augen zu
sehen.

Voraussetzung: `konto` aus Teil 7 — [`sql/04_konto.sql`](../sql/04_konto.sql)

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/04_konto.sql
```

---

## 12.0 Die Idee

Ein Leser und ein Schreiber behindern sich nicht. Damit das geht, wird nichts
überschrieben: **jedes `UPDATE` schreibt eine neue Fassung der Zeile** und lässt
die alte stehen. Jede dieser Fassungen ist eine *Zeilenversion* (Doku: „a row
version is an individual state of a row").

Die alte Fassung verschwindet nicht durch Sperren, sondern dadurch, dass sie
irgendwann **niemandem mehr sichtbar** ist. Und eingesammelt wird sie erst von
`VACUUM` (Teil 13).

Referenz: https://www.postgresql.org/docs/18/mvcc.html

---

## 12.1 Die Systemspalten

Jede Tabelle hat sie, man kann sie ausdrücklich auswählen:

```sql
SELECT ctid, xmin, xmax, cmin, cmax, * FROM konto;
```

| Spalte | Bedeutung (Doku 5.6) |
|--------|----------------------|
| `xmin` | Transaktions-ID, die **diese Version eingefügt** hat |
| `xmax` | Transaktions-ID, die diese Version **gelöscht** hat, oder `0` |
| `ctid` | **physische Lage** der Version: Seite und Position, z. B. `(0,24)` |
| `cmin` / `cmax` | welche Anweisung *innerhalb* der Transaktion das getan hat |
| `tableoid` | OID der Tabelle (nützlich bei Partitionen und Vererbung) |

Die Doku sagt dazu beruhigend: *„Eigentlich musst du dich um diese Spalten nicht
kümmern; wisse einfach, dass es sie gibt."* Für den Alltag stimmt das. Eine
Ausnahme ist wichtig und steht auch dort:

> Obwohl man mit `ctid` die Zeilenversion sehr schnell finden kann, ändert sich
> die `ctid` einer Zeile, wenn sie geändert oder von `VACUUM FULL` verschoben
> wird. Deshalb sollte `ctid` nicht als Zeilenbezeichner verwendet werden. Ein
> Primary Key sollte logische Zeilen identifizieren.

`ctid` ist also eine **Adresse**, keine Identität. Wer sie in einer Anwendung
speichert, hält irgendwann auf die falsche Zeile.

---

## 12.2 Ein `UPDATE` in Zeitlupe

Zwei Fenster. In **Fenster B**:

```sql
BEGIN;
SELECT pg_current_xact_id();     -- diese Nummer merken
UPDATE konto SET betrag = betrag + 100 WHERE id = 1;
-- NICHT committen
```

In **Fenster A**:

```sql
SELECT ctid, xmin, xmax, betrag FROM konto WHERE id = 1;
```

Erwartung: A sieht den **alten** `betrag`, und `xmax` ist die Nummer aus B. Die
Transaktion B ist noch nicht bestätigt — also gilt die alte Version weiter. A
wartet dabei **nicht**: MVCC heißt, Lesen stört das Schreiben nicht und umgekehrt
(anders als bei den Sperren in 7.6, wo A die Zeile geändert hatte).

Jetzt in B:

```sql
COMMIT;
```

Und in A noch einmal dieselbe Abfrage. Erwartung: eine **neue `ctid`**, `xmin`
ist die Nummer aus B, `xmax` wieder `0`, neuer `betrag`. Das ist die neue
Zeilenversion.

---

## 12.3 Der Fall aus dem Kurs: sichtbar mit `xmax` ungleich null

Nach einem **`ROLLBACK`** passiert etwas, das zuerst falsch aussieht: die Zeile
ist sichtbar — und trägt trotzdem noch ein `xmax`.

Dafür gibt es einen Satz in der Doku, der genau diesen Fall nennt:

> Es ist möglich, dass diese Spalte in einer **sichtbaren** Zeilenversion ungleich
> null ist. Das deutet normalerweise darauf hin, dass die löschende Transaktion
> **noch nicht bestätigt** wurde, oder dass ein versuchtes Löschen **zurückgerollt**
> wurde.

Beide Fälle sind harmlos:

- **Nicht bestätigt** → die andere Sitzung darf die alte Version noch sehen (12.2).
- **Zurückgerollt** → das Löschen ist nie passiert. Warum steht die Nummer dann
  noch da? Weil niemand sie ausgetragen hat: der Zeilenkopf wird nicht
  zurückgeschrieben, nur weil eine Transaktion gescheitert ist. Jeder Leser
  schlägt den Status nach und sieht „abgebrochen" — und behandelt die Zeile als
  nicht gelöscht.

Was beim `ROLLBACK` noch entsteht: die Transaktion hatte in 12.2 eine **zweite
Zeilenversion geschrieben**. Die ist jetzt tot — sie hat ein `xmin` einer
abgebrochenen Transaktion, also sieht sie niemand. Sie liegt aber physisch auf
der Seite und wird erst von `VACUUM` weggeräumt (Teil 13).

Zwei Dinge, die man daraus mitnimmt:

- `xmax` ist **kein Löschvermerk**, sondern ein Verweis auf die *versuchende*
  Transaktion. Ob der Versuch erfolgreich war, sagt erst deren Status.
- Ein `ROLLBACK` ist nicht „sauber": er lässt eine tote Version liegen und ein
  `xmax` stehen, das nicht mehr bedeutet, was es aussieht.

---

## 12.4 Die Kochrezepte

```sql
SELECT ctid, xmin, xmax, betrag FROM konto;
```

| was du siehst | was es heißt |
|---------------|--------------|
| `xmax = 0` | niemand hat an dieser Version gezogen — aktueller Stand |
| `xmax <> 0`, Zeile **unsichtbar** | gelöscht (bestätigt) |
| `xmax <> 0`, Zeile **sichtbar** | Löschen läuft noch oder ist zurückgerollt |

Und den Status direkt fragen:

```sql
SELECT xmax::text::xid8 AS wer,
       pg_xact_status(xmax::text::xid8) AS status
FROM konto
WHERE id = 1;
```

Erwartung: `in progress` (läuft noch), `committed` (gelöscht) oder `aborted`
(zurückgerollt). `NULL`, wenn die Information schon weggeräumt ist.

Der Umweg über `::text::xid8` ist nötig, weil `xid` (32 Bit) und `xid8` (64 Bit)
verschiedene Typen sind.

---

## 12.5 Die xid-Werkzeuge

| Funktion | Was sie liefert |
|----------|-----------------|
| `pg_current_xact_id()` | die ID **dieser** Transaktion — vergibt eine neue, falls noch keine da ist |
| `pg_current_xact_id_if_assigned()` | dieselbe, aber `NULL` statt einer neuen ID — für Lesetransaktionen |
| `pg_xact_status(xid8)` | `in progress`, `committed`, `aborted` |
| `pg_current_snapshot()` | der aktuelle Schnappschuss |
| `pg_snapshot_xmin/xmax/xip(...)` | dessen Bestandteile |
| `pg_visible_in_snapshot(xid8, snap)` | war diese Transaktion beim Schnappschuss schon fertig? |
| `age(xid)` | Anzahl Transaktionen seit dieser ID |

Ein Detail, das man leicht falsch macht: **eine ID entsteht erst beim Schreiben.**
Laut Doku vergibt `pg_current_xact_id()` „eine neue, falls die Transaktion noch
keine hat (weil sie keine Datenbankänderung vorgenommen hat)". Deshalb gibt es die
`_if_assigned`-Variante — sie verbraucht keine.

Und die veralteten Namen: seit PostgreSQL 13 gibt es `xid8`, und die alten
Funktionen heißen weiter, stehen aber in der Doku unter **„Deprecated"**. Man
sollte sie in neuem Code nicht mehr nehmen.

| veraltet | aktuell |
|----------|---------|
| `txid_current()` | `pg_current_xact_id()` |
| `txid_current_if_assigned()` | `pg_current_xact_id_if_assigned()` |
| `txid_current_snapshot()` | `pg_current_snapshot()` |
| `txid_snapshot_xmin/xmax/xip(...)` | `pg_snapshot_xmin/xmax/xip(...)` |
| `txid_visible_in_snapshot(...)` | `pg_visible_in_snapshot(...)` |
| `txid_status()` | `pg_xact_status()` |

Der Grund für `xid8`: `xid` ist 32 Bit und läuft alle 4 Milliarden Transaktionen
über; `xid8` läuft „während der Lebensdauer einer Installation" nicht über.

---

## 12.6 Die Namensfalle: zwei verschiedene `xmin`/`xmax`

`pg_current_snapshot()` hat **auch** ein `xmin` und `xmax` — und die bedeuten
etwas völlig anderes als die Spalten in 12.1:

| Snapshot-Bestandteil | Bedeutung (Doku, Tabelle 9.85) |
|----------------------|-------------------------------|
| `xmin` | niedrigste Transaktions-ID, die noch **aktiv** war — alles darunter ist fertig (sichtbar oder tot) |
| `xmax` | eins **über** der höchsten abgeschlossenen — alles ab `xmax` war unsichtbar |
| `xip_list` | die zu diesem Zeitpunkt **laufenden** Transaktionen |

Die Textform ist `xmin:xmax:xip_list`, z. B. `10:20:10,14,15`.

```sql
SELECT pg_current_snapshot(),
       pg_snapshot_xmin(pg_current_snapshot()) AS untergrenze,
       pg_snapshot_xmax(pg_current_snapshot()) AS obergrenze;
```

Merksatz: **Zeilen-`xmin`/`xmax` = wer hat diese Fassung gemacht und wer zieht
daran. Snapshot-`xmin`/`xmax` = was ist gerade sichtbar.** Gleiche Namen, kein
Zusammenhang.

---

## 12.7 Warum das mehr als Theorie ist

Zwei praktische Konsequenzen:

1. **`ctid` nie als Schlüssel.** Siehe 12.1 — nimm einen Primary Key.
2. **Ein langer Schnappschuss hält Müll am Leben.** Solange irgendeine
   Transaktion einen Schnappschuss hat, der eine alte Zeilenversion noch sehen
   *könnte*, darf `VACUUM` sie nicht wegräumen. Genau deshalb:

   - ist „Transaktion immer beenden" keine Stilfrage, sondern eine Frage der
     Datenbankgröße (7.6b, 8.3),
   - wartet ein `CREATE INDEX CONCURRENTLY` auf alte Schnappschüsse (11.2),
   - und bläht eine Tabelle auf, in der ständig aktualisiert wird (Teil 13).

---

## 12.8 Übung für `06-kurs-notizen.md`

**Fenster B:**

```sql
BEGIN;
SELECT pg_current_xact_id();          -- diese Nummer aufschreiben
UPDATE konto SET betrag = betrag + 100 WHERE id = 1;
SELECT ctid, xmin, xmax FROM konto WHERE id = 1;
```

Notiere `ctid`, `xmin`, `xmax` **innerhalb** der Transaktion. Dann:

```sql
ROLLBACK;
SELECT ctid, xmin, xmax, betrag FROM konto WHERE id = 1;
```

Erwartung: `betrag` unverändert, `xmax` steht aber weiter auf der Nummer aus B.
Jetzt:

```sql
SELECT pg_xact_status(<deine Nummer>::text::xid8) AS status;
SELECT ctid, xmin, xmax FROM konto WHERE id = 1;
```

Und dann der Vergleich mit `COMMIT` statt `ROLLBACK` — erst dann wird aus der
zweiten Version die sichtbare, und die `ctid` **muss** sich ändern.

---

## 12.8 Aufräumen

```sql
SELECT ctid, xmin, xmax, * FROM konto;
```

Wenn die Daten aus den Experimenten stören, hilft Teil 13 oder einfach neu
anlegen:

```bash
docker compose exec -T db psql -U kurs -d kurs -f /sql/04_konto.sql
```
