# 6 — Kurs-Notizen

Sammelstelle für alles, was aus der Schulung noch dazukommt.

*(Der Link aus der Arbeitsmail lässt sich noch nicht aufrufen — die weiteren
Inhalte kommen nach und nach hier hinein. Pro Thema wird ein eigenes Dokument
unter `docs/` angelegt und hier verlinkt.)*

Bereits als eigenes Dokument angelegt:

- [7 — Transaktionen, Sperren und Isolationsstufen](07-transaktionen-und-isolation.md)
- [8 — Timeouts: Anweisung, Transaktion, Sperre](08-timeouts.md)

---

## Offene Punkte

- [ ] Weitere Kursinhalte ergänzen, sobald der Link erreichbar ist
- [ ] Eigene Messwerte eintragen (siehe unten)
- [ ] Teil 7 durchspielen: zwei Sitzungen, Sperren, Isolationsstufen

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

---

## Eigene Fragen

- [ ] …
