# 6 — Kurs-Notizen

Sammelstelle für alles, was aus der Schulung noch dazukommt.

*(Der Link aus der Arbeitsmail lässt sich noch nicht aufrufen — die weiteren
Inhalte kommen nach und nach hier hinein. Pro Thema wird ein eigenes Dokument
unter `docs/` angelegt und hier verlinkt.)*

Bereits als eigenes Dokument angelegt:

- [7 — Transaktionen, Sperren und Isolationsstufen](07-transaktionen-und-isolation.md)
- [8 — Timeouts: Anweisung, Transaktion, Sperre](08-timeouts.md)
- [9 — Verklemmungen: erkennen, protokollieren, vermeiden](09-verklemmungen.md)
- [10 — Warteereignisse: worauf wartet eine Sitzung wirklich?](10-warteereignisse.md)
- [11 — Indizes anlegen, ohne den Betrieb anzuhalten](11-indizes-im-betrieb.md)
- [12 — MVCC: Zeilenversionen, `xmin`/`xmax` und alte Werte](12-mvcc.md)
- [13 — Tote Zeilen, VACUUM und Bloat](13-vacuum-und-tote-zeilen.md)
- [14 — Konfiguration: wo Einstellungen stehen und wann sie wirken](14-konfiguration.md)
- [15 — REPACK: Tabelle neu schreiben statt `VACUUM FULL`](15-repack.md) — Ausblick, ab PostgreSQL 19
- [16 — Einen Ausführungsplan lesen](16-explain-analyze-plan-lesen.md)
- [17 — Nested Loop, Hash, Merge: welche Verbindungsmethode wann](17-join-methoden.md)
- [18 — Testdaten erzeugen: Werte statt Zähler](18-testdaten-erzeugen.md)
- [19 — Vom falschen Schätzwert zum parallelen Plan](19-schaetzung-und-parallele-plaene.md)
- [20 — Wiederherstellung: ganzer Server, ein Zeitpunkt, einzelne Objekte](20-sicherung-und-wiederherstellung.md)
- [21 — Streaming-Replikation: Primary, Standby, WAL sender](21-streaming-replikation.md)
- [22 — Logische Replikation: Publication, Subscription, Logical Decoding](22-logische-replikation.md)
- [23 — WAL und Haltbarkeit: die Schalter aus dem `# WRITE-AHEAD LOG`-Block](23-wal-und-haltbarkeit.md)
- [24 — Rollen und Rechte: wer darf was](24-rollen-und-rechte.md)
- [25 — Verbindungen von außen: `listen_addresses`, Port, `pg_hba.conf`](25-verbindungen-von-aussen.md)
- [26 — TLS: verschlüsselte Verbindungen (`ssl = on`, Zertifikate, `sslmode`)](26-tls-verschluesselte-verbindungen.md)
- [27 — Eigentümer, ACL und `GRANT OPTION`](27-eigentuemer-und-acl.md)

---

## Offene Punkte

- [ ] Weitere Kursinhalte ergänzen, sobald der Link erreichbar ist
- [ ] Eigene Messwerte eintragen (siehe unten)
- [ ] Teil 7 durchspielen: zwei Sitzungen, Sperren, Isolationsstufen
- [ ] Teil 17 durchspielen: die drei Methoden einmal erzwingen und vergleichen
- [ ] Teil 18 durchspielen: `adresse` einmal in Blöcken und einmal gemischt füllen, `pg_stats.correlation` vergleichen
- [ ] Teil 19 durchspielen: `CREATE STATISTICS` vorher/nachher messen
- [ ] Teil 20 durchspielen: Archiv einschalten, `pg_basebackup`, Unfall, zweite Instanz auf Port 5433
- [ ] Teil 20: eine einzelne Tabelle aus dem Dump zurückholen (20.2) und aus der wiederhergestellten Instanz kopieren (20.6, Schritt 7)
- [ ] Teil 20: den Kurs-Ablauf in-place nachvollziehen — einmal mit `rm -rf`, einmal mit `mv` — und notieren, was das Log jeweils sagt
- [ ] Teil 21 durchspielen: Standby als zweite Instanz auf Port 5433 aufsetzen, `pg_stat_replication` und `pg_stat_wal_receiver` vergleichen
- [ ] Teil 21: `pg_wal_replay_pause()` / `pg_wal_replay_resume()` und die Wirkung auf `replay_lag` beobachten
- [ ] Teil 21: ein `COMMIT` mit gesetztem `synchronous_standby_names` gegen den asynchronen Fall messen
- [ ] Teil 22 durchspielen: `wal_level = logical`, zweite Datenbank `kurs_abo`, Publication/Subscription aufsetzen
- [ ] Teil 22: `UPDATE`/`DELETE` ohne Replica Identity provozieren und die Meldung auf der Quelle finden
- [ ] Teil 22: `pg_logical_slot_peek_changes` gegen `pg_logical_slot_get_changes` vergleichen
- [ ] Teil 23 durchspielen: den WAL-Block mit der `pg_settings`-Abfrage aus 23.9 überblicken, `context` und `pending_restart` notieren
- [ ] Teil 23: 500 Zeilen mit `synchronous_commit = on` gegen `off` messen (Versuch 1) und beide Zeiten eintragen
- [ ] Teil 23: `wal_fpi` nach `CHECKPOINT` vor/nach einem `UPDATE` vergleichen — einmal über viele Zeilen, einmal über eine (Versuch 2)
- [ ] Teil 23: `wal_compression` setzen (Wert aus `pg_settings.enumvals`) und `wal_bytes` gegen den unkomprimierten Fall messen (Versuch 3)

---

## Eigene Messwerte

Ort: eigener Rechner · Datum: ____________________

| Abfrage | Zustand | Plan | Execution Time | gelesene Blöcke |
|---------|---------|------|----------------|-----------------|
| `WHERE id = 3999999` | ohne Index | | | |
| `WHERE id = 3999999` | mit Index | | | |
| `WHERE name = 'Kurs Nr. 123456'` | ohne Index auf name | | | |
| `WHERE name = 'Kurs Nr. 123456'` | mit Index auf name | | | |

| Einfügen | Dauer |
|----------|-------|
| 4 Mio. mit `generate_series` (ein Befehl) | |
| erster 100.000er-Block | |
| letzter 100.000er-Block | |

### Transaktionen (`konto`, Ausgangssumme 20000)

| Schritt | Summe innerhalb der Transaktion | Summe danach |
|---------|--------------------------------|--------------|
| halbe Überweisung, **ohne** `BEGIN` | — | |
| Überweisung in `BEGIN … COMMIT` | | |
| Überweisung in `BEGIN … ROLLBACK` | | |
| `ROLLBACK TO SAVEPOINT` nach einem Fehler | | |
| Summe in einer zweiten Sitzung, während die erste noch offen ist | | |

### Isolationsstufen (zwei Sitzungen)

| Experiment | Stufe | Sitzung A sieht | Sitzung B bekommt | SQLSTATE |
|------------|-------|-----------------|-------------------|----------|
| `SELECT sum()` zweimal, dazwischen bestätigt B ein `UPDATE` | `READ COMMITTED` | | | |
| derselbe Ablauf | `REPEATABLE READ` | | | |
| beide `UPDATE` dieselbe Zeile | `READ COMMITTED` | | | |
| beide `UPDATE` dieselbe Zeile | `REPEATABLE READ` | | | |
| A und B zeigen **gleichzeitig** verschiedene Summen (veralteter Wert) | `REPEATABLE READ` | | | |
| derselbe Versuch in **einer** Sitzung — Kontrolle | egal | kein Konflikt | — | — |
| beide lesen `sum()` und schreiben alle Zeilen | `SERIALIZABLE` | | | |
| zwei Transaktionen sperren zwei Zeilen in umgekehrter Reihenfolge | beliebig | | | |

| Sperre | Wert |
|--------|------|
| Wartezeit, bis ein blockiertes `UPDATE` weiterläuft | |
| `SHOW deadlock_timeout` | |
| wartende PID → blockierende PID (`pg_blocking_pids`) | |
| `state` des Blockierers (`active` / `idle in transaction`) | |

### Timeouts

| Einstellung | Vorgabewert auf diesem Server (`SHOW …`) | eigenes Ergebnis |
|-------------|------------------------------------------|------------------|
| `statement_timeout` | | bricht ab nach |
| `lock_timeout` | | bricht ab nach |
| `idle_in_transaction_session_timeout` | | Sitzung weg nach |
| `idle_session_timeout` | | Sitzung weg nach |
| `transaction_timeout` | | Sitzung weg nach |

| Frage | eigene Beobachtung |
|-------|--------------------|
| Zählt die Wartezeit auf eine Sperre in `statement_timeout` mit? | |
| Läuft `transaction_timeout` vor den beiden anderen ab? | |
| Was stand nach dem `idle_in_transaction_session_timeout` in `konto`? | |

### Verklemmungen

| Frage | eigene Beobachtung |
|-------|--------------------|
| gesetztes `deadlock_timeout` im Versuch | |
| Zeit bis `deadlock detected` | |
| SQLSTATE (`\set VERBOSITY verbose`) | |
| Log-Zeile im Container (`docker compose logs db`) — steht die Abfrage darin? | |
| `log_lock_waits`: Zeile nach welcher Wartezeit? | |
| `SKIP LOCKED`: was kam zurück, während die andere Sitzung sperrte? | |

### Warteereignisse

| Situation | `wait_event_type` | `wait_event` |
|-----------|-------------------|--------------|
| `SELECT pg_sleep(5);` läuft | | |
| Sitzung wartet auf die Zeilensperre aus 7.6 | | |
| Sitzung hält die Sperre (ist also nicht wartend) | | |
| `BEGIN` gesagt, dann nichts getan | | |
| Hintergrundprozess ohne `datname` | | |

| Frage | eigene Beobachtung |
|-------|--------------------|
| Welche `backend_type`-Werte haben keine `datname`? | |
| Steht bei der haltenden Sitzung (`SELECT FOR UPDATE …`) `Lock` / `transactionid`? | |

### Sperrmodi (`pg_locks`)

| Situation | `mode` | `granted` |
|-----------|--------|-----------|
| offener `SELECT` (Fenster A in 7.6c) | | |
| wartendes `ALTER TABLE` (Fenster B) | | |
| zwei `UPDATE` auf verschiedene Zeilen | | |

### Indizes im Betrieb

| Frage | eigene Beobachtung |
|-------|--------------------|
| Laufzeit `CREATE INDEX CONCURRENTLY` auf `kurs`, bis zum Abbruch | |
| Größe des `INVALID`-Index danach (`pg_indexes_size`) | |
| Plan nach dem Abbruch: `Seq Scan` oder `Index Scan`? | |
| Plan nach `DROP INDEX` + `ANALYZE` + neuem Build | |
| Wartezeit des Builds (erste Phase mit nur einem `kurs`, zweite mit offener Transaktion) | |

### MVCC (`xmin`, `xmax`, `ctid`)

| Schritt | `ctid` | `xmin` | `xmax` | `betrag` |
|---------|--------|--------|--------|----------|
| vor dem `UPDATE` | | | | |
| innerhalb der Transaktion (Fenster A) | | | | |
| nach `ROLLBACK` | | | | |
| nach `COMMIT` (der Vergleich) | | | | |

| Frage | eigene Beobachtung |
|-------|--------------------|
| `pg_current_xact_id()` deiner Transaktion | |
| `pg_xact_status(...)` dieses Werts nach dem Rollback | |
| Taucht die eigene Sitzung in `pg_snapshot_xip(pg_current_snapshot())` auf, während sie in einer Transaktion sitzt? | |

### VACUUM

| Messung | Wert |
|---------|------|
| `n_dead_tup` nach 1000 Änderungen | |
| `VACUUM VERBOSE konto` meldet: tote Zeilenversionen / Seiten | |
| davon „cannot be removed yet", solange Fenster A offen war | |
| `removable cutoff` aus dem Bericht | |
| `visibility map`: Seiten `all-visible` nach dem Lauf | |
| `WAL usage`: Bytes, die das Aufräumen gekostet hat | |
| `new relfrozenxid` und der Abstand zum vorherigen Wert | |
| `n_dead_tup` nach `VACUUM` | |
| `pg_relation_size('kurs')` vor dem `UPDATE` | |
| nach `UPDATE kurs SET name = name;` | |
| nach `VACUUM kurs` | |
| nach `VACUUM FULL kurs` | |
| `last_autovacuum` (falls vorhanden) | |
| `age(datfrozenxid)` in `pg_database` | |

### Autovacuum

| Frage | eigene Beobachtung |
|-------|--------------------|
| `SHOW autovacuum_vacuum_threshold` / `_scale_factor` / `naptime` | |
| Taucht `backend_type = 'autovacuum worker'` bei dir auf, wenn du 50.000 Änderungen machst? | |
| Wie lange nach den Änderungen war `last_autovacuum` gesetzt? | |
| Bleibt `n_dead_tup` hoch, wenn eine Transaktion offen steht? | |
| Was meldet `pg_stat_progress_vacuum`, während er läuft? | |

### Konfiguration

| Frage | eigene Beobachtung |
|-------|--------------------|
| `SHOW config_file;` — welcher Pfad? | |
| `context` und `source` von `autovacuum_max_workers` | |
| `pending_restart` nach `ALTER SYSTEM SET autovacuum_naptime` | |
| `source` von `work_mem` nach einem `SET` in der Sitzung | |
| Steht nach dem Aufräumen noch etwas auf `source <> 'default'`? | |

### REPACK (ab PostgreSQL 19)

| Messung | Wert |
|---------|------|
| `pg_total_relation_size('vactest')` frisch angelegt | |
| nach `UPDATE vactest SET id = id + 1;` | |
| nach `REPACK (ANALYZE) vactest` | |
| dasselbe über `VACUUM FULL` auf `vactest_full` | |
| `pg_indexes_size` vor und nach dem Neu-Schreiben | |
| `relfrozenxid` vor und nach dem Lauf — für beide Befehle | |
| Zeigt `\dt+` dieselbe Größe wie `pg_total_relation_size`? | |
| Meldet `pg_stat_progress_repack` bei `CONCURRENTLY` etwas? | |

### Pläne lesen (`EXPLAIN`)

| Frage | eigene Beobachtung |
|-------|--------------------|
| Größter Faktor zwischen geschätzter und tatsächlicher Zeilenzahl | |
| Knoten mit `loops > 1` — und seine Gesamtzeit (`actual time` × `loops`) | |
| `Buffers`: `hit` und `read` beim ersten und beim zweiten Lauf | |
| `Batches` im `Hash`-Knoten | |
| `Memory Usage` gegen `work_mem` | |
| Bleibt der `Seq Scan` mit `SET enable_seqscan = off` stehen? | |
| Laufzeitunterschied `TIMING ON` gegen `TIMING OFF` | |
| Blöcke in der Wurzel gegen die Summe ihrer Kinder | |

### Join-Methoden (`Nested Loop`, `Hash Join`, `Merge Join`)

| Frage | eigene Beobachtung |
|-------|--------------------|
| Methode für `thema` × `kurs_thema`, und welche Seite ist der `Hash`-Knoten? | |
| dieselbe Abfrage mit `enable_hashjoin = off` / `enable_mergejoin = off` | |
| dieselbe Abfrage nach `CREATE INDEX` auf `kurs_thema (thema_id)` + `ANALYZE` | |
| `loops` des inneren Knotens im erzwungenen Nested Loop, und `actual time` × `loops` | |
| `Memory Usage` und `Batches` im Hash-Knoten bei Vorgabe-`work_mem` | |
| dasselbe mit `work_mem = '64MB'` — fällt `Batches` auf 1? | |
| `Merge Join` erzwungen: `Sort`-Knoten vorhanden, mit und ohne Index auf `kurs_id`? | |
| `SHOW work_mem` — passt die Hash-Tabelle laut `Memory Usage` hinein? | |
| `Rows Removed by Join Filter` bei `thema a JOIN thema b ON a.id < b.id` | |
| Drei-Tabellen-Join (`kurs` → `kurs_thema` → `thema`): welcher Join-Knoten saß unter welchem, welche Methode hatte jeder — und wurde die `FROM`-Reihenfolge getauscht? | |
| Sind alle drei Methoden verboten — kommt trotzdem ein Plan, und zu welchem `cost`? | |

### Schätzung, Statistik und Parallelität (`adresse`)

| Messung | Wert |
|---------|------|
| `WHERE stadt = 1` — geschätzt / tatsächlich | |
| `WHERE stadt = 1 AND plz = 100` — geschätzt / tatsächlich | |
| dasselbe nach `CREATE STATISTICS … (dependencies)` — `rows`, `cost`, Zeit | |
| `GROUP BY stadt, plz` — geschätzte / tatsächliche Gruppenzahl | |
| dasselbe nach `… (ndistinct)` | |
| `SHOW parallel_setup_cost` gegen die Differenz `Gather` − Kindkosten | |
| `Workers Planned` / `Workers Launched` bei leerem Server | |
| dieselben zwei Zahlen, während andere Sitzungen arbeiten | |
| `max_parallel_workers_per_gather = 0`: Zeit über fünf Läufe, Streuung | |
| `Buffers: shared hit` im `Gather` und im `Seq Scan` — dieselbe Zahl? | |

### Wiederherstellung (Sicherung, WAL-Archiv, PITR)

| Messung | Wert |
|---------|------|
| `pg_size_pretty(pg_database_size('kurs'))` | |
| Größe des Dumps (`-Fc`) — und Dauer von `pg_dump` | |
| Größe des Base-Backups und Dauer von `pg_basebackup` | |
| Meldung von `pg_verifybackup` — und nach einer absichtlich veränderten Datei in `base` | |
| `archived_count` / `failed_count` in `pg_stat_archiver` vor und nach `pg_switch_wal()` | |
| Was passiert bei `archive_command` mit `exit 1`: wächst `pg_wal`? | |
| `last_failed_wal` und `last_failed_time` in `pg_stat_archiver` | |

| Frage | eigene Beobachtung |
|-------|--------------------|
| Erste Log-Zeile der Wiederherstellung, und die Zeile mit „recovery stopping" | |
| Erreichte LSN am Haltepunkt gegen die LSN aus `pg_create_restore_point()` | |
| `pg_is_in_recovery()` und `pg_last_xact_replay_timestamp()` vor und nach `pg_wal_replay_resume()` | |
| Ist der Stand nach `recovery_target_time` derselbe wie nach `recovery_target_name`? | |
| Was ändert `recovery_target_inclusive = off` bei einem `DELETE` in derselben Sekunde? | |
| Steht die Tabelle nach Schritt 7 wirklich mit denselben Zeilen in der laufenden Instanz? | |
| Was unterscheidet `pg_controldata` in `base` von dem in `restore`? | |
| Wiederherstellung `in-place` (Kurs): erreichtes Ziel laut Log gegen den notierten Zeitstempel | |

### Replikation (Standby, WAL-Streaming)

| Messung | Wert |
|---------|------|
| `SHOW wal_level;` / `SHOW max_wal_senders;` / `SHOW hot_standby;` | |
| Dauer von `pg_basebackup … -R` und Größe von `standby` | |
| erste Log-Zeile des Streamens (Segment, Sender) | |
| Abstand `sent_lsn` ↔ `replay_lsn` bei Ruhe / unter Last | |
| Dauer eines `COMMIT`, asynchron gegen `synchronous_standby_names` gesetzt | |
| `pg_wal`-Größe, solange ein ungenutzter Slot existiert | |

| Frage | eigene Beobachtung |
|-------|--------------------|
| `state` und `sync_state` in `pg_stat_replication` im Normalbetrieb | |
| Was passiert mit `replay_lag`, solange `pg_wal_replay_pause()` aktiv ist? | |
| `application_name` der Standby gegen den Eintrag in `synchronous_standby_names` | |
| Was steht im Log der Standby bei falschem `primary_conninfo` oder belegtem Port? | |
| Was meldet `pg_stat_wal_receiver` bei laufender vs. gestoppter Standby? | |
| Ändert `pg_promote()` den `status` in `pg_stat_wal_receiver`? | |

### Logische Replikation (Publication, Subscription, Slot)

| Messung | Wert |
|---------|------|
| Dauer der Startkopie (`copy_data`) und Zeilen im Ziel danach | |
| `srsubstate` in `pg_subscription_rel` während und nach der Kopie | |
| `confirmed_flush_lsn` des Slots vor/nach `pg_logical_slot_get_changes` | |
| `pg_wal`-Größe, solange ein Abonnement deaktiviert ist und der Slot bleibt | |
| Verzögerung Quelle → Ziel unter Last | |

| Frage | eigene Beobachtung |
|-------|--------------------|
| `wal_level` vor und nach dem Umstellen — was fordert `logical` zusätzlich? | |
| genaue Meldung bei `UPDATE` ohne Replica Identity — auf welcher Seite, und wann? | |
| `pg_stat_subscription_stats` vor/nach einem erzeugten Fehler | |
| Erscheint ein `COMMIT` mit mehreren Änderungen als eine Gruppe im `test_decoding`-Ausgang? | |
| Steht in `pg_stat_replication` etwas, wenn nur logisch repliziert wird? | |
| Was passiert mit den Zeilen im Ziel, wenn du auf der Quelle `TRUNCATE` machst? | |

### WAL-Schalter und Haltbarkeit (`fsync`, `synchronous_commit`, …)

| Messung | Wert |
|---------|------|
| `wal_level` / `fsync` / `synchronous_commit` / `wal_sync_method` (`SHOW …`) | |
| `context` und `pending_restart` der sieben Einstellungen aus 23.9 | |
| `enumvals` von `wal_compression` auf dieser Installation | |
| Dauer eines `INSERT` mit `synchronous_commit = on` / `= off` (Versuch 1) | |
| `wal_fpi`-Differenz nach `CHECKPOINT` — viele Zeilen geändert | |
| dieselbe Messung mit nur einer geänderten Zeile | |
| `wal_bytes`-Differenz mit / ohne `wal_compression` (Versuch 3) | |
| `pending_restart` nach `ALTER SYSTEM SET wal_level = 'logical'` | |

| Frage | eigene Beobachtung |
|-------|--------------------|
| Wirkt ein `pg_reload_conf()` nach `ALTER SYSTEM SET wal_level = …`? | |
| Ändert `wal_compression` die Zahl in `wal_fpi` oder nur die in `wal_bytes`? | |
| Warum fällt die `wal_fpi`-Differenz kleiner aus, wenn nur eine Zeile geändert wird? | |
| Steht in `source` bei den sieben Werten `default` oder `configuration file`? | |
| Was steht in deiner eigenen `postgresql.conf` an diesen sieben Zeilen — welche sind auskommentiert? | |

---

## Eigene Fragen

- [ ] …
