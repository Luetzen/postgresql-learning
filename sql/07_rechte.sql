-- ---------------------------------------------------------------------------
-- Eigentümer und Rechte: der Durchlauf zu Teil 27
--
-- Zum Abschreiben und Selber-Ausführen. Die Erklärungen stehen in
-- docs/27-eigentuemer-und-acl.md; hier stehen nur die Befehle in der
-- Reihenfolge, in der sie etwas zeigen.
--
-- Voraussetzung: du bist als Superuser verbunden (nachsehen mit \du).
-- Die Abschnitte bauen aufeinander auf -- die Reihenfolge ist der Inhalt.
--
--   docker compose exec -T db psql -U kurs -d kurs -f /sql/07_rechte.sql
--
-- ACHTUNG, Übungsskript: es legt die Rollen sepp und accounting an, wechselt
-- Eigentum und ändert in Abschnitt 5 die Rechte der Datenbank "kurs". Auf einem
-- Produktivserver hat das nichts zu suchen. Abschnitt 5 nimmt PUBLIC das
-- CONNECT und gibt es am Ende wieder zurück -- brich dort nicht mittendrin ab,
-- sonst kommst du nur noch als Superuser hinein.
--
-- Heißt deine Datenbank anders als "kurs", setz den Namen in Abschnitt 5 ein.
--
-- Die Meldungen in den Kommentaren sind Meldungen, die man bekommt -- keine
-- gemessenen Werte. Was bei DIR dasteht, entscheidet dein Server.
-- ---------------------------------------------------------------------------

-- Dein Superuser, automatisch der Benutzer dieser Sitzung (siehe \du).
-- Wird in Abschnitt 8 gebraucht, damit das Skript unabhängig vom Namen ist.
\set superuser :USER

-- ---------------------------------------------------------------------------
-- 1) Erst nachsehen: wer besitzt was, und wo stehen die Rechte?
--    (nur lesend, dieser Abschnitt ändert nichts)
-- ---------------------------------------------------------------------------

\dt                       -- Tabellen MIT Eigentümer -- aber ohne Rechte
\dp                       -- dieselben Tabellen MIT Rechten -- aber ohne Eigentümer
\l                        -- Datenbanken: Eigentümer und "Access privileges"
\dn+                      -- Schemata; public gehört pg_database_owner

-- Dasselbe aus den Katalogen, filterbar und sortierbar:
SELECT c.relname, pg_get_userbyid(c.relowner) AS eigentuemer
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY c.relname;

-- datacl ist genau die Spalte, die \l anzeigt. Ist sie NULL, sind es die
-- Vorgaberechte (5.8): für eine Datenbank also "Tc" für PUBLIC.
SELECT datname, pg_get_userbyid(datdba) AS eigentuemer, datacl
FROM pg_database
ORDER BY datname;

-- Die eingebauten Vorgaben selbst, lesbar gemacht -- das ist die Bedeutung
-- einer leeren Spalte. (Typschlüssel neben acldefault() in functions-info.html.)
SELECT acldefault('d', (SELECT datdba FROM pg_database
                        WHERE datname = current_database()))
       AS vorgabe_fuer_eine_datenbank;

-- ---------------------------------------------------------------------------
-- 2) Übungsmaterial: zwei Rollen und eine Tabelle
--
--    sepp      = die Person (LOGIN)
--    accounting = die Gruppe (NOLOGIN), in der sepp Mitglied ist
--
--    In der Kursumgebung waren die Objekte waltest/test/test2 -- hier ist es
--    eine eigene Tabelle, die man gefahrlos kaputtmachen darf.
-- ---------------------------------------------------------------------------

-- Rollen nur anlegen, wenn sie fehlen (CREATE ROLE ist nicht wiederholbar)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'accounting') THEN
        CREATE ROLE accounting NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sepp') THEN
        CREATE ROLE sepp LOGIN PASSWORD 'geheim';
    END IF;
END
$$;

GRANT accounting TO sepp;      -- Mitgliedschaft; zweimal ausgeführt ist es ein Hinweis

DROP TABLE IF EXISTS rechte_demo;

-- Bewusst ohne Primary Key und ohne alles: hier geht es nur um Eigentum
-- und Rechte, nicht um Datensätze.
CREATE TABLE rechte_demo (
    id    int,
    notiz text
);

INSERT INTO rechte_demo (id, notiz) VALUES (1, 'gehoert erst dem Superuser');

\dt rechte_demo                -- Owner = wer das Skript ausführt
\dp rechte_demo                -- "Access privileges" ist LEER = die Vorgaben gelten

-- ---------------------------------------------------------------------------
-- 3) Eigentum übertragen -- und was daraus folgt
-- ---------------------------------------------------------------------------

-- 5.8: Superuser dürfen das immer; gewöhnliche Rollen nur, wenn sie beides
-- sind -- aktueller Eigentümer (oder Erbe davon) UND Mitglied der neuen Rolle.
ALTER TABLE rechte_demo OWNER TO sepp;

\dt rechte_demo                -- Owner: sepp
\dp rechte_demo                -- unverändert leer -- \dp kennt keinen Eigentümer!

-- Die Meldung, um die es im ganzen Dokument geht. Sie ist das Ziel, kein Fehler
-- des Skripts -- psql macht danach weiter. Die DETAIL-Zeile nennt das Objekt.
DROP ROLE sepp;

-- Der Eigentümer darf das Objekt ändern, der Nicht-Eigentümer nicht.
SET ROLE accounting;
ALTER TABLE rechte_demo ADD COLUMN probe int;   -- hier kommt eine Meldung: lies sie
RESET ROLE;

SET ROLE sepp;
ALTER TABLE rechte_demo ADD COLUMN probe int;   -- Eigentümer: geht
ALTER TABLE rechte_demo DROP COLUMN probe;
SELECT * FROM rechte_demo;                      -- auch lesen, ganz ohne GRANT
INSERT INTO rechte_demo (id, notiz) VALUES (2, 'vom Eigentuemer');
RESET ROLE;

-- Optional, weil es die Tabelle wirklich kostet -- nur der Eigentümer darf sie
-- löschen, auch dafür gibt es kein Grant:
--   SET ROLE sepp;  DROP TABLE rechte_demo;  RESET ROLE;

-- Gegenprobe: eine Rolle ohne Rechte kommt nicht an die Tabelle. (Auf einem
-- Schema ohne USAGE scheitert es früher und mit anderer Meldung -- schema public
-- hat PUBLIC das USAGE, siehe \dn+ in Abschnitt 1.)
SET ROLE accounting;
SELECT * FROM rechte_demo;                      -- permission denied for table ...
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 4) Die ACL lesen -- und was das erste GRANT anrichtet
-- ---------------------------------------------------------------------------

-- 5.8: "The first GRANT or REVOKE on an object will instantiate the default
-- privileges". Aus der leeren Spalte wird jetzt eine ausgeschriebene Liste:
-- der Eigentümer mit allen Rechten einer Tabelle (arwdDxtm) und accounting
-- mit dem einen r, das hier vergeben wird.
GRANT SELECT ON rechte_demo TO accounting;

\dp rechte_demo
-- Aufbau: Empfänger=Rechte/Geber. Leerer Empfänger = PUBLIC.

-- Dieselbe Zeichenkette aus dem Katalog, einmal als Liste und einmal zerlegt:
SELECT relname, relacl FROM pg_class WHERE relname = 'rechte_demo';

SELECT grantor, grantee, privilege_type, is_grantable
FROM aclexplode((SELECT relacl FROM pg_class WHERE relname = 'rechte_demo'));
-- grantee-OID 0 ist PUBLIC; is_grantable ist das "*" aus \dp.

-- Die Frage aus der anderen Richtung, ohne ACL-Lesen:
SELECT has_table_privilege('accounting', 'rechte_demo', 'SELECT');
SELECT has_table_privilege('accounting', 'rechte_demo', 'INSERT');

SET ROLE accounting;
SELECT * FROM rechte_demo;                      -- geht jetzt
INSERT INTO rechte_demo (id, notiz) VALUES (3, 'noch nicht erlaubt');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 5) Die drei Datenbankrechte: C, c, T
--
--    Hier wird es ernst: PUBLIC verliert CONNECT. Laufende Sitzungen merken
--    das nicht -- CONNECT wird beim Verbindungsaufbau geprüft. Deshalb gilt
--    auch hier: zweite Sitzung offen lassen (docker compose exec db psql ...).
-- ---------------------------------------------------------------------------

\l kurs
-- Ist "Access privileges" leer, ist die ACL NULL -- es gelten die Vorgaben
-- aus Abschnitt 1: PUBLIC hat T und c.

REVOKE CONNECT ON DATABASE kurs FROM PUBLIC;

\l kurs
-- Jetzt steht ein Eintrag da, der mit "=" beginnt (PUBLIC) -- und in ihm
-- fehlt das "c". Der Zustand davor ist damit eingefroren: die leere Spalte
-- kommt durch GRANT/REVOKE nicht zurück, auch wenn unten wieder dasselbe
-- dasteht.

GRANT CONNECT ON DATABASE kurs TO accounting;

\l kurs
-- accounting kann hinein (c), sepp nicht -- bis du es ihm ausdrücklich gibst.
-- Wer in der Kursumgebung mit fremden Rollen arbeitet: hier nicht vergessen.

-- ---------------------------------------------------------------------------
-- 6) WITH GRANT OPTION: weitergeben dürfen
-- ---------------------------------------------------------------------------

GRANT SELECT ON rechte_demo TO accounting WITH GRANT OPTION;
\dp rechte_demo                -- achte auf das "*" hinter dem Buchstaben

-- accounting gibt selbst weiter -- genau dafür ist die Option da. Der Geber
-- rechts vom "/" wechselt dadurch von dir zu accounting.
SET ROLE accounting;
GRANT SELECT ON rechte_demo TO sepp;
RESET ROLE;
\dp rechte_demo

-- Nur die Weitergabe zurücknehmen. 5.8: "If the grant option is subsequently
-- revoked then all who received the privilege from that recipient (directly or
-- through a chain of grants) will lose the privilege." -- CASCADE ist nötig,
-- sonst bricht der Befehl ab (RESTRICT ist die Vorgabe).
REVOKE GRANT OPTION FOR SELECT ON rechte_demo FROM accounting CASCADE;
\dp rechte_demo                -- was ist mit sepp passiert?

-- Und jetzt das Recht selbst. CASCADE auch hier, damit der Zustand eindeutig
-- ist: danach hält niemand mehr ein Recht auf der Tabelle.
REVOKE SELECT ON rechte_demo FROM accounting CASCADE;
\dp rechte_demo

-- Frage zum Selbernachsehen: lass beim nächsten Durchlauf einmal "CASCADE"
-- weg. Welche Meldung kommt -- und warum nennt sie sepp?

-- ---------------------------------------------------------------------------
-- 7) Gruppen als Eigentümer: die Lösung für das Problem aus Abschnitt 3
--
--    Objekte gehören Rollen ohne LOGIN, Personen sind nur Mitglieder.
-- ---------------------------------------------------------------------------

ALTER TABLE rechte_demo OWNER TO accounting;
\dt rechte_demo                -- Owner: accounting -- sepp kommt nicht mehr vor

-- Genau der Befehl, der in Abschnitt 3 gescheitert ist:
DROP ROLE sepp;
\du                            -- sepp ist weg, die Tabelle ist noch da

-- Sollte hier doch noch eine DETAIL-Zeile kommen, hält sepp noch ein Recht auf
-- einem fremden Objekt -- genau der Fall in Abschnitt 8a.

-- Zur Kontrolle, dass die Gruppe die Tabelle trotzdem noch bedienen kann:
SET ROLE accounting;
SELECT * FROM rechte_demo;     -- als Eigentümerin: ja
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 8) Aufräumen -- die Reihenfolge aus Abschnitt 21.4
--
--    REASSIGN OWNED überträgt Eigentum und berührt fremde Objekte nicht;
--    DROP OWNED nimmt zusätzlich die Rechte auf fremden Objekten weg.
--    In einer Umgebung mit mehreren Datenbanken: in JEDER wiederholen.
-- ---------------------------------------------------------------------------

-- 8a) Eigentum ist nur die eine Hälfte. accounting besitzt rechte_demo (7) --
--     und bekommt jetzt zusätzlich Rechte auf einem FREMDEN Objekt:

CREATE TABLE fremd_demo (id int);            -- gehört dir, nicht accounting
GRANT SELECT ON fremd_demo TO accounting;    -- Rechte auf einem fremden Objekt

DROP ROLE accounting;
-- Die DETAIL-Zeile kann mehrere Ursachen auflisten. Welche steht bei dir --
-- Eigentum, Rechte oder beides?

-- 8b) Also beide Schritte aus 21.4, in dieser Reihenfolge:
REASSIGN OWNED BY accounting TO :superuser;  -- Eigentum übertragen (rechte_demo)
DROP OWNED    BY accounting;                 -- Rechte auf fremden Objekten weg
DROP ROLE     accounting;                    -- jetzt geht es

DROP TABLE fremd_demo;

-- 8c) Zurück zur Ausgangslage. PUBLIC das CONNECT wiedergeben (Abschnitt 5).
--     Die Spalte in \l bleibt gefüllt -- vergleiche mit dem Zustand ganz oben.
GRANT CONNECT ON DATABASE kurs TO PUBLIC;

-- Endkontrolle: es sollte wieder aussehen wie am Anfang.
\du
\l
\dt
\dp

-- Die Übungstabelle wegwerfen, wenn du sie nicht mehr brauchst:
DROP TABLE rechte_demo;

-- ---------------------------------------------------------------------------
-- Wenn etwas hängt: die DETAIL-Zeile von DROP ROLE nennt das Objekt, das noch
-- an der Rolle hängt. Die Zuordnung "Meldung -> Abschnitt" steht in 27.9.
-- ---------------------------------------------------------------------------
