# 1 — PostgreSQL aus dem Quellcode installieren

Warum überhaupt aus dem Quellcode? Nicht weil man das im Alltag so macht — im
Alltag nimmt man Pakete oder das Docker-Image. Sondern um einmal gesehen zu
haben, was in so einer Installation steckt: ein Paket, ein Konfigurationsskript,
ein Compiler, ein Installationsverzeichnis, ein `initdb`, ein Serverprozess.

**Kurzantwort auf deine Frage:** Genau, man holt den *gepackten* Quellcode —
`postgresql-18.6.tar.bz2` — und packt ihn aus. Das ist kein fertiges Programm,
sondern der Quelltext, der auf dem eigenen Rechner übersetzt wird.

> 18.6 ist tatsächlich die aktuelle Version: Release am 13.08.2026, letzter
> Stand in der 18er-Reihe. (18.5 wurde nie veröffentlicht.)

---

## 1.0 Nicht auf dem eigenen Rechner — sondern in einem Container

Damit nichts am eigenen System kaputtgeht, machen wir das Ganze in einem
Wegwerf-Container. Das ist kein Betrug am Lernziel: **im Container läuft genau
derselbe Ablauf** — dieselben Pakete, dasselbe `./configure`, dasselbe `make`.

Linux oder macOS-Bash:

```bash
docker run --rm -it --name pg-bau \
  -v "$PWD/pgsrc:/pgsrc" \
  debian:12 bash
```

Windows PowerShell:

```powershell
docker run --rm -it --name pg-bau -v "${PWD}\pgsrc:/pgsrc" debian:12 bash
```

Alles, was folgt, läuft **in diesem Container**. Der Ordner `pgsrc` liegt auf dem
eigenen Rechner und ist die einzige Verbindung nach außen.

---

## 1.1 Werkzeuge installieren

```bash
apt update
apt install -y build-essential bison flex libreadline-dev zlib1g-dev \
               libicu-dev pkg-config wget ca-certificates
```

Wofür das alles ist (das ist der eigentliche Lerneffekt):

| Paket | Wofür |
|-------|-------|
| `build-essential` | C-Compiler (`gcc`), `make`, `tar` |
| `bison`, `flex` | Parser-Generatoren — PostgreSQL braucht sie zwingend |
| `libreadline-dev` | damit `psql` die Pfeiltasten und Historie kann |
| `zlib1g-dev` | für komprimierte Dumps (`pg_dump`) |
| `libicu-dev` | Kollationen/Zeichensätze |

Prüfen (die Doku verlangt GNU make ≥ 3.81):

```bash
make --version
gcc --version
```

---

## 1.2 Quellcode holen und auspacken

```bash
mkdir -p /pgsrc && cd /pgsrc

wget https://ftp.postgresql.org/pub/source/v18.6/postgresql-18.6.tar.bz2

# Prüfsumme — guter Brauch, keine Pflicht
wget https://ftp.postgresql.org/pub/source/v18.6/postgresql-18.6.tar.bz2.sha256
sha256sum -c postgresql-18.6.tar.bz2.sha256

tar xjf postgresql-18.6.tar.bz2
cd postgresql-18.6
```

`xjf` = entpacken (`x`), bzip2 (`j`), Datei (`f`).

---

## 1.3 Konfigurieren

```bash
./configure --prefix=/usr/local/pgsql
```

`--prefix` legt fest, wohin später installiert wird. Ohne Angabe wäre es
ebenfalls `/usr/local/pgsql`.

Was passiert hier? `configure` ist ein Skript, das den Rechner untersucht:
Welcher Compiler ist da? Gibt es readline? Wie heißen die Bibliotheken? Am Ende
schreibt es ein `Makefile`, das genau zu diesem Rechner passt. Deshalb gibt es
den Quellcode-Weg überhaupt: der Code wird für die Zielmaschine gebaut.

Nützliche Optionen, die man im Vorbeigehen verstehen sollte:

```bash
./configure --help | less
```

---

## 1.4 Bauen

```bash
make -j"$(nproc)"
```

Das dauert ein paar Minuten. `-j` baut parallel mit allen Kernen.

**Tipp:** `make` kann mittendrin abbrechen. Meistens fehlt dann ein Paket aus
Schritt 1.1. Die letzte Zeile vor dem Abbruch verrät, welches — danach
`make -j"$(nproc)"` einfach noch einmal starten.

---

## 1.5 Installieren

```bash
make install
```

Ab jetzt liegen die Programme in `/usr/local/pgsql/bin`. Anschauen lohnt sich:

```bash
ls /usr/local/pgsql/bin
```

Da stehen alle Namen, die einem später immer wieder begegnen: `initdb`,
`pg_ctl`, `psql`, `createdb`, `postgres`.

---

## 1.6 Benutzer, Datenverzeichnis, Server starten

PostgreSQL weigert sich, als `root` zu laufen. Also einen eigenen Benutzer
anlegen:

```bash
useradd -m postgres
mkdir -p /usr/local/pgsql/data
chown postgres /usr/local/pgsql/data

export PATH=/usr/local/pgsql/bin:$PATH
```

Datenverzeichnis mit `initdb` erzeugen (das legt die Systemkataloge an, aus
denen später deine eigene Datenbank entsteht):

```bash
su postgres -c '/usr/local/pgsql/bin/initdb -D /usr/local/pgsql/data'
```

Server starten:

```bash
su postgres -c '/usr/local/pgsql/bin/pg_ctl -D /usr/local/pgsql/data \
                 -l /usr/local/pgsql/data/server.log start'
```

Test:

```bash
su postgres -c '/usr/local/pgsql/bin/createdb test'
su postgres -c '/usr/local/pgsql/bin/psql test -c "SELECT version();"'
```

Wenn eine Versionszeile mit „PostgreSQL 18.6" erscheint, ist die Installation
fertig.

Server wieder stoppen:

```bash
su postgres -c '/usr/local/pgsql/bin/pg_ctl -D /usr/local/pgsql/data stop'
```

---

## 1.7 Was man daraus mitnehmen soll

- Die **Docker-Variante** (Teil 2) macht genau diese Schritte automatisch — nur
  in einer fertigen Umgebung. Man überspringt Compiler und `make`, nicht das
  Konzept.
- `initdb` einmal pro Datenverzeichnis, nicht pro Datenbank.
- `pg_ctl start`/`stop` ist der Serverprozess. Im Container übernimmt das der
  Einstiegspunkt des Images.

---

## Aufräumen

Container verlassen:

```bash
exit
```

Beim `--rm` von oben wird er dabei automatisch gelöscht. Der heruntergeladene
und ausgepackte Quellcode bleibt im Ordner `pgsrc` auf dem eigenen Rechner und
kann gelöscht werden, wenn er nicht mehr gebraucht wird.
