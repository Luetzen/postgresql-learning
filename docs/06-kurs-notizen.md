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

---

## Offene Punkte

- [ ] Weitere Kursinhalte ergänzen, sobald der Link erreichbar ist
- [ ] Eigene Messwerte eintragen (siehe unten)
- [ ] Teil 7 durchspielen: zwei Sitzungen, Sperren, Isolationsstufen
- [ ] Teil 17 durchspielen: die drei Methoden einmal erzwingen und vergleichen
- [ ] Teil 18 durchspielen: `adresse` einmal in Blöcken und einmal gemischt füllen, `pg_stats.correlation` vergleichen
- [ ] Teil 19 durchspielen: `CREATE STATISTICS` vorher/nachher messen

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

---

## Eigene Fragen

- [ ] …
