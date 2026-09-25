# 28 — Rechte gezielt setzen: Schema, Read-only-Rolle, Vorgaberechte

In deiner Sitzung sind zwei Befehle hintereinander gelaufen, und sie gehören
zusammen:

```sql
GRANT USAGE ON SCHEMA myapp TO readonly;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA myapp
    GRANT SELECT ON TABLES TO readonly;
```

Teil 27 war das **Lesen**: wer besitzt was, und was steht in den Zeichenketten.
Das hier ist die andere Richtung — **Rechte einrichten**, und zwar so, dass sie
nicht beim nächsten `CREATE TABLE` wieder kaputt sind. Die beiden Befehle decken
dabei zwei verschiedene Hälften ab:

| | gilt für | Befehl | Abschnitt |
|---|----------|--------|-----------|
| was **jetzt schon da ist** | die vorhandenen Tabellen | `GRANT … ON …` | 28.4 |
| was **künftig entsteht** | alles, was danach angelegt wird | `ALTER DEFAULT PRIVILEGES` | 28.3 |
| **dazwischen** | die Tür: das Schema selbst | `GRANT USAGE ON SCHEMA` | 28.2 |

Die dritte Zeile ist die, die man vergisst, und genau daran scheitert der
häufigste Fall: `GRANT SELECT` auf alles — und trotzdem `permission denied for
schema myapp`. Und die Lücke, die die beiden Befehle aus der Sitzung offen
lassen, steht in 28.4: die Tabellen, die **zwischen** „jetzt" und „künftig"
liegen, sind nicht mitgemeint.

Die Doku-Kapitel, um die es geht:

- https://www.postgresql.org/docs/18/sql-alterdefaultprivileges.html — **die
  Seite für diesen Teil.** Alle Regeln in 28.3 und 28.8 sind von dort.
- https://www.postgresql.org/docs/18/sql-grant.html und
  https://www.postgresql.org/docs/18/sql-revoke.html — die Befehle selbst,
  inklusive `GRANT OPTION` und `CASCADE`
- https://www.postgresql.org/docs/18/ddl-priv.html — Abschnitt 5.8: was `USAGE`
  auf einem Schema bedeutet, und Tabelle 5.2 (die Vorgaben für `PUBLIC`)
- https://www.postgresql.org/docs/18/sql-createschema.html — ein neues Schema
  und sein Eigentümer
- https://www.postgresql.org/docs/18/user-manag.html — Mitgliedschaft (21.3);
  davon hängt ab, wer `FOR ROLE …` überhaupt schreiben darf
- https://www.postgresql.org/docs/18/sql-createview.html — eine Frage, die
  später wiederkommt: mit wessen Rechten eine View ihre Basistabellen liest
- https://www.postgresql.org/docs/18/app-psql.html — `\ddp` (Vorgaberechte),
  `\dn+` (Schemata mit Eigentümer und ACL)
- https://www.postgresql.org/docs/18/catalogs.html — `pg_default_acl` und
  `pg_namespace`, wenn du filtern willst statt zu schauen

> **Zwei Umgebungen, dieselben Befehle — hier aber mit Folgen.** Der Kurs
> arbeitet auf PostgreSQL **19** (in der Doku: `/docs/19/…`), dieses Repo auf
> `postgres:18.6`, siehe [`compose.yaml`](../compose.yaml). Bei diesem Thema ist
> der Unterschied nicht bloß ein Name: **im Container dieses Repos gibt es die
> Rolle `postgres` nicht** (`POSTGRES_USER: kurs`), und `FOR ROLE postgres` ist
> keine Beschreibung, sondern ein Rollenname. Dort bricht die Zeile mit
> `role "postgres" does not exist` ab — nachsehen mit `\du`.

---

## 28.0 Das Schema gehört jemandem

Alles in diesem Teil hängt an einem Objekt, das man leicht überspringt: dem
**Schema**. Es ist nicht nur ein Ordner, es ist selbst ein Objekt mit Eigentümer
und Rechten (5.8) — und es ist der Punkt, an dem der Zugriff entschieden wird.

```sql
CREATE SCHEMA myapp;      -- braucht CREATE auf der Datenbank (Superuser: immer)
```

Wer ein Objekt anlegt, ist sein Eigentümer (5.8) — beim Schema also die Rolle,
die `CREATE SCHEMA` ausgeführt hat. Nachsehen:

```text
\dn+ myapp
```

Zwei Dinge sieht man dort, und beide sind für den Rest wichtig:

- **Owner** — wer Objekte darin anlegen darf. Den brauchst du, wenn du später
  `ALTER DEFAULT PRIVILEGES FOR ROLE …` schreibst (28.3) und wenn die Frage
  auftaucht, ob jemand „in `myapp` schreiben darf".
- **Access privileges** — und die ist bei einem frisch angelegten Schema **leer**.
  Das heißt nach 27.4 nicht „keine Rechte", sondern: es gelten die Vorgaben.
  Für `SCHEMA` sagt Tabelle 5.2: der Eigentümer hat `UC`, `PUBLIC` hat **nichts**.

`myapp` ist also von Anfang an zu — nicht weil jemand etwas verboten hätte,
sondern weil es nichts zu erlauben gab. Deshalb ist der erste Befehl aus deiner
Sitzung kein Detail, sondern der Türöffner.

**Aufgabe.** Leg `CREATE SCHEMA myapp;` an und sieh mit `\dn+ myapp` nach. Was
steht in der Spalte `Access privileges` — und was bedeutet das, wenn du daneben
die Vorgaben für `SCHEMA` aus Tabelle 5.2 hältst?

---

## 28.1 Der Pfad für die neue Rolle: `CONNECT` → `USAGE` → `SELECT`

Aus 24.3 und 27.5: um eine Tabelle zu lesen, braucht es Rechte auf **drei**
verschiedenen Objekten. Für eine frisch angelegte Rolle heißt das, in dieser
Reihenfolge:

```sql
GRANT CONNECT ON DATABASE kurs TO readonly;   -- 1. hinein in die Datenbank
GRANT USAGE   ON SCHEMA   myapp TO readonly;  -- 2. das Schema benutzen dürfen
GRANT SELECT  ON TABLE    …     TO readonly;  -- 3. die Tabelle lesen dürfen
```

Fehlt eine Stufe, kommt eine andere Meldung — und wer sie verwechselt, ändert
immer das Falsche (24.11, 28.9). Die erste Stufe fällt übrigens oft weg, weil
`PUBLIC` das `CONNECT` von Haus aus hat; sobald jemand es `PUBLIC` entzogen hat
(27.5), wird sie plötzlich wichtig.

---

## 28.2 `GRANT USAGE ON SCHEMA` — was „benutzen" genau heißt

`USAGE` auf einem Schema ist kleiner, als der Name klingt. 5.8 sagt, es „erlaubt
den Zugriff auf die Objekte im Schema" — mit Klammer: **(vorausgesetzt, die
Rechte der Objekte selbst sind auch da)**. Und dann der entscheidende Satz:

> … im Wesentlichen darf der Empfänger Objekte im Schema **nachschlagen**.

Nachschlagen, nicht lesen. Damit löst PostgreSQL den *Namen* `myapp.rechnung`
auf — ob du die Tabelle dann lesen darfst, ist eine zweite, unabhängige Frage
(`SELECT`). Zwei getrennte Rechte auf zwei getrennten Objekten, in derselben
Kette wie oben:

| Recht | Objekt | beantwortet |
|-------|--------|-------------|
| `USAGE` | Schema | „darf ich diesen Namen auflösen?" |
| `SELECT` | Tabelle | „darf ich diese Zeilen lesen?" |

Und das Gegenstück, das eine Read-only-Rolle **nicht** bekommen darf: `CREATE`
auf dem Schema. Damit dürfte sie eigene Objekte darin anlegen — „readonly" ist
nämlich kein Attribut, das die Rolle davor schützt (28.6).

```sql
GRANT  USAGE  ON SCHEMA myapp TO readonly;   -- Namen auflösen
-- und ausdrücklich nicht:
-- GRANT CREATE ON SCHEMA myapp TO readonly; -- eigene Objekte anlegen
```

Nachsehen: `has_schema_privilege('readonly', 'myapp', 'USAGE')`,
`has_table_privilege('readonly', 'myapp.rechnung', 'SELECT')` (5.8,
`functions-info.html`).

---

## 28.3 `ALTER DEFAULT PRIVILEGES` Zeile für Zeile

Jetzt der zweite Befehl aus deiner Sitzung, in seine vier Knöpfe zerlegt:

```sql
ALTER DEFAULT PRIVILEGES
    FOR ROLE postgres       -- (1) wessen Objekte?
    IN SCHEMA myapp         -- (2) wo?
    GRANT SELECT ON TABLES  -- (3) was genau?
    TO readonly;            -- (4) für wen?
```

Der Zweck in einem Satz, wörtlich aus der Doku: **„set the privileges that will
be applied to objects created in the future"** — und ausdrücklich: „It does not
affect privileges assigned to already-existing objects." Genau das ist die
Hälfte, die ein `GRANT` nicht kann.

### (1) `FOR ROLE` — wessen Objekte

Ohne den Zusatz gelten die Vorgaben für Objekte, die **du** anlegst. Mit
`FOR ROLE postgres` schreibst du sie für eine **andere** Rolle fest — schreiben
darfst du sie, wenn du diese Rolle *bist* oder **Mitglied** in ihr bist (21.3);
als Superuser sowieso. Deshalb funktioniert die Zeile in deiner Sitzung: du warst
`postgres`.

Und das ist der Satz, an dem man sich später die Zähne ausbeißt:

> Beim Anlegen eines Objekts zählen **nur die Vorgaberechte der aktuellen
> Rolle** — sie werden **nicht** von den Rollen geerbt, in denen die aktuelle
> Rolle Mitglied ist.

Heißt: legt eine Migration die Tabelle an, greift die Zeile nur dann, wenn die
Migration als **genau diese Rolle** läuft. Läuft sie als ein Mitglied von
`postgres`, greifen dessen Vorgaben — und die `readonly`-Zeile tut nichts. Die
Frage ist also nicht „wer darf", sondern **„wer legt die Tabellen wirklich an"**.

### (2) `IN SCHEMA` — wo

Ohne `IN SCHEMA` gilt die Vorgabe **global**, für alles in der Datenbank. Mit
`IN SCHEMA myapp` nur für Objekte, die in `myapp` entstehen. Zwei Regeln dazu
aus der Doku:

- Per-Schema-Vorgaben **kommen zu den globalen hinzu**: „Default privileges that
  are specified per-schema are added to whatever the global default privileges
  are." Zurücknehmen lässt sich per Schema deshalb nur, was per Schema gegeben
  wurde — „Per-schema `REVOKE` is only useful to reverse the effects of a
  previous per-schema `GRANT`."
- Bei `SCHEMAS` und `LARGE OBJECTS` ist `IN SCHEMA` **nicht erlaubt** — Schemata
  kann man nicht verschachteln, Large Objects gehören zu keinem Schema.

### (3) `ON TABLES` — was genau

Mehr als nur Tabellen gibt es nicht; die Liste ist kurz und geschlossen:

| Klassen | Rechte, die dort möglich sind |
|---------|-------------------------------|
| `ON TABLES` | `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER`, `MAINTAIN` — **inklusive Views und Foreign Tables** |
| `ON SEQUENCES` | `USAGE`, `SELECT`, `UPDATE` |
| `ON FUNCTIONS` / `ON ROUTINES` | `EXECUTE` (Aggregate und Prozeduren mitgezählt) |
| `ON TYPES` | `USAGE` (inklusive Domains) |
| `ON SCHEMAS` | `USAGE`, `CREATE` |
| `ON LARGE OBJECTS` | `SELECT`, `UPDATE` |

**Spalten sind nicht dabei.** Und Sequenzen sind eine eigene Zeile — die Falle
für jede schreibende Rolle (28.6).

### (4) `TO readonly` — für wen

Wie bei `GRANT`, `PUBLIC` und `WITH GRANT OPTION` eingeschlossen. `GRANT OPTION`
heißt hier: die Rolle darf die Rechte auf **künftigen** Objekten selbst
weitergeben (27.6).

---

## 28.4 Beide Hälften zusammen: das Rezept

```sql
CREATE SCHEMA IF NOT EXISTS myapp;

-- 1. die Tür
GRANT USAGE ON SCHEMA myapp TO readonly;

-- 2. die Tabellen, die es JETZT gibt (Momentaufnahme!)
GRANT SELECT ON ALL TABLES IN SCHEMA myapp TO readonly;

-- 3. die Tabellen, die KÜNFTIG entstehen (Vorlage)
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA myapp
    GRANT SELECT ON TABLES TO readonly;
```

Die Zeilen 2 und 3 sehen ähnlich aus und tun etwas völlig Verschiedenes: Zeile 2
geht die vorhandenen Objekte **durch** und vergibt jetzt; Zeile 3 schreibt **eine
Regel** auf, die beim nächsten `CREATE TABLE` angewendet wird. Wird eine Tabelle
zwischen zwei Läufen angelegt, ohne dass Zeile 3 schon stand, fällt sie durch
beide Netze — das ist die Lücke aus der Einleitung.

Nachsehen, dass Zeile 3 wirklich greift:

```sql
SET ROLE postgres;                   -- die Rolle aus (1)
CREATE TABLE myapp.probe (id int);
RESET ROLE;

\dp myapp.probe
```

Und jetzt der Rückschluss auf 27.4: die Spalte `Access privileges` ist bei
`myapp.probe` **nicht** leer, obwohl sie das nach dem `CREATE TABLE` gerade noch
war. 5.8 sagt warum: bei einem Objekt, dessen Rechte durch
`ALTER DEFAULT PRIVILEGES` beeinflusst wurden, steht die ACL immer ausgeschrieben
da. Die leere Spalte kommt nur bei den *eingebauten* Vorgaben zurück.

**Aufgabe.** Leg `myapp.probe` an, sieh mit `\dp` nach — und dann lass `readonly`
einmal `SET ROLE` machen und `SELECT * FROM myapp.probe;` ausführen. Erst
probieren, dann die Meldung lesen.

---

## 28.5 Nachsehen: `\ddp` und die Kataloge

Die Vorgaberechte sieht man **nirgends** in den normalen Ausgaben — `\dp` zeigt
Rechte auf Objekten, `\dn+` die Rechte auf dem Schema, aber nicht die Vorlage
für morgen:

```text
\ddp                 -- alle Vorgaberechte (mit Muster: \ddp readonly)
\dn+ myapp           -- Owner und ACL des Schemas
\dp                  -- Rechte auf Tabellen, Views, Sequenzen
```

Dieselbe Information aus dem Katalog, wenn du filtern willst:

```sql
-- das Schema selbst
SELECT nspname, pg_get_userbyid(nspowner) AS eigentuemer, nspacl
FROM pg_namespace
WHERE nspname = 'myapp';

-- die Vorgaberechte; defaclnamespace = 0 heißt "global"
SELECT pg_get_userbyid(defaclrole)             AS ersteller,
       NULLIF(defaclnamespace, 0)::regnamespace AS schema,
       defaclobjtype, defaclacl
FROM pg_default_acl;
```

`defaclobjtype` unterscheidet Tabellen, Sequenzen, Funktionen, Typen, Schemata
und Large Objects; die Buchstaben stehen in `catalogs.html` beim Katalog
`pg_default_acl`. Und die Frage aus der anderen Richtung, ohne ACL-Lesen:

```sql
SELECT has_schema_privilege('readonly', 'myapp', 'USAGE');
SELECT has_table_privilege('readonly', 'myapp.probe', 'SELECT');
```

---

## 28.6 Die Fallen

- **Sequenzen sind nicht mitgemeint.** `ON TABLES` deckt sie nicht ab, und
  `SERIAL`/`GENERATED`-Spalten sind Sequenzen. Für eine Rolle, die nur liest,
  ist das egal — für die Rolle, die schreibt, ist es der Klassiker: `INSERT`
  scheitert dann an einem fehlenden Recht auf der Sequenz, nicht an der Tabelle
  (24.6). Eigene Zeile: `ALTER DEFAULT PRIVILEGES … GRANT USAGE ON SEQUENCES …`.
- **Views sind mitgemeint** (`ON TABLES` schließt sie ein), aber mit wessen
  Rechten eine View ihre Basistabellen liest, ist eine eigene Frage — siehe
  `sql-createview.html`, Stichwort „privileges of the view owner". Nicht raten.
- **`FOR ROLE` beschreibt nicht, wer *darf*, sondern wer *anlegt*** (28.3).
  Wenn die Vorgabe nicht wirkt, ist meistens die Rolle bei (1) falsch.
- **`readonly` ist nur ein Name.** Die Rolle ist nicht „schreibgeschützt", sie
  hat nur bestimmte Rechte. Read-only ist die Summe aus: kein `CREATE` auf dem
  Schema, keine Schreibrechte auf den Tabellen, kein `INSERT`/`UPDATE`/`DELETE`.
- **Per Schema zurücknehmen, was global gegeben wurde, geht nicht** (28.3).
- **Die Vorgabe vererbt sich nicht** über Mitgliedschaft — sie hängt an der
  Rolle, die das Objekt anlegt.

---

## 28.7 Die andere Richtung: wer soll *nicht* hinein

Hier muss man nichts tun — ein neues Schema ist von Haus aus zu (28.0). Die
Frage ist eher, ob noch etwas offen steht:

- **`CONNECT`** auf der Datenbank: hat `PUBLIC` es noch (27.5) und soll es das?
- **`public`**: das Schema, in dem `PUBLIC` das `USAGE` hat (24.7). Wenn die
  Anwendung nur in `myapp` arbeiten soll, ist das die Stelle, an der ein Fremder
  trotzdem Objekte *sehen* kann.
- **`search_path`**: damit die App ohne Schema-Präfix arbeiten kann, muss `myapp`
  im Pfad stehen — und was das an Nebenwirkungen hat, steht in 24.7.

Zurücknehmen ist symmetrisch, auch bei den Vorgaben:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA myapp
    REVOKE SELECT ON TABLES FROM readonly;
```

---

## 28.8 `DROP ROLE` und die Vorgaberechte — die Verbindung zu Teil 27

Zum Schluss der Fall, der scheinbar aus dem Nichts kommt. Aus der Doku-Seite:

> If you wish to drop a role for which the default privileges have been altered,
> it is necessary to reverse the changes in its default privileges or use
> `DROP OWNED BY` to get rid of the default privileges entry for the role.

Ein `DROP ROLE`, das an einer Rolle hängt, die **nichts besitzt**, kann also hier
seinen Grund haben: die Vorgaberechte sind neben Eigentum, Rechten auf fremden
Objekten und Mitgliedschaften die vierte Art von Abhängigkeit (27.3). Die
`DETAIL`-Zeile nennt den Eintrag — lies sie, statt zu raten. Und `DROP OWNED BY`
räumt ihn mit weg.

---

## 28.9 Was schiefgeht

| Meldung | wahrscheinliche Ursache | wo nachsehen |
|---------|-------------------------|--------------|
| `permission denied for schema myapp` | `USAGE` auf dem Schema fehlt | `\dn+ myapp`, 28.2 |
| `permission denied for table …`, obwohl `USAGE` da ist | `SELECT` auf der Tabelle fehlt — `USAGE` ist nur das Nachschlagen | `\dp`, 28.2 |
| `permission denied for database kurs` | `CONNECT` fehlt (z. B. weil es `PUBLIC` entzogen wurde) | `\l`, 27.5 |
| die neue Tabelle ist wieder unlesbar | das `GRANT … ON ALL TABLES` war eine Momentaufnahme | `\ddp`, 28.4 |
| die Vorgabe steht da, wirkt aber nicht | `FOR ROLE` nennt nicht die Rolle, die die Tabellen **anlegt** | `\ddp`, 28.3 |
| `role "postgres" does not exist` | die Rolle aus `FOR ROLE` gibt es in dieser Umgebung nicht (Container: `kurs`) | `\du` |
| `DROP ROLE …` hängt, obwohl die Rolle nichts besitzt | Vorgaberechte oder Rechte auf fremden Objekten | `\ddp`, `DROP OWNED BY`, 28.8 |
| per-Schema-`REVOKE` wirkt nicht | global Gegrantetes lässt sich per Schema nicht zurücknehmen | 28.3 |
| `INSERT` scheitert, `SELECT` geht | die Sequenz ist eine eigene Zeile | 28.6 |

Zum Weiterlesen: wie man das alles **liest** — `\dt` gegen `\dp`, die
ACL-Zeichenkette, `WITH GRANT OPTION` — steht in
[Teil 27](27-eigentuemer-und-acl.md).
