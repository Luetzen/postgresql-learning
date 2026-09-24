# 25 — Verbindungen von außen: `listen_addresses`, Port, `pg_hba.conf`

In Teil 2 war eine Verbindung ein `docker compose exec db psql` — also *auf* der
Maschine, auf der der Server läuft. In Teil 21 und 24 kamen „Host"-Zeilen in der
`pg_hba.conf` schon vor, aber nur als Nebensatz. Hier kommt ein **zweiter Rechner**
dazu: ein Client, der über das Netz auf den Server zugreift.

Zwischen „ich tippe `psql -h …`" und „ich bin drin" liegen **drei Tore**, und jedes
hat eine eigene Meldung. Das ist der ganze Inhalt dieses Dokuments:

| Tor | wer es schließt | was der Client dann sagt | steht es im **Server**-Log? |
|-----|-----------------|--------------------------|------------------------------|
| 1. der Weg | Firewall, Routing, Portfreigabe | Zeitüberschreitung oder „connection refused" | **nein** — der Server hat nie davon gehört |
| 2. der Zuhörer | `listen_addresses`, `port` in `postgresql.conf` | „connection refused" | nein |
| 3. die `pg_hba.conf` | Server, bei **jeder** Verbindung neu gelesen | „no pg_hba.conf entry …", „password authentication failed" | **ja** |
| danach | Rechte am Objekt (`GRANT`, Teil 24) | „permission denied for table …" | nein |

Die letzte Spalte ist der wichtigste Satz dieses Dokuments: **nur Tor 3 hinterlässt
eine Spur auf dem Server.** Wenn im Log nichts steht, hast du bei Tor 1 oder 2
gesucht — und umgekehrt ist eine Zeile im Log ein Beweis, dass Tor 1 und 2 offen
sind.

Die Doku-Kapitel, um die es geht:

- https://www.postgresql.org/docs/18/runtime-config-connection.html —
  `listen_addresses`, `port`
- https://www.postgresql.org/docs/18/auth-pg-hba-conf.html — die `pg_hba.conf`
  (dieselbe Seite wie in 24.4, hier unter dem Netz-Aspekt)
- https://www.postgresql.org/docs/18/client-authentication.html — Überblick
  Authentifizierung, inklusive `sslmode` auf der Client-Seite
- https://www.postgresql.org/docs/18/app-psql.html — `psql`-Aufruf, `\conninfo`
- https://www.postgresql.org/docs/18/libpq-connect.html — die Verbindungsparameter
  (`host`, `port`, `sslmode`, `passfile`) und die Umgebungsvariablen
- https://www.postgresql.org/docs/18/app-pg-isready.html — das Werkzeug, das Tor 1
  und 2 von Tor 3 trennt
- https://www.postgresql.org/docs/18/runtime-config-logging.html —
  `log_connections`, `log_line_prefix`: was der Server über Verbindungen schreibt
- https://www.postgresql.org/docs/18/monitoring-stats.html — `pg_stat_activity`

> **Zwei Umgebungen, dieselben Befehle.** Der Kurs arbeitet auf PostgreSQL **19**
> (in der Doku: `/docs/19/…`), dieses Repo auf `postgres:18.6`, siehe
> [`compose.yaml`](../compose.yaml). Ein Handgriff ist hier **nicht** identisch:
> Im Container gibt es keine LAN-Adresse, die man freischalten könnte — dort ist
> der Weg nach außen die Portveröffentlichung in `compose.yaml` (25.8). Der Rest
> ist derselbe.
>
> In den Befehlen unten steht `kurs-00` für den **Server** und `<client>` für den
> **Client**. Deine eigenen Namen verrät der Shell-Prompt (`user@host`) — setz sie
> dort ein, wo sie stehen.

---

## 25.0 Die Reihenfolge, in der man sucht

Die drei Tore werden **von außen nach innen** geprüft, und man kann sie nicht
überspringen. Ein beliebter Fehler ist, mit der `pg_hba.conf` anzufangen — die
sieht man ja im `SHOW hba_file;`, sie ist also „greifbar". Nur nützt die schönste
`pg_hba`-Zeile nichts, wenn Tor 2 geschlossen ist und der Server auf der Adresse
gar nicht lauscht.

Die Prüfreihenfolge ist deshalb:

1. **Ist der Server erreichbar?** (Tor 1 und 2 zusammen, mit einem Werkzeug, das
   sich **nicht** anmeldet: `pg_isready`, 25.2)
2. **Wie kommt die Sitzung an, wenn sie ankommt?** (`\conninfo`,
   `inet_server_addr()`, 25.5)
3. **Wer darf mit welcher Methode hinein?** (`pg_hba.conf`, 25.3/25.4)
4. **Was darf die Rolle dann tun?** (`GRANT`, Teil 24)

Wenn du in umgekehrter Reihenfolge arbeitest, ist das nicht verboten — aber du
reparierst dann möglicherweise das dritte Tor, während das erste zu ist, und
schließt aus „geht immer noch nicht" den falschen Schluss.

---

## 25.1 Tor 2: hört der Server überhaupt?

Erst ohne Netz, nur am Server. Zwei Werte, und beide sind Pflicht:

```sql
SHOW listen_addresses;
SHOW port;
```

Und die Frage, die in Teil 14 die wichtigste war: **wann wirkt eine Änderung?**

```sql
SELECT name, setting, context, source, pending_restart
FROM pg_settings
WHERE name IN ('listen_addresses', 'port')
ORDER BY name;
```

`listen_addresses` hat den `context` **`postmaster`** — also Neustart, kein Reload
(14.4). Genau deshalb steht in einem Neustart-Befehl wie
`pg_ctl restart -D … -l …` die Antwort auf „warum reicht `pg_reload_conf()` hier
nicht?". Und `pending_restart` sagt dir, ob der Wert in der Datei schon geändert
ist, aber noch nicht gilt — **das ist die häufigste Ursache für „ich habe es doch
eingetragen!"**

Was die Werte bedeuten:

| Wert | was er bedeutet |
|------|-----------------|
| `localhost` (die Vorgabe) | nur `127.0.0.1` und `::1` — **die LAN-Adresse gehört nicht dazu** |
| `'*'` | alle Adressen, auf denen die Maschine erreichbar ist (auch die öffentliche!) |
| `'10.0.0.5,127.0.0.1'` | genau diese Adressen — die präzisere Variante |

Der zweite Punkt ist die Sicherheitsfrage: `'*'` heißt *nicht* „alle Clients dürfen
hinein" (das entscheidet Tor 3), aber es heißt „**jeder kann es versuchen**". Ein
Server, der nur von einem bestimmten Subnetz erreichbar sein soll, bekommt besser
die Adresse oder das Interface genannt als `'*'`.

Der **Beweis** liegt nicht in PostgreSQL, sondern im Betriebssystem: man kann
fragen, wer auf dem Port lauscht.

```bash
# auf dem Server
ss -ltn                       # wer hört auf welcher Adresse? (netstat -ltn kann dasselbe)
ss -ltnp                      # zusätzlich: welcher Prozess (pid/Programm)
```

Lies die Adresse vor `:5432` und entscheide selbst:

- `127.0.0.1:5432` — nur lokal. Eine Verbindung von außen kann nicht ankommen,
  egal was in der `pg_hba.conf` steht.
- `*:5432`, `0.0.0.0:5432` oder `[::]:5432` — der Server nimmt auf allen Adressen an.

Und wenn `ss` nichts auf 5432 zeigt, obwohl der Server läuft, hilft der zweite
Blick: welchen Port hast du in `postgresql.conf` gesetzt, und hast du danach
wirklich neu gestartet (`pending_restart`)?

---

## 25.2 Tor 1 und 2 zusammen: `pg_isready`

Für die Frage „kann ich überhaupt bis zum Server kommen?" gibt es ein eigenes
Werkzeug — und der entscheidende Punkt ist, was es **nicht** tut: es **meldet sich
nicht an**. Die `pg_hba.conf` ist ihm egal.

```bash
# auf dem Client (oder auf dem Server, mit der Adresse des Servers)
pg_isready -h kurs-00 -p 5432 -t 3
```

Die vier Antworten, die es gibt, und was sie auseinanderhalten:

| Antwort | Bedeutung |
|---------|-----------|
| `accepting connections` | der Server antwortet — Tor 1 und 2 sind offen, Tor 3 ist noch nicht geprüft |
| `rejecting connections` | er hört, nimmt aber gerade nichts an (z. B. noch im Start) |
| `no response` | niemand antwortet: Firewall (Paket verworfen), Routing, oder der Port ist zu |
| `no attempt` | es wurde gar nicht erst versucht — Adresse/Name schon falsch |

Damit ist die Reihenfolge aus 25.0 praktisch:

- `pg_isready` sagt `no response` → **Tor 1 oder 2.** `ss` auf dem Server (25.1)
  und die Firewall sind die nächsten Schritte. Die `pg_hba.conf` ist unschuldig.
- `pg_isready` sagt `accepting connections`, `psql` scheitert aber → **Tor 3**
  (25.3/25.4) oder die Rechte (Teil 24). Und *jetzt* steht auch etwas im Log.

Denselben Befehl gibt es in zwei Geschmacksrichtungen: `pg_isready` fragt den
Zustand eines *Servers*, nicht einer Datenbank — deshalb funktioniert er auch für
die zweite Instanz aus Teil 21:

```bash
pg_isready -h kurs-00 -p 5433        # die Standby
```

---

## 25.3 Tor 3: die `pg_hba.conf` für einen fremden Host

Jetzt darf die `pg_hba.conf` dran. Den Pfad hast du seit Teil 14:

```sql
SHOW hba_file;
```

Und dann die Datei selbst lesen — **von oben nach unten**. Die erste passende Zeile
gewinnt (24.4). Der Denkfehler, der hier fast immer passiert:

```ini
# TYPE   DATABASE  USER  ADDRESS       METHOD
local    all       all                 peer
host     all       all   127.0.0.1/32  scram-sha-256
host     all       all   ::1/128       scram-sha-256
```

**Keine dieser drei Zeilen deckt einen fremden Rechner ab.** `local` ist der
Unix-Socket, also dieselbe Maschine; `127.0.0.1/32` und `::1/128` sind Loopback,
also ebenfalls dieselbe Maschine. Ein Client mit der Adresse `10.0.0.5` fällt durch
alle drei hindurch — und bekommt deshalb genau die Meldung, die im Log steht:

```text
FATAL:  no pg_hba.conf entry for host "10.0.0.5", user "sepp", database "kurs"
```

Die fehlende Zeile sieht dann so aus:

```ini
# TYPE   DATABASE  USER  ADDRESS         METHOD
host     kurs      sepp  10.0.0.5/32     scram-sha-256
```

Vier Entscheidungen stecken darin, und jede ist eine eigene Frage:

| Spalte | was du entscheidest |
|--------|--------------------|
| `TYPE` | `host` = TCP (mit **oder** ohne SSL), `hostssl` = **nur** mit SSL, `hostnossl` = nur ohne |
| `DATABASE` | `kurs` (eine), `all`, oder eine Liste; `replication` ist eine eigene Zeilenart (24.9) |
| `USER` | die Rolle — `sepp`, `all`, oder `+accounting` (Mitglieder einer Rolle, 24.5) |
| `ADDRESS` | **wer** es versuchen darf: ein `/32` = genau diese Adresse, ein `/24` = das ganze Netz |
| `METHOD` | was geprüft wird: `scram-sha-256`, `md5`, `trust`, `reject` … (24.4) |

Der Unterschied `/32` gegen `/24` ist keine Formalität: `/24` lässt *jeden* Rechner
dieses Netzes den Anmeldeversuch unternehmen — und sei es nur, um Passwörter zu
raten.

Und die gute Nachricht zum Schluss: **eine Änderung an der `pg_hba.conf` braucht
keinen Neustart.**

```sql
SELECT pg_reload_conf();
```

Der Server liest die Datei bei **jeder** Verbindung neu — ein Reload ist streng
genommen nur für den Fall, dass ein Fehler beim Lesen gemeldet werden soll (dann
steht er im Log). Wenn du unsicher bist, ob die Datei überhaupt gelesen wird: bau
absichtlich einen Syntaxfehler ein, reload, und schau ins Log. Genau so lernt man,
wo das Log steht.

---

## 25.4 Tor 3, zweiter Teil: Passwort und Methode

Dass die Zeile da ist, reicht nicht — die **Methode** muss zur Rolle passen.

| Methode | über TCP sinnvoll? | warum |
|---------|--------------------|-------|
| `peer` | **nein** | vergleicht den **Betriebssystem**-Benutzer mit dem Rollennamen — den gibt es nur beim Socket |
| `ident` | selten | fragt einen ident-Dienst (meist nicht vorhanden) |
| `trust` | ja, aber … | lässt **jeden** hinein, der die Zeile erreicht |
| `scram-sha-256` | ja | das Passwort, salted+gehasht (die moderne Vorgabe) |
| `md5` | ja | das Passwort, schwächer gehasht |
| `reject` | ja | immer nein — nützlich, um eine Zeile gezielt stillzulegen |

Zwei Dinge, die dann noch zusammengehören:

```sql
SHOW password_encryption;      -- womit das Passwort beim Setzen gehasht wird
ALTER ROLE sepp PASSWORD 'geheim';   -- oder: ... PASSWORD NULL, um es zu entfernen
```

Und ein Fall, der verwirrt, weil die Meldung *ähnlich* aussieht wie die fehlende
Zeile, aber etwas anderes heißt. Wenn in der `pg_hba.conf` nur `hostssl`-Zeilen
passen und der Client **ohne** SSL kommt, steht im Log eine Zeile, die dieses
„no encryption" ausdrücklich erwähnt — kein Rechteproblem, sondern eine
ausdrücklich *nicht erfüllte Bedingung*. Auf der Client-Seite ist die Antwort
`sslmode` (Client-Authentifizierung, `libpq-connect.html`), und das ist ein eigenes
Thema: SSL gehört auf den Server (`ssl = on`, Zertifikat) und auf den Client
(`sslmode`). Merken genügt hier — die Meldung wirst du erkennen, wenn sie kommt.

---

## 25.5 Der Client: was man tippt und wo man es nachliest

Ein Aufruf, vier Angaben:

```bash
psql -h kurs-00 -p 5432 -U sepp -d kurs
```

`-h` ist der **Host** — und genau hier liegt die Brücke zu Teil 2 und 21. Denn
`-h` akzeptiert auch einen *Verzeichnis*pfad; dann bedeutet es „verbinde dich über
den Unix-Socket in diesem Verzeichnis":

```bash
psql -h /var/run/postgresql -U sepp -d kurs     # Socket, kein Netz
pg_isready -h /var/run/postgresql               # geht auch (Teil 21.2)
```

Dieselben vier Angaben gibt es als Umgebungsvariablen — praktisch, weil `-h` sonst
stillschweigend auf den Socket zeigt, wenn man es weglässt:

```bash
PGHOST=kurs-00 PGPORT=5432 PGUSER=sepp PGDATABASE=kurs psql
```

Für Skripte statt Passwort-Eingabe gibt es die Passwortdatei (der Name steht in
`libpq-connect.html`): sie **muss** so gesetzt sein, dass weder Gruppe noch andere
sie lesen können — sonst wird sie vom Client ignoriert, und das Suchen beginnt.
Prüf mit `ls -l`, ob die Rechte stimmen, statt dich auf das Gedächtnis zu verlassen.

Und jetzt der Blick, der in Teil 21 gefehlt hat. Zwei Funktionen und ein Befehl
sagen dir, **wie diese Sitzung angekommen ist**:

```sql
\conninfo
SELECT current_user, inet_server_addr(), inet_server_port();
```

- `inet_server_addr()` ist die Adresse, über die **du** den Server erreicht hast —
  bei einer Socket-Verbindung ist sie leer.
- `\conninfo` sagt dasselbe in Worten: Socket oder Host/Port.

Das ist besonders nützlich, wenn **zwei Instanzen** laufen (die Standby aus Teil 21
auf Port 5433). Der Befehl verrät dir, ob du gerade auf der Primary oder auf der
Standby gelandet bist — ergänzend zu `pg_is_in_recovery()` aus 21.3:

```bash
psql -h kurs-00 -p 5433 -U sepp -d kurs
```

```sql
SELECT pg_is_in_recovery();     -- t = du bist auf der Standby (nur lesen, 21.4)
```

Und auf dem Server sieht man die Hereingekommenen in `pg_stat_activity`:

```sql
SELECT pid, usename, application_name, client_addr, client_port, state
FROM pg_stat_activity
ORDER BY backend_start;
```

Die Spalte, an der man hängen bleibt: **`client_addr` ist leer (`NULL`) bei einer
Socket-Verbindung.** Leer heißt hier nicht „kein Client", sondern „kein Netz".

---

## 25.6 Was schiefgeht

| Symptom | wahrscheinliche Ursache | wo nachsehen |
|---------|-------------------------|--------------|
| Zeitüberschreitung, kein Text | Firewall verwirft die Pakete, oder Routing stimmt nicht | `pg_isready` (25.2), Firewall, Netz |
| `connection refused` | auf dieser Adresse lauscht niemand | `ss -ltn` (25.1), `SHOW listen_addresses;`, `pending_restart` |
| `connection refused`, obwohl `ss` `*:5432` zeigt | Firewall **lehnt ab** statt zu verwerfen — dieselbe Meldung, andere Ursache | Firewall-Regeln, `pg_isready` |
| „no pg_hba.conf entry for host …, user …, database …" | keine passende Zeile für diese Adresse/diesen Benutzer | `SHOW hba_file;`, Datei **von oben nach unten** (25.3) |
| dieselbe Meldung mit „no encryption" | es passt nur eine `hostssl`-Zeile, der Client kam ohne SSL | `sslmode` auf der Client-Seite, 25.4 |
| `password authentication failed` | Zeile passt, Passwort falsch — oder gar keins gesetzt | `ALTER ROLE … PASSWORD`, `password_encryption` (24.4) |
| Passwort wird nie abgefragt | weiter oben steht eine `trust`-Zeile, die schon passt | dieselbe Datei, Reihenfolge |
| „role … does not exist" beim Anmelden | die Rolle gibt es auf **dieser** Instanz nicht (zwei Instanzen!) | `\du` **auf dem Ziel**, `pg_is_in_recovery()` |
| verbinden klappt, lesen nicht | **Tor 4**: `GRANT` fehlt | Teil 24.3 |
| verbinden klappt, **schreiben** nicht | du bist auf der Standby (21.4) — oder es fehlt `INSERT` | `pg_is_in_recovery()`, `\dp` |
| Änderung an `listen_addresses` wirkt nicht | `context` ist `postmaster` — Reload reicht nicht | `pending_restart` (25.1) |
| Änderung an der `pg_hba.conf` wirkt nicht | falsche Datei bearbeitet, oder die Zeile steht zu weit unten | `SHOW hba_file;`, `pg_reload_conf()` |

Der Merksatz über der Tabelle steht schon in 25.0: **sag `pg_isready` zuerst.**
Seine Antwort sortiert die Tabelle in zwei Hälften — alles über der Zeile
„no pg_hba.conf entry" ist Tor 1/2, alles darunter ist Tor 3 oder die Rechte.

---

## 25.7 Und wieder dichtmachen

Was man zum Üben aufgemacht hat, macht man danach zu — und zwar an **beiden**
Enden, wenn man es sauber haben will:

```sql
-- auf dem Server: listen_addresses zurück auf die Vorgabe?
SELECT name, setting, source, pending_restart
FROM pg_settings WHERE name = 'listen_addresses';
```

Ist der Wert nicht mehr die Vorgabe: in `postgresql.conf` (oder per
`ALTER SYSTEM`) zurückstellen, dann neu starten — **Reload genügt hier nicht**
(`context = postmaster`, 25.1).

Und die Zeile in der `pg_hba.conf`, die du für den Testclient angelegt hast:

```ini
# host  kurs  sepp  10.0.0.5/32  scram-sha-256     <- löschen oder auskommentieren
```

```sql
SELECT pg_reload_conf();      -- hier reicht der Reload
```

Die Kontrolle danach ist dieselbe wie in 14.8 — sie zeigt, was du selbst verstellt
hast:

```sql
SELECT name, setting, source
FROM pg_settings
WHERE source NOT IN ('default', 'configuration file')
ORDER BY name;
```

---

## 25.8 Im Container sieht Tor 1 anders aus

Im Docker-Container gibt es keine LAN-Adresse des Containers, die man freischalten
könnte — der Container hat eine interne IP, die von außen niemand kennt. Der Weg
nach außen ist stattdessen eine Zeile in der [`compose.yaml`](../compose.yaml):

```yaml
ports:
  - "5432:5432"          # links: Port auf dem Wirt, rechts: Port im Container
```

Fällt diese Zeile weg, ist der Container von außen nicht mehr erreichbar — unabhängig
von `listen_addresses` und `pg_hba.conf`. Und umgekehrt: die Zeile macht den Port
**auf allen Adressen des Wirts** auf, was auf einem Laptop mit öffentlichem Netz
eine bewusste Entscheidung sein sollte (`127.0.0.1:5432:5432` bindet nur lokal).

Was in dieser Umgebung tatsächlich gilt, ist genau wie auf dem Server eine Abfrage —
nichts, was man annimmt:

```bash
docker compose exec db psql -U kurs -d kurs -c "SHOW listen_addresses;"
docker compose exec db psql -U kurs -d kurs -c "SHOW hba_file;"
```

Der Rest des Dokuments gilt unverändert: Die `pg_hba.conf` **im Container** ist
dieselbe Datei mit denselben Regeln — nur ist der „fremde Host" dort der
Docker-Host, und die Adresse, die in den Zeilen steht, hängt davon ab, wie Docker
den Verkehr weiterleitet. Vergleiche die Ausgabe von `client_addr` aus 25.5 im
Container mit den Adressen in den `host`-Zeilen — dann siehst du, welche Adresse
dort ankommt.

---

## Was in `06-kurs-notizen.md` gehört

- `SHOW listen_addresses;` und `SHOW port;` — welche Werte gelten bei dir, und was
  sagt `context`? Steht bei dir noch die Vorgabe `localhost`?
- Die Zeile aus `ss -ltn`, die auf deinen Port passt: welche Adresse steht vor dem
  Doppelpunkt — `127.0.0.1`, `0.0.0.0` oder `*`?
- `pending_restart` für `listen_addresses`, **bevor** und **nach** einem Neustart.
- Was `pg_isready` gegen den Server sagt — und was gegen eine Adresse, auf der
  nichts läuft (zum Vergleich).
- Die Meldung im **Server**-Log beim ersten Anmeldeversuch von außen: steht dort
  die Adresse des Clients, wie du sie erwartet hast?
- `client_addr` in `pg_stat_activity` für eine Socket-Verbindung und für eine
  Verbindung über das Netz — was steht im ersten Fall in der Spalte?
- Verbindung auf Port 5433 (Standby): Was sagt `pg_is_in_recovery()`, und was
  passiert beim Schreiben?
- Nach dem Aufräumen: steht `listen_addresses` wieder auf der Vorgabe, und ist die
  Testzeile in der `pg_hba.conf` wirklich weg?
