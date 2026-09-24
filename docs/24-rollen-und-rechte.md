# 24 — Rollen und Rechte: wer darf was

„Wer bin ich?" war bisher nie eine Frage. In Teil 21 hat sich die Standby mit einer
Rolle verbunden, die `REPLICATION` durfte, in Teil 22 hat die Subscription dasselbe
getan — aber du selbst warst immer der Superuser, und damit hat alles geklappt.
Dieses Dokument dreht die Frage um: **Wer bist du überhaupt, und wo steht
geschrieben, was du darfst?**

Der Einstieg ist die Ausgabe, die man sich am schnellsten ansieht:

```text
\du           -- wer existiert
\h CREATE ROLE   -- was an einer Rolle überhaupt einstellbar ist
```

Die beiden gehören zusammen: `\du` sagt **wer**, `\h CREATE ROLE` sagt **was** — und
`pg_roles` (24.2) ist die Stelle, an der beides zusammenläuft.

Der rote Faden dieses Dokuments ist eine Trennung, die der Server selbst macht:

| Frage | wo die Antwort steht | Abschnitt |
|-------|---------------------|-----------|
| „Darf diese Rolle **hinein**?" | Rolle selbst (`LOGIN`, Passwort) **und** `pg_hba.conf` | 24.4 |
| „Darf diese Rolle **das hier** tun?" | Rechte am Objekt (`GRANT`) | 24.3 |

Eine Rolle kann hineindürfen und trotzdem nichts tun dürfen. Umgekehrt kann sie alle
Rechte haben und trotzdem nicht hineinkommen, weil die `pg_hba.conf` sie nicht lässt.
**Beide Fehlermeldungen sehen ähnlich aus und bedeuten etwas völlig Verschiedenes** —
wer sie verwechselt, sucht stundenlang an der falschen Stelle.

Die Doku-Kapitel, um die es geht:

- https://www.postgresql.org/docs/18/user-manag.html — das Kapitel „Database Roles"
  (Rollen, Attribute, Mitgliedschaft, vordefinierte Rollen)
- https://www.postgresql.org/docs/18/role-attributes.html — dieselben Attribute noch
  einmal in Prosa, mit Begründung
- https://www.postgresql.org/docs/18/sql-createrole.html und
  https://www.postgresql.org/docs/18/sql-createuser.html — die beiden Befehle
- https://www.postgresql.org/docs/18/ddl-priv.html — Rechte auf Objekten
  (im Handbuch auch als „Section 5.9" zitiert)
- https://www.postgresql.org/docs/18/sql-grant.html und
  https://www.postgresql.org/docs/18/sql-revoke.html — die beiden Befehle dazu
- https://www.postgresql.org/docs/18/predefined-roles.html — die fertigen Rollen
- https://www.postgresql.org/docs/18/auth-pg-hba-conf.html — `pg_hba.conf`, Zeile
  für Zeile
- https://www.postgresql.org/docs/18/ddl-rowsecurity.html — Row Level Security
  (Ausblick, 24.13)
- https://www.postgresql.org/docs/18/functions-info.html — `has_table_privilege`
  und Verwandte

> **Zwei Umgebungen, dieselben Befehle.** Der Kurs arbeitet auf PostgreSQL **19**
> (in der Doku: `/docs/19/…`), dieses Repo auf `postgres:18.6`, siehe
> [`compose.yaml`](../compose.yaml). Die Handgriffe sind identisch. Ein
> Unterschied ist für dieses Thema aber wichtig: **im Container dieses Repos ist
> `kurs` der Superuser** (`POSTGRES_USER: kurs`), in der Kursumgebung heißt er
> `postgres`. Wer dein Superuser ist, sagt `\du` — nicht dieses Dokument.

---

## 24.0 Ein Begriff statt zwei: Rolle

In PostgreSQL gibt es **kein „User"-Objekt neben der Rolle**. Es gibt nur `role`.
Was andere Systeme „Benutzer" nennen, ist eine Rolle mit einem bestimmten Attribut:

| was man anderswo so nennt | in PostgreSQL |
|---------------------------|---------------|
| Benutzer | Rolle mit `LOGIN` |
| Gruppe | Rolle **ohne** `LOGIN` |
| beides gleichzeitig | Rolle mit `LOGIN`, die Mitglieder hat |

Das ist keine Spitzfindigkeit, sondern die Erklärung für einen Befehl, den man
ständig sieht:

```sql
CREATE ROLE name;          -- kein LOGIN — anmelden kann sich damit niemand
CREATE USER name;          -- dasselbe, nur mit LOGIN
CREATE ROLE name LOGIN;    -- identisch zu CREATE USER name
```

**`CREATE USER` ist genau `CREATE ROLE` plus `LOGIN`.** Prüf das, statt es zu
glauben: vergleiche `\h CREATE USER` mit `\h CREATE ROLE` Zeile für Zeile und schau,
ob sich außer dieser einen Vorgabe überhaupt etwas unterscheidet.

---

## 24.1 Die Attribute aus `\h CREATE ROLE`, Zeile für Zeile

| Attribut (Vorgabe fett) | was es erlaubt | wer es vergeben darf |
|-------------------------|----------------|----------------------|
| `LOGIN` / **`NOLOGIN`** | sich überhaupt verbinden — der Unterschied „Benutzer" zu „Gruppe" | jeder, der die Rolle verwalten darf |
| **`NOSUPERUSER`** / `SUPERUSER` | alle Rechteprüfungen umgehen (wie `root`) | nur ein Superuser |
| **`NOCREATEDB`** / `CREATEDB` | eigene Datenbanken anlegen | jeder |
| **`NOCREATEROLE`** / `CREATEROLE` | weitere Rollen anlegen — **kein** Superuser-Ersatz (siehe unten) | jeder |
| **`INHERIT`** / `NOINHERIT` | Rechte der Rollen erben, in denen man Mitglied ist | jeder |
| **`NOREPLICATION`** / `REPLICATION` | physische Replikation starten — die Brücke zu Teil 21 | nur ein Superuser |
| **`NOBYPASSRLS`** / `BYPASSRLS` | jede Row-Level-Security-Richtlinie umgehen (24.13) | nur ein Superuser |
| **`CONNECTION LIMIT -1`** | wie viele Verbindungen gleichzeitig offen sein dürfen (`-1` = egal) | jeder |
| `[ENCRYPTED] PASSWORD '…'` / `PASSWORD NULL` | das Anmeldepasswort (24.4) | jeder |
| `VALID UNTIL '…'` | ab wann das Passwort **nicht mehr** gilt | jeder |
| `IN ROLE r` / `ROLE r` / `ADMIN r` | Mitgliedschaften schon beim Anlegen (24.5) | siehe 24.5 |
| `SYSID n` | Relikt aus Vor-8.1-Zeiten — in neuen Skripten hat es nichts zu suchen | — |

Vier Dinge, die man an dieser Tabelle leicht falsch liest:

- **`CREATEROLE` ist nicht die kleine Ausgabe von `SUPERUSER`.** Es erlaubt *nicht*,
  `SUPERUSER`- oder `REPLICATION`-Rollen zu erzeugen, und auch nicht,
  `BYPASSRLS` zu vergeben. In modernen Versionen darf ein `CREATEROLE`-Benutzer
  außerdem nur die Rollen verwalten, die er selbst angelegt hat (oder für die er
  ausdrücklich `ADMIN` bekommen hat). Genau diese Einschränkungen stehen im
  Abschnitt „role creation" von `role-attributes.html` — lies ihn im Original.
- **`REPLICATION` braucht `LOGIN` dazu.** Ein `REPLICATION`-Attribut auf einer
  `NOLOGIN`-Rolle ist wirkungslos.
- **Das Passwort ist nur die halbe Miete.** Ob es überhaupt abgefragt wird,
  entscheidet die `pg_hba.conf` (24.4). Steht dort `trust`, ist dein Passwort
  irrelevant — auch wenn `pg_roles.rolpassword` es schön gehasht anzeigt.
- **`\du` zeigt nur einen Teil der Spalten.** Passwort, Gültigkeitsdatum,
  Verbindungslimit und Mitgliedschaften sieht man erst mit `\du+` oder in `pg_roles`.

Nachträglich ist alles mit `ALTER ROLE` änderbar — die Attributnamen sind dieselben
(`ALTER ROLE name NOLOGIN;`, `ALTER ROLE name CONNECTION LIMIT 5;`). Nur `SYSID`
nicht, und das ist gut so.

---

## 24.2 Nachsehen: `\du`, `pg_roles`, `pg_auth_members`

Bevor du etwas anlegst, sieh dir an, was da ist. Erst die Kurzform, dann die
Langform:

```sql
\du              -- Übersicht: Rolle + Attribute
\du+             -- zusätzlich Beschreibung und Mitgliedschaften
\du postgres     -- dasselbe, auf eine Rolle eingeschränkt
```

```sql
SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolinherit,
       rolcanlogin, rolreplication, rolbypassrls, rolconnlimit, rolvaliduntil
FROM pg_roles
ORDER BY rolname;
```

Und die Mitgliedschaften stehen **nicht** in `pg_roles`, sondern in einer eigenen
Sicht. Sieh dir an, welche Spalten sie hat, statt dir Spaltennamen zu merken:

```sql
\d pg_auth_members
SELECT * FROM pg_auth_members;
```

Dieselbe Auskunft gibt es als `psql`-Kurzform — sie ist die bequemere der beiden:

```text
\drg           -- "List of role grants": Role name, Member of, Options, Grantor
```

> `\drg` nicht mit `\drds` verwechseln (24.10): das eine endet auf **g** wie
> *grants*, das andere auf **s** wie *settings*. Die Namen sehen ähnlich aus und
> haben nichts miteinander zu tun. Und wenn dein `psql` einen der beiden nicht
> kennt: `\?` listet die Befehle **deiner** Version.

> In neueren Versionen trägt `pg_auth_members` nicht mehr nur `admin_option`,
> sondern zusätzlich `inherit_option` und `set_option` — genau die drei
> Schalter aus `GRANT` (24.5). Deine Spaltenliste sagt dir, welche Version du
> vor dir hast.

Die Frage, die sich beim ersten `\du` sofort aufdrängt: **welche Attribute stehen
beim Superuser deiner Installation, und warum war `Replication` davon für Teil 21
notwendig?** Trag deine `pg_roles`-Ausgabe in
[`06-kurs-notizen.md`](06-kurs-notizen.md) ein.

---

## 24.3 Rechte am Objekt: `GRANT` und `REVOKE`

Eine eben angelegte Rolle ist **nicht** „fast wie der Superuser, nur ein bisschen
kleiner". Sie darf zunächst einmal fast nichts. Die Rechte werden einzeln vergeben,
und zwar auf jeder Ebene des Objektpfads:

| Objekt | Recht | wofür |
|--------|-------|-------|
| `DATABASE` | `CONNECT` | hineinkommen |
| | `CREATE` | im Schema `public` Objekte anlegen |
| | `TEMP` / `TEMPORARY` | temporäre Tabellen anlegen |
| `SCHEMA` | `USAGE` | die Objekte darin überhaupt **sehen/benutzen** |
| | `CREATE` | Objekte darin anlegen |
| `TABLE` | `SELECT`, `INSERT`, `UPDATE`, `DELETE` | lesen und schreiben |
| | `TRUNCATE`, `REFERENCES`, `TRIGGER` | seltener gebraucht |
| | `MAINTAIN` | `VACUUM`, `ANALYZE`, `REINDEX`, … (Teil 11/13) |
| `SEQUENCE` | `USAGE` | `nextval()` — **nicht** in den Tabellenrechten enthalten! |
| `FUNCTION` / `PROCEDURE` | `EXECUTE` | aufrufen |
| `TYPE`, `DOMAIN`, `LANGUAGE` | `USAGE` | verwenden |

Der wichtigste Punkt steht in der ersten Spalte: **um eine Tabelle zu lesen,
braucht es drei Rechte auf drei verschiedenen Objekten** — `CONNECT` auf der
Datenbank, `USAGE` auf dem Schema, `SELECT` auf der Tabelle. Fehlt eines,
kommt eine andere Meldung. Genau daran lernt man, was die Meldungen bedeuten.

Voraussetzung ist wie in Teil 23 die Tabelle `konto` (falls sie fehlt:
`CREATE TABLE konto (id int, betrag numeric);`). Erst eine Rolle, dann der Versuch:

```sql
CREATE ROLE sepp LOGIN PASSWORD 'geheim';

-- von hier an ist "du" nicht mehr der Superuser, sondern sepp:
SET ROLE sepp;

SELECT count(*) FROM konto;
-- ERROR: permission denied for table konto

SELECT count(*) FROM pg_roles;    -- Systemkataloge sind die Ausnahme: erlaubt
```

Jetzt Stück für Stück freigeben — am besten mit `SET ROLE` hin und her, um zu sehen,
welches Recht welche Meldung verschwinden lässt:

```sql
RESET ROLE;                        -- zurück zum Superuser

GRANT CONNECT ON DATABASE kurs TO sepp;
GRANT USAGE   ON SCHEMA  public TO sepp;
GRANT SELECT  ON TABLE   konto  TO sepp;

SET ROLE sepp;
SELECT count(*) FROM konto;        -- jetzt erlaubt
INSERT INTO konto VALUES (1, 1);
-- ERROR: permission denied for table konto
RESET ROLE;
```

Massenweise statt einzeln, wenn ein Schema viele Tabellen hat:

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO sepp;
```

Und das Zurücknehmen ist symmetrisch:

```sql
REVOKE SELECT ON TABLE konto FROM sepp;
```

Zwei Dinge, die man dabei lernt und leicht übersieht:

- **Der Eigentümer braucht keine Rechte.** Wer ein Objekt anlegt, darf es von
  selbst aus — `GRANT` ist nur für alle *anderen*. Deshalb funktioniert
  `GRANT` bei dir als Superuser oft „einfach so" und später nicht mehr.
- **Rechte sind additiv.** Was über `PUBLIC`, über eine Rolle und über eine
  Mitgliedschaft gewährt wird, addiert sich. `REVOKE` an einer Stelle nimmt
  nichts weg, was an einer anderen Stelle gewährt wurde (24.7).

Zum Nachsehen, wer auf was sitzt, gibt es die `psql`-Kurzformen — die zeigen
dieselbe Information wie `information_schema`, nur lesbarer:

```sql
\dp konto        -- Rechte auf Tabellen (auch: \z)
\dn+             -- Schemata mit ihren Rechten
\l+              -- Datenbanken mit ihren Rechten
\df+             -- Funktionen
```

---

## 24.4 Hineinkommen: Passwort, `pg_hba.conf`, `CONNECTION LIMIT`

Jetzt der Teil, der nichts mit `GRANT` zu tun hat und trotzdem am häufigsten
schiefgeht. Eine Verbindung wird in **zwei** Schritten geprüft: die Client-
Authentifizierung (`pg_hba.conf`) und danach die Rechte aus 24.3. Erst nachsehen,
dann ändern — dieselbe Regel wie in Teil 14:

```sql
SHOW hba_file;              -- wo die Datei liegt
SHOW password_encryption;   -- womit das Passwort beim Setzen gehasht wird
```

Die `pg_hba.conf` ist eine Liste von Zeilen, von oben nach unten gelesen; die
**erste passende** Zeile entscheidet, alle weiteren werden ignoriert. Vier Spalten,
mehr nicht:

```ini
# TYPE   DATABASE  USER     ADDRESS       METHOD
local    all       all                    trust
host     all       all      127.0.0.1/32  trust
```

Lies deine eigene Datei an der Stelle, die `SHOW hba_file;` nennt, und beantworte
dir selbst:

- Welche Methode steht in der ersten `local`-Zeile — `trust`, `peer`, `scram-sha-256`?
- Würde eine Rolle mit `PASSWORD 'geheim'` auf deiner Installation also **mit** oder
  **ohne** Passwort hineinkommen?

Die Methoden, um die es geht:

| Methode | was sie prüft |
|---------|---------------|
| `trust` | nichts — **jeder**, der die Zeile erreicht, kommt hinein |
| `peer` | den Betriebssystem-Benutzer gegen den Rollennamen (nur über Socket) |
| `scram-sha-256` | das Passwort, salted+gehasht (die moderne Vorgabe) |
| `md5` | das Passwort, schwächer gehasht (Altbestand) |
| `reject` | immer nein |

Zwei Konsequenzen, die man einmal erlebt haben muss:

- Eine Änderung an der `pg_hba.conf` braucht **keinen** Neustart, sondern nur
  `SELECT pg_reload_conf();` — sie wird bei jeder Verbindung neu gelesen.
- Eine `trust`-Zeile weiter oben **entwertet** jede Passwortregel weiter unten.
  Die Datei ist eine Liste, keine Sammlung — deshalb ist die Reihenfolge Teil der
  Konfiguration, nicht Kosmetik.

Und die Verbindung selbst nachsehen (dieselben zwei Funktionen wie in Teil 21):

```sql
\conninfo                    -- Host, Port, Datenbank, Rolle
SELECT current_user, session_user;
```

`CONNECTION LIMIT` schließlich ist das einzige Attribut aus 24.1, das man
**messen** kann: Verbindungen zählen, nicht Abfragen. Setze es klein und öffne
mehr Sitzungen, als erlaubt sind:

```sql
ALTER ROLE sepp CONNECTION LIMIT 2;
SELECT rolname, rolconnlimit FROM pg_roles WHERE rolname = 'sepp';
SELECT usename, count(*) FROM pg_stat_activity GROUP BY usename ORDER BY 2 DESC;
```

Was der Server bei der dritten Verbindung sagt, und ob es im Log steht oder nur auf
der Client-Seite — das ist eine deiner Notizen. Nebenbei: die Grenze gilt **pro
Rolle über alle Datenbanken**, nicht pro Datenbank.

---

## 24.5 Gruppen: Mitgliedschaft, `INHERIT`, `SET ROLE`

Bisher hat jede Rolle ihre Rechte einzeln. Das skaliert nicht — deshalb ist die
zweite Hälfte von `GRANT` die **Mitgliedschaft**:

```sql
-- sepp hat sein SELECT bisher einzeln bekommen (24.3). Das skaliert nicht:
REVOKE SELECT ON TABLE konto FROM sepp;

CREATE ROLE accounting NOLOGIN;           -- eine "Gruppe": nur ein Container für Rechte
GRANT SELECT ON ALL TABLES IN SCHEMA public TO accounting;

GRANT accounting TO sepp;                 -- sepp wird Mitglied

SET ROLE sepp;
SELECT count(*) FROM konto;               -- funktioniert, ohne dass sepp ein GRANT bekam
RESET ROLE;
```

Genau hier fällt der Groschen: **Rechte werden nicht an Personen vergeben, sondern
an Rollen, und Personen werden Mitglied.** Wer eine Kollegin hat, gibt ihr
Mitgliedschaft, statt zwölf `GRANT`-Zeilen zu tippen.

Drei Schalter gehören zu jeder Mitgliedschaft — sie stehen in `GRANT` und in
`pg_auth_members` (24.2):

| Schalter | Vorgabe | Bedeutung |
|----------|---------|-----------|
| `INHERIT` | die des Mitglieds | Rechte der Rolle **automatisch** mitbenutzen |
| `SET` | `TRUE` | mit `SET ROLE` in die Rolle **hineinschlüpfen** dürfen |
| `ADMIN` | `FALSE` | die Mitgliedschaft **weitergeben** dürfen |

Die drei stehen als Spalten in `\drg` (24.2) — und **was dort nicht steht, ist
nicht gesetzt**: hat eine Zeile nur `INHERIT, SET`, kann das Mitglied die
Mitgliedschaft nicht weitergeben.

`INHERIT` ist der Unterschied zwischen zwei sehr verschiedenen Dingen, und beides
ist nützlich:

```sql
GRANT accounting TO sepp WITH INHERIT FALSE;

SET ROLE sepp;
SELECT count(*) FROM konto;               -- geht nicht: Mitgliedschaft wird nicht geerbt
SET ROLE accounting;                      -- geht weiterhin: SET ist davon nicht betroffen
SELECT count(*) FROM konto;               -- jetzt erlaubt — "ich" bin jetzt accounting
RESET ROLE;

GRANT accounting TO sepp WITH INHERIT TRUE;   -- zurück zur Vorgabe
```

`INHERIT FALSE` heißt also nicht „darf nicht", sondern „**muss es bewusst
einschalten**": die Rechte sind da, man nimmt die Rolle nur nicht automatisch an.
Dasselbe bewirkt das Rollenattribut `NOINHERIT` (24.1) — es ist der Vorgabewert für
*alle* Mitgliedschaften dieser Rolle, während `WITH INHERIT TRUE/FALSE` **eine
einzelne** Mitgliedschaft überstimmt.

Und `SET ROLE` ist dabei dein Werkzeug beim Testen: du bleibst der Superuser
in der Sitzung, siehst aber die Welt wie die Rolle. `RESET ROLE` bringt dich zurück.

Der Zusammenhang zu 24.3: Objekte, die einer Rolle gehören, kann man nicht per
`GRANT` öffnen — man wird Mitglied der Rolle, der sie gehören. Deshalb steht in der
`GRANT`-Doku der Satz, dass die Rechte des Eigentümers nicht vergebbar sind.

---

## 24.6 Eigentümer und Vorgaberechte: `OWNER`, `ALTER DEFAULT PRIVILEGES`

Jedes Objekt hat einen **Eigentümer**, und der ist mächtiger als jedes `GRANT`:
er darf das Objekt ändern und löschen, und das ist kein vergebbares Recht.
`OWNER` steht auch in der Ausgabe von `\dp`.

```sql
ALTER TABLE konto OWNER TO accounting;    -- Eigentum übertragen
```

Und die Falle, die daraus folgt: `GRANT SELECT ON ALL TABLES …` gilt nur für
Tabellen, die **jetzt** existieren. Legt jemand später eine Tabelle an, hat die
Gruppe wieder nichts. Dagegen sind die **Vorgaberechte** da:

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO accounting;
```

Zwei Feinheiten, die in der Doku (und in jedem echten Vorfall) wichtig sind:

- `ALTER DEFAULT PRIVILEGES` gilt für Objekte, die **du** in Zukunft anlegst —
  nicht für die, die ein anderer anlegt. Deshalb gibt es die Variante
  `ALTER DEFAULT PRIVILEGES FOR ROLE <name> …`.
- Sequenzen sind **nicht** mitgemeint, auch nicht bei `ALL TABLES` und nicht bei
  `SERIAL`-Spalten. Sequenzrechte werden getrennt vergeben (24.3).

---

## 24.7 `PUBLIC` und die Vorgaben des Servers

`PUBLIC` ist keine Rolle, sondern der Sammelbegriff für **alle Rollen** — auch für
die, die es noch nicht gibt. Was `PUBLIC` hat, hat jeder. Deshalb ist die
interessante Frage nicht „wer hat es", sondern „**was hat `PUBLIC` von Haus aus?**"
Da hilft die Gegenprobe: vergib einer neuen Rolle nichts und sieh, was trotzdem geht.

Beim Anlegen einer Datenbank vergibt PostgreSQL einige Rechte an `PUBLIC` — sonst
könnte niemand hinein. Sie stehen in der Vorlage `template1` und vererben sich an
jede neue Datenbank. Nachsehen kannst du das in einer frisch angelegten Datenbank:

```sql
-- in einer neuen Datenbank:
\dp
\dn+ public
```

Seit PostgreSQL 15 ist dabei **eine** Vorgabe weggefallen, die die älteren
Handbücher und Tutorials noch durchgehend annehmen: `PUBLIC` hat auf dem Schema
`public` nur noch `USAGE`, **kein `CREATE` mehr**. Das Schema `public` gehört jetzt
`pg_database_owner`. Wenn ein altes Skript „mal eben eine Tabelle in `public`
anlegen" will und mit `permission denied for schema public` abbricht, ist das der
Grund — und nicht die Rolle.

Was man an dieser Stelle **probieren sollte, weil es weh tut, wenn man es
aus Versehen tut** (und weil es die Auswirkung von `PUBLIC` zeigt):

```sql
REVOKE ALL ON DATABASE kurs FROM PUBLIC;
```

Danach kommt keine Rolle mehr hinein, die nicht ausdrücklich `CONNECT` bekommen
hat. Mit `GRANT CONNECT ON DATABASE kurs TO PUBLIC;` ist es wieder wie vorher — aber
gemerkt hat man es jetzt.

Dazu gehört `search_path`, weil er bestimmt, *welches* Objekt mit einem Namen
gemeint ist: steht dort ein Schema, in dem die Rolle schreiben darf, kann sie dort
auch Objekte mit gleichem Namen anlegen. Die Absicherung dazu heißt, ein Schema
erst gar nicht ins `search_path` zu nehmen — mehr dazu in „Function Security"
(`user-manag.html`, letzter Abschnitt).

---

## 24.8 Vordefinierte Rollen statt vieler Einzelrechte

Viele Rechte-Kombinationen braucht man ständig. Dafür liefert PostgreSQL fertige
Rollen mit — man wird einfach Mitglied:

```sql
GRANT pg_monitor TO sepp;
```

| Rolle | wofür (Auszug) |
|-------|----------------|
| `pg_monitor` | Überwachen: enthält die drei folgenden Rollen |
| `pg_read_all_settings` | **alle** Einstellungen lesen, auch die sonst unsichtbaren |
| `pg_read_all_stats` | alle `pg_stat_*`-Sichten lesen |
| `pg_stat_scan_tables` | Überwachungsfunktionen, die Tabellen sperren können |
| `pg_read_all_data` / `pg_write_all_data` | alle Daten lesen / schreiben (ohne RLS-Umgehung) |
| `pg_signal_backend` | fremde Sitzungen abbrechen/beenden |
| `pg_signal_autovacuum_worker` | Autovacuum-Worker abbrechen (Teil 13) |
| `pg_checkpoint` | `CHECKPOINT` (Teil 23) |
| `pg_maintain` | `VACUUM`, `ANALYZE`, `CLUSTER`, `REINDEX`, … (ab 17; ab 19 auch `REPACK`, Teil 15) |
| `pg_create_subscription` | `CREATE SUBSCRIPTION` (Teil 22) |
| `pg_read_server_files` / `pg_write_server_files` / `pg_execute_server_program` | Dateien und Programme **auf dem Server** — gefährlich, siehe Warnung in der Doku |
| `pg_use_reserved_connections` | reservierte Verbindungsplätze nutzen |
| `pg_database_owner` | Sonderfall: immer der aktuelle Datenbank-Eigentümer, nicht vergebbar |

Zur `pg_database_owner` gehört der Satz, der 24.7 erklärt: **diese Rolle besitzt das
Schema `public`** — deshalb hat jeder Datenbank-Eigentümer die Hoheit darüber und
`PUBLIC` nicht mehr.

Zur Liste selbst: sie wächst mit jeder Version. Die verbindliche Liste steht in
`predefined-roles.html`, nicht hier — deshalb sind in der Tabelle die
Versionsangaben dort, wo sie sich unterscheiden.

---

## 24.9 Die `REPLICATION`-Rolle: die Brücke zu Teil 21 und 22

Jetzt schließt sich der Kreis zum Standby. In Teil 21 hat sich die zweite Instanz
mit `-U kurs` verbunden — das hat nur funktioniert, weil diese Rolle das Attribut
`REPLICATION` hatte und `LOGIN` dazu (24.1). Eine Rolle ohne `REPLICATION` bekommt
genau hier ihre Fehlermeldung.

Beides gehört zusammen — Rolle **und** Zeile in der `pg_hba.conf`:

```sql
CREATE ROLE standby LOGIN REPLICATION PASSWORD 'geheim';
```

```ini
# TYPE         DATABASE   USER       ADDRESS       METHOD
host           replication  standby    127.0.0.1/32  scram-sha-256
```

Drei Beobachtungen, die den Zusammenhang erklären:

- Eine **physische** Replikationsverbindung (Teil 21) verbindet sich **nicht mit
  einer Datenbank** — deshalb gibt es die eigene Zeilenart `replication`.
- Eine **Subscription** (Teil 22) verbindet sich dagegen mit einer *Datenbank* auf
  der Quelle. Dafür greifen die normalen `host`/`local`-Zeilen, und die Rolle
  braucht die Rechte aus 24.3 — plus `pg_create_subscription`, wenn sie die
  Subscription anlegen soll.
- Nach dem Start ist die Verbindung sichtbar wie in 21.3 — nur diesmal weißt du,
  **warum** die Rolle drinsteht: `SELECT * FROM pg_stat_replication;` auf der
  Primary.

Und die Gegenprobe: `ALTER ROLE standby NOREPLICATION;` bei laufender Standby. Was
passiert beim nächsten Verbindungsversuch, und wo steht es — im Log der Standby
oder in dem der Primary? (Teil 21.8 hat die Antwort für die verwandte Frage.)

---

## 24.10 Rollenspezifische Einstellungen: `ALTER ROLE … SET`

`ALTER ROLE` kann mehr als Attribute: es kann **Einstellungen** setzen, die für
diese Rolle bei jeder neuen Verbindung gelten. Das ist die Brücke zu Teil 14 und 23:

```sql
ALTER ROLE sepp SET synchronous_commit = off;
ALTER ROLE sepp SET statement_timeout = '2s';
```

Danach braucht die Rolle es nicht mehr selbst zu setzen — es wirkt, als hätte sie es
beim Verbinden getan. Nachsehen mit einem Befehl, den man leicht vergisst:

```text
\drds           -- alle datenbank- und rollenspezifischen Einstellungen
```

Und zurücknehmen:

```sql
ALTER ROLE sepp RESET ALL;
```

Der Merksatz aus der Doku: für Rollen **ohne** `LOGIN` ist das sinnlos — sie
verbinden sich ja nie.

---

## 24.11 Was beim Anlegen und Aufräumen schiefgeht

| Symptom | wahrscheinliche Ursache | wo nachsehen |
|---------|-------------------------|--------------|
| `permission denied for table …` | es fehlt das `GRANT` auf **dieser** Tabelle | `\dp tabelle`, 24.3 |
| `permission denied for schema public` | `USAGE` (oder vor 15: `CREATE`) auf dem Schema fehlt | `\dn+`, 24.7 |
| `permission denied for database kurs` | `CONNECT` auf der Datenbank fehlt | `\l+`, 24.3 |
| `role "…" does not exist` beim Anmelden | die Rolle gibt es nicht — oder sie wurde in einer **anderen** Datenbank/Cluster angelegt als du denkst | `\du`, `\conninfo` |
| Passwort wird abgefragt, obwohl keins gesetzt ist | die `pg_hba`-Methode verlangt eines (`md5`/`scram`), gesetzt ist `PASSWORD NULL` | `SHOW hba_file;` + Datei, 24.4 |
| Passwort wird **nicht** abgefragt, obwohl eins gesetzt ist | eine `trust`-Zeile steht **weiter oben** und passt schon | dieselbe Datei, **von oben nach unten** lesen |
| Anmeldung plötzlich unmöglich nach `VALID UNTIL` | Ablaufdatum erreicht | `pg_roles.rolvaliduntil`, 24.2 |
| `must be superuser to create superusers` | `CREATEROLE` ≠ `SUPERUSER` | 24.1 |
| `permission denied to set role "…"` | die Mitgliedschaft hat `SET FALSE` | `\drg`, `pg_auth_members`, 24.5 |
| neue Tabelle für die Gruppe wieder unlesbar | `GRANT` gilt nur für vorhandene Objekte | `ALTER DEFAULT PRIVILEGES`, 24.6 |
| `cannot execute … in a read-only transaction` | du bist auf der **Standby** (Teil 21) — das ist kein Rechteproblem | `pg_is_in_recovery()`, 21.4 |

Der Merksatz über der Tabelle: **zwei Meldungen, zwei Baustellen.** „permission
denied" ist die Ebene `GRANT` (24.3), alles rund um Anmelden, Passwort und
`pg_hba` ist die Ebene Authentifizierung (24.4). Wer die beiden vermischt, ändert
immer das Falsche.

---

## 24.12 Aufräumen

Rollen lassen sich nur löschen, wenn sie **nichts** besitzen und niemand mehr
Mitglied ist. Deshalb räumt man in dieser Reihenfolge auf — erst die Objekte, dann
die Rolle:

```sql
DROP OWNED BY sepp;              -- in JEDER Datenbank, in der sepp etwas besitzt
DROP ROLE sepp;
```

`DROP OWNED` löscht die Objekte. Will man sie behalten und nur den Eigentümer
wechseln, ist es `REASSIGN OWNED`:

```sql
REASSIGN OWNED BY sepp TO kurs;   -- statt kurs: dein Superuser aus \du
DROP ROLE sepp;
```

Zwei Fallen dabei:

- **Beide Befehle wirken nur in der Datenbank, in der du sie ausführst.** Gibt es
  mehrere Datenbanken mit Objekten dieser Rolle, muss der Befehl in jeder laufen —
  sonst bleibt `DROP ROLE` mit einem Verweis auf das erste abhängige Objekt stehen.
  Dieselbe Meldung führt dich dann zur nächsten Datenbank.
- Die Mitgliedschaften muss man nicht von Hand entfernen: `DROP ROLE` erledigt das
  mit. Was bleibt, ist `DROP OWNED` beziehungsweise `REASSIGN OWNED`.

Und die Rollen aus den Beispielen dieses Dokuments, falls du sie nicht behalten
willst:

```sql
DROP OWNED BY sepp;       DROP ROLE sepp;
DROP OWNED BY accounting; DROP ROLE accounting;
```

Zum Schluss der Blick, mit dem dieses Dokument angefangen hat — es sollte wieder
nach einem aufgeräumten Server aussehen:

```sql
\du
```

---

## 24.13 Ausblick: Row Level Security

Das `BYPASSRLS` aus deiner ersten `\du`-Ausgabe gehört zu einem Thema, das
**innerhalb** der Tabelle greift, nicht an ihrer Grenze: **Row Level Security**.
Statt „darf diese Rolle die Tabelle lesen?" fragt man dort „darf sie **diese
Zeilen** sehen?" — jede Rolle sieht nur ihre eigenen Daten, in derselben Tabelle.

Die Befehle, um die es gehen wird:

```sql
ALTER TABLE konto ENABLE ROW LEVEL SECURITY;
CREATE POLICY eigene_zeilen ON konto
    USING (konto_inhaber = current_user);
```

Drei Sätze als Vorwarnung, damit die Erwartung stimmt — die drei Stolpersteine des
Themas:

- **Der Eigentümer umgeht seine eigenen Richtlinien** (24.6), solange kein
  `FORCE ROW LEVEL SECURITY` auf der Tabelle steht.
- `BYPASSRLS` umgeht **alle** Richtlinien — das ist ein Attribut wie `SUPERUSER`,
  nicht eine Ausnahme für eine Tabelle.
- Die vordefinierten Sammelrollen (`pg_read_all_data`, 24.8) umgehen RLS gerade
  **nicht** — dafür gibt es den ausdrücklichen Hinweis in `predefined-roles.html`.

Das ist ein eigener Teil, nicht ein Abschnitt dieses hier. Der Zweck des Ausblicks
ist nur: **wenn dir `BYPASSRLS` später begegnet, weißt du schon, wozu.**

---

## Was in `06-kurs-notizen.md` gehört

- `\du` und `\du+` auf **deiner** Installation: welche Attribute stehen beim
  Superuser, und was zeigen die beiden Varianten unterschiedlich?
- `\h CREATE USER` gegen `\h CREATE ROLE` — welche Zeile(n) unterscheiden sich?
- `SHOW password_encryption;` — welcher Wert, und wie sieht ein damit gesetztes
  Passwort in `pg_roles.rolpassword` aus (Anfang genügt: welches Verfahren)?
- `SELECT * FROM pg_auth_members;` — welche Spalten hat die Sicht bei dir?
- Die `pg_hba.conf`, die `SHOW hba_file;` nennt: welche Methode steht in der ersten
  `local`-Zeile, und welche Rolle hätte ohne Passwort hineingekommen?
- Die Meldungen **wörtlich** notieren — welche kommt beim Verbinden, welche beim
  `SELECT`? Sie sind der einzige Weg, die beiden Ebenen auseinanderzuhalten.
- `CONNECTION LIMIT` auf einen kleinen Wert gesetzt: was steht auf der Client-Seite
  und was im Log des Servers?
- Was zeigt `\drds`, nachdem mit `ALTER ROLE … SET` gearbeitet wurde?
- Was sagt `DROP ROLE` genau, wenn die Rolle im aktuellen Datenbankkontext noch
  Objekte besitzt — und in welcher Reihenfolge arbeitest du dich dann durch?
