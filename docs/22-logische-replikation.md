# 22 — Logische Replikation: Publication, Subscription, Logical Decoding

Teil 21 war **physisch**: die ganze Instanz, Block für Block, gleiche
Version, alles oder nichts. Hier geht es um den **anderen** Weg. Man wählt
**einzelne Tabellen** aus, die andere Seite ist eine ganz normale Datenbank mit
eigenen Tabellen — und sie darf eine andere PostgreSQL-Version haben.

Der Preis dafür: man muss mehr selbst mitbringen. Was genau, steht in 22.0.

Die Doku-Kapitel, um die es geht:

- https://www.postgresql.org/docs/18/logical-replication.html (Publication und
  Subscription)
- https://www.postgresql.org/docs/18/logicaldecoding.html (was darunter passiert)
- https://www.postgresql.org/docs/18/sql-createsubscription.html
- https://www.postgresql.org/docs/18/runtime-config-wal.html (`wal_level`)
- https://www.postgresql.org/docs/18/runtime-config-replication.html
- https://www.postgresql.org/docs/18/monitoring-stats.html
  (`pg_stat_subscription`)

> **Zwei Umgebungen, dieselben Befehle.** Der Kurs arbeitet auf PostgreSQL **19**
> (in der Doku: `/docs/19/…`). Dieses Repo läuft auf `postgres:18.6`, siehe
> [`compose.yaml`](../compose.yaml). Die Handgriffe sind identisch, nur die
> Versionsnummer unterscheidet sich.

---

## 22.0 Was mitkommt — und was nicht

| kommt mit | kommt **nicht** mit |
|-----------|---------------------|
| `INSERT`, `UPDATE`, `DELETE` auf den **veröffentlichten** Tabellen | **DDL** — ein `CREATE`/`ALTER TABLE` interessiert die andere Seite nicht |
| `TRUNCATE` (ab PostgreSQL 11) | **Sequenzwerte** — `serial`/`identity` läuft auf beiden Seiten auseinander |
| die Reihenfolge **innerhalb** einer Transaktion | Systemkataloge, Rollen, Rechte |
| der Startbestand, sofern `copy_data` (Vorgabe) an ist | Large Objects, Tablespaces, Konfiguration |
| eine andere Version/Architektur der Gegenseite ist erlaubt | `COPY` — der geht nicht durch die Leitung |

Der Punkt in der zweiten Spalte, der im Betrieb am meisten Ärger macht: **die
Tabellenstruktur muss auf der Gegenseite schon stimmen.** Man legt sie dort
selbst an — und wenn man später eine Spalte hinzufügt, tut man das auf beiden
Seiten von Hand. Deshalb der Merksatz: **logische Replikation repliziert Daten,
kein Schema.**

---

## 22.1 Die drei Begriffe

| Begriff | wo er lebt | was er ist |
|---------|-----------|------------|
| **Publication** | auf der Quelle (der „Publisher") | die **Auswahlliste**: welche Tabellen angeboten werden |
| **Subscription** | auf dem Ziel (dem „Subscriber") | der **Abonnent**: wer welche Publication nimmt |
| **Replikationsslot** | auf der Quelle | der **Lesezeichen-Zeiger**: wie weit gelesen wurde |

Der Slot ist der wichtigste der drei, und der einzige, den man vergisst:

- `CREATE SUBSCRIPTION` legt ihn **auf der Quelle automatisch** an (sofern man
  ihn nicht mit `create_slot = false` abwählt).
- Er hält **WAL zurück**, solange er existiert — auch wenn niemand liest. Ein
  Slot ohne Abonnent lässt `pg_wal` wachsen (22.8).
- Er gehört zur **Datenbank** der Quelle, nicht zum Cluster.

Anders als in Teil 21 ist das **nicht** „die Instanz nochmal" — es ist ein
Datenstrom, den ein Prozess auf dem Ziel entgegennimmt und als normale
SQL-Befehle anwendet.

---

## 22.2 Voraussetzung: `wal_level = logical`

```sql
SHOW wal_level;    -- muss 'logical' sein
```

Steht dort `replica`, ist es das Niveau aus Teil 21 — für logische Replikation
reicht das nicht. Umstellen heißt: in die Konfiguration schreiben und
**neu starten** (kein Reload):

```sql
ALTER SYSTEM SET wal_level = 'logical';
```

```bash
docker compose restart db
docker compose exec -T db psql -U kurs -d kurs -c "SHOW wal_level;"
```

Sieh zur Kontrolle auch nach `max_replication_slots` und
`max_logical_replication_workers` — beide haben eine Vorgabe, die für die Übung
reicht, aber man sollte wissen, dass sie existieren.

---

## 22.3 Aufsetzen: zwei Datenbanken in derselben Instanz

Logische Replikation darf **innerhalb** eines Clusters laufen — im Gegensatz zur
physischen. Deshalb braucht diese Übung keinen zweiten Server: eine zweite
Datenbank daneben genügt. (Sie muss eine **andere** sein als die Quelle; auf
sich selbst kann man nicht abonnieren.)

**1. Die Zieldatenbank anlegen** (in der Shell):

```bash
docker compose exec -T db psql -U kurs -d postgres -c "CREATE DATABASE kurs_abo;"
```

**2. Die Tabelle auf beiden Seiten anlegen.** Wir nehmen `konto` aus Teil 7 —
die Datei legt dieselbe Struktur an:

```bash
docker compose exec -T db psql -U kurs -d kurs    -f /sql/04_konto.sql
docker compose exec -T db psql -U kurs -d kurs_abo -f /sql/04_konto.sql
```

**3. Auf der Quelle veröffentlichen** (in `kurs`):

```sql
CREATE PUBLICATION pub_konto FOR TABLE konto;
```

**4. Auf dem Ziel abonnieren** (in `kurs_abo`) — vorher leeren:

```sql
-- Das Ziel hat die Startzeilen aus 04_konto.sql (1 und 2) noch drin.
-- Die Startkopie würde daran mit „duplicate key" scheitern (22.8) —
-- deshalb erst leer machen:
TRUNCATE konto;

CREATE SUBSCRIPTION sub_konto
    CONNECTION 'host=/var/run/postgresql port=5432 dbname=kurs user=kurs'
    PUBLICATION pub_konto;
```

Zwei Dinge dazu, die man leicht falsch macht:

- `CREATE SUBSCRIPTION` läuft **nicht** in einem Transaktionsblock. Es muss
  währenddessen ja die Quelle anfassen (den Slot anlegen) — deshalb wäre ein
  `BEGIN` davor ein Fehler.
- Die **Vorgabe `copy_data = true`** kopiert den Startbestand. Deine Zieltabelle
  darf also nicht schon dieselben Primärschlüssel enthalten, sonst kollidiert
  der Kopiervorgang (22.8). Wer den Startbestand **nicht** will, nimmt
  `WITH (copy_data = false)`.

---

## 22.4 Zusehen: vier Abfragen auf beiden Seiten

Auf der **Quelle** (`kurs`) — was ist veröffentlicht, und welcher Slot liest?

```sql
SELECT schemaname, tablename FROM pg_publication_tables WHERE pubname = 'pub_konto';

SELECT slot_name, plugin, slot_type, database, active, restart_lsn,
       confirmed_flush_lsn, wal_status
FROM pg_replication_slots;
```

Auf dem **Ziel** (`kurs_abo`) — läuft der Abonnent?

```sql
SELECT subname, pid, received_lsn, last_msg_receipt_time, latest_end_lsn
FROM pg_stat_subscription;

SELECT count(*) FROM pg_subscription_stats;
```

Und dann etwas ändern und beobachten, wie es durchkommt. Auf der Quelle:

```sql
UPDATE konto SET betrag = betrag + 1 WHERE id = 1;
BEGIN;
INSERT INTO konto (id, name, betrag) VALUES (999, 'neu', 100);
UPDATE konto SET betrag = betrag * 2 WHERE id = 1;
COMMIT;
```

Auf dem Ziel:

```sql
SELECT * FROM konto;
```

Der Vergleich mit Teil 21 lohnt hier besonders: auch die logische Replikation
läuft über eine WAL-sender-Verbindung — aber sie erscheint in **anderen**
Sichten. Schau nach, was auf der Quelle in `pg_stat_replication`
und `pg_stat_replication_slots` auftaucht, und was auf dem Ziel nur in
`pg_stat_subscription` steht. Welche Sicht welchen Weg zeigt, liest man nicht
aus dem Gedächtnis ab, sondern sieht nach.

> **Keine Zahlen in diesem Dokument.** Wie groß die Verzögerung ist und wie
> lange die Startkopie dauert, steht nirgends hier — das hängt an deiner Maschine,
> nicht an PostgreSQL.

---

## 22.5 Replica Identity: warum UPDATE/DELETE einen Schlüssel brauchen

Für jedes `UPDATE`/`DELETE` muss die Quelle sagen können, **welche** Zeile
gemeint ist — auf dem Ziel wird ja nicht dieselbe `ctid` (Teil 12) existieren.
Man benutzt dazu die **Replica Identity**, per Vorgabe den Primärschlüssel.

`konto` hat einen Primärschlüssel — probier es bewusst **ohne**. Auf beiden
Seiten:

```sql
CREATE TABLE ohne_pk (id int, notiz text);
```

Auf der Quelle veröffentlichen und auf dem Ziel abonnieren:

```sql
-- Quelle:
CREATE PUBLICATION pub_ohne_pk FOR TABLE ohne_pk;

-- Ziel:
CREATE SUBSCRIPTION sub_ohne_pk
    CONNECTION 'host=/var/run/postgresql port=5432 dbname=kurs user=kurs'
    PUBLICATION pub_ohne_pk;
```

Jetzt auf der Quelle einfügen und ändern:

```sql
-- Quelle:
INSERT INTO ohne_pk VALUES (1, 'a');
UPDATE ohne_pk SET notiz = 'b' WHERE id = 1;
```

Das `INSERT` kommt an — das `UPDATE` bricht dagegen **ab, und zwar sofort auf
der Quelle**, noch bevor irgendetwas übertragen wird:

```
ERROR:  cannot update table "ohne_pk" because it does not have a replica identity and publishes updates
HINT:  To enable updating the table, set REPLICA IDENTITY using ALTER TABLE.
```

Das ist ein wichtiger Punkt und eine schöne Abgrenzung zu 22.8: **diese Meldung
steht auf der Quelle, nicht im Log des Ziels.** Die Quelle merkt schon beim
Schreiben, dass sie die alte Zeile gar nicht ins WAL legen kann. Besser so —
man erfährt es dort, wo die Änderung entsteht, statt still auf dem Ziel zu
scheitern.

Zwei Wege heraus, beide in der Doku unter `ALTER TABLE … REPLICA IDENTITY`:

```sql
-- Quelle: entweder einen Schlüssel setzen …
CREATE UNIQUE INDEX ohne_pk_id ON ohne_pk (id);
ALTER TABLE ohne_pk REPLICA IDENTITY USING INDEX ohne_pk_id;
```

```sql
-- … oder die ganze alte Zeile mitschicken (teurer):
ALTER TABLE ohne_pk REPLICA IDENTITY FULL;
```

`REPLICA IDENTITY` und der Index sind DDL — sie kommen **nicht** mit (22.0).
Lege sie auf dem Ziel ebenfalls an, damit beide Strukturen gleich bleiben, und
wiederhole das `UPDATE`.

---

## 22.6 Was wirklich über die Leitung geht: Logical Decoding pur

Man kann den Strom auch **ohne** Abonnenten lesen. Dazu legt man einen
logischen Slot mit einem *Ausgabe-Plugin* an — `test_decoding` ist das
Beispiel-Plugin, das die Änderungen als Text ausgibt. Das zeigt am deutlichsten,
dass logische Replikation auf dem WAL aufsetzt, das wir seit Teil 20 kennen.

Auf der Quelle:

```sql
SELECT * FROM pg_create_logical_replication_slot('probe_slot', 'test_decoding');

UPDATE konto SET betrag = betrag + 1 WHERE id = 1;

-- ansehen, ohne zu verbrauchen:
SELECT * FROM pg_logical_slot_peek_changes('probe_slot', NULL, NULL);

-- und diesmal verbrauchen (der Lesezeichen-Zeiger rückt vor):
SELECT * FROM pg_logical_slot_get_changes('probe_slot', NULL, NULL);

SELECT slot_name, confirmed_flush_lsn FROM pg_replication_slots WHERE slot_name = 'probe_slot';
```

Zwischen `peek` und `get` liegt der ganze Unterschied: das eine lässt den Slot
stehen, das andere schiebt ihn weiter. Genau dieses Weiterrücken macht ein
Abonnent im Betrieb — und deshalb hält ein Slot, den niemand liest, den WAL
fest.

Aufräumen:

```sql
SELECT pg_drop_replication_slot('probe_slot');
```

> Wenn `pg_create_logical_replication_slot` das Plugin nicht findet: nachsehen,
> welche Plugins da sind (`ls /usr/lib/postgresql/18/lib/*.so`) — `test_decoding`
> ist Teil der Contrib-Module und in dieser Installation normalerweise dabei.

---

## 22.7 Die Tabelle wächst: `REFRESH PUBLICATION`

Ein neues Objekt auf der Quelle wird **nicht** automatisch mitgenommen. Der Weg
ist: auf der Quelle veröffentlichen, auf dem Ziel die Tabelle anlegen, dann den
Abonnenten nachziehen lassen.

```sql
-- Quelle: eine neue Tabelle und in die Publication aufnehmen
CREATE TABLE thema2 (id int PRIMARY KEY, bezeichnung text);
ALTER PUBLICATION pub_konto ADD TABLE thema2;
```

```sql
-- Ziel: dieselbe Struktur anlegen, dann nachziehen
CREATE TABLE thema2 (id int PRIMARY KEY, bezeichnung text);
ALTER SUBSCRIPTION sub_konto REFRESH PUBLICATION;
SELECT * FROM pg_subscription_rel;      -- welcher Zustand pro Tabelle?
```

`pg_subscription_rel` ist die Sicht, die diese Fälle beantwortet: pro Tabelle
ein `srsubstate` — ist sie schon kopiert (`r` = ready), läuft sie noch (`i` =
initialize, `d` = data copy), oder hat sie einen Fehler (`e`)?

---

## 22.8 Wenn es hakt

| Symptom | wahrscheinliche Ursache | wo nachsehen |
|---------|-------------------------|--------------|
| „logical decoding requires wal_level >= logical" | `wal_level` zu niedrig | `SHOW wal_level;`, 22.2 |
| `CREATE SUBSCRIPTION` scheitert | innerhalb eines Transaktionsblocks | Fehlermeldung; `BEGIN` davor entfernen |
| Abonnent läuft nicht an | Quelle nicht erreichbar, kein `replication`-Eintrag in der `pg_hba.conf` der Quelle, oder Slot schon belegt | `pg_stat_subscription` (leer?), Log des **Ziels**, `pg_hba.conf` der Quelle (21.8) |
| `ERROR: … does not have a replica identity` | `UPDATE`/`DELETE` ohne Schlüssel | **Quelle**, sofort beim Schreiben — 22.5 |
| „duplicate key value violates unique constraint" bei der Startkopie | Ziel hatte die Zeilen schon | `copy_data`, oder vorher leeren |
| „column … does not exist" / Typ passt nicht | Schemata laufen auseinander | beide Tabellen mit `\d` vergleichen |
| neue Tabelle kommt nicht an | nicht in der Publication bzw. kein `REFRESH` | 22.7 |
| `pg_wal` auf der Quelle wächst | Slot ohne Leser | `pg_replication_slots` (`active`), `max_slot_wal_keep_size` |
| `wal_status` nicht mehr `reserved` | der Slot braucht WAL, der schon recycelt ist | `pg_replication_slots`, Log — Abhilfe: neu aufsetzen |

Der wichtigste Punkt der Liste, wie schon in Teil 21: **Fehler beim *Anwenden*
stehen im Log des Ziels, nicht der Quelle** — die Quelle merkt nur, dass der
Slot nicht gelesen wird. Eine Ausnahme ist die Replica-Identity-Meldung aus
22.5: die kommt von der Quelle, weil sie schon beim Schreiben nicht
durchkommt.

---

## 22.9 Der Unterschied zu Teil 21 — auf einen Blick

| | Physisch (Teil 21) | Logisch (Teil 22) |
|---|--------------------|-------------------|
| Umfang | die **ganze** Instanz | **ausgewählte** Tabellen |
| Gegenseite | dieselbe Version, dieselbe Struktur | beliebige Version, eigenes Schema |
| Transportweg | `walsender` → `walreceiver`, Block für Block | Slot + Apply-Prozess, Änderungen als Daten |
| Gegenseite schreibbar? | nein, read-only (`t` in `pg_is_in_recovery()`) | ja, es ist eine normale Datenbank |
| DDL, Sequenzen | laufen mit (ist ja derselbe Zustand) | **nicht** — 22.0 |
| sichtbar in | `pg_stat_replication`, `pg_stat_wal_receiver` | `pg_stat_subscription`, `pg_replication_slots`, `pg_stat_replication_slots` |
| wofür | Ausfallsicherheit, ein Abbild der Instanz | Datenverteilung, Migration zwischen Versionen |

Sie schließen sich nicht aus: man kann eine physische Standby **und**
logische Abonnenten gleichzeitig auf derselben Quelle laufen lassen. Beide
lesen dasselbe WAL.

---

## 22.10 Aufräumen

Erst das Abonnement **auf dem Ziel** — das räumt den Slot auf der Quelle mit ab:

```sql
-- Ziel (kurs_abo):
DROP SUBSCRIPTION sub_konto;
DROP SUBSCRIPTION sub_ohne_pk;
```

```sql
-- Quelle (kurs):
DROP PUBLICATION pub_konto;
DROP PUBLICATION pub_ohne_pk;
SELECT slot_name, active FROM pg_replication_slots;   -- leer?
```

Ist die Quelle beim `DROP` gerade **nicht** erreichbar, verweigert PostgreSQL
das Aufräumen des Slots — dann muss man es ausdrücklich abwählen und den Slot
selbst löschen:

```sql
-- Ziel: Slot nicht mehr anfassen
ALTER SUBSCRIPTION sub_konto SET (slot_name = NONE);
DROP SUBSCRIPTION sub_konto;
```

```sql
-- Quelle: dann per Hand
SELECT pg_drop_replication_slot('sub_konto');
```

Zum Schluss die Übungsreste weg — und `wal_level` wieder zurückstellen, falls du
diesen Teil nicht ohnehin weiterverfolgst:

```bash
docker compose exec -T db psql -U kurs -d kurs     -c "DROP TABLE IF EXISTS ohne_pk, thema2;"
docker compose exec -T db psql -U kurs -d postgres -c "DROP DATABASE kurs_abo;"
docker compose exec -T db psql -U kurs -d kurs     -c "SELECT slot_name FROM pg_replication_slots;"
```

Ein Slot, den niemand mehr liest, hält WAL für immer zurück — dieselbe Regel wie
in 21.10.
