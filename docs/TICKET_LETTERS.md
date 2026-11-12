# Ticket-Schreiben (Widerspruchsbrief · Kündigungsschreiben · Raten-Übersicht)

KlimaBilanz schreibt dir die Briefe, die ein KlimaTicket-Ö-Inhaber sonst selbst formulieren muss, und zeigt, was du schon bezahlt
hast. Alles entsteht auf dem iPhone; nichts wird gesendet, bis du den PDF-Brief selbst teilst oder druckst. **Keine Rechtsberatung** –
der Brief fasst zusammen, was in den AGB steht (einmal, leise, am Ende jedes Formulars gesagt).

Code: `Packages/KlimaCore/Sources/KlimaCore/TicketRights/` (reine Logik, Linux-Tests) und `App/Sources/Features/TicketRights/` (Screens).
Tests: `swift test --package-path Packages/KlimaCore --no-parallel --filter TicketRights`.

## 1. Was die App kann

| Screen | Wo | Für wen |
|---|---|---|
| **Widerspruchsbrief** (Sheet) | Ratgeber › Verlängern, Zeile „Widerspruchsbrief erstellen“ | KlimaTicket Ö mit SEPA-Verlängerung (`autoRenews`) |
| **Kündigungsschreiben** (Sheet) | Ratgeber › Kündigen, Zeile „Kündigungsschreiben erstellen“ | laufendes KlimaTicket Ö |
| **Raten-Übersicht** (Push) | Ratgeber › Verlängern, Zeile „Raten-Übersicht“ | KlimaTicket Ö mit monatlicher Zahlung |

Beide Briefe: Felder (Name, Straße, PLZ, Ort, Ticketnummer vom Ticket vorbelegt, Ort/Datum), die Empfängeradresse (aus den AGB, editierbar),
**Live-Vorschau als A4-Seite** (echter Text, kein Bild – VoiceOver liest Absatz für Absatz; „Bereit“-Stempel, wenn nichts mehr fehlt),
ein Hinweisblock mit den Regeln, **Als PDF teilen** (Share-Sheet, Datei „Widerspruch-KlimaTicket.pdf“ usw.) und **Drucken** (AirPrint).
Der Widerspruchsbrief hat zusätzlich **Erinnerung setzen** (siehe §3). „Name und Adresse merken“ (Standard **aus**) legt beides im Schlüsselbund
ab (`KeychainStore`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: nicht synchronisiert, nicht in Backups auf andere Geräte).
Die Frist aus dem Verlängerungsbrief wird je Ticket in `UserDefaults` gemerkt (nur ein Datum, `letters.deadlines.v1`).

Die Briefe sind in der Sie-Form (Brief an ein Unternehmen), die App spricht dich mit „du“ an. Keine Logos, kein Briefkopf, kein Ticketverkauf.

### Der Widerspruchsbrief nennt

Absender, Empfänger, Ort/Datum, Betreff mit Ticketnummer; Produkt, Ticket-/Vertragsnummer, Ablaufdatum; den Widerspruch gegen die Verlängerung nach
den Punkten 17.4 und 20.1 (Stand 1.1.2026); dass er innerhalb der Frist des Einladungsschreibens erfolgt (Datum, das du eingibst); die Folge nach 20.1
(kein neuer Vertrag, SEPA-Mandat wird storniert); die Bitte um **schriftliche Bestätigung**. Der Text steht als Golden-Test
(`TicketRightsObjectionLetterTests.testGoldenLetterOfTheDemoTicket`): eine Textänderung ist eine bewusste Änderung, gegen die AGB gelesen.

- Einmalzahlung: der Screen sagt „Du musst nichts tun – ohne Zahlung verlängert sich das Ticket nicht.“
- Regionales oder eigenes Ticket: „Für dein Ticket gelten die Bedingungen des Verkehrsverbunds – dieses Schreiben passt nicht.“
- Eine **vergangene Frist** blockiert den Brief (er würde behaupten, fristgerecht zu sein); PDF/Druck sind erst möglich, wenn nichts fehlt.

### Das Kündigungsschreiben

- **Ohne Grund** (AGB 17.1) erst ab dem 7. Gültigkeitsmonat. Verfügbarkeit, Monat, Datum und Entgelt kommen aus dem Ratgeber
  (`TicketAdvisor.cancellationPolicy` und `cancellationAdvice`): die Briefe rechnen nichts selbst. Die Entgeltzeile ist der eine Monatsbetrag
  aus der Quote (Klassik € 116,70; AGB Anhang 4: 116,70 / 87,50 / 128,30 / 99,20 – im Test geprüft).
- **Vor Monat 7** gibt es nie einen „ordentlichen“ Brief: der Screen nennt das Datum, ab dem es geht, und bietet nur die Gründe nach 17.2.
- **Wichtiger Grund** (AGB 17.2): Umzug ins Ausland (Nachweis der neuen Adresse), Krankheit ab drei Monaten (ärztliches Attest, keine Diagnose im Brief),
  Arbeitslosigkeit (Arbeitslosenbestätigung). Der Brief nennt Grund, **vier-Wochen-Frist** (ab dem Tag, an dem der Grund vorlag, den du wählst;
  Fristende wird gerechnet), „Als Nachweis liegt bei: …“, entfallendes Entgelt. Liegt der Grund in der Zukunft oder länger als vier Wochen zurück, ist der Brief blockiert.
- Die Kennenlern-Aktion 2026 (Start 1.5.–30.6.2026, kündbar ab Monat 2, kein Entgelt) kommt aus `TicketAdvisor`; sie steht **nicht** in der AGB, sondern in einer
  Pressemitteilung des Ministeriums – der Brief nennt deshalb „Kennenlern-Aktion 2026“ und keine Klausel.
- Die AGB verlangen für eine wirksame Kündigung das **Kündigungsformular** mit eigenhändiger Unterschrift und die **nachweisliche Rückgabe der Karte** bei einer
  Servicestelle (17.1/17.2). Das Schreiben ersetzt das Formular **nicht**; der Hinweisblock und der Brief („Kündigungsformular liegt bei“) sagen das.
  Bei Einmalzahlung steht im Brief eine handschriftliche IBAN-Zeile (die App fragt nach keiner IBAN).

### Raten-Übersicht

12 Raten (AGB 15.2): die ersten zwei mit der Bestellung, die übrigen zehn in den ersten fünf Werktagen eines Monats (angezeigt als „rund um den Monatsanfang“).
Zeigt **Bezahlt bis heute € X (n Raten)**, **Noch offen € Z** und daneben **Nutzen der Fahrten bis heute € Y** (Wert der erfassten Fahrten, `SavingsSummary.totalValue`),
dazu eine ehrliche Aussage, ob die Fahrten die Raten schon decken. Die Zahlenlogik (`InstallmentPlan`) ist getestet: 12 Raten, Summe = Ticketpreis auf den Cent
(elf Raten auf den Cent gerundet, die zwölfte gleicht aus), zwei mit der Bestellung im Monat 1.

Annahmen, die im Screen stehen: als bezahlt zählt eine Rate erst **nach** den ersten fünf Werktagen ihres Monats (Mo–Fr, Feiertage nicht berücksichtigt);
bei einer automatischen Verlängerung buchen sie alle zwölf monatlich (AGB 15.6) – der Unterschied liegt nur im ersten Gültigkeitsmonat und ist nicht abgebildet;
ein Zuschuss des Arbeitgebers ist nicht abgezogen.

## 2. Quelle: die AGB, Punkt für Punkt gelesen

Gelesen am 12.11.2026 im PDF `https://www.klimaticket.at/wp-content/uploads/2026/01/KTOE_AGB_260101.pdf` (4 Seiten, „Stand 1.1.2026“):

| Punkt | Was dort steht | Wo die App es nutzt |
|---|---|---|
| **15.2** | SEPA monatlich: erste zwei Monatsraten sofort bei der Bestellung, Rest in **zehn gleichen Monatsraten innerhalb der ersten fünf Werktage jedes Kalendermonats** | `InstallmentPlan` |
| **15.6** | Bei Vertragserneuerung per SEPA: **zwölf gleiche Monatsraten** innerhalb der ersten fünf Werktage jedes Kalendermonats | Fußnote der Raten-Übersicht |
| **17.1** | Kündigung ab dem **siebenten Gültigkeitsmonat** ohne Gründe, **schriftlich mittels Kündigungsformular**; wirksam mit eigenhändig unterfertigtem Formular **und nachweislicher Rückgabe des Tickets bei einer Servicestelle**; Kündigungsentgelt **ein Monatsbetrag = ein Zwölftel des Kaufpreises** (Anhang 4); SEPA: letzter Monatsbetrag wird als Entgelt abgebucht, nicht angefangene Monate nicht mehr; Einmalzahlung: nicht angefangene Monate abzüglich Entgelt überwiesen | `CancellationLetter` (ordentlich) |
| **17.2** | Außerordentlich: Umzug ins Ausland (Nachweis neue Adresse), Krankheit ≥ 3 Monate (ärztliches Attest), Arbeitslosigkeit (Bestätigung); Ticket **und** Formular **innerhalb von vier Wochen nach Vorliegen des Grundes** bei einer Servicestelle; **kein Kündigungsentgelt** | `CancellationLetter` (außerordentlich), `FilingWindow` |
| **17.4** | Bei SEPA-Mandat kann der Verlängerung **innerhalb der im Einladungsschreiben angegebenen Zahlungsfrist** schriftlich widersprochen werden; **mit eigenhändiger Unterschrift**, per Post („empfohlen wird per Einschreiben“) an **KlimaTicket Kundenservice, Postfach 100, 1020 Wien**, per Kontaktformular (mit eingescannter Unterschrift) oder nachweislich bei einer Servicestelle | `RenewalObjectionLetter`, `LetterRecipient.kundenservice` |
| **20.1** | Einladung 2 Monate vor Ablauf; SEPA: automatische Verlängerung um zwölf Monate, **wenn nicht innerhalb der im Einladungsschreiben angegebenen Widerspruchsfrist schriftlich widersprochen wird** (Post/Einschreiben oder Kontaktformular); bei Widerspruch **kommt kein neuer Vertrag zustande, das SEPA-Mandat wird storniert**; Einmalzahlung: Verlängerung nur durch Einzahlung des Zahlscheins | Brief, Hinweise, „Du musst nichts tun“ |
| 18.1 | Erstattung vor dem ersten Gültigkeitstag gebührenfrei (Rückgabe bei Servicestelle) | Hinweis „Dein Ticket gilt noch nicht“ |

**Empfängeradresse.** „KlimaTicket Kundenservice, Postfach 100, 1020 Wien“ steht in 15.4, 17.4, 18.3, 18.5 und 20.1 gleichlautend: eindeutig, eine Konstante
(`LetterRecipient.kundenservice`, zitiert „AGB 17.4 und 20.1“). Trotzdem ist das Feld **editierbar** und der Hinweis sagt: nennt dein Verlängerungsbrief eine andere
Adresse, nimm diese (Platzhalter bei leerem Feld: „Adresse laut deinem Verlängerungsbrief“; Knopf „Adresse aus den AGB einsetzen“).

### Abweichungen von der Planvorgabe (bewusst, der Ehrlichkeit wegen)

1. Der Plan formulierte den Hinweis: „… muss der Widerspruch schriftlich und unterschrieben **bis zur Frist im Brief eintreffen**“. Die AGB sagen das nicht:
   17.4 und 20.1 verlangen den Widerspruch „**innerhalb** der … Frist“ und sprechen vom „Senden“; ob **Absende- oder Eingangsdatum** zählt, steht dort nicht
   (bei einem Widerruf nach 18.3 dagegen schon: Absenden genügt). Der Hinweis sagt deshalb: schriftlich, mit eigener Unterschrift, innerhalb der Frist; unklar, welches
   Datum zählt; also eingeschrieben senden, so früh, dass er sicher vor Fristende ankommt, Beleg aufheben. Dazu die erlaubten Alternativen (Kontaktformular, Servicestelle).
2. 17.4 nennt die Frist „Zahlungsfrist“, 20.1 „Widerspruchsfrist“ – gemeint ist dieselbe Frist des Einladungsschreibens. Das Feld heißt „Frist laut deinem Brief“.
3. 17.1/17.2 verlangen das Kündigungsformular; das Schreiben ersetzt es nicht (siehe oben).
4. Der Plan nannte für die Raten nur 15.2 (zwei sofort + zehn); für Verlängerungen gilt 15.6 (zwölf monatlich).

## 3. Erinnerungen (Widerspruchsbrief)

„Erinnerung setzen“ plant zwei lokale Mitteilungen **5 Tage und 1 Tag vor der Frist, 9:00 Uhr (Wien)**, Kennungen `letter.<ticket-id>.d5` / `.d1`
(`LetterDeadline`, `LetterReminders`). Die Erlaubnis für Mitteilungen wird erst beim Tippen gefragt. Vergangene Zeitpunkte werden übersprungen
(Frist in 3 Tagen: nur die 1-Tage-Erinnerung; Frist heute oder vorbei: keine). Ändert sich die Frist, ziehen die Erinnerungen mit; „Erinnerung entfernen“ nimmt sie zurück.
`AlarmIdentifier.letterPrefix = "letter."` gehört zur Art `objectionLetter`; beide Erinnerungen sind **eine Zeile** unter Einstellungen › Alarme. Ein Tipp auf die Mitteilung öffnet den Ticket-Tab.

## 4. PDF

`LetterPDF` (`LetterPDF.swift`) zeichnet mit `UIGraphicsPDFRenderer` (RepPDFRenderer bleibt unberührt): A4, echter Text (auswählbar in Dateien/Vorschau), Dokumenttitel,
Autor = dein Name, Ersteller „KlimaBilanz <Version>“. Die Seitenmaße teilen sich `LetterLayout` mit der Bildschirm-Vorschau (`LetterPaper`), daher gleiche Textstellen.
Der Text fließt; ein Block, der nicht mehr passt, beginnt eine zweite Seite (die heutigen Briefe passen auf eine Seite).

## 5. Demo und Screenshots

`-KBDemo YES -KBScreenshot <name>` (`TicketLettersScreenshotHost`; fiktive Person „Maria Beispiel, Musterweg 1, 1234 Musterstadt“):
`lettersObjection`, `lettersObjectionPreview`, `lettersReminder`, `lettersEmptyAddress`, `lettersCancellation`, `lettersCancellationPreview`, `lettersExtraordinary`,
`lettersCancellationEarly`, `lettersInstallments`, `lettersInstallmentsList`, `lettersEntry`, `lettersCancelEntry`, `lettersAX5`, `lettersAX5Preview`,
`lettersPDF`, `lettersPDFExtra` (das PDF des Widerspruchs und des längsten Kündigungsbriefs, mit `LetterPDF` gezeichnet, mit PDFKit zurückgelesen: Seitenzahl,
auslesbarer Text, Titel, Seite 1 – der CI-Beleg, dass es ein echtes Dokument mit Text ist).

AX5: Die Aktionen („Als PDF teilen“, „Drucken“) stehen bei Bedienungshilfen-Schriftgrößen am Ende des Formulars statt unten angeheftet (sie würden sonst die halbe Seite füllen).

## 6. Nicht in CI prüfbar (Gerät / Mensch)

- Druckdialog und AirPrint, Aussehen des PDF in anderen Betrachtern, ob Dateien/Vorschau den Text auswählbar zeigen.
- **Ob die Kundenservice-Adresse und die Fristformulierung im eigenen Einladungsschreiben mit der AGB übereinstimmen** – ein Mensch muss den echten Brief mit dem Hinweis vergleichen.
- Zustellung der Mitteilungen (Erlaubnis, Fokus-Modi), Erscheinen in Alarme auf dem Gerät.
- Wann genau die Bank die Raten bucht (die Übersicht nimmt „nach den ersten fünf Werktagen“ an).
- Schlüsselbund-Verhalten von „Name und Adresse merken“ (`…ThisDeviceOnly`) auf einem echten Gerät mit/ohne Backup-Wiederherstellung.

Geräte-Checkliste: Widerspruchsbrief ausfüllen → „Als PDF teilen“ → in Dateien öffnen (Text markierbar?) → Druckvorschau → „Erinnerung setzen“ → unter Einstellungen › Alarme
erscheint eine Zeile „Morgen/In 5 Tagen endet deine Widerspruchsfrist“.
