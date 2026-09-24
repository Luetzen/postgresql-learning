# 27 — Eigentümer, ACL und `GRANT OPTION`

In Teil 24 ging es darum, **wer** was darf: Rollen, Attribute, `GRANT`, `pg_hba.conf`.
Drei Dinge sind dabei aufgefallen und dort offen geblieben:

1. `\dt` hat eine Spalte `Owner` — und die lässt sich nicht per `GRANT` vergeben.
2. `DROP ROLE sepp;` bricht ab, weil an der Rolle ein Objekt hängt.
3. In `\l` steht eine Spalte `Access privileges`, in der Zeichenketten wie
   `=c/postgres` oder `accounting=c/postgres` stehen.

Alle drei sind dasselbe Thema von verschiedenen Seiten: **jedes Objekt hat einen
Eigentümer und eine Liste von Rechten (die „ACL")**, und beides wird an
unterschiedlichen Stellen angezeigt — und läuft nach unterschiedlichen Regeln.

| Frage | wo die Antwort steht | Abschnitt |
|-------|---------------------|-----------|
| „Wem **gehört** das Objekt?" | Spalte `Owner` in `\dt` und `\l`, `pg_class.relowner`, `pg_database.datdba` | 27.1 |
| „Wer **darf was** damit tun?" | Spalte `Access privileges` in `\dp`, `\l`, `\dn+`; `relacl`, `datacl` | 27.4 |
| „Wie werde ich das Eigentum wieder los?" | `ALTER … OWNER TO` | 27.2 |
| „Warum hängt die Rolle an ihrem Objekt fest?" | `REASSIGN OWNED`, `DROP OWNED` | 27.3 |

Der ganze Durchlauf als Skript zum Abschreiben: [`sql/07_rechte.sql`](../sql/07_rechte.sql)
— es legt zwei Rollen und eine Übungstabelle an, geht die Abschnitte in dieser
Reihenfolge durch und räumt am Ende wieder auf. Die Abschnitte unten erklären,
*warum* jeder Schritt dort steht.

Die Doku-Kapitel, um die es geht:

- https://www.postgresql.org/docs/18/ddl-priv.html — Abschnitt 5.8, „Privileges":
  **die eine Seite, auf der alles aus diesem Dokument steht.** Die Besitz-Regel,
  Tabelle 5.1 (die Buchstaben der ACL) und Tabelle 5.2 (Vorgaben für `PUBLIC`)
  sind von dort.
- https://www.postgresql.org/docs/18/role-removal.html — Abschnitt 21.4,
  „Dropping Roles": erklärt die Meldung aus 27.3 und liefert das Rezept dagegen
- https://www.postgresql.org/docs/18/sql-altertable.html und
  https://www.postgresql.org/docs/18/sql-alterdatabase.html — die `OWNER TO`-Klauseln
- https://www.postgresql.org/docs/18/sql-grant.html und
  https://www.postgresql.org/docs/18/sql-revoke.html — `WITH GRANT OPTION`,
  `REVOKE GRANT OPTION FOR`, `CASCADE`
- https://www.postgresql.org/docs/18/sql-reassign-owned.html und
  https://www.postgresql.org/docs/18/sql-drop-owned.html — die beiden Aufräumbefehle
- https://www.postgresql.org/docs/18/user-manag.html — Mitgliedschaft (21.3),
  aus der das „geerbte" Eigentum kommt (27.8)
- https://www.postgresql.org/docs/18/app-psql.html — `\dp`/`\z`, `\l`, `\dn+`,
  `\dT+`, `\df+`; die Seite verweist für die Bedeutung der Anzeige
  ausdrücklich auf Abschnitt 5.8

> **Zwei Umgebungen, dieselben Befehle.** Der Kurs arbeitet auf PostgreSQL **19**
> (in der Doku: `/docs/19/…`), dieses Repo auf `postgres:18.6`, siehe
> [`compose.yaml`](../compose.yaml). Die Handgriffe sind identisch. Ein
> Unterschied ist für dieses Thema wichtig: **im Container dieses Repos ist
> `kurs` der Superuser** (`POSTGRES_USER: kurs`), in der Kursumgebung heißt er
> `postgres`. Wer dein Superuser ist, sagt `\du` — nicht dieses Dokument. Ein
> Superuser ist bei allem in diesem Dokument die Abkürzung: er darf jedes
> `ALTER … OWNER TO`, jedes `GRANT` und jedes `DROP ROLE`, unabhängig von
> Eigentum und Mitgliedschaft. Was du hier lernst, siehst du also erst, wenn du
> `SET ROLE` benutzt oder dich als Nicht-Superuser anmeldest.

---

## 27.0 Eigentum ist kein Recht

Der Satz, an dem sich alles aufhängt, steht in 5.8 und ist kurz:

> Das Recht, ein Objekt zu ändern oder zu zerstören, steckt **im Eigentum** und
> ist selbst **nicht** vergebbar und nicht wieder zurücknehmbar. (Wörtlich: „The right to modify
> or destroy an object is inherent in being the object's owner, and cannot be
> granted or revoked in itself.")

| | Eigentümer | Rechte (ACL) |
|---|-----------|--------------|
| wer | genau **eine** Rolle | beliebig viele Rollen, `PUBLIC` eingeschlossen |
| was | das Objekt ändern, löschen, weitergeben, Rechte daran vergeben | genau die aufgezählten Tätigkeiten (`SELECT`, `CONNECT`, …) |
| vergebbar? | **nein** — nur übertragbar (27.2) | ja, `GRANT`/`REVOKE` |
| wo sichtbar | Spalte `Owner`, `relowner`/`datdba` | Spalte `Access privileges`, `relacl`/`datacl` |
| wer es kann | der Eigentümer, Mitglieder seiner Rolle, Superuser | wer es bekommen hat |

Zwei Folgen, die die drei Beobachtungen von oben erklären:

- **In keiner ACL-Zeichenkette wirst du einen Eintrag für `ALTER` oder `DROP`
  finden.** Die ACL listet nur Rechte **für andere**. Ein `GRANT` kann einem
  Kollegen also nie das geben, was ein Eigentümer hat.
- **Solange eine Rolle ein Objekt besitzt, ist sie ein Teil des Objekts.** Genau
  deshalb scheitert `DROP ROLE` (27.3) — und genau deshalb ist es keine gute
  Idee, Objekte Personen zu geben (27.8).

Und die Ausnahme, die alles rettet, steht im selben Absatz, in der Klammer:
Eigentum ist **nicht** als Recht vergebbar, aber es ist „wie alle Rechte" von den
**Mitgliedern der Eigentümerrolle erbbar** (21.3). Das ist der Grund, warum
Gruppen als Eigentümer funktionieren — und der Grund, warum du als Superuser
davon nichts merkst, solange du nichts ausprobierst.

---

## 27.1 Nachsehen: wo der Eigentümer steht

Die `psql`-Kurzformen trennen die beiden Dinge sauber, und man greift
regelmäßig zur falschen:

| Befehl | zeigt | Rechte? |
|--------|-------|---------|
| `\dt` | Tabellen: Schema, Name, Typ, **Eigentümer** | nein |
| `\dt+` | zusätzlich Größe, Persistenz, Beschreibung | nein |
| `\dp` (auch `\z`) | Tabellen, Views, Sequenzen mit **`Access privileges`** | ja |
| `\l` | Datenbanken: Eigentümer **und** `Access privileges` | ja |
| `\dn+` | Schemata: Eigentümer, `Access privileges`, Beschreibung | ja |
| `\dT+`, `\dD+`, `\df+`, `\dL+` | Typen, Domains, Funktionen, Sprachen — jeweils mit Eigentümer/Rechten | ja |

`\dt` beantwortet also nur die erste Frage. Wer in `\dt` nach Rechten sucht,
findet sie nie. Tabelle 5.2 im Handbuch stellt genau diese Paare nebeneinander —
pro Objekttyp die passende `psql`-Kurzform.

Dieselbe Information aus den Katalogen, wenn du sie filtern oder zählen willst:

```sql
-- Tabellen im Schema public mit ihrem Eigentümer
SELECT c.relname, pg_get_userbyid(c.relowner) AS eigentuemer
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY c.relname;

-- Datenbanken mit Eigentümer und ACL  (datacl ist die Spalte aus \l)
SELECT datname, pg_get_userbyid(datdba) AS eigentuemer, datacl
FROM pg_database
ORDER BY datname;
```

(`relkind = 'r'` sind die gewöhnlichen Tabellen. Die anderen Werte — `'p'` für
partitionierte, `'v'` für Views, `'S'` für Sequenzen — stehen in
`pg_class.relkind`.)

Die `pgbench_*`-Tabellen, die in deiner `\dt`-Ausgabe stehen, sind übrigens
nichts Besonderes: sie kommen aus `pgbench -i` (Teil 18) und gehören dem, der sie
angelegt hat.

**Aufgabe.** Nimm eine Tabelle aus deiner `\dt`-Ausgabe und sieh sie dir zweimal
an — einmal mit `\dt tabelle`, einmal mit `\dp tabelle`. Beantworte dann diese
Frage, bevor du weiterliest: *Was genau* steht in der einen Ausgabe, was in der
anderen — und warum ist in `\dt` keine einzige der Rollen aus `\dp` zu sehen?

---

## 27.2 Eigentum übertragen: `ALTER … OWNER TO`

Eigentum wechselt man mit der `ALTER`-Form des jeweiligen Objekttyps; der Satz
ist überall derselbe:

```sql
ALTER TABLE    waltest  OWNER TO accounting;
ALTER DATABASE kurs     OWNER TO accounting;
ALTER SCHEMA   reports  OWNER TO accounting;
```

Wer das darf, steht in 5.8 — und die Regel ist zweiteilig:

- **Superuser:** immer.
- **Gewöhnliche Rolle:** nur wenn sie **beides** ist — aktueller Eigentümer des
  Objekts (oder erbt dessen Rechte) **und** in der Lage, `SET ROLE` auf die neue
  Eigentümerrolle zu machen (also Mitglied ist).

Genau das war deine Beobachtung „dafür braucht man hohe Rechte": wer auf eine
Rolle übertragen will, in der er **nicht** Mitglied ist, braucht Superuser. Prüf
es, statt es zu glauben — `\du dein_name` und `\drg dein_name` sagen dir, ob du
Mitglied bist, und der Versuch sagt den Rest.

Zwei Sätze aus 5.8, die man leicht überliest:

- **„Alle Objektrechte des alten Eigentümers gehen mit dem Eigentum auf den neuen
  über."** Eigentum ist also kein zweites Konto, das man getrennt pflegt; es
  hängt zusammen.
- Der Eigentümer **kann sich selbst** Rechte nehmen (eine Tabelle für sich selbst
  nur lesbar machen), „aber Eigentümer werden immer so behandelt, als hätten sie
  alle Grant-Optionen" — er holt sie sich jederzeit zurück (27.6).

**Aufgabe.** Beobachte vor und nach einem `ALTER TABLE … OWNER TO` die Ausgabe
von `\dp` und `\l`: Was passiert mit den Rechten, die **andere** Rollen auf dem
Objekt haben? Und was passiert mit der `DETAIL`-Meldung aus 27.3, wenn du danach
`DROP ROLE` versuchst?

---

## 27.3 Die Folge: `DROP ROLE` bleibt an Objekten hängen

In deiner Sitzung sah das so aus:

```text
kurs=# DROP ROLE sepp;
ERROR:  role "sepp" cannot be dropped because some objects depend on it
DETAIL:  owner of table waltest
```

Das ist keine Fehlfunktion, sondern die Kurzfassung von Absatz eins in 21.4:
weil Rollen Objekte besitzen und Rechte halten können, ist `DROP ROLE` oft „nicht
einfach eine schnelle Sache". Erst muss alles neu zugeordnet oder gelöscht
werden. Die Meldung ist extra so gebaut, dass sie dir das Objekt **nennt** —
„it will issue messages identifying which objects need to be reassigned or
dropped" (21.4).

Das allgemeine Rezept steht dort wörtlich:

```sql
REASSIGN OWNED BY doomed_role TO successor_role;
DROP OWNED BY doomed_role;
-- repeat the above commands in each database of the cluster
DROP ROLE doomed_role;
```

Drei Dinge daran sind die eigentliche Information:

- **Die Reihenfolge ist Absicht.** `REASSIGN OWNED` überträgt das Eigentum,
  lässt aber Rechte auf *fremden* Objekten in Ruhe; `DROP OWNED` nimmt genau
  die weg („it also takes care of removing any privileges granted to the target
  role for objects that do not belong to it"). Du brauchst in der Regel **beide**,
  in dieser Reihenfolge.
- **Beide Befehle wirken nur in der Datenbank, in der du sie ausführst.** Deshalb
  die Zeile mit dem Kommentar in der Mitte: bei mehreren Datenbanken muss das
  Rezept mehrfach laufen. Die `DETAIL`-Zeile kennt nur die Objekte der
  **aktuellen** Datenbank — dieselbe Meldung führt dich dann zur nächsten.
- **Die Ausnahme:** der *erste* `REASSIGN OWNED` nimmt auch die
  datenbankübergreifenden Objekte mit, also **Datenbanken und Tablespaces**, die
  der Rolle gehören. Die kann `DROP OWNED` nicht anfassen und muss man von Hand
  behandeln.

Was `DROP ROLE` dagegen **nicht** stört: die Mitgliedschaften. Die räumt es selbst
mit weg (24.12). Hängen bleibt nur, was in `pg_shdepend` steht — Eigentum und
Rechte.

Und der Satz, der das ganze Kapitel in die Kurs-Ökonomie einordnet: **Das muss
man nicht auswendig wissen, man muss nur die `DETAIL`-Zeile lesen.** Sie sagt dir,
was zu tun ist; 21.4 sagt dir, wie.

---

## 27.4 Die ACL-Zeichenkette lesen

Jetzt die Zeichenketten aus `\l`. Ihre Grammatik steht in 5.8, und sie ist
kleiner, als sie aussieht:

```text
grantee=rechte/grantor
```

- **Links vom `=` steht der Empfänger** (`grantee`), also *wer* das Recht hat.
- **Ist das Feld leer, ist der Empfänger `PUBLIC`** — also alle Rollen, auch die,
  die es noch nicht gibt. Wörtlich: „An empty grantee field in an `aclitem`
  stands for `PUBLIC`." Deshalb fängt eine Zeile wie `=c/postgres` mit dem `=` an:
  das ist kein fehlender Wert, sondern die wichtigste Zeile der ganzen Ausgabe.
- **Rechts vom `/` steht der `grantor`**, also **wer** das Recht vergeben hat —
  nicht automatisch der Eigentümer. Dieselbe Rolle kann mehrfach auftauchen, wenn
  mehrere Geber im Spiel waren: „each `aclitem` lists all the permissions of one
  grantee that have been granted by a particular grantor".
- **Ein `*` hinter einem Buchstaben heißt `WITH GRANT OPTION`** (27.6), also „darf
  weitergegeben werden". Es ist der **Stern**, nicht Groß- oder Kleinschreibung —
  die Buchstaben haben in ihrer Schreibweise selbst keine Bedeutung.

Die Buchstaben sind Tabelle 5.1 („ACL Privilege Abbreviations"):

| Buchstabe | Recht | gilt für |
|-----------|-------|----------|
| `r` | `SELECT` | Tabelle, Spalte, Sequenz, Large Object |
| `a` | `INSERT` | Tabelle, Spalte |
| `w` | `UPDATE` | Tabelle, Spalte, Sequenz, Large Object |
| `d` | `DELETE` | Tabelle |
| `D` | `TRUNCATE` | Tabelle |
| `x` | `REFERENCES` | Tabelle, Spalte |
| `t` | `TRIGGER` | Tabelle |
| `m` | `MAINTAIN` | Tabelle |
| `C` | `CREATE` | Datenbank, Schema, Tablespace |
| `c` | `CONNECT` | Datenbank |
| `T` | `TEMPORARY` | Datenbank |
| `X` | `EXECUTE` | Funktion, Prozedur |
| `U` | `USAGE` | Schema, Sequenz, Typ, Domain, Sprache, FDW, Foreign Server |
| `s` | `SET` | Parameter |
| `A` | `ALTER SYSTEM` | Parameter |

Und Tabelle 5.2 beantwortet die Frage, die sich sofort stellt, wenn die Spalte mal
leer ist — „was gilt denn dann?":

| Objekttyp | alle Rechte | Vorgabe für `PUBLIC` | nachsehen mit |
|-----------|-------------|----------------------|---------------|
| `DATABASE` | `CTc` | **`Tc`** | `\l` |
| `SCHEMA` | `UC` | keine | `\dn+` |
| `TABLE` | `arwdDxtm` | keine | `\dp` |
| `SEQUENCE` | `rwU` | keine | `\dp` |
| `FUNCTION`/`PROCEDURE` | `X` | **`X`** | `\df+` |
| `TYPE`, `DOMAIN` | `U` | **`U`** | `\dT+`, `\dD+` |
| `LANGUAGE` | `U` | **`U`** | `\dL+` |
| `TABLESPACE` | `C` | keine | `\db+` |
| `PARAMETER` | `sA` | keine | `\dconfig+` |

Damit stimmt der Verdacht aus deinen Notizen — und es ist genau die Stelle, an
der die Anzeige täuscht:

> Ist die Spalte `Access privileges` **leer**, hat das Objekt die
> **Vorgaberechte**; der Eintrag im Katalog ist `NULL`. (5.8)

Es steht dort nicht „nichts", sondern „die Vorgaben". Und die Vorgaben sind für
`DATABASE` eben **nicht** leer: `PUBLIC` darf `T` und `c`. Wer die leere Spalte
für „keine Rechte" hält, sucht an der falschen Stelle.

Zwei Feinheiten aus 5.8, die man dort leicht überliest:

- **Das erste `GRANT` oder `REVOKE` auf einem Objekt friert die Vorgaben ein.**
  Wörtlich: „The first `GRANT` or `REVOKE` on an object will instantiate the
  default privileges … and then modify them per the specified request." Ab dann
  steht die ACL ausgeschrieben im Katalog — und die **leere Spalte kommt durch
  `GRANT`/`REVOKE` nicht zurück**, auch wenn die Rechte wieder dieselben sind.
- **`(none)` ist etwas anderes als leer.** Leer = Vorgaben. `(none)` = der
  Katalogeintrag ist gesetzt, aber die Liste ist leer — dem Objekt wurden also
  wirklich *alle* Rechte genommen, auch die des Eigentümers, der sie aber
  jederzeit zurückholen kann (27.6).

Und die Zeile, die beim Rechnen mit `*` wichtig wird: **die stillschweigenden
Grant-Optionen des Eigentümers stehen nicht in der Anzeige** — „a `*` will appear
only when grant options have been explicitly granted to someone."

Nachsehen statt glauben:

```sql
-- dieselbe Zeichenkette, ungefiltert, aus dem Katalog
SELECT datname, datacl FROM pg_database ORDER BY datname;
SELECT relname, relacl FROM pg_class WHERE relname = 'konto';

-- als Spalten: eine Zeile je Recht, mit is_grantable = das '*'
SELECT grantor, grantee, privilege_type, is_grantable
FROM aclexplode((SELECT datacl FROM pg_database
                 WHERE datname = current_database()));

-- die eingebauten Vorgaben selbst ausgeben — das ist genau das, was eine
-- leere Spalte in \l bedeutet ('d' steht für DATABASE)
SELECT acldefault('d', (SELECT datdba FROM pg_database
                         WHERE datname = current_database()));

-- die Frage aus der anderen Richtung, ohne ACL-Lesen
SELECT has_database_privilege('sepp', current_database(), 'CONNECT');
SELECT has_table_privilege('sepp', 'konto', 'SELECT');
```

`aclexplode()` und `acldefault()` stehen in `functions-info.html` („Access
Privilege Inquiry Functions") zusammen mit `has_database_privilege()` und
Verwandten; dort steht auch, welcher Buchstabe bei `acldefault()` welcher
Objektart entspricht. `aclexplode()` gibt OIDs zurück, keine Namen —
`pg_get_userbyid()` hilft beim Auflösen, und die `grantee`-OID `0` ist `PUBLIC`;
das siehst du sofort, wenn du die Ausgabe gegen die Zeichenkette aus `\l` hältst.

Ergänzend: `\h GRANT` und `\h REVOKE`.

---

## 27.5 Die drei Datenbankrechte und der Objektpfad

Auf einer `DATABASE` gibt es genau drei Rechte — mehr kann `GRANT … ON DATABASE`
nicht, siehe die Spalte „alle Rechte" in der Tabelle oben (`CTc`):

| Recht | was es erlaubt (5.8) |
|-------|----------------------|
| `CREATE` | neue **Schemata und Publications** in der Datenbank anlegen; vertrauenswürdige Erweiterungen installieren |
| `CONNECT` | sich überhaupt verbinden — **geprüft beim Verbindungsaufbau**, zusätzlich zur `pg_hba.conf` |
| `TEMPORARY` | temporäre Tabellen in dieser Datenbank anlegen |

Das `CONNECT` ist dabei nicht das Gegenstück zur `pg_hba.conf`, sondern eine
**zweite** Hürde danach (der Objektpfad aus 24.3): `CONNECT` auf der Datenbank,
`USAGE` auf dem Schema, `SELECT` auf der Tabelle — drei Objekte, drei Rechte,
kein Durchreichen.

Und jetzt das Experiment aus deiner Sitzung, Schritt für Schritt, mit der
Erklärung daneben:

```sql
\l kurs   -- Spalte "Access privileges" ist LEER -> das sind die Vorgaben: PUBLIC hat Tc
REVOKE CONNECT ON DATABASE kurs FROM PUBLIC;
\l kurs   -- ab jetzt steht dort ein Eintrag, der mit "=" beginnt (PUBLIC), und
          -- in ihm fehlt das "c" für CONNECT
GRANT CONNECT ON DATABASE kurs TO accounting;
\l kurs   -- zusätzlich steht accounting da, mit "c" und mit dem Geber nach dem "/"
```

Drei Konsequenzen, die aus der Doku folgen und die man nicht erraten muss:

- **Laufende Sitzungen fliegen nicht raus.** `CONNECT` wird „at connection
  startup" geprüft. Wer schon drin ist, bleibt drin — die Wirkung siehst du erst
  beim **nächsten** Verbindungsversuch. Das ist der Grund, warum man sich bei
  `REVOKE ALL ON DATABASE … FROM PUBLIC` (24.7) eine zweite Sitzung offen lässt:
  die alte verdeckt das Problem, die neue zeigt es.
- **`PUBLIC` betrifft auch Rollen, die es noch nicht gibt.** Jede neu angelegte
  Rolle kommt ohne `CONNECT` nicht mehr hinein — bis du es ausdrücklich vergibst.
- **Der Zustand davor kommt nicht zurück.** Nach dem ersten `REVOKE` ist die ACL
  explizit („instantiate the default privileges"). Ein `GRANT CONNECT … TO PUBLIC`
  stellt das *Verhalten* wieder her, aber die Spalte bleibt gefüllt — das
  `NULL` im Katalog holt nur ein direkter Katalogschreibvorgang zurück, und den
  macht man nicht.

**Aufgabe.** Vergleiche die Zeile in `\l` vor dem `REVOKE` und danach und benenne
die drei Teile (`grantee`, Rechte, `grantor`). Frage dann: wer ist in deinem Fall
der `grantor` — und warum steht dort der Superuser und nicht der Eigentümer der
Datenbank?

---

## 27.6 `WITH GRANT OPTION`: weitergeben dürfen

Ein Recht weitergeben zu dürfen, ist ein **eigenes** Zugeständnis:

```sql
GRANT  SELECT ON konto TO accounting WITH GRANT OPTION;      -- darf selbst weitergeben
REVOKE GRANT OPTION FOR SELECT ON konto FROM accounting;     -- nur die Weitergabe weg
REVOKE SELECT ON konto FROM accounting;                      -- das Recht selbst weg
```

In der ACL ist es der `*` (27.4). Die beiden Regeln, die dieses Thema
ausmachen, stehen wörtlich in 5.8:

- „…it is possible to grant a privilege *with grant option*, which gives the
  recipient the right to grant it in turn to others."
- „If the grant option is subsequently revoked then all who received the privilege
  from that recipient (directly or through a chain of grants) will lose the
  privilege." — **es wirkt durch die ganze Kette.** Wurde das Recht bereits
  weitergegeben, verlangt `REVOKE` ein `CASCADE` (oder bricht ab).

Und der Satz, der erklärt, warum man den `*` in `\l` so selten sieht:
**Eigentümer werden immer so behandelt, als hätten sie alle Grant-Optionen**, aber
„the owner's implicit grant options are not marked in the access privileges
display". Der Eigentümer braucht also kein `WITH GRANT OPTION` — er hat es
ohnehin, nur unsichtbar.

Zu deinem Einwand aus den Notizen („wird wohl nirgends verwendet, weil man später
nicht mehr weiß, wer welche Rechte hat") die präzise Fassung: **wer** vergeben
hat, steht sehr wohl in der ACL — das ist genau der `grantor` rechts vom `/`.
Was fehlt, ist eine Übersicht über alle Objekte hinweg: die Kette sieht man immer
nur *pro Objekt*. Und der eigentliche Preis ist das `CASCADE`: ein `REVOKE` an
einer Stelle nimmt Rechte weg, die jemand anderes weitergegeben hat. Das ist ein
Grund, es sparsam zu vergeben — eine Regel ist es nicht.

**Aufgabe.** Vergib einer Rolle `SELECT … WITH GRANT OPTION`, lass sie das Recht
weitergeben (dafür braucht sie `LOGIN` oder `SET ROLE`) und sieh dir dann das
`REL`-Konto der Kette in `\dp` an. Nimm anschließend nur die Grant-Option
zurück — und schau, was mit dem weitergegebenen Recht passiert.

---

## 27.7 Kein Durchreichen nach unten — aber Addition über Rollen

Zwei Sätze aus deinen Notizen, die beide stimmen, aber nicht dasselbe meinen:

- **„Es gibt keine Rechte-Vererbung."** Richtig — über die **Objektgrenzen**:
  aus `CONNECT` auf der Datenbank folgt kein `SELECT` auf der Tabelle, aus
  `USAGE` auf dem Schema kein Recht in der Tabelle. Es gibt kein „Ordner"-Recht,
  das nach unten durchreicht (24.3). Und zwei Dinge, die *wie* eine Vererbung
  aussehen, aber keine sind: `GRANT … ON ALL TABLES IN SCHEMA …` ist eine
  **Momentaufnahme** (nur die jetzt existierenden Objekte, 24.6), und
  `ALTER DEFAULT PRIVILEGES` ist eine **Vorlage**, die beim `CREATE` angewendet
  wird — keine Regel auf einem Elternobjekt.
- **„Jedes Objekt bekommt sein eigenes."** Richtig — und zugleich ist die ACL
  **additiv**: was über `PUBLIC`, über eigene Grants und über Rollen-
  Mitgliedschaften zusammenkommt, addiert sich (24.3). Ein `REVOKE` an einer
  Stelle nimmt nichts weg, was an einer anderen Stelle gewährt wurde.

Die Vererbung, die es gibt, läuft also entlang der **Rollen**, nicht entlang der
Objekte — `INHERIT` plus Mitgliedschaft (24.5) — und mit einer Besonderheit:
auch das **Eigentum** wird von den Mitgliedern der Eigentümerrolle geerbt (27.0).
Das ist der Hebel für den nächsten Abschnitt.

---

## 27.8 Gruppen als Eigentümer: die Antwort auf das `sepp`-Problem

Aus 27.0 bis 27.3 folgt eine Faustregel, die in keinem `GRANT` steht und doch alles
einfacher macht:

> **Objekte gehören Rollen ohne `LOGIN`. Personen sind nur Mitglieder.**

```sql
CREATE ROLE accounting NOLOGIN;          -- die "Gruppe"
GRANT accounting TO sepp;                -- sepp ist Mitglied (INHERIT ist Vorgabe)

ALTER TABLE waltest OWNER TO accounting; -- nicht "sepp", sondern die Gruppe
```

Was das ändert:

- `\dt` zeigt als `Owner` jetzt `accounting`. **`sepp` kommt in der Spalte gar
  nicht mehr vor** — und damit auch nicht in `pg_shdepend`.
- `sepp` darf die Tabelle trotzdem ändern und löschen: als Mitglied der
  Eigentümerrolle erbt er das Eigentumsrecht (27.0). Mit `SET ROLE accounting`
  ist er sogar wörtlich der Eigentümer.
- **`DROP ROLE sepp` funktioniert jetzt ohne jedes `REASSIGN OWNED`** — es gibt
  nichts, was an ihm hängt. Geht jemand, nimmst du nur die Mitgliedschaft weg.
- Geht die **Gruppe** weg, brauchst du das Rezept aus 27.3 genau einmal — und
  nicht einmal je Person.

Der Server erzwingt diese Regel nicht: nichts hindert eine `LOGIN`-Rolle daran,
Eigentümer zu sein — du siehst es nur in der Spalte `Owner`. Und das Muster hat
PostgreSQL selbst eingebaut: das Schema `public` gehört der Rolle
`pg_database_owner`, in die sich niemand einloggt (24.7). Das ist genau dieselbe
Idee, nur vom System vorgemacht.

Für Objekte, die künftig entstehen, kommt `ALTER DEFAULT PRIVILEGES` dazu (24.6)
— es regelt **Rechte**, nicht Eigentum: neue Tabellen gehören weiterhin dem, der
sie anlegt.

**Aufgabe.** Entscheide für `konto` (oder eine Tabelle deiner Wahl), wer sie in
Zukunft besitzen soll — und begründe es, bevor du das `ALTER … OWNER TO`
absetzt. Schau danach mit `\dt` und `\dp` nach, ob das, was du erwartest, auch
dasteht.

---

## 27.9 Was schiefgeht

| Meldung | wahrscheinliche Ursache | wo nachsehen |
|---------|-------------------------|--------------|
| `role "…" cannot be dropped because some objects depend on it` + `DETAIL: owner of table …` | die Rolle besitzt noch Objekte | `REASSIGN OWNED` / `DROP OWNED`, 27.3 |
| dieselbe Meldung, aber `DETAIL: privileges for table …` | sie *besitzt* nichts, sie *hält* nur Rechte auf fremden Objekten | `DROP OWNED` (räumt beides), 27.3 |
| dieselbe Meldung nach dem Aufräumen wieder | es gibt noch eine **andere Datenbank** mit Objekten dieser Rolle | `\l`, dann dort wiederholen, 27.3 |
| `must be owner of table …` | du bist nicht Eigentümer und nicht Mitglied der Eigentümerrolle | `\dt`, `\dp`, 27.1 |
| beim `ALTER … OWNER TO` fehlt die Berechtigung | du kannst nicht `SET ROLE` auf die neue Eigentümerrolle — kein Superuser, keine Mitgliedschaft | `\drg`, 27.2 |
| `Access privileges` ist leer und du hältst es für „keine Rechte" | es sind die **Vorgaberechte** (Katalogeintrag `NULL`), für `DATABASE` also `Tc` | 27.4, Tabelle 5.2 |
| nach `REVOKE … FROM PUBLIC` „kommt keiner mehr rein", deine eigene Sitzung aber schon | `CONNECT` wird beim Verbindungsaufbau geprüft, nicht laufend | 27.5, zweite Sitzung öffnen |
| ein `REVOKE` bricht ab, obwohl die Rolle das Recht hat | es wurde mit `WITH GRANT OPTION` weitergegeben — es fehlt `CASCADE` | 27.6 |

---

## 27.10 Aufräumen

Die Reihenfolge aus 21.4, mit den Rollen dieses Dokuments — **in jeder Datenbank**,
in der `sepp` etwas besessen hat:

```sql
\c kurs                       -- und dann für jede weitere Datenbank: \c name

REASSIGN OWNED BY sepp TO accounting;   -- Eigentum übertragen …
DROP OWNED    BY sepp;                  -- … dann Rechte auf fremden Objekten weg
DROP ROLE sepp;
```

Hast du `PUBLIC` das `CONNECT` genommen, stell es wieder her — mit dem
Unterschied aus 27.5, dass die Spalte danach gefüllt bleibt:

```sql
GRANT CONNECT ON DATABASE kurs TO PUBLIC;
\l kurs
```

Und der Blick, mit dem dieses Dokument angefangen hat — die beiden Fragen an
derselben Tabelle, plus die Rollenliste:

```text
\du
\dt
\dp
\l
```

Rollen aufräumen, die nichts besitzen: 24.12.

---

## 27.11 Ausblick: wo Eigentum noch auftaucht

Der Eigentümer verschwindet nicht, wenn man ihn einmal verstanden hat — er taucht
an drei Stellen wieder auf, die später drankommen:

- **`SECURITY DEFINER`-Funktionen** laufen mit den Rechten ihres **Eigentümers**,
  nicht des Aufrufers. Eigentum ist dort kein Ordnungsproblem, sondern die
  Sicherheitsgrenze — das ist der letzte Abschnitt von `user-manag.html`
  („Function Security"), den 24.7 schon erwähnt.
- **Row Level Security** (24.13): der Eigentümer umgeht seine eigenen
  Richtlinien, solange kein `FORCE ROW LEVEL SECURITY` gesetzt ist. Auch dort ist
  „Eigentümer" die Sonderrolle, nicht „Superuser".
- **Erweiterungen und ihre Objekte** (`\dx+`) hängen an dem, der
  `CREATE EXTENSION` ausgeführt hat — dieselbe Frage noch einmal, nur ohne
  `ALTER … OWNER TO`.
