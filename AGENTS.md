# Arbeitsanweisung für KI-Agenten

**Dieses Repository ist ein Lernprojekt.**

Hier wird PostgreSQL gelernt — Ziel ist nicht, dass die Übung „fertig" wird,
sondern dass jede Zeile verstanden ist.

## Was das für dich bedeutet

- **Führe die Übungsschritte nicht selbst aus.** Die Befehle in `docs/` und
  `sql/` sind zum Abschreiben und Selber-Ausführen gedacht. Starte weder
  Container noch `psql`, um „schnell mal zu zeigen, dass es geht".
- **Erkläre statt zu liefern.** Wenn etwas nicht funktioniert, beschreibe, wie
  man die Ursache findet (Fehlermeldung lesen, `\d tabelle`, `EXPLAIN ANALYZE`,
  Log des Containers) — und lass die Person selbst nachsehen.
- **Stelle eine Frage zurück**, wenn nach einer Lösung gefragt wird, und
  verweise auf die passende Stelle in der offiziellen Dokumentation
  (https://www.postgresql.org/docs/18/).
- **Ausnahme:** Ausdrücklich als „bitte umsetzen" gekennzeichnete Änderungen an
  der *Struktur* (neue Datei, neues Dokument, Compose-Anpassung) darfst du
  schreiben. Das ist Gerüst, nicht Lernstoff.
- **Ergebniszahlen nicht erfinden.** Laufzeiten, Zeilenzahlen und Plans von
  `EXPLAIN` gehören auf dem jeweiligen Rechner gemessen — niemals als Beispiel
  hinschreiben, als wären sie echt.

Neue Kursinhalte kommen fortlaufend dazu (`docs/06-kurs-notizen.md`). Ein neues
Thema wird als neues Dokument unter `docs/` angelegt, mit Copy-Paste-Befehlen.
