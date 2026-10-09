# KlimaBilanz – Design Spec „Alpine Glass“

> Gewinner des Design-Wettbewerbs (3 Richtungen, 3 unabhängige Juroren, einstimmig: Alpine Glass 50 · Rail Editorial 49 · Vivid Eco 46),
> ergänzt um die übereinstimmenden Verbesserungen der Jury. **Finale Referenz-Mockups (nach Jury-Synthese): `docs/design/final/*.jpg`**
> (Übersicht `00-overview.jpg`), ausführliche Synthese-Spezifikation: `docs/DESIGN_FINAL_SYNTHESIS.md`. Ursprüngliche Konzepte: `docs/design/concepts/alpine-glass/*.jpg`
> (Ideen aus `rail-editorial/` und `vivid-eco/` sind unten explizit übernommen). Tokens & Komponenten: `docs/DESIGN_SYSTEM_API.md`.

## 1. Konzept – „Dein Weg zum Gipfel“

Amortisation ist ein Aufstieg auf einen Arlberg-Gipfel. **Der Ticketpreis ist der Gipfel, der Break-even der Tag, an dem du die Fahne
hissst.** Danach führt der Weg in die grüne **Gewinnzone** – jede weitere Fahrt ist Gewinn.

- Jeder Screen liegt auf einem lebendigen Alpenhimmel (`AmbientBackground`): hell „Morgendämmerung“ (Gletscherblau → Morgenrot hinter
  dem Gipfel → Talnebel), dunkel „Blaue Stunde“ (Navy, Indigo, Alpenglühen, Sterne).
- **Luxus-Signal = Typo-Kontrast:** eine riesige, ultraleichte SF-Pro-Rounded-Zahl (73 %) wie die Temperatur in Apple Wetter, dazu ruhige
  SF-Pro-Labels und gesperrte Großbuchstaben-Eyebrows.
- Das Motiv wiederholt sich: Übersicht (Gipfel-Hero), Statistik (Ticketpreis als gestrichelte „Gipfellinie“, Gewinnzone), Ticket
  (Topo-Linien, Holo-Folie), Fahrt erfassen („Danach 77 % amortisiert“), Onboarding (Gipfelszene), App-Icon, Widgets.
- Sprache: österreichisches Deutsch, Du-Form, warm („Servus-Wärme“), „Jänner“, „Öffis“, „Bim“. Beträge `€ 1.400`, `€ 23,50`.

## 2. Glas-Regeln (HIG, Performance)

- **Liquid Glass (`glassEffect`, `.buttonStyle(.glass/.glassProminent)`) nur für Bedienelemente:** Tab-Leiste, Toolbar-Kreise, Chips,
  Segment-Controls, schwebende Pillen („Heute“, Toasts), der „+“-Slot.
- **Inhaltskarten** über dem Himmel: `GlassCard` / `.frostedCard()` (Material + spekularer Rand + weicher Schatten) – nie Glas auf Glas.
- **Sheets/Formulare:** ruhige gruppierte Flächen (`Theme.sheetBackground`, `List(.insetGrouped)` oder `SurfaceCard`), kein Himmel-Mesh
  voll deckend – höchstens blass.
- Max. eine animierte Ebene (der Himmel) pro Screen; Charts auf ruhigen Flächen.

## 3. Tokens (Kurzfassung – Werte in `Shared/Theme.swift`)

| Rolle | Hell | Dunkel |
|---|---|---|
| glacier (Primär, Tint) | `#2A7BD4` | `#7CC4FF` |
| dawn (Gipfel, Break-even, Ticketpreis) | `#F08A5B` | `#FFAD85` |
| pine (Gewinn, CO₂, „auf Kurs“) | `#23876A` | `#6BD6A9` |
| dusk (Routen-Mitte, Kletterer) | `#7A6FE0` | `#A99FFF` |
| alpenglow (Rosé-Akzent) | `#E86C8A` | `#FF8FAB` |
| gold (Favorit, Erfolge) | `#E2A93B` | `#F5C25B` |
| ink / ink2 / ink3 | `#0C1A2B` / 62 % / 40 % | `#F3F7FC` / 66 % / 42 % |
| background | `#E6ECF3` | `#08132A` |

- **Verkehrsmittel (immer mit Icon + Label):** Zug Gletscher `#2F7FDA`, S-Bahn Bergsee `#1FA9B8`, Bus Morgenrot `#F0904F`,
  Bim Dämmerung `#8673E6`, U-Bahn Alpenglühen `#E0628A`, Seilbahn Zirbe, Schiff Türkis.
- **Kleiner Text in Akzentfarbe nur mit `positiveText` / `summitText` / `accentText` (≥ 4,5 : 1).** Sonst Akzente nur als Flächen/große Zahlen.
- Route/Fortschritt: `Theme.routeGradient` (glacier → dusk @55 % → dawn). CTA: `Theme.ctaGradient`.
- Typo: Hero 112–130 pt Rounded UltraLight (bei Fettschrift/Kontrast: Regular; hell: Light), Preis-Zahl 46 Light Rounded, Large Title 34 Bold,
  Eyebrow 12,5 Semibold UPPERCASE +1.06, Section 20 Bold, Stat-Werte 30/18 Bold Rounded, alle Zahlen `monospacedDigit` + `.numericText`.
- Abstände: 4er-Raster; Screen-Rand 20 (Text) / 16 (Karten); Kartenabstand 10–12; Sektionsabstand 18–24.
- Radien (continuous): Modus-Kachel 12, Chip Kapsel, Karte 26–28, Formgruppe 24, Ticket 30, Sheet 38.

## 4. Komponenten

Siehe `docs/DESIGN_SYSTEM_API.md`. Signatur: `AmortizationHero` (Zahl + Klartext-Urteil + `SummitChart`), `SummitChart`
(Bergkamm, Route, Meilenstein-Hütten 25/50/75 %, Gewinnzone, Fahne), `TicketCard` (Begleitkarte), `StatTile`, `TripRow`, `ModeIcon`,
`Chip`, `ProgressRail`, `RouteGlyph`, `EmptyStateView`, `BreakEvenCelebration`, `ConfettiView`, `ToastOverlay`, `AuthButtonStack`.

**Verkehrsmittel-Plaketten (aus Rail Editorial):** kleine Kapsel-Badges mit Kategorie (`RJX`, `REX`, `S`, `U`, `Bus`, `Bim`) als
sekundäres Badge neben dem farbigen Modus-Icon in Zeilen und Favoriten – nur wenn bekannt (Zug ohne Kategorie → kein Badge).

## 5. Screens

### 5.1 Übersicht (Tab 1)
Oben → unten (Mockup `alpine-glass/01-dashboard-*.jpg`):
1. **Header:** Eyebrow „FREITAG, 9. OKTOBER“ über dem Large Title „Übersicht“ (eigener Header, nicht der Nav-Bar-Titel), rechts
   Toolbar-Kreise: Avatar (Initialen, öffnet Einstellungen). Kein Streak-Flammen-Badge.
2. **Ticket-Pille** (Glas-Kapsel): `🎫 KlimaTicket Ö Klassik · noch 143 Tage` → wechselt zum Ticket-Tab.
3. **Hero `AmortizationHero`:** riesige Zahl „73 %“; darunter **Klartext-Urteil** „Noch € 354 bis zum Break-even“ (Betrag in Akzent)
   bzw. nach dem Break-even „✓ Rentiert seit 14. Dez. · + € 412 gespart“; Zeile „€ 946 von € 1.400 amortisiert“; Gipfel-Grafik
   (~15 % flacher als im Mockup, damit 2 letzte Fahrten über der Tab-Leiste sichtbar bleiben).
4. **Bilanz-Karte** (eine Karte, beantwortet die Frage): links „NOCH BIS ZUM GIPFEL € 354 · ≈ 15 Fahrten“, rechts
   „BREAK-EVEN · PROGNOSE 14. Dez. · in 66 Tagen“ + `✓ 48 Tage vor Ablauf` (pine) – oder Warnung „Bei deinem Tempo: € 1.180 bis Ablauf“;
   darunter 4 Mini-Stats (Fahrten · km · CO₂ · Auto). Auto-Stat als **eigene positive Aussage**: „€ 2.406 mit dem Auto“ +
   „günstiger als Auto seit 18. Juli“ (nie im Widerspruch zum Haupturteil). Bei großer Schrift: 2×2-Raster (ViewThatFits).
   **Tempo-Pille** (Glas): „Schneller als nötig · + € 370 vor Plan“ bzw. „Etwas hinter Plan · – € 120“ (Wert-% vs. Zeit-%).
5. **Schnell erfassen:** horizontale Favoriten-Chips (Modus-Icon + Badge + „St. Anton → Innsbruck“ + € + runder „+“-Knopf, 1 Tap =
   erfasst + Haptik + Toast); sauber angeschnitten mit `contentMargins` + `scrollTargetBehavior(.viewAligned)`, kein abgeschnittener Preis.
   Kein doppelter „Neue Fahrt“-Knopf (der „+“-Slot der Tab-Leiste reicht); bei 0 Favoriten ein Hinweis-Chip „Favorit anlegen“.
6. **Vorschläge** (automatische Fahrterkennung) – nur wenn vorhanden.
7. **Letzte Fahrten** (5) in einer Karte mit `TripRow`, „Alle“ → Fahrten-Tab.
8. **Nächster Erfolg** (kompakte Zeile, öffnet „Gipfelbuch“) und **„Diese Woche“** (Fahrten & Wert vs. Vorwoche).
Leerzustand: Gipfelszene mit 0 % und „Erste Fahrt erfassen“.

### 5.2 Fahrt hinzufügen (Sheet, `.large`)
Mockup `alpine-glass/02-add-trip.jpg`, Sheet-Hintergrund blass, Formgruppen ruhig:
- Toolbar: ✕ (`.cancellationAction`) und Titel. **Kein zweites ✓** – gespeichert wird über den unteren Button.
- Favoriten-Chips (Stern) oben.
- Routen-Karte: Von/Nach mit `RouteGlyph`, Stationsname (18 Semibold) + „Bahnhof · Tirol“, Tausch-Knopf (Glas-Kreis, 180°-Rotation,
  Labels mit matchedGeometry). **Routen-Meta** darunter: „Zug · 101 km“ (+ „ca. 1 h 13 min“ nur falls bekannt – nicht erfinden).
- Verkehrsmittel-Wahl: Chips/Segmente in einem `GlassEffectContainer`, Auswahl-Kapsel gleitet (matchedGeometry/glassEffectID),
  erkennbare S/U-Badges.
- Datum & Uhrzeit (kompakte Picker-Pillen).
- **Preis-Karte:** Eyebrow „NORMALPREIS“ + ⓘ (Popover: Copy.fareExplanation), große Zahl `€ 23,50` „pro Richtung“, Erklärung
  („ÖBB-Standardticket 2. Kl. · Tarif ab 14.12.2025“), Badge „Offizieller ÖBB-Preis“ bei exaktem Tabellenpreis, „Anpassen“ →
  Inline-Feld; Aufschlüsselung „2 × € 23,50 · Hin + Rück“ bei Retour; 2. Kl./1. Kl. + Vorteilscard.
- Hin- und Rückfahrt (Toggle „Wert wird verdoppelt“), Mitfahrende (nur Familie), Notiz, „Als Favorit speichern“.
- **Wirkung:** „Danach 77 % amortisiert“ mit „73 → 77 %“ und „+ 3,8 % · + € 47,00“; neues Segment leuchtend/gestreift auf der Leiste.
- Unten (safeAreaInset): `Fahrt speichern · € 47,00` (CTA-Verlauf). Erfolgs-Haptik, Toast, bei Gipfelüberschreitung Feier.

### 5.3 Fahrten (Tab 2) & Fahrt-Detail
- Large Title „Fahrten“, Zusammenfassung (Fahrten · km · Wert) für das gewählte Ticketjahr, Suche, Modus-Filter-Chips.
- Liste nach Monaten (Header „Oktober 2026 · € 186“), **Zeilen-Layout aus Rail Editorial:** links gestapelt „HEUTE / 07:12“
  (Eyebrow + Zeit), vertikale 2-Stopp-`RouteGlyph`, Stationen, rechts Badge + Betrag; Wischen: Löschen / Nochmal / Favorit.
- Detail: Routen-Hero (Von → Nach, Modus, Datum), großer Wert, Kacheln (Distanz, CO₂, € pro km, Anteil am Ticket), Karte (MapKit,
  Marker + Linie), Preis-Erklärung, Notiz, Aktionen (Bearbeiten, Nochmal fahren, Als Favorit, Löschen).

### 5.4 Statistik (Tab 3)
Mockup `alpine-glass/03-statistik.jpg`:
- Eyebrow „TICKETJAHR 2026/27“, Large Title, Teilen-Kreis (Bilanz-Teilkarte), Ticketjahr-Wahl.
- **Ersparnis-Verlauf:** Fläche glacier→0, Linie glacier→dusk; Ticketpreis als gestrichelte **Gipfellinie** (dawn) „Ticketpreis € 1.400“;
  schraffierte **Gewinnzone** darüber (beschriftet); Prognose gepunktet mit Endlabel „Prognose € 2.040“; „HEUTE“-Punkt; Break-even-
  Fahne mit Glas-Pille „⚑ 14. Dez.“; Pine-Gewinnkeil nach dem Break-even; Scrubbing mit Callout.
- **Monatsbilanz:** ganzes Ticketjahr, gestrichelte Prognose-Balken für kommende Monate, laufender Monat teilweise, „Ø“-Linie und
  „Soll € 117“ (Ticketpreis ÷ 12) als Referenz, bester Monat dawn→dusk.
- **Verkehrsmittel:** kleiner Donut + **direkt beschriftete horizontale Balken** „Zug 59 · 68 %“ (nicht nur Farbe).
- **Reise-Kalender:** Heatmap mit einfarbiger Helligkeitsrampe (glacier), heute mit dawn-Rand, Zukunft gestrichelt; Fußzeile
  „87 Fahrten · 50 Reisetage · Längste Serie 9 Tage“.
- Wochentage, Top-Strecken, Rekorde (Bundesländer-Chips), „Welches Ticket lohnt sich?“, Auto & CO₂ (mit Äquivalenten, „ca.“),
  effektive Kosten (€/Fahrt, €/km, €/Tag).

### 5.5 Ticket (Tab 4)
Mockup `alpine-glass/04-ticket.jpg`:
- Eyebrow „GÜLTIG BIS 28. FEBRUAR 2027“, Large Title „Ticket“.
- **`TicketCard` = Begleitkarte · kein Fahrschein** (kein QR/Aztec, kein „Vorzeigen“): Themen-Verlauf, Topo/Guilloché-Linien,
  Holo-Siegel & Folie folgen der Neigung, Perforation; Tippen dreht zur Rückseite mit dem Foto des echten Tickets (PhotosPicker)
  oder Hinweis „Foto deines Tickets hinzufügen“.
- **Gültigkeit:** große Zahl „142 Tage übrig“, Pille „Tag 223 von 365“, Leiste Start → Heute → Ende mit **Break-even-Fahne** darauf.
- Erinnerungen (30/7/1 Tage, „Jänner“), Zahlungsart monatlich (bisher bezahlt n/12), Verlängern-Karte (≤ 45 Tage).
- Details: Ticketart, Preis, € pro Monat, **„Kosten pro Tag € 3,84“**, **„Pro Fahrt bisher € 14,94 ↓“** (sinkt mit jeder Fahrt),
  Gültigkeitsbereich, Berechtigung; Ticket-Verlauf (Jahre mit Ergebnis); bearbeiten/löschen.

### 5.6 Gipfelbuch (Erfolge)
Statt Medaillen auf der Startseite: **„Gipfelbuch“** (Sheet aus Übersicht/Statistik). Glas-Medaillons mit Tier-Verlauf, gesperrte mit
Fortschrittsring, Kopf „9 von 17“, Abschnitte „Erreicht“ / „Als Nächstes“, Detail mit Neigungs-Glanz und Teilen. Keine Streak-Flamme.

### 5.7 Einstellungen & Update
Gruppierte Liste (system Liquid Glass), farbige Icon-Kacheln (Modus-Radius 9–10). Konto (Avatar, Anbieter, Sync), Bewertung (Vorteilscard,
Klasse, Heimatbahnhof), Fahrterkennung, Darstellung, Mitteilungen, Updates (Version, Prüfen, AltStore/SideStore-Quelle, Tarif-Stand),
Daten (CSV, Backup, Import, Demo, Löschen), Über (FAQ, Quellen, Datenschutz, Hinweis).
**Update-Sheet:** App-Icon, „Version 1.1 ist da“, Notizen mit Häkchen, „Jetzt aktualisieren“ (CTA), „AltStore-Quelle hinzufügen“, „Später“.
Zusätzlich darf eine Glas-Kapsel „Neue Version verfügbar“ oben in der Übersicht erscheinen.

### 5.8 Onboarding
Mockup `alpine-glass/05-onboarding.jpg`: Onboarding-Himmel (dunkler), App-Icon + „KlimaBilanz“, Gipfelszene (Demo 73 %) mit
schwebenden Glas-Chips (Break-even 14. Dez., CO₂ 612 kg, Amortisiert 73 %; sanftes ±4 pt Schweben via phaseAnimator), Headline
„Hat sich dein Ticket / **schon rentiert?**“ (zweite Zeile im Routen-Verlauf), Unterzeile, Anmelde-Buttons (Apple zuerst, gleiche Breite
52 pt Kapseln), „Ohne Konto fortfahren“, Rechtstext. **Erklär-Zeile aus Rail Editorial:** „TICKET GEKAUFT → GRATIS FAHREN“ – „bis zum Tag,
ab dem du gratis fährst“. Folgeschritte schlicht auf ruhigem Himmel mit Fortschrittsanzeige.

### 5.9 Widgets
- Klein: Mini-Gipfel + „73 %“ + „noch € 354“. Mittel: + Prognose „14. Dez.“, Sparkline-Route. Groß: + Favoriten-Knöpfe.
- Sperrbildschirm: rund `Gauge` (Kapazität, Berg-Symbol), rechteckig „73 % · noch € 354“, inline „73 % rentiert“.
- Schnellerfassung (interaktiv), Kontrollzentrum „Fahrt erfassen“. iOS-26-Render-Modi: Akzent-Elemente `widgetAccentable`.

## 6. Bewegung & Haptik
- Hero-Zahl zählt hoch (`.numericText`, spring 0,6/0,15); Route `trim` 0→p (1,2–1,4 s); Kletterer-Halo pulsiert (2,4 s).
- Himmel driftet minimal; Sterne funkeln. Reduce Motion: alles statisch, Crossfades.
- Break-even: Fahne dawn→gold, Konfetti, `.sensoryFeedback(.success)`.
- Tausch-Knopf `.bouncy`; Modus-Kapsel gleitet; Speichern → `.success`; Löschen → `.warning`; Auswahl → `.selection`.
- Screenshot-Modus: Animationen sofort im Endzustand.

## 7. Barrierefreiheit
Dynamic Type (Hero via `@ScaledMetric`/minimumScaleFactor, Stat-Reihen → 2×2), VoiceOver-Labels für Grafiken (Wert + Prognose),
Kontrast ≥ 4,5 : 1 für Text, Reduce Transparency → opake Karten, Reduce Motion, Farbe nie alleiniger Bedeutungsträger.
