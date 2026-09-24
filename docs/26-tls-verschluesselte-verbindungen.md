# 26 — TLS: verschlüsselte Verbindungen (`ssl = on`, Zertifikate, `sslmode`)

In Teil 25 ging es darum, **ob** eine Verbindung ankommt und **wer** hineindarf.
Offen geblieben ist die Frage dazwischen: **kann jemand mitlesen?** Bisher war alles,
was über das Netz lief, Klartext — das Passwort aus 24.4 eingeschlossen.

Man kann das auf zwei Weisen angehen, und PostgreSQL macht **beides**, mit zwei
verschiedenen Mechanismen:

| was geschützt wird | wodurch | wo es steht |
|--------------------|---------|-------------|
| der **Inhalt** der Verbindung | TLS-verschlüsselte Verbindung | 18.9 (`ssl-tcp.html`) |
| der **Zugang** zur Datenbank | Authentifizierung in der `pg_hba.conf` | Kapitel 20 (`client-authentication.html`), Teil 24/25 |

Die beiden greifen ineinander, aber sie sind nicht dasselbe — und genau daraus
entstehen die Verwechslungen dieses Themas. Die Kapitelnummer, die dir aufgefallen
ist, lohnt deshalb ein zweites Hinschauen:

- **18.9** ist die Stelle, an der Zertifikat, Schlüssel und `ssl = on` stehen.
- **Kapitel 20** ist *Client Authentication* — dort stehen `hostssl`,
  `clientcert=` und die Authentifizierungsmethode `cert`. Das sind die Stellen, an
  denen TLS **erzwungen** wird, nicht die, an denen es eingerichtet wird.

Die Doku-Kapitel, um die es geht:

- https://www.postgresql.org/docs/18/ssl-tcp.html — 18.9, „Secure TCP/IP
  Connections with SSL": Dateien, Rechte, `openssl`-Befehle, SNI
- https://www.postgresql.org/docs/18/libpq-ssl.html — 32.19, die **Client**-Seite:
  `sslmode` mit seinen sechs Werten, `root.crt`, Client-Zertifikate
- https://www.postgresql.org/docs/18/client-authentication.html — Kapitel 20;
  darin 20.1 (`pg_hba.conf`) und 20.11 (`cert`-Methode)
- https://www.postgresql.org/docs/18/auth-pg-hba-conf.html — `hostssl`,
  `hostnossl`, `clientcert=`
- https://www.postgresql.org/docs/18/runtime-config-connection.html — `ssl`,
  `ssl_cert_file`, `ssl_key_file`, `ssl_ca_file`, `ssl_min_protocol_version`,
  `ssl_ciphers`
- https://www.postgresql.org/docs/18/encryption-options.html — 18.8, der Überblick
  über *alle* Verschlüsselungsoptionen (die Seite davor — gut zum Einordnen)
- https://www.postgresql.org/docs/18/monitoring-stats.html — `pg_stat_ssl`

> **Zwei Umgebungen, dieselben Befehle.** Der Kurs arbeitet auf PostgreSQL **19**
> (in der Doku: `/docs/19/…`), dieses Repo auf `postgres:18.6`, siehe
> [`compose.yaml`](../compose.yaml). Die `openssl`-Befehle und die Dateinamen sind
> dieselben. Ein Unterschied ist wichtig: der `openssl`-Aufruf aus 18.9 **erzeugt
> eine Datei im Datenverzeichnis** — im Container geht das nur mit
> `-u postgres` und einem beschreibbaren Ort (26.10).

---

## 26.0 Drei Angriffe, drei Schutzmaßnahmen

Die `libpq`-Doku zählt drei Dinge auf, gegen die eine verschlüsselte Verbindung
schützen kann. Die Liste ist deshalb so gut, weil aus ihr **direkt** folgt, was
`sslmode` bedeutet (26.5):

| Angriff | was passiert | was dagegen hilft |
|---------|--------------|-------------------|
| **Mitlesen** (eavesdropping) | jemand liest den Verkehr mit: Zugangsdaten und Daten | **Verschlüsselung** |
| **Zwischenmann** (MITM) | jemand *gibt sich als Server aus*, leitet weiter und kann mitlesen, **obwohl** verschlüsselt wird | **Zertifikatsprüfung des Servers** auf der Client-Seite |
| **Sich ausgeben als Client** | jemand tritt als berechtigter Benutzer auf | **Client-Zertifikate** |

Der zweite Punkt ist der, den man überspringt: **Verschlüsselung allein schützt
nicht gegen den falschen Server.** Wer sich als Server ausgibt, bekommt eine
verschlüsselte Verbindung mit sich selbst — und das Passwort darin. Deshalb ist
`sslmode = require` ausdrücklich *keine* Absicherung gegen MITM, und deshalb heißt
der sichere Wert `verify-full`. Die Tabelle in 26.5 ist genau diese Liste in
konkreten Werten.

Und der Merksatz aus der Doku, der die Richtung angibt: **Verschlüsselung nützt nur,
wenn beide Seiten davon wissen.** Ist TLS nur auf dem Server eingeschaltet, kann der
Client Zugangsdaten senden, bevor er weiß, dass der Server hohe Sicherheit verlangt.

---

## 26.1 `ssl = on` — der Schalter und die zwei Dateien

Ein Server mit TLS-Unterstützung lauscht **auf demselben Port** und handelt mit
jedem Client aus, ob TLS benutzt wird. Der Schalter:

```ini
ssl = on
```

Und die zwei Dateien, die dafür da sein müssen — mit Vorgabenamen im
Datenverzeichnis:

```sql
SHOW data_directory;      -- hier erwartet der Server sie
SHOW ssl;
SHOW ssl_cert_file;
SHOW ssl_key_file;
```

| Datei (Vorgabe) | Inhalt | wofür sie da ist |
|-----------------|--------|------------------|
| `server.crt` | das Server-Zertifikat | wird dem Client geschickt, um die Identität des Servers zu zeigen |
| `server.key` | der private Schlüssel des Servers | beweist, dass das Zertifikat von *ihm* kommt |

Zwei Dinge, die man am Anfang nicht erwartet:

- **Der Server liest diese Dateien beim Start und bei jedem Reload.** Anders als
  `listen_addresses` aus 25.1 braucht TLS also **keinen** Neustart — die Prüfung
  gehört trotzdem gemacht, mit demselben Werkzeug wie immer:
  ```sql
  SELECT name, setting, context, source, pending_restart
  FROM pg_settings WHERE name IN ('ssl', 'ssl_cert_file', 'ssl_key_file')
  ORDER BY name;
  ```
- **Ein Fehler in einer Zertifikatsdatei beim Reload legt den Server nicht um.**
  Er behält die alte TLS-Konfiguration bei und schreibt den Fehler ins Log. Beim
  *Start* dagegen verweigert er den Start ganz. (Was das für die Suche heißt: wenn
  du etwas an den Zertifikaten änderst und „nichts passiert", ist das Log die
  erste Adresse, nicht die letzte.)

Der zweite Punkt gilt auch für die Rechte (26.2): eine zu weit geöffnete
Schlüsseldatei ist so ein Fehler, und er ist **still**, bis man nachsieht.

---

## 26.2 Ein Zertifikat erzeugen: was der `openssl`-Befehl tut

Für einen Test reicht ein selbst signiertes Zertifikat. Es ist derselbe Befehl, den
die Doku in 18.9.5 zeigt:

```bash
openssl req -new -x509 -days 365 -nodes -text -out server.crt \
  -keyout server.key -subj "/CN=<hostname-des-servers>"
```

Er sieht kryptisch aus, besteht aber aus lauter einzeln erklärbaren Teilen:

| Schalter | was er bedeutet |
|----------|-----------------|
| `req` | „ich will ein Zertifikat erzeugen" (request) |
| `-new` | ein **neues** Zertifikat, nicht ein vorhandenes |
| `-x509` | kein Antrag an eine CA, sondern **direkt** ein Zertifikat — daher „selbst signiert" |
| `-days 365` | gilt ein Jahr |
| `-nodes` | **kein Passwort** auf den Schlüssel („no DES") — siehe unten |
| `-text` | druckt den Inhalt des Zertifikats **auf den Bildschirm** (das ist die Ausgabe, die du siehst) |
| `-out server.crt` | hierhin das Zertifikat |
| `-keyout server.key` | hierhin der private Schlüssel |
| `-subj "/CN=…"` | der **Name** des Servers — er zählt später beim Prüfen |

Danach der Schritt, der am häufigsten fehlt — und den die Doku deshalb eigens
hinschreibt:

```bash
chmod og-rwx server.key
```

**Der Server weist den Schlüssel zurück, wenn seine Rechte zu weit offen sind.**
Beim Start startet er deshalb gar nicht; beim Reload bleibt die alte Konfiguration
stehen und der Fehler geht ins Log (26.1). Das ist kein Ärger, sondern der Punkt:
ein privater Schlüssel, den die ganze Maschine lesen kann, ist kein Geheimnis.

Zwei Details zum Verständnis:

- **`-nodes` ist der Grund, warum das hier funktioniert.** Ein passwortgeschützter
  Schlüssel lässt den Server beim Start nach dem Passwort **fragen** — und sperrt
  damit den bequemen Weg (Reload) aus, weil die TLS-Konfiguration dann nicht ohne
  Neustart gewechselt werden kann. Für Übungen ist `-nodes` richtig; über
  `ssl_passphrase_command` gibt es Wege, das im Betrieb zu lösen.
- **Das `CN` muss der Name sein, den der Client später benutzt.** Nicht der Name,
  den du schön findest — deshalb steht in der Doku `dbhost.yourdomain.com` als
  Platzhalter. Warum das so ist, steht in 26.5: es ist genau die Prüfung, die
  `verify-full` durchführt.

---

## 26.3 Selbst signiert gegen CA — und wer welche Datei bekommt

| | selbst signiert | mit CA |
|---|------------------|--------|
| wer es erzeugt | der Server selbst (`-x509`) | eine Zertifizierungsstelle (`root.crt`, `root.key`) |
| was der Client braucht | das Zertifikat selbst, um es zu prüfen | nur das **Root**-Zertifikat |
| wofür gut | Übung, Test, internes Werkzeug | alles, wo ein Client die Identität prüfen soll |

Und die Aufteilung, die man leicht durcheinanderbringt — auf **welcher** Maschine
welche Datei liegt. Zwei Tabellen aus der Doku, hier zusammengefasst:

| auf dem **Server** | was er damit macht |
|--------------------|--------------------|
| `server.crt` (`ssl_cert_file`) | die eigene Identität vorzeigen |
| `server.key` (`ssl_key_file`) | beweisen, dass das Zertifikat zu ihm gehört |
| `ssl_ca_file` | prüfen, ob ein **Client**-Zertifikat von einer vertrauten CA ist |
| `ssl_crl_file` | prüfen, ob ein Client-Zertifikat **zurückgezogen** wurde |

| auf dem **Client** (Vorgabepfade) | wofür |
|-----------------------------------|-------|
| `~/.postgresql/root.crt` | prüfen, ob das **Server**-Zertifikat von einer vertrauten CA ist |
| `~/.postgresql/postgresql.crt` | sich selbst als Client ausweisen |
| `~/.postgresql/postgresql.key` | beweisen, dass das Client-Zertifikat zu ihm gehört |

Die Client-Dateien werden in 26.7 gebraucht — und wie auf der Server-Seite gilt für
`postgresql.key` dasselbe Rechtethema wie für `server.key`.

---

## 26.4 Ist es wirklich an?

Drei Nachweise, vom Allgemeinen zum Konkreten. Erst der Schalter, dann diese
Verbindung, dann alle Verbindungen:

```sql
SHOW ssl;
```

```text
\conninfo
```

Bei einer verschlüsselten Verbindung ergänzt `\conninfo` eine Zeile, die
**Protokollversion und Cipher** dieser Sitzung nennt. Fehlt die Zeile, ist die
Sitzung nicht verschlüsselt — und dafür gibt es zwei harmlose Erklärungen, an die
man zuerst denkt:

- **Du bist über den Unix-Socket verbunden.** TLS gilt für TCP; eine
  Socket-Verbindung hat gar keine TLS-Schicht. `\conninfo` sagt dir, welcher Fall
  vorliegt (25.5).
- **`sslmode` steht auf `disable`** (oder `allow`, und der Server verlangt nichts).
  Der Client hat es also gar nicht versucht — mehr dazu in 26.5.

Und für **alle** Verbindungen auf einmal, auf dem Server:

```sql
SELECT a.pid, a.usename, a.client_addr, s.ssl, s.version, s.cipher, s.bits,
       s.client_dn, s.issuer_dn
FROM pg_stat_activity a
LEFT JOIN pg_stat_ssl s USING (pid)
ORDER BY a.backend_start;
```

Diese Sicht ist der eigentliche Gewinn: sie zeigt **pro Verbindung**, ob TLS läuft
(`ssl`), mit welcher **Version** und **Cipher**, und — sobald Client-Zertifikate im
Spiel sind (26.7) — auch den Namen (`client_dn`) und den Aussteller
(`issuer_dn`) des Client-Zertifikats.

Zwei Beobachtungen sind hier fast garantiert:

- **Eine Zeile mit `ssl = false`** — das ist meistens die eigene Sitzung über den
  Socket, oder ein Werkzeug, das ohne TLS verbindet.
`client_dn` ist leer, obwohl `ssl` wahr ist.** Das ist kein Fehler: ein
Client-Zertifikat wird nur geschickt, wenn es verlangt wird (26.7) — die
Verschlüsselung braucht es nicht.

Und `wal_compression` aus Teil 23 hat mit alldem nichts zu tun: das eine ist
Kompression des WAL, das andere Verschlüsselung der Leitung. Zwei Wörter,
dieselbe Vorsilbe, kein Zusammenhang.

---

## 26.5 Auf der Client-Seite: `sslmode`

Hier entscheidet sich, was TLS überhaupt leisten soll. Sechs Werte, und die drei
Angriffe aus 26.0 als Spalten:

| `sslmode` | gegen Mitlesen | gegen MITM | der Satz dahinter |
|-----------|----------------|------------|-------------------|
| `disable` | nein | nein | „Verschlüsselung ist mir egal, ich will sie nicht bezahlen." |
| `allow` | vielleicht | nein | „egal — aber *wenn* der Server darauf besteht, zahle ich sie." |
| `prefer` (**Vorgabe**) | vielleicht | nein | „egal — *wenn* der Server sie kann, nehme ich sie mit." |
| `require` | ja | nein | „ich will Verschlüsselung — und vertraue dem Netz, dass ich beim richtigen Server lande." |
| `verify-ca` | ja | hängt von der CA ab | „ich will Verschlüsselung **und** sicher sein, dass der Server vertrauenswürdig ist." |
| `verify-full` | ja | ja | „…und dass es **genau der** Server ist, den ich angegeben habe." |

Der wichtigste Satz über dieser Tabelle: **`prefer` ist die Vorgabe, und die Vorgabe
ist aus Sicherheitssicht keine Empfehlung.** Sie steht nur aus
Abwärtskompatibilität dort. Wer Verschlüsselung *will*, muss sie sagen — und wer
Prüfung will, muss `verify-full` sagen.

Was `verify-full` konkret prüft, ist der Anschluss an 26.2:

- den **Namen**: gegen die SAN-Einträge (`dNSName` für Namen, `iPAddress` für
  Adressen) des Zertifikats, und nur wenn solche fehlen, gegen das `CN`. Deshalb
  muss das `CN` (oder eine SAN) zum Namen passen, den du in `-h` benutzt.
- einen `*` im Zertifikat als Platzhalter — der **keine Punkte** überdeckt: ein
  Zertifikat für `*.example.com` passt also **nicht** zu `tief.example.com`.

Daraus folgt eine Falle, die man einmal erlebt haben muss: **dieselbe Verbindung
kann mit `-h kurs-00` gelingen und mit `-h 10.0.0.5` scheitern** (oder umgekehrt),
weil der eine Aufruf ein `dNSName` prüft und der andere eine `iPAddress`. Der Name
in `-h` ist bei `verify-full` keine Bequemlichkeit, sondern Teil der Prüfung.

Angegeben wird der Modus auf drei Wegen — alle drei sind derselbe Wert:

```bash
psql "host=kurs-00 dbname=kurs user=sepp sslmode=require"    # im Connection-String
PGSSLMODE=verify-full psql -h kurs-00 -U sepp -d kurs        # als Umgebungsvariable
psql "host=kurs-00 sslmode=verify-full sslrootcert=/pfad/root.crt" -U sepp -d kurs
```

Und woher der Client das **Root**-Zertifikat nimmt, das er für `verify-ca` /
`verify-full` braucht:

| Datei (Vorgabe) | überschreibbar mit |
|-----------------|--------------------|
| `~/.postgresql/root.crt` | `sslrootcert=…` bzw. `PGSSLROOTCERT` |
| `~/.postgresql/root.crl` | `sslcrl=…` / `sslcrldir=…` (zurückgezogene Zertifikate) |

Ein Hinweis, der in älteren Anleitungen falsch herum steht und deshalb hier
ausdrücklich: **`require` verhält sich wie `verify-ca`, wenn ein Root-Zertifikat
vorhanden ist** — das ist nur noch aus Abwärtskompatibilität so. Wer prüfen will,
schreibt `verify-ca` oder `verify-full` hin; auf dieses Verhalten zu bauen ist
ausdrücklich nicht empfohlen.

---

## 26.6 Erzwingen: `hostssl`

Der Client kann TLS ablehnen — der Server kann es verlangen. Und das ist wieder eine
`pg_hba.conf`-Zeile (25.3), nur mit anderem `TYPE`:

```ini
# TYPE     DATABASE  USER  ADDRESS       METHOD
hostssl    kurs      all   0.0.0.0/0     scram-sha-256
```

Die drei `TYPE`-Werte, die es in diesem Zusammenhang gibt:

| `TYPE` | Bedeutung |
|--------|-----------|
| `host` | TCP — **mit oder ohne** TLS (der Client entscheidet) |
| `hostssl` | TCP, **nur mit** TLS |
| `hostnossl` | TCP, **nur ohne** TLS |

Und die Meldung, die dann im Server-Log steht, wenn eine `hostssl`-Zeile passt und
der Client **ohne** TLS kommt — sie sieht aus wie die „keine Zeile passt"-Meldung
aus 25.3, sagt aber etwas anderes: sie nennt ausdrücklich **„no encryption"**. Kein
Rechteproblem, kein falscher Benutzer — eine Bedingung ist unerfüllt. In 25.4 steht
sie schon als Ausblick; hier ist die Stelle, an der sie entsteht.

Die Kontrolle nach dem Ändern ist wie immer dieselbe: Datei bearbeiten,
`SELECT pg_reload_conf();`, und dann *nachsehen* statt hoffen — in
`pg_stat_ssl` (26.4) für die Verbindung, im Log für den Versuch.

---

## 26.7 Zertifikate für Clients — Ausblick auf Kapitel 20

Bis hierher hat TLS nur **verschlüsselt** und (mit `verify-full`) den **Server**
geprüft. Der dritte Angriff aus 26.0 bleibt offen: jemand gibt sich als *Client*
aus. Dafür braucht der Client ein eigenes Zertifikat — und das ist Inhalt von
Kapitel 20, nicht von 18.9. Die Befehle gehören dorthin, die Dateien stehen in 26.3.
Die zwei Bauformen:

- **`clientcert=verify-ca`** bzw. **`verify-full`** als Option an einer
  `hostssl`-Zeile: das Zertifikat wird verlangt und geprüft — bei `verify-full`
  zusätzlich gegen den Benutzernamen.
- die **Methode `cert`**: das Client-Zertifikat *ist* die Anmeldung (kein Passwort).
  Hier wird immer geprüft, dass die Kette gültig ist.

Was der Server dafür braucht, ist die Zeile aus 26.3: das **Root**-Zertifikat in
`ssl_ca_file`. Und was du als Nachweis siehst, steht schon in 26.4 bereit: die
Spalten `client_dn` und `issuer_dn` in `pg_stat_ssl` füllen sich genau dann.

Mehr steht hier absichtlich nicht — das ist ein eigener Teil. Der Zweck des
Ausblicks ist derselbe wie in 24.13: **wenn dir `clientcert=` begegnet, weißt du,
wo es hingehört.**

---

## 26.8 Was schiefgeht

| Symptom | wahrscheinliche Ursache | wo nachsehen |
|---------|-------------------------|--------------|
| Server startet nicht nach `ssl = on` | `server.crt`/`server.key` fehlen, sind unlesbar oder **zu weit geöffnet** | Log, `chmod og-rwx server.key` (26.2) |
| Server läuft weiter, aber TLS wirkt nicht | der letzte Reload fand einen Fehler und hat die **alte** Konfiguration behalten | Log, `pending_restart`, `SHOW ssl;` |
| `\conninfo` zeigt keine TLS-Zeile | Socket-Verbindung, oder `sslmode=disable`/`allow` | `\conninfo`, 25.5, 26.5 |
| „server does not support SSL, but SSL was required" | Client verlangt TLS, Server hat `ssl = off` | `SHOW ssl;` (26.1) |
| Verbindung scheitert **nur** mit `verify-full` | Name in `-h` passt nicht zu SAN/CN des Zertifikats | das Zertifikat (`-text`), 26.2, 26.5 |
| `verify-ca`/`verify-full` scheitert immer | kein Root-Zertifikat auf dem Client, oder das falsche | `~/.postgresql/root.crt`, `sslrootcert` (26.5) |
| „no pg_hba.conf entry …, **no encryption**" | es passt nur eine `hostssl`-Zeile, der Client kam ohne TLS | Datei von oben nach unten (25.3a), `sslmode` (26.6) |
| Server fragt beim Start nach einem Passwort | der private Schlüssel hat eine Passphrase (nicht `-nodes`) | `ssl_passphrase_command` (26.2) |
| Client-Zertifikat wird nicht benutzt | es wird keines **verlangt** — TLS braucht keine Client-Zertifikate | `client_dn` leer in `pg_stat_ssl` (26.4), 26.7 |
| `ssl = on` geändert, aber kein Neustart gemacht | für `ssl` reicht der Reload — aber nur, wenn die Dateien in Ordnung sind | `SELECT pg_reload_conf();`, Log |

Der Merksatz über der Tabelle: **TLS scheitert fast immer an einer Datei oder an
einem Namen, nicht an einem Schalter.** Der Schalter ist eine Zeile; die Fehler
stecken in Rechten, Pfaden und im `CN` — und deshalb steht bei fast jeder Zeile
„Log" oder „Zertifikat" und nicht „Konfiguration".

---

## 26.9 Aufräumen

Die Zertifikate wieder wegnehmen und den Schalter zurückstellen:

```ini
# ssl = on        <- auskommentieren oder auf off
```

```sql
SELECT pg_reload_conf();
SHOW ssl;
SELECT name, setting, context, pending_restart
FROM pg_settings WHERE name = 'ssl';
```

Und die Dateien, die der `openssl`-Aufruf angelegt hat — sie liegen im
Datenverzeichnis, also dort, wo auch `postgresql.conf` liegt (`SHOW data_directory;`):

```bash
# auf dem Server, im Datenverzeichnis:
rm -f server.crt server.key
```

Die `pg_hba.conf`-Zeile aus 26.6 nicht vergessen — sie ist die Zeile, die den
Client ohne TLS **abweisen** würde, und genau das will man nach einer Übung nicht
stehen lassen:

```ini
# hostssl  kurs  all  0.0.0.0/0  scram-sha-256    <- entfernen
```

```sql
SELECT pg_reload_conf();
```

Und, wie nach jedem Experiment in diesem Repo (14.8):

```sql
SELECT name, setting, source
FROM pg_settings
WHERE source NOT IN ('default', 'configuration file')
ORDER BY name;
```

---

## 26.10 Im Container

Hier gibt es eine Eigenheit, die vor allem Zeit kostet: **das Datenverzeichnis ist
ein Docker-Volume** (siehe [`compose.yaml`](../compose.yaml)), kein eingebundener
Ordner. Der `openssl`-Befehl ist im `postgres`-Image vorhanden, aber:

- er muss als `postgres` laufen — als `root` passt der Eigentümer der Dateien später
  nicht, und der Server kann den Schlüssel nicht lesen;
- das Ziel muss beschreibbar sein, also innerhalb des Volumes
  (`/var/lib/postgresql/…`), nicht in `./sql` — das ist read-only eingebunden;
- `chmod og-rwx` gilt im Container genauso, und die Rechte müssen für die
  Server-`uid` passen.

```bash
docker compose exec -u postgres -T db bash
# in dieser Shell: ins Datenverzeichnis wechseln, dann der openssl-Aufruf aus 26.2
```

Alles andere — `SHOW ssl;`, `\conninfo`, `pg_stat_ssl`, `sslmode` auf der
Client-Seite — gilt unverändert. Und der Hinweis aus 25.8 gilt auch hier: was in
dieser Umgebung wirklich eingestellt ist, ist eine Abfrage, keine Annahme:

```bash
docker compose exec -T db psql -U kurs -d kurs -c "SHOW ssl;"
docker compose exec -T db psql -U kurs -d kurs -c "SHOW ssl_cert_file;"
```

---

## Was in `06-kurs-notizen.md` gehört

- `SHOW ssl;` und `SHOW ssl_cert_file;` auf **deiner** Installation: wie heißen die
  Dateien bei dir, und liegt der Schlüssel dort, wo der Server ihn erwartet?
- Der `openssl`-Aufruf aus 26.2 mit **deinem** `CN` — was steht im Zertifikat unter
  `Subject:` und `Subject Alternative Name`, wenn du `-text` liest?
- `ls -l` auf `server.key`: welche Rechte stehen dort, und was passiert, wenn du sie
  absichtlich auf `0644` setzt (Server **starten**, nicht reloaden)?
- `\conninfo` derselben Rolle über den Socket und über TCP — in welchem Fall fehlt
  die TLS-Zeile?
- `pg_stat_ssl`: welche `version` und welche `cipher` stehen bei deiner Verbindung —
  und ist `client_dn` leer? Warum (oder warum nicht)?
- Was passiert mit `sslmode=verify-full`, wenn du das `CN` im Zertifikat absichtlich
  nicht zum Namen in `-h` passend machst? Notiere die Meldung **wörtlich**.
- Was steht im Log, wenn eine `hostssl`-Zeile passt und der Client ohne TLS kommt?
- `SHOW ssl;` vor und nach einem `pg_reload_conf()` — reicht der Reload bei dir,
  oder meldet `pending_restart` etwas?
