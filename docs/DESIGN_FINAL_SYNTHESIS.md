# KlimaBilanz — Design System & UI Spec (FINAL v1.0)

This document is the source of truth for SwiftUI engineers. Target: iPhone, iOS 26, SwiftUI, Liquid Glass. UI language: Austrian German.
Where a mockup and this document disagree, this document wins. The HTML mockups are reference renders only; web fonts and CSS blur stand in for SF Pro and real Liquid Glass (see §14).

Base direction: **ALPINE GLASS** ("Dein Weg zum Gipfel"), winner of the design panel (100.5 pts). It adds the best ideas from RAIL EDITORIAL and VIVID ECO, plus every fix the judges asked for.

---

## 0. File index (mockups @3x, 1206×2622)

All files are in `scratchpad/design/final/`:

| File | Content |
|---|---|
| `00-overview.png` | Contact sheet of all screens |
| `01-dashboard-light.png` / `01-dashboard-dark.png` | Übersicht at 73 % (Morgendämmerung / Blaue Stunde) |
| `01c-dashboard-profit-dark.png` | Übersicht after break-even (112 %, "Höhenweg" state) |
| `02-add-trip.png` / `02-add-trip-dark.png` | Fahrt hinzufügen (sheet) |
| `03-statistik-dark.png` / `03-statistik-light.png` | Statistik, top of the page |
| `03b-statistik-scrolled-light.png` / `03c-statistik-scrolled-dark.png` | Statistik scrolled: Verkehrsmittel, Aktivität, Top-Strecken, Gipfelbuch |
| `04-ticket-dark.png` / `04-ticket-light.png` | Ticket (Begleitkarte, validity, details) |
| `05-onboarding.png` | Willkommen + sign-in with Apple, Google and Microsoft |
| `07-fahrten-light.png` | Fahrten list (month sections, swipe actions) |
| `08-widgets-home.png` | Home Screen widgets, small and medium |
| `09-widgets-lockscreen.png` | Lock Screen widgets: inline, circular, rectangular |
| `app-icon.svg` / `app-icon-1024.png` | App icon master (vector) |
| `common.css`, `common.js`, `appicon.js`, `0x-*.html` | Reference implementation of the tokens and the summit geometry (`summit()` in `common.js`) |

---

## 1. Brand

### 1.1 Name, promise, personality
- **Name:** KlimaBilanz. Always one word with a capital B. Never "Klima Bilanz" or "KLIMABILANZ" in running text.
- **Promise:** "Hat sich mein Ticket schon rentiert?" The app answers this in under one second, every time it opens.
- **Metaphor:** amortisation is a climb. The ticket price is the **Gipfel** (summit). Break-even is the day you plant the flag. Value beyond the price is the **Höhenweg** (the high trail after the summit).
- **Personality:** calm, competent, quietly proud, alpine. Premium like Apple Weather or Wallet. Never gamey or loud. Warm Austrian tone ("Servus" level), never folksy.
- **Ownership:** this is an independent companion app. It never uses ÖBB, KlimaTicket or One Mobility logos, colours or typefaces. "KlimaTicket Ö" appears only as a descriptive product name in text.

### 1.2 Voice & German copy guidelines
- **Du-form** everywhere ("Erfasse deine Fahrten", "Du fährst jetzt gratis"). Never "Sie".
- **Austrian vocabulary:** "Jänner" (abbreviated "Jän."), "Öffis", "Fahrt" and "Fahrten", "heuer" (allowed in casual copy, e.g. "heuer schon 87 Fahrten"), "Bahnhof" and "Hbf", "Servus" for greetings (onboarding, empty states). Use "Februar", not "Feber". Use "Ticket" for the KlimaTicket and "Fahrschein" only in the legal note.
- **Short and concrete.** Lead with the number, then the meaning: "Noch € 354 bis zum Break-even". Avoid jargon. Write "€ 52 vor Plan", not "4 Prozentpunkte über Soll".
- **Mark forecasts clearly:** "Prognose", "voraussichtlich", "≈". A forecast is never written as a fact.
- **Glossary (use exactly these terms):**

| Term | Meaning | Notes |
|---|---|---|
| Break-even | Value ≥ ticket price | Explained once in the info sheet: "der Tag, ab dem du gratis fährst" |
| amortisiert | % of the ticket price recovered | "73 % amortisiert" |
| Gipfel | Ticket price / break-even point in the metaphor | "Gipfel € 1.300", "Gipfel erreicht" |
| Höhenweg | Profit zone after break-even | Used in the hero and in Statistik ("Gewinnzone" on charts) |
| Basislager / Halbzeit / Gipfelgrat | Milestones at 25 / 50 / 75 % | Used in VoiceOver and the Gipfelbuch, not as labels in the hero |
| Normalpreis | Estimated regular single fare | Always "geschätzt" until the user edits it |
| Prognose | Forecast from current pace | |
| Hin + Rück | Round trip | Counts as 2 Fahrten |
| Gipfelbuch | Achievements | |
| Begleitkarte | Our pass visual | Always paired with "kein Fahrschein" |

- **Formatting (Locale `de_AT`):**
  - Currency: "€ 1.300" (symbol, space, number). Use whole euros in summaries ≥ € 100 and cents for trip values ("€ 24,90"). Price fields show "€ 1.300,00".
  - Percent: "73 %" with a no-break space U+00A0 (or U+202F).
  - Thousands "." and decimals "," ("4.812 km", "€ 3,56"). Units: "km", "kg", "CO₂" (subscript ₂, U+2082).
  - Dates: short "14. Dez.", with weekday "Fr., 9. Okt.", long "17. Jänner 2027". January is **always** "Jänner"/"Jän.", which needs a custom month-symbol override (see §4.4).
  - Times: 24 h, "07:42".
  - Relative dates: "Heute", "Gestern", then weekday for the last 6 days ("Mi, 7. Okt."), then the date.
- **Do / Don't**

| Do | Don't |
|---|---|
| "Noch € 354 bis zum Break-even" | "Sie müssen noch 354 € erwirtschaften" |
| "Rentiert seit 14. Dez. · + € 156" | "Ticket amortisiert!!! 🎉" |
| "Prognose 14. Dez. · in 66 Tagen" | "Break-even am 14. Dez." (stated as fact) |
| "Günstiger als mit dem Auto seit 18. Juli" | "RENTIERT" next to an unfinished amortisation |
| "Begleitkarte · kein Fahrschein" | "Vorzeigen", "Gültig mit Lichtbildausweis" |

### 1.3 App icon (vector master, 1024×1024, no text)
File: `app-icon.svg`. The squircle mask is applied by the system; draw full-bleed. Build it in **Icon Composer** with three layer groups so iOS 26 can derive the clear, tinted and dark variants.

1. **Background group**
   - Rect 0,0–1024,1024 filled with a linear gradient from (0.18, 0) to (0.5, 1) in unit space. Stops: `#14306A` @0, `#3E4A9E` @0.52, `#EA977E` @1.0.
   - Sun glow on top: radial gradient centred at (680, 330), r = 380. `#FFD3B4` α0.85 @0 → α0 @1.
2. **Mountains group**
   - Far ridge polygon, white α0.16: (−20,700) (150,570) (262,616) (420,392) (520,458) (680,262) (800,430) (900,378) (1044,480) (1044,1044) (−20,1044).
   - Front "glass" peak polygon, vertical gradient white α0.97 → α0.62: (−20,820) (190,690) (300,660) (470,480) (560,450) (680,300) (820,520) (900,490) (1044,600) (1044,1044) (−20,1044). The ascent to the summit is strictly rising, like the in-app route.
3. **Route group**
   - Polyline (−20,820) → (190,690) → (300,660) → (470,480) → (560,450) → (680,300). Stroke 58, round caps and joins. Gradient in user space x 0 → 680: `#4FA8FF` @0, `#8F7FFF` @0.6, `#FF9466` @1.
   - Summit marker: circle (680,300) r 40, fill `#FFFFFF`, stroke `#FF9466` width 24.

**Variants (Icon Composer):**
- Dark: background stops `#0A1630 / #26306A / #A8604F`, glow α0.5, peak α0.85 → 0.4.
- Tinted: the route and summit layer carries the tint; mountains are monochrome.
- Clear: mountains get `glass = true`; the route stays opaque.

Minimum check: at 29 pt the summit dot and the route must still be visible. Do not add a flag (too fine at small sizes).

### 1.4 Legal guardrails (design-relevant)
- The ticket pass is a **Begleitkarte**. It has no QR, Aztec or barcode, no "Vorzeigen" button and no "gültig mit Ausweis" text. It always carries the visible note "Begleitkarte · kein Fahrschein".
- "Original" opens the user's real ticket: an imported PDF or photo, or a deep link or URL they configured. The app never sells or renews tickets. The reminder only reminds.
- Settings → Über carries this disclaimer: "KlimaBilanz ist eine unabhängige App und steht in keiner Verbindung zu KlimaTicket Ö, One Mobility oder Verkehrsunternehmen."

---

## 2. The signature: Gipfelkurs (summit hero)

The hero is the single most important element. It must be implemented with care, as specified in §8.1.

- **X axis = money.** x(€0) = left edge; x(ticket price) = summit x. The climber's x position is **exactly** proportional to the amortisation. The route is **monotonic** (it never descends before the summit).
- The **Y axis is decorative** (altitude) and rises with x.
- **Progress line:** glacier → dusk → dawn gradient, from €0 to today. **Trail:** dotted, from today to the summit. **Summit flag** = ticket price.
- **Milestones** at 25 / 50 / 75 % ("Basislager", "Halbzeit", "Gipfelgrat") are small dots on the route.
- **After the summit (p > 1):** the summit moves left (x = 0.53 W). The route crosses it and continues on a near-level ridge to the right, the **Höhenweg**, drawn in pine green. The flag turns gold. Numeral, verdict and card switch to profit copy.

States (all mandatory):

| State | Condition | Numeral | Verdict line | Visual |
|---|---|---|---|---|
| Empty | 0 trips | `0 %` | "Erfasse deine erste Fahrt" + CTA | Climber at base, full dotted trail |
| Climbing (on track) | p < 1, forecast ≤ expiry | `73 %` | "Noch **€ 354** bis zum Break-even" | Default (mock 01) |
| Climbing (behind) | p < 1, forecast > expiry | `41 %` | "Noch **€ 767** · knapp bis Ablauf" | Trail drawn in dawn at 60 % opacity; Bilanz col 2 shows "Fehlt bei Ablauf ≈ € 120" with `exclamationmark.triangle` in dawnText |
| Break-even moment | crossing 1.0 during a save | animates to `100 %` | "Gipfel erreicht!" | Flag dawn → gold, sparkle burst, haptic (§10) |
| Profit (Höhenweg) | p ≥ 1 | `112 %` | "Rentiert seit 14. Dez. · **+ € 156**" | Mock 01c |
| Expired | today > validUntil | final % | "Ticketjahr beendet · + € 256 gespart" (or "€ 120 gefehlt") | Static, no animation; CTA "Neues Ticketjahr anlegen" |

---

## 3. Color

All colors are dynamic (light / dark). Ship them as Asset Catalog colors (Any / Dark appearance, plus **High Contrast** variants where noted) and expose them via `extension Color` / `ShapeStyle`.
Naming rule: `glacier` = fill / graphic use; `glacierText` = text-safe variant (≥ 4.5:1 on surfaces).

### 3.1 Brand & accents

| Token | Light | Dark | Use |
|---|---|---|---|
| `glacier` | `#2A7BD4` | `#7CC4FF` | Primary tint, route start, links (dark), selected tab icon (fill) |
| `glacierText` | `#1F66B8` | `#7CC4FF` | Links, selected tab label, accent text |
| `glacier2` | `#63B3EE` | `#A9DBFF` | Light glacier, gradient stops |
| `glacierSoft` | `#2A7BD4` @ 12 % | `#7CC4FF` @ 16 % | Tinted fills ("Anpassen" button bg, selected chip bg) |
| `dawn` | `#F08A5B` | `#FFAD85` | Summit / ticket price, break-even marker, flag, "new value" segments (graphics only in light) |
| `dawnText` | `#9A3F16` | `#FFAD85` | "BREAK-EVEN" tag, "+ € 49,80", dawn labels in light mode |
| `dawn2` | `#F8B48E` | `#FFCDB0` | Stripes in the impact bar |
| `alpenglow` | `#E86C8A` | `#FF8FAB` | Rare rose accent (gradients only) |
| `pine` | `#23876A` | `#6BD6A9` | Positive / profit / CO₂ graphics, Höhenweg route |
| `pineText` | `#17694F` | `#6BD6A9` | "✓ rentiert sich rechtzeitig", "+ € 156", "Günstiger seit …" |
| `pineSoft` | `#23876A` @ 12 % | `#6BD6A9` @ 15 % | Positive pill backgrounds |
| `dusk` | `#7A6FE0` | `#A99FFF` | Route middle, climber ring, chart line end |
| `duskText` | `#5A4FC4` | `#A99FFF` | Gradient text end (light) |
| `gold` | `#E2A93B` | `#F5C25B` | Favorite star, planted flag after break-even, achievements |
| `goldText` | `#8A5F0C` | `#F5C25B` | "GIPFEL ✓" tag |
| `destructive` | system `.red` | system `.red` | Delete only |

### 3.2 Text & surfaces

| Token | Light | Dark | Notes |
|---|---|---|---|
| `ink` (primary text) | `#0C1A2B` | `#F3F7FC` | 16.5:1 / 15:1 on cards |
| `ink2` (secondary) | `#0C1A2B` @ 64 % | `#E8F1FC` @ 68 % | 5.2:1 / 7.2:1 |
| `ink3` (tertiary) | `#0C1A2B` @ 46 % | `#E8F1FC` @ 46 % | 3:1 / 4:1. Non-essential only (placeholders, separators in text). Never data. |
| `ink4` (quaternary) | `#0C1A2B` @ 16 % | `#E8F1FC` @ 16 % | Grabber, disabled |
| `hairline` | `#0C1A2B` @ 9 % | `#E8F1FC` @ 10 % | Separators (1 px) |
| `bgBase` | `#E6ECF3` | `#08132A` | Behind the mesh; also the Reduce Motion / Low Power fallback |
| `cardFill` | `#FFFFFF` @ 66 % | `#16244A` @ 58 % | Content cards (no blur, see §6) |
| `cardRim` (specular) | white 95 % → 25 % → 0 → 25 % | white 30 % → 5 % → 0 → 5 % | 1 pt gradient stroke at 150° |
| `sheetBg` | `#F1F4F8` | `#0D1830` | Sheet base under its mesh |
| `formFill` | `#FFFFFF` @ 80 % | `#FFFFFF` @ 7 % | Grouped rows inside sheets |
| `formLine` | `#0C1A2B` @ 8 % | `#FFFFFF` @ 8 % | |
| `fillTertiary` | `#768096` @ 16 % | `#A0AFCD` @ 18 % | Progress tracks, date pills, segmented track |
| `platter` | `#0C1A2B` @ 6 % | `#FFFFFF` @ 9 % | Selected tab platter (system draws it natively) |

**Semantic mapping**
- Savings, positive, profit, CO₂ → `pine` / `pineText`.
- Remaining, ticket price, break-even target → `dawn` / `dawnText`.
- Progress (value so far) → route gradient (`glacier` → `dusk`).
- Warning (behind plan) → `dawnText` with `exclamationmark.triangle.fill`.
- Error, destructive → system red.
- Eco / CO₂ icon → `leaf.fill` in `pine`.

### 3.3 Gradients

| Name | Definition | Use |
|---|---|---|
| `route` | Linear, user space, x0 → summit x: light `#3B8BE0` @0, `#7C79E6` @0.55, `#F08A5B` @1 · dark `#6CB6FF`, `#A99FFF`, `#FFAD85` | Hero route, onboarding, widgets |
| `routeProfit` | `route` up to the summit, then dawn → `pine` within +8 % of the width, then `pine` | Höhenweg state |
| `verdictAmount` | Light `#1F66B8` → `#5A4FC4` (text-safe) · dark `#7CC4FF` → `#A99FFF` → `#FFAD85` | Amount in the verdict line (`Text.foregroundStyle`) |
| `cta` | 100°: light `#2A6FCF` → `#5468D8` @0.55 → `#6E5FD6` (white label ≥ 4.8:1) · dark `#5AAEF5` → `#7C9CF5` → `#A193F7` (label `#06162B`) | Primary buttons, quick-add "+" |
| `pass` | 158°: `#12284E` → `#1B3A70` @0.48 → `#2C4A86`. Radial glows: `#5ABEEB` α0.45 top-left 260×220; `#9682F0` α0.35 at (70 %, 35 %) 200×160; `#FFA07D` α0.55 bottom-right 240×200 | Ticket pass (same in both modes) |
| `holoFoil` | Angular from 210° at (0.62, 0.40): `#FF9FB1 #FFD6A5 #FDFFB6 #CAFFBF #9BF6FF #A0C4FF #BDB2FF #FFC6FF #FF9FB1`, blend `.overlay`, opacity 0.55, masked by a 118° stripe (0 @30 %, 1 @44–52 %, 0 @66 %) | Pass sheen (moves with tilt) |
| `holoSeal` | Angular from 30°: `#FFD1DC #C9F2FF #D9FFCF #FFF3B0 #E5D4FF #FFD1DC` | 44 pt seal on the pass |
| `medal.*` | 150°: Halbzeit `#6CB6FF → #2F6FD0`, Arlberg-Profi `#A99FFF → #6A5FD8`, CO₂ `#5FD3A2 → #1E7F62`, Break-even `#FFC27A → #E2A93B` | Gipfelbuch |

### 3.4 Background: MeshGradient sets (3 × 3)

Points (all sets): `[[0,0],[0.5,0],[1,0], [0,Y],[0.5,Y],[1,Y], [0,1],[0.5,1],[1,1]]`. `Y` is the middle row height given per set. Settings: `smoothsColors: true`, `colorSpace: .perceptual`.

| Set | Y | Row 0 (top) | Row 1 (middle) | Row 2 (bottom) | Used on |
|---|---|---|---|---|---|
| `skyLight` "Morgendämmerung" | 0.38 | `#93BCE4 #A9C9EB #BCCFEE` | `#DDE3F2 #F2DAD3 #F8CDB6` | `#E1E8F1 #E4EAF2 #DCE4EE` | Übersicht (light) |
| `skyDark` "Blaue Stunde" | 0.38 | `#060D1C #0A1328 #0D1830` | `#1A3260 #3A3B74 #7A4C6E` | `#07122A #081329 #070F24` | Übersicht (dark) |
| `calmLight` | 0.30 | `#97BFE5 #AECBEC #C3D3EF` | `#DCE4F2 #E9E3EC #F0DFDA` | `#E1E8F1 #E4EAF2 #DCE4EE` | Fahrten, Statistik, Ticket, Einstellungen (light) |
| `calmDark` | 0.30 | `#060D1C #0A1328 #0D1830` | `#132A55 #22306A #3A3468` | `#07122A #081329 #070F24` | Same screens (dark) |
| `onboarding` | 0.44 | `#050B19 #070F22 #0A142B` | `#152B5C #2C2F6A #5C406E` | `#060F24 #07112A #060E22` | Onboarding (always dark) |
| `sheetLight` | 0.30 | `#E3ECF7 #EEF0F8 #F8E9E2` | `#EEF2F8 #F2F4F9 #F5F1F2` | `#F1F4F8 #F1F4F8 #F1F4F8` | Sheets (`presentationBackground`) |
| `sheetDark` | 0.30 | `#132449 #16264C #2A2950` | `#0F1D3C #0E1B38 #0F1C3A` | `#0D1830 #0D1830 #0D1830` | Sheets (dark) |
| `widgetDark` | 0.62 | `#0B1834 #122248 #1A2754` | `#152A55 #2E3570 #6A466E` | `#0D1B3A #101E40 #141E44` | Widgets (dark) |
| `widgetLight` | 0.62 | `#9EC3E7 #B4CDEC #C9D4EF` | `#DCE3F2 #F0DAD5 #F6D0BC` | `#E4EAF2 #E6EBF2 #E0E7F0` | Widgets (light) |

Overlays on the hero screens (drawn above the mesh, below content):
- **Sun glow**, centred on the summit point (in screen coordinates). Light: `EllipticalGradient` `#FFC4A0` α0.70 → 0, frame 440×320. Dark: `#FF9682` α0.42 → 0, frame 480×300, plus `#966EC8` α0.22 → 0, frame 840×520, offset (+30, +40). In the profit state alpha rises by +0.1 (light 0.80–0.85, dark 0.50).
- **Stars (dark only):** 70 dots on Übersicht and 40–45 on other screens. Radius 0.55–1.1 pt (12 % are 1.1 pt), opacity 0.25–0.85 × (1 − 0.7 · y / maxY). Region y 56 … 300 pt. Seeded random so positions are stable.
- **Grain (optional):** monochrome noise tile, `.blendMode(.overlay)`, opacity 0.045 light / 0.06 dark. Drop it first if performance requires.

### 3.5 Transport modes

Every mode is **always** shown with glyph + label (or plate). Color is never the only signal.

| Mode | Tile fill (both modes, white glyph ≥ 3:1) | Stroke / chart light | Stroke / chart dark | SF Symbol | Plate examples |
|---|---|---|---|---|---|
| Zug | `#2F7FDA` | `#2F7FDA` | `#6CB6FF` | `train.side.front.car` | RJX, RJ, IC, REX, R |
| S-Bahn | `#168C99` | `#168C99` | `#4FD3DD` | `s.circle.fill` | S1, S2 … |
| Bus | `#D96A2B` | `#D96A2B` | `#FFAE73` | `bus.fill` | Bus, line no. |
| Tram | `#7A66DE` | `#7A66DE` | `#A897FF` | `tram.fill` | T 2, line no. |
| U-Bahn | `#D6517E` | `#D6517E` | `#FF86AA` | `u.square.fill` | U1 … U6 |
| Fähre | `#4F6D8F` | `#4F6D8F` | `#9DB6D6` | `ferry.fill` | Schiff |
| Seilbahn | `#B07A12` | `#B07A12` | `#F5C25B` | `cablecar.fill` | Seilbahn |

- **Mode tile:** 38 pt rounded rect, r 12 (continuous). `LinearGradient(145°, fill → fill mixed 24 % black)`, inner top highlight white 25 % (1 pt). White glyph at 21 pt semibold. Sizes 34 / 30 use r 11 / 9.
- **Plate:** height 18, min width 30, horizontal padding 5, r 5. Text: `.system(size: 10.5, weight: .bold)` with tracking 0.3. Two styles:
  - **solid** (mode fill + white text): favorites, Fahrten list, add-trip meta.
  - **outline** (1.2 pt `ink3` stroke + `ink2` text): compact rows on Übersicht.

### 3.6 Chart palette

| Role | Light | Dark |
|---|---|---|
| Value line | gradient `#2F7FDA` → `#6E68E0`, 3 pt + glow (blur 2.2) | `#6CB6FF` → `#B3A8FF` |
| Area under line | `#2F7FDA` 28 % → 0 | `#6CB6FF` 42 % → 0 |
| Forecast | `dusk`, 2.2 pt, dash `[0.1, 5]`, round caps | same token |
| Ticket price rule ("Gipfellinie") | `dawn` 1.5 pt dash `[4, 4]`; label `dawnText` | same tokens |
| Gewinnzone | Hatch 45°, 6 pt pitch, 1.2 pt lines `pine` 26 % over `pine` 6 % fill; label "GEWINNZONE" `pineText` 9.5 pt bold tracked | lines 32 %, fill 7 % |
| Profit wedge | `pine` 70 % → 25 % | same |
| Break-even point | r 5.5 `dawn`, 2.2 pt ring in card color, halo `dawn` 60 % → 0 r 14 | same |
| Break-even callout | Capsule fill `ink`, text `bgBase`, flag `dawn2` | inverse: fill `ink` (= light), text `#0C1A2B`, flag `#9A3F16` |
| Grid | `ink` @ 8 % | `ink` @ 9 % |
| Axis labels | `ink` @ 62 % (10 pt medium); current month `ink` bold | same rule |
| Bars | `glacier` 90 % → 50 % vertical; best month `dawn` → `dusk`; current month outlined 1.4 pt `glacier`; forecast months 1.2 pt dashed `[2.5, 2.5]` outline `ink` 62 % | same |
| "Soll" rule (price ÷ 12) | `ink` @ 45 %, dash `[3, 3]`, label "Soll / € 108" | same |
| Heatmap ramp (single hue, 5 steps) | `#0C1A2B` @ 6 %, `#C6DBF4`, `#86B3E8`, `#3F85D6`, `#1A55A3` | `#E8F1FC` @ 7 %, `#1C3A68`, `#2C619F`, `#4C93DC`, `#A6D2FF` |
| Heatmap today | 1.8 pt `dawn` ring, 2.2 pt outset, r 6 | same |
| Heatmap future | 1.2 pt dashed outline `ink` @ 35 % | same |
| Categorical (modes) | §3.5 strokes, order: Zug, S-Bahn, Bus, Tram, U-Bahn, Fähre, Seilbahn | §3.5 dark strokes |

### 3.7 Contrast notes (measured, WCAG 2.x)
- `ink` on card: 16.5:1 (light), 15.0:1 (dark). `ink2`: 5.2 / 7.2. `ink3`: 3.0 / 4.0 (non-essential only).
- Light text accents on card: `glacierText` 5.4, `dawnText` 6.4 (5.05 on the peach summit glow), `pineText` 6.3, `duskText` 5.9, `goldText` 5.3.
- **Do not** put light-mode `dawn` (2.3:1), `pine` (4.2:1) or `glacier` (4.1:1) on text. They are graphic colors.
- Dark accents on card: `glacier` 8.6, `dawn` 8.9, `pine` 9.1, `dusk` 7.0, `gold` 9.8.
- CTA white label on the `cta` gradient: ≥ 4.8:1 at every stop. Dark CTA label `#06162B` on `#7CC4FF`: 9.7:1.
- Mode tiles with white glyph: 3.5–5.4:1 (UI graphics ≥ 3:1).
- **High-contrast asset variants:** `ink2` → 80 %, `hairline` → 18 %, `cardFill` → 92 % (light) / 85 % (dark), accent text variants one step darker (light) or lighter (dark).

### 3.8 Swift token sketch
```swift
extension Color {
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha) })
    }
    static let glacier     = Color(light: 0x2A7BD4, dark: 0x7CC4FF)
    static let glacierText = Color(light: 0x1F66B8, dark: 0x7CC4FF)
    static let dawn        = Color(light: 0xF08A5B, dark: 0xFFAD85)
    static let dawnText    = Color(light: 0x9A3F16, dark: 0xFFAD85)
    static let pine        = Color(light: 0x23876A, dark: 0x6BD6A9)
    static let pineText    = Color(light: 0x17694F, dark: 0x6BD6A9)
    static let dusk        = Color(light: 0x7A6FE0, dark: 0xA99FFF)
    static let gold        = Color(light: 0xE2A93B, dark: 0xF5C25B)
    static let ink         = Color(light: 0x0C1A2B, dark: 0xF3F7FC)
    static let ink2        = Color(light: 0x0C1A2B, dark: 0xE8F1FC, lightAlpha: 0.64, darkAlpha: 0.68)
    static let cardFill    = Color(light: 0xFFFFFF, dark: 0x16244A, lightAlpha: 0.66, darkAlpha: 0.58)
    // … every token in §3.1–3.2; prefer Asset Catalog colors to get High Contrast variants.
}
enum TransportMode: String, CaseIterable { case zug, sBahn, bus, tram, uBahn, faehre, seilbahn
    var tile: Color { … }  var stroke: Color { … }  var symbol: String { … }  var label: String { … } }
```

---

## 4. Typography

SF Pro (default design) for UI. **SF Pro Rounded** (`design: .rounded`) for every number that carries meaning. All numbers use `.monospacedDigit()`. Animated numbers use `.contentTransition(.numericText(value:))`.
The mock uses Inter (for SF Pro) and Nunito (for SF Rounded). Nunito weight 800 ≈ SF Rounded **Bold**, and Nunito 230 ≈ SF Rounded **Thin**.

### 4.1 Roles

| Role | SwiftUI | Size / leading | Weight | Design | Tracking | Dynamic Type |
|---|---|---|---|---|---|---|
| `heroNumeral` | `.system(size: s, weight: .thin, design: .rounded)` | 114 / 92 | thin (light with Increase Contrast, regular with Bold Text) | rounded | −2 | `@ScaledMetric(relativeTo: .largeTitle)`, clamp 96…150 |
| `heroPercent` | same family | 40 | light, 85 % opacity | rounded | 0 | scales with hero, top-aligned, offset −10 |
| `verdict` | `.headline` | 17 / 24 | semibold | default | — | yes |
| `verdictAmount` | `.system(size: 21, weight: .bold, design: .rounded)` | 21 | bold | rounded | −0.4 | `relativeTo: .title3` |
| `verdictSub` | `.subheadline.weight(.medium)` | 15 / 19 (mock 14.5) | medium | default | — | yes |
| `largeTitle` | `.largeTitle.bold()` | 34 / 41 | bold | default | system | yes (or navigation large title) |
| `eyebrow` | `.footnote.weight(.semibold)` + `.textCase(.uppercase)` | 13 / 16 (mock 12.5) | semibold | default | +0.9 | yes, single line, truncates tail |
| `sectionTitle` | `.title3.bold()` | 20 / 25 | bold | default | — | yes |
| `cardLabelCaps` | `.footnote.weight(.semibold)`, uppercase | 13 | semibold | default | +0.8 | yes |
| `cardLabel` | `.footnote.weight(.semibold)` | 13 / 16 | semibold | default | — | yes |
| `statL` (Bilanz values) | `.system(size: 27, weight: .bold, design: .rounded)` | 27 / 31 | bold | rounded | −0.6 | `relativeTo: .title2` |
| `statUnit` | `.system(size: 17, weight: .bold, design: .rounded)` @ 70 % | 17 | | rounded | | follows statL |
| `statS` (mini stats) | `.system(size: 18, weight: .bold, design: .rounded)` | 18 / 22 | bold | rounded | −0.3 | `relativeTo: .headline` |
| `unitS` | `.footnote.weight(.bold)` `ink2` | 13 | bold | default | | yes |
| `chartValue` | `.system(size: 32, weight: .bold, design: .rounded)` | 32 / 36 | bold | rounded | −0.9 | `relativeTo: .largeTitle` |
| `priceNumeral` | `.system(size: 44, weight: .light, design: .rounded)` | 44 / 46 | light | rounded | −1.5 | `relativeTo: .largeTitle` |
| `validityNumeral` | `.system(size: 38, weight: .light, design: .rounded)` | 38 / 40 | light | rounded | −1.5 | same |
| `stationName` | `.system(size: 18, weight: .semibold)` | 18 / 23 | semibold | default | −0.35 | `relativeTo: .headline` |
| `tripTitle` | `.subheadline.weight(.semibold)` | 15 / 20 (list 15 / 21) | semibold | default | — | yes |
| `tripMeta` | `.footnote` `ink2` | 13 / 18 | regular | default | — | yes |
| `tripValue` | `.system(size: 17, weight: .bold, design: .rounded)` | 17 | bold | rounded | | `relativeTo: .body` |
| `timeStack` (list) | date `.caption2.weight(.bold)` caps +0.6 tracking; time `.system(size: 16, weight: .bold, design: .rounded)` | 10.5 / 16 | | | | yes |
| `body` / `callout` / `subheadline` / `footnote` | system styles | 17 / 16 / 15 / 13 | regular–medium | default | — | yes |
| `caption` | `.caption.weight(.medium)` | 12 / 16 | medium | | | yes |
| `caption2` | `.caption2.weight(.semibold)` | 11 / 13 | semibold | | | yes |
| `tag` (hero summit tag key) | `.caption2.weight(.bold)` uppercase | 11 / 13 | bold | | +0.8 | yes |
| `tagValue` | `.system(size: 16, weight: .bold, design: .rounded)` | 16 / 20 | | rounded | | yes |
| `plate` | `.system(size: 10.5, weight: .bold)` | 10.5 | bold | default | +0.3 | `relativeTo: .caption2`, max 14 |
| `chartAxis` | `.system(size: 10, weight: .medium)` | 10 | medium (current: bold) | | | `relativeTo: .caption2`, max 13 |
| `button` | `.headline` | 17 | semibold | | | yes |
| `tabLabel` | system | — | — | — | — | system |

### 4.2 Text composition
- **Verdict:** `Text("Noch \(amountText) bis zum Break-even")`, where `amountText = Text(remaining, format: .currency…).font(.verdictAmount).foregroundStyle(LinearGradient.verdictAmount)`. This uses Text interpolation of styled Text.
- **Currency glyph in large values:** render "€" at 0.63× the size with 70 % opacity (e.g. the price numeral "€" is 27 pt). Use `Text(…)` concatenation.

### 4.3 Number formatting helpers (Locale `de_AT`)
```swift
let at = Locale(identifier: "de_AT")
value.formatted(.currency(code: "EUR").locale(at).precision(.fractionLength(0)))   // "€ 1.300"
value.formatted(.currency(code: "EUR").locale(at))                                 // "€ 24,90"
pct.formatted(.percent.precision(.fractionLength(0)).locale(at))                   // "73 %"
```
**Percent rule:** `display = p < 1 ? min(99, round(p*100)) : floor(p*100)`. Never show "100 %" before break-even.

### 4.4 Austrian months
Use a `DateFormatter` with `locale = de_AT` and override `shortMonthSymbols[0] = "Jän."` and `monthSymbols[0] = "Jänner"` (also the standalone variants), or wrap `Date.FormatStyle` output and replace "Jan." with "Jän.". Chart axes use one-letter months ("F M A M J J A S O N D J").

---

## 5. Layout, spacing, radii, shadows

**Canvas:** iPhone 17 Pro, 402 × 874 pt. Safe areas: 62 top, 34 bottom. All layouts must adapt down to 375 pt wide (SE / mini) and up to Pro Max widths.

### 5.1 Spacing scale (4 pt grid)
`2 · 4 · 6 · 8 · 10 · 12 · 14 · 16 · 20 · 24 · 32`

| Name | Value | Use |
|---|---|---|
| `gutterCard` | 16 | Card left/right inset |
| `gutterText` | 20 | Titles, section headers, eyebrow |
| `cardPadH` / `cardPadV` | 16 / 13–14 | Card content padding (Bilanz 16 / 13) |
| `cardGap` | 10–12 | Between cards (Statistik 12, Übersicht 10) |
| `sectionGap` | 12 | Section header → content 8, card → next section header 12 |
| `chipGap` | 8 | |
| `rowH` | trip compact 55 · trip list 66 · form 50–58 · detail 44 | |
| `chipH` | info 24 · filter 34 · favorite 46 · CTA 56 · sign-in 52 | |
| `heroStack` | title → numeral 10 · numeral → verdict 6 · verdict → sub 1 · mountain overlaps sub by ~6 (summit flag sits 8 pt under the sub line) | |
| `tabBar` | system (floating, inset ~20 L/R, 26 bottom, height 62, detached "+" circle 62 at 10 gap) | |

### 5.2 Corner radii (always `.continuous`)
- Card 26 · form group in sheets 24 · sheet 38 (system) · ticket pass 30 (notch r 12 at y = 194) · medal circle · widget: system `containerBackground`.
- Toolbar button: 44 circle (system) · chip / capsule / CTA: `Capsule()`.
- Mode tile 12 (38 pt) / 11 (34) / 9 (30) · icon tile in rows 9–10 · plate 5.
- Segmented: system · progress tracks 4–5 · bars capsule · heatmap cell 4 · date pill 10.

### 5.3 Shadows / elevation

| Token | Light | Dark |
|---|---|---|
| `shadowCard` | `0 1 2 #102446 @5 %` + `0 10 28 (−12) #1A3460 @20 %` | `0 1 1 #000 @20 %` + `0 16 40 (−14) #000 @55 %` |
| `shadowGlass` | system (Liquid Glass) | system |
| `shadowPass` | `0 22 26 #102450 @36 %` + `0 6 10 #102450 @18 %`, shape-aware (follows the notches) | `0 22 30 #000 @55 %` + `0 6 10 #000 @30 %` |
| `shadowCTA` | `0 12 28 (−10) #3464D2 @65 %` + inner top white 45 % 1 pt | same, dark CTA colors |
| `shadowQuickAdd` | `0 4 12 (−4) #2A6FCF @60 %` | same |
| `shadowMedal` | inner top white 50 % 1.5 pt, inner bottom black 18 % blur 8, outer `0 8 18 (−8) #14285A @45 %` | same |
| `climberHalo` | radial `dusk` 55 % → 0, r 20 (profit: `pine`) | lighter dusk `#C9B8FF` |

SwiftUI negative spread: use `.shadow(color:radius:y:)` on a slightly inset background shape, or `.compositingGroup()`.

### 5.4 Hit targets
Minimum 44 × 44 pt. Chips are 34 pt tall but get `.contentShape(Rectangle().inset(by: -5))`. The quick-add "+" is 34 pt but the whole chip is tappable (see §8.9).

---

## 6. Materials: Liquid Glass and content surfaces

**Rule:** glass goes on the **navigation and control layer only**. Content is drawn on tinted, unblurred surfaces. Never put glass on glass.
Because the mesh sky is a smooth gradient, a blur adds nothing visually behind cards. Skipping it saves GPU, keeps 120 fps, and follows the HIG.

| Element | Treatment | SwiftUI |
|---|---|---|
| Tab bar | System Liquid Glass | `TabView` + `Tab`; `.tabBarMinimizeBehavior(.onScrollDown)` |
| "+" add button | Detached system glass circle | `Tab(value: .add, role: .search) { EmptyView() } label: { Label("Fahrt hinzufügen", systemImage: "plus") }`; intercept the selection (§8.22) |
| Toolbar buttons (avatar, share, ellipsis, filter, export, xmark, star) | System glass circles | Plain `ToolbarItem` `Button`s; `ToolbarSpacer(.fixed)` between groups |
| Chips (favorites, filters, onboarding floaters, "Heute" pill) | Glass capsule | `.glassEffect(.regular.interactive(), in: .capsule)` (non-interactive for the "Heute" pill); rows wrapped in `GlassEffectContainer(spacing: 8)` |
| Segmented period switch | System segmented (glass in iOS 26) | `Picker(...).pickerStyle(.segmented)` |
| Swap button in add sheet | Glass circle | `.buttonStyle(.glass)` + `.clipShape(.circle)` |
| Content cards (Bilanz, recents, charts, validity, details) | `SurfaceCard`: `cardFill` + specular rim + `shadowCard`, **no blur** | see below |
| Sheet form groups | `formFill`, `formLine` separators, no glass | `.background(Color.formFill, in: .rect(cornerRadius: 24, style: .continuous))` |
| Hero mountain front ridge | Material (`.ultraThinMaterial`) clipped to the ridge shape. It is a content-layer frosted shape, not a control. | §8.1 |
| Ticket pass | Opaque gradient object | §8.15 |
| Primary CTA | Custom gradient capsule (not glass) | §8.10 |

```swift
struct SurfaceCard<Content: View>: View {
    var radius: CGFloat = 26
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                shape.fill(Color.cardFill)
                    .overlay(shape.strokeBorder(LinearGradient(
                        stops: scheme == .dark
                          ? [.init(color: .white.opacity(0.30), location: 0), .init(color: .white.opacity(0.05), location: 0.30),
                             .init(color: .clear, location: 0.52), .init(color: .white.opacity(0.05), location: 0.76)]
                          : [.init(color: .white.opacity(0.95), location: 0), .init(color: .white.opacity(0.25), location: 0.30),
                             .init(color: .clear, location: 0.52), .init(color: .white.opacity(0.25), location: 0.76)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                    .shadow(color: scheme == .dark ? .black.opacity(0.55) : Color(hex: 0x1A3460).opacity(0.20), radius: 14, y: 10)
            }
    }
}
```

**Scroll edge effects:** every scroll view uses `.scrollEdgeEffectStyle(.soft, for: .all)`. The tab bar gets the bottom soft edge automatically. When the large title collapses, the inline title sits on the soft top edge (mock 03b / 03c).

**Reduce Transparency:**
- Glass is handled by the system.
- `SurfaceCard` switches to an opaque fill: light `#F7F9FB`, dark `#121F41`.
- The mountain material becomes a solid fill: light `#F4F6FA`, dark `#1A2A52`.
- The mesh stays, but stars and grain are removed.

---

## 7. Background recipe (AlpineSky)

```swift
struct AlpineSky: View {
    enum Variant { case hero, calm, onboarding, sheet }
    var variant: Variant
    var summit: CGPoint? = nil          // screen-space summit for the sun glow (hero only)
    var profit = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var phase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        let set = MeshSet.for(variant, scheme)                 // §3.4 colors + middle-row Y
        let animate = !(reduceMotion || lowPower) && phase == .active
        TimelineView(.animation(minimumInterval: 1/30, paused: !animate)) { ctx in
            let t = animate ? ctx.date.timeIntervalSinceReferenceDate : 0
            MeshGradient(width: 3, height: 3, points: set.points(drift: t), colors: set.colors,
                         smoothsColors: true, colorSpace: .perceptual)
        }
        .overlay { if let s = summit { SunGlow(center: s, dark: scheme == .dark, profit: profit) } }
        .overlay { if scheme == .dark && !reduceTransparency { StarField(count: variant == .hero ? 70 : 42) } }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }
}
```

- **Drift:** only the 3 middle-row points move, by ±0.02 in x and ±0.015 in y, on sine periods of 19 s and 23 s with a different phase per point. Colors are static.
- **Budget:** 30 fps cap. Paused when inactive, in Low Power Mode, with Reduce Motion, and when the view is off-screen (`.onDisappear`). Widgets render a static mesh.
- **StarField:** a `Canvas` with seeded points. Twinkle: opacity ±20 % on a random 3–6 s phase, driven by the same timeline (static under Reduce Motion).
- Each tab's `NavigationStack` gets `.background { AlpineSky(...) }`. Content scrolls over it; the sky stays fixed.

---

## 8. Components

### 8.1 SummitHero ("Gipfelkurs")
**Anatomy (top → bottom, Übersicht):**
1. Numeral row: `73` + raised `%`.
2. Verdict line and sub line (§8.2).
3. Mountain canvas: full screen width, height 134 pt. The Bilanz card overlaps its lowest ~10 pt.

Layers, back to front:
1. **Far ridge:** fill light `#96ACD6` @ 40 % / dark `#40548C` @ 42 %.
2. **Mid ridge:** fill light `#7692C4` @ 38 % / dark `#162246` @ 90 %. Widgets omit the mid ridge.
   - Both ridges are masked by a vertical fade: opaque at 0–55 %, 90 % at 55 %, 0 at 100 % (bottom).
3. **Front ridge glass:** `Rectangle().fill(.ultraThinMaterial).clipShape(FrontRidge())`, masked to fade out over the bottom 50 %.
4. **Front fill:** `LinearGradient` top → bottom. Light: white 90 % → 22 % @0.62 → 0. Dark: `#AFC8FF` 26 % → 2 % → 0.
5. **Topo lines:** three copies of the ridge outline offset y +14, +34, +56 (×scale). Stroke 1 pt in light `#5A78AA` @ 11 % / dark `#AAC8FF` @ 13 %, at opacity 1 / 0.75 / 0.5.
6. **Rim:** the ridge outline stroked 1.3 pt with a horizontal gradient: light white 70 % → 100 % (at summit x) → 70 %; dark `#AAC8FF` 25 % → `#FFBEAA` 80 % (at summit x) → 25 %.
7. **Trail:** today → summit, 2 pt, `StrokeStyle(lineCap: .round, dash: [0.1, 6], dashPhase: -7)`. Color light `#1E3C6E` @ 50 % / dark white @ 60 %.
8. **Route:** start → today, 4 pt, round caps and joins, `route` gradient. Glow: duplicate blurred 3.2 at 60 %, or `.shadow(color: .dusk.opacity(0.6), radius: 6)`.
9. **Milestone dots** at 25 / 50 / 75 %, r 3.4: passed = filled white; upcoming = card-colored fill with a 1.4 pt trail-colored ring. A dot is hidden when |f − p| < 0.045 and in the profit state.
10. **Climber:** halo r 20; disc r 7.5 filled white (light) / `#0B1730` (dark); ring 3 pt `#6E68E0` (light) / `#C3B6FF` (dark); core r 2.6 in the ring color. Profit: ring and core in `pine`.
11. **Summit:** dot r 4.5 in `dawn` (profit: `gold`) with a 2 pt ring in the climber fill color. Pole 1.6 pt `ink` @ 85 %, from summit −3 to −27. Pennant 15 × 10 with a 3.6 pt swallowtail notch.
12. **Labels:**
    - Summit tag right of the flag at (sx + 19, sy − 27): "BREAK-EVEN" (`tag`, `dawnText`) over "€ 1.300" (`tagValue`, `ink`). If it would overflow W − 8, place it right-aligned left of the flag.
    - Profit: "GIPFEL ✓" in `goldText` over "14. Dez.", right-aligned, left of the flag.
    - "Heute" pill: glass capsule h 24, centred at (cx, cy + 16 + 12), with a 6 pt dot (`dusk` / `pine`) and "Heute · € 946" (profit "Heute · + € 156"), `caption` semibold.

**Geometry** (port of `summit()` in `common.js`; W = width, H = 134):
```swift
struct SummitGeometry {
    let W, H, sx, sy, y0, x0: CGFloat           // Übersicht: sx = 0.716W, sy = 44, y0 = 136, x0 = 0
    static let widths: [CGFloat] = [1.1, 0.85, 1.15, 0.8, 1.1, 0.85, 1.05, 0.9, 1.0]
    static let slopes: [CGFloat] = [1.45, 0.42, 1.35, 0.48, 1.4, 0.4, 1.3, 0.55, 1.6]  // alternating steep/gentle, all > 0 → monotonic
    var ascent: [CGPoint] {                     // from (x0-6, y0+3) to (sx, sy)
        var pts = [CGPoint(x: x0 - 6, y: y0 + 3)]; var x = x0 - 6, y = y0 + 3
        let wsum = Self.widths.reduce(0, +), dsum = zip(Self.widths, Self.slopes).map(*).reduce(0, +)
        for (w, s) in zip(Self.widths, Self.slopes) {
            x += w / wsum * (sx - x0 + 6); y -= (y0 + 3 - sy) * (w * s) / dsum; pts.append(.init(x: x, y: y))
        }
        pts[pts.count - 1] = .init(x: sx, y: sy); return pts
    }
    var descent: [CGPoint] { [.init(x: sx+26, y: sy+24), .init(x: sx+46, y: sy+19), .init(x: sx+74, y: sy+48),
                              .init(x: sx+100, y: sy+42), .init(x: W+6, y: sy+74)] }
    // profit: sx = 0.53W, xEnd = W-30; ridge = [sx+(xEnd-sx)*0.22, sy+7], [0.45, sy+3], [0.70, sy+9], [xEnd, sy+5], then [xEnd+14, sy+22], [W+6, sy+40]
    func x(for p: Double, pEnd: Double) -> CGFloat {   // money → x
        p <= 1 ? x0 + p * (sx - x0) : sx + (p - 1) / (pEnd - 1) * (xEnd - sx) }
    // y(x): linear interpolation along the walkable route (ascent [+ Höhenweg]).
    // Trim: compute cumulative segment lengths once; trimEnd = lengthUpTo(climber)/totalLength.
}
```
- **Far / mid ridge outlines** use fractions of W relative to sy. Example far ridge: (−6, sy+50), (0.07W, sy+32), (0.13W, sy+42), (0.21W, sy+12) … (sx+0.04W, sy−14) … (W+6, sy+8). Copy them verbatim from `summit()` in `common.js`.
- **pEnd** = max(forecastValueAtExpiry / price, p) + 0.02. Mock: 1.556 / 1.300 → 1.2.
- **Animation:** `progress` is `Animatable`. On first appearance it runs 0 → p with `.smooth(duration: 1.4)`. On data change it uses `.spring(duration: 0.6, bounce: 0.15)`. The climber is placed with the same interpolated value, so dot and route stay locked together.
- **Sizes:**
  - Onboarding: H 244, sx 0.726W, sy 66, y0 236.
  - Medium widget: 364 × 110, sx 214, sy 26, scale 0.8, no huts.
  - Small widget: 170 × 84, sx 128, sy 22, scale 0.62, no huts or topo.
  - `scale` multiplies every stroke width, radius and offset.
- **Accessibility:** one element. Label: "Gipfelkurs". Value: "73 Prozent amortisiert. Noch 354 Euro bis zum Break-even. Prognose 14. Dezember, in 66 Tagen. Nächster Meilenstein: Gipfelgrat, 75 Prozent." Trait `.updatesFrequently` is off.

### 8.2 VerdictLine
- Line 1 (`verdict`, `ink`), centred and wrapping to two lines max:
  - Climbing: "Noch {amount} bis zum Break-even"
  - Profit: "Rentiert seit {date} {+amount in pineText}"
  - Behind: "Noch {amount} · knapp bis Ablauf"
  - Empty: "Erfasse deine erste Fahrt"
- Line 2 (`verdictSub`, `ink2`):
  - Climbing: "≈ {n} Fahrten · € 946 von € 1.300 amortisiert"
  - Profit: "Ab jetzt fährst du gratis · € 1.456 von € 1.300"
- The amount uses the `verdictAmount` gradient. In the profit state it is solid `pineText`.

### 8.3 BilanzCard (`SurfaceCard`, inset 16, padding 16 / 13)
- **Row A**, two columns split by a 1 px hairline (left padding 16 on column 2):
  - Column 1: `cardLabel` "Break-even · Prognose" / `statL` "14. Dez." / `cardLabel` `ink2` "Mo · in 66 Tagen".
  - Column 2: "Vor Ablauf am 31. Jän." / `statL` "48" + `statUnit` "Tage" / `pineText` "✓ rentiert sich rechtzeitig" (`checkmark` 12 pt).
  - Behind state, column 2: "Fehlt bei Ablauf" / "≈ € 120" / `dawnText` "⚠︎ Tempo erhöhen: ≈ 2 Fahrten/Woche mehr".
  - Profit, column 1: "Gewinn bisher" / "+ € 156" in `pineText` / "≈ 6 Gratisfahrten".
  - Profit, column 2: "Prognose Ticketende" / "+ € 256" / "31. Jänner · in 19 Tagen".
- **Row B:** hairline top, 9 pt padding. Three mini stats, equal flex, 12 pt between: value (`statS`) + unit (`unitS`), then label (11.5 pt medium `ink2`) with a 13 pt colored glyph:
  - 87 Fahrten (`train.side.front.car`, glacier)
  - 4.812 km (`point.topleft.down.to.point.bottomright.curvepath`, dusk)
  - 612 kg CO₂ gespart (`leaf.fill`, pine)
- **Row C (car verdict):** hairline top, height 35. Shows `car.fill` (dawnText, 16) "Mit dem Auto **€ 2.406**" and, trailing, `pineText` "✓ Günstiger seit 18. Juli". Tapping it opens the explanation sheet: Kilometergeld € 0,50/km × 4.812 km.
  - If the car cost is still below the ticket price, show "Auto-Vergleich: noch € 320 bis gleichauf" in `ink2`.
- **Dynamic Type ≥ AX1:**
  - Row A stacks vertically (`ViewThatFits`).
  - Row B becomes a vertical list of rows (`label …… value`).
  - Row C wraps to two lines.
- Tapping the card pushes Statistik.

### 8.4 Stat tile (generic)
Used in Statistik headers and widgets: `cardLabelCaps` / `chartValue` with a "€" prefix (0.63×, 70 %) / supporting `subheadline` `ink2`. An optional delta pill sits trailing: h 26, capsule, `pineSoft` bg, `pineText`, `arrow.up.right` 13.

### 8.5 Card
See `SurfaceCard` (§6). Radius 26; padding 16 / 14. Charts inside cards use full width with 16 pt inner padding and the y axis on the trailing side.

### 8.6 Section header
HStack, `firstTextBaseline`: `sectionTitle` + Spacer + trailing.
- Trailing is either a link (`subheadline` semibold, `glacierText`, e.g. "Alle") or meta (`footnote` semibold `ink2` with a bold rounded value, e.g. "8 Fahrten · **€ 87,00**").
- Insets 20; 8 pt above content.

### 8.7 Trip row
**Compact (Übersicht recents), height 55:**
- `ModeTile` 38.
- VStack:
  - `tripTitle` "St. Anton → Innsbruck Hbf". The arrow is `arrow.right` 13 in `ink3`. Single line, middle truncation of the origin.
  - `tripMeta`: outline plate + "Heute 07:42 · 101 km".
- Trailing: `tripValue` "€ 49,80", and below it, for round trips, "⇄ Hin + Rück" (11.5 semibold `ink2`, `arrow.left.arrow.right` 11).
- Separator inset 66.

**List (Fahrten), height 66:**
- Time stack 46 wide: "HEUTE" / "07:42".
- Route glyph 12 × 42 in the mode stroke color: origin = hollow 10 pt circle with a 2.4 pt stroke; line 2 pt at 55 %; destination = filled 10 pt circle.
- Stations on two lines (15 / 21 semibold, tail truncation).
- Trailing: value, then "⇄" + solid plate.
- Separator inset 84.

**Swipe actions:**
- Trailing: "Löschen" (`.destructive`, `trash`), then "Erneut" (`plus`, glacier). "Erneut" re-logs the trip for now.
- Leading: "Favorit" (`star.fill`, gold).
- Use `List` with `.listRowBackground(Color.clear)` inside a `SurfaceCard` section, or `.swipeActions` on custom rows.
- **Accessibility:** combined label "Zug, Railjet Xpress. St. Anton am Arlberg nach Innsbruck Hauptbahnhof. Heute, 7 Uhr 42. Hin- und Rückfahrt. Wert 49 Euro 80." Custom actions mirror the swipe actions.

### 8.8 Mode tile, plate, filter chip, mode picker
- **ModeTile / Plate:** §3.5.
- **Filter chip** (Fahrten): glass capsule h 34, mode glyph 16 in the mode stroke color + label `subheadline` semibold. The selected chip ("Alle") is a solid `ink` capsule with `bgBase` text and no glass. The row scrolls horizontally with `.contentMargins(.horizontal, 16)`, a right-edge fade mask (88 % → 100 %) and `.scrollClipDisabled()`.
- **Mode picker** (add sheet): a `formFill` group with 5 pt padding and 6 equal items:
  - Zug, S-Bahn, Bus, Tram, U-Bahn, Mehr. "Mehr" opens a menu with Fähre and Seilbahn.
  - Each item: 56 tall, glyph 24 + label 11.5 semibold, `ink2`.
  - Selection: a sliding thumb (r 19), `matchedGeometryEffect(id: "modeThumb")`, fill mode tile @ 16 % → 9 % (light) / mode @ 30 % (dark), 1.5 pt inner stroke mode @ 42 %, shadow mode @ 60 % blur 14.
  - Selected glyph uses the mode color; selected label `glacierText`.
  - `.sensoryFeedback(.selection, trigger: mode)`.
  - The mode is auto-suggested from the route (station types) and can be overridden.

### 8.9 Favorite chip (one-tap logging)
- Glass capsule h 46, horizontal padding 8 / 6, spacing 8: solid plate ("RJX") + route `subheadline` semibold "St. Anton ⇄ Innsbruck" + price (`tripValue`, `ink2`) + **add button** (34 circle, `cta` gradient, `plus` 17 white; dark label `#06162B`, shadow `shadowQuickAdd`).
- **Tap "+":** logs immediately with `.sensoryFeedback(.success)`, shows the undo toast (§8.19), and the hero animates.
- **Tap the chip body:** opens the add sheet pre-filled.
- **Long-press:** context menu with Bearbeiten, Hin + Rück erfassen, Aus Favoriten entfernen.
- Row: `GlassEffectContainer(spacing: 8)` in a horizontal `ScrollView` with `.scrollTargetBehavior(.viewAligned)` and a trailing fade mask. Max 6 favorites; then "Alle Favoriten" (chevron chip).

### 8.10 Buttons
- **Primary CTA:** capsule h 56, full width (inset 16), `cta` gradient, label `button` (white light / `#06162B` dark), leading SF Symbol 19.
  - Optional trailing amount after a 1 px separator (white @ 40 %), e.g. "Fahrt speichern │ € 49,80".
  - Shadow `shadowCTA`. Pressed: scale 0.97 + brightness −4 %, `.spring(duration: 0.25, bounce: 0.3)`.
  - Disabled: `fillTertiary` + `ink3` label.
  - Implemented as a custom `ButtonStyle`. Do not use `.glassProminent` here, so the gradient survives.
- **Secondary:** `.buttonStyle(.glass)` capsule h 44, label `glacierText`.
- **Tertiary / text:** `.buttonStyle(.borderless)`, `glacierText` (e.g. "Ohne Konto fortfahren", "Alle").
- **Tinted soft:** capsule h 30, `glacierSoft` bg, `glacierText` label with an icon (e.g. "✎ Anpassen").
- **Destructive:** `Button(role: .destructive)`; confirmation via `.confirmationDialog`.
- **Toolbar:** system glass circles; icons 20–21 pt medium.
- **FAB "+":** system tab slot (§8.22).

### 8.11 Segmented filters
`Picker` with `.segmented` style: "Woche · Monat · Quartal · Ticketjahr". Default "Ticketjahr". Persist the selection per screen with `@SceneStorage`.

### 8.12 Rows, toggles, pills
- **Form row:** h 50–52, leading icon tile 30 (r 9, gradient, white glyph 17), title `callout` medium, trailing control.
- **Toggle:** system `Toggle` with `.tint(.glacier)` (it renders the glacier gradient look natively).
- **Date / time:** `DatePicker(..., displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.compact)` gives the native grey pills ("Fr., 9. Okt." "07:42").

### 8.13 Price estimate card (add sheet)
- Header: `cardLabelCaps` "Geschätzter Normalpreis" + `info.circle` (opens a popover explaining the tariff basis) + trailing tinted soft button "Anpassen".
- Value: `priceNumeral` "€49,80" (round trip, total), then `subheadline` `ink2` "2 × **€ 24,90** · Hin + Rück". Single trip: "pro Richtung".
- Explanation: `footnote` `ink2` "Standardpreis 2. Klasse · 101 km · ohne Ermäßigung".
- Hairline, then the toggle row "Hin- und Rückfahrt" / "Zählt als 2 Fahrten".
- "Anpassen" swaps the numeral for `TextField(value:format: .currency(code: "EUR"))` with `.keyboardType(.decimalPad)`. An edited price shows the badge "angepasst" and a reset link.

### 8.14 Impact bar (before → after)
- Row: `statS` "73 %" → (`arrow.right` 15, `ink3`) → `statS` in `glacierText` "77 %" + `subheadline` `ink2` "amortisiert". Trailing `dawnText` rounded bold "+ € 49,80".
- Bar: h 10, capsule track `fillTertiary`; current fill = route gradient to 72.8 %; new segment = diagonal stripes `dawn` / `dawn2` (3 pt) from 72.8 % to 76.6 %.
- Ticks (11.5 semibold `ink2`): "€ 0" · "+3,8 Prozentpunkte" · "Gipfel € 1.300".
- If the trip crosses break-even: the label reads "Damit erreichst du den Gipfel!" and the new segment turns `gold`.
- Values animate with `.numericText`.

### 8.15 Ticket card (Begleitkarte)
- **Size:** full width − 32, height 280, radius 30. Notches: r 12 cut-outs at y = 194 on both edges, via a `TicketShape` that uses `RoundedRectangle.subtracting(Circle…)` (iOS 17+ shape ops) so the shadow follows the shape.
- **Layers:**
  - `pass` gradient + radial glows.
  - **TopoLines** `Canvas`: concentric distorted loops r_k · (1 + .16 sin 3θ + .09 sin 5θ + .05 sin 2θ), x-stretched 1.25. Two centres: (292, 92) with 14 rings step 17; (40, 300) with 8 rings step 18. Stroke white at op · (1 − k/(n+4)), width 0.8 (every 4th ring 1.2).
  - `holoFoil`.
  - Content.
  - Rim: 1 pt gradient white 70 % → 8 % → 0 → `#FFBEA0` 45 %.
- **Top half:**
  - Logo 30 (the app icon) + "KlimaBilanz" 15 semibold.
  - `holoSeal` 44 at top-right with `mountain.2` and an inner dashed ring.
  - Kicker "JAHRESTICKET · GANZ ÖSTERREICH" (11 semibold, tracking 1.3, white 66 %).
  - Name "KlimaTicket Ö" 27 bold + "Klassik" 27 light white 88 %.
  - Fields: "INHABER / Lukas Feuerstein", "GÜLTIG / 01.02.26 – 31.01.27".
- **Perforation:** 1.5 pt dashed white @ 30 % at y 194.
- **Stub:**
  - Mini summit (66 × 44): route to 73 %, climber, dotted trail, pennant.
  - "73 % amortisiert" (24 bold rounded + 13 semibold) / "€ 946 von € 1.300".
  - Trailing capsule "Original" (`doc.fill`, white 16 % fill, 1 pt white 26 % stroke). It opens the imported PDF or photo or the configured link. With nothing imported, it opens the import sheet.
- Below the pass: `footnote` `ink2` with `info.circle` "Begleitkarte · kein Fahrschein".
- **Tilt:** `CMMotionManager` deviceMotion at 30 Hz drives an `@Observable MotionModel(roll, pitch)` clamped to ±25°, applied with `.interpolatingSpring(stiffness: 80, damping: 12)`.
  - Foil stripe offset = roll · 1.6 pt; foil angle = 118° + pitch · 0.6; seal hue rotation = roll · 1°; card `.rotation3DEffect` ≤ 3° (off with Reduce Motion).
  - Stop motion updates when the view disappears and in Low Power Mode.
- **Long-press:** zoom transition to a full-screen pass (`.navigationTransition(.zoom(sourceID: "pass", in: ns))`) showing the details. Brightness is not changed, because there is no code to scan.
- **Share:** `ImageRenderer` of the pass + summary as an image ("Mein KlimaTicket hat sich zu 73 % rentiert").

### 8.16 Validity timeline
- Header: `cardLabelCaps` "Gültigkeit" + `validityNumeral` "114" + `subheadline` `ink2` "Tage übrig". Trailing pill (h 24, `fillTertiary`) "Tag 251 von 365".
- Track: h 8, `fillTertiary`, with a `route` gradient fill to elapsed/total (68.8 %).
- Thumb: 16 white circle, 3 pt ring `#6E68E0`, shadow.
- Break-even marker: `flag.fill` 15 in `dawn` + a 2 × 20 pole at forecast/total (86.6 %). Label above the track, right-aligned to the flag: "Break-even 14. Dez." (`dawnText`, 11.5 bold).
- Labels below (11.5 semibold `ink2`): "1. Feb." · "Heute" (`ink`, bold, centred on the thumb) · "31. Jän." (trailing). Labels hide when they collide (keep "Heute").
- Footer (hairline top): `pineText` `arrow.up.right` "€ 52 vor Plan" + `ink2` "· Break-even 48 Tage vor Ablauf". Behind plan: `dawnText` "€ 40 hinter Plan".

### 8.17 Charts (Swift Charts)
**Cumulative value** (card height 262, chart 186):
```swift
Chart {
    RectangleMark(xStart: .value("", start), xEnd: .value("", end), yStart: .value("", price), yEnd: .value("", yMax))
        .foregroundStyle(hatchPaint)                       // ImagePaint of a 6pt 45° hatch tile; fallback .pine.opacity(0.06)
    ForEach(points) { AreaMark(x: .value("Datum", $0.date), y: .value("Wert", $0.cum))
        .foregroundStyle(LinearGradient(colors: [.chartLine1.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
        .interpolationMethod(.monotone) }
    ForEach(points) { LineMark(x: .value("Datum", $0.date), y: .value("Wert", $0.cum), series: .value("S", "Ist"))
        .lineStyle(.init(lineWidth: 3, lineCap: .round, lineJoin: .round)).interpolationMethod(.monotone)
        .foregroundStyle(LinearGradient(colors: [.chartLine1, .chartLine2], startPoint: .leading, endPoint: .trailing)) }
    ForEach(forecast) { LineMark(x: .value("Datum", $0.date), y: .value("Wert", $0.cum), series: .value("S", "Prognose"))
        .lineStyle(.init(lineWidth: 2.2, lineCap: .round, dash: [0.1, 5])).foregroundStyle(Color.dusk) }
    ForEach(profitWedge) { AreaMark(x: .value("Datum", $0.date), yStart: .value("Preis", price), yEnd: .value("Wert", $0.cum))
        .foregroundStyle(LinearGradient(colors: [.pine.opacity(0.7), .pine.opacity(0.25)], startPoint: .top, endPoint: .bottom)) }
    RuleMark(y: .value("Ticketpreis", price)).lineStyle(.init(lineWidth: 1.5, dash: [4, 4])).foregroundStyle(Color.dawn)
        .annotation(position: .bottom, alignment: .leading) { Text("Ticketpreis € 1.300").font(.caption2.bold()).foregroundStyle(.dawnText) }
    RuleMark(x: .value("Heute", today)).foregroundStyle(Color.dusk.opacity(0.45))
    PointMark(x: .value("Heute", today), y: .value("Wert", value)).symbol { TodayDot() }
        .annotation(position: .leading) { Text("HEUTE").font(.caption2.bold()).tracking(0.6) }
    PointMark(x: .value("BE", breakEven), y: .value("Wert", price)).symbol { BreakEvenDot() }
        .annotation(position: .topLeading, spacing: 10) { BreakEvenCallout(date: breakEven) }   // "⚑ Break-even 14. Dez."
}
.chartXScale(domain: validFrom...validUntil)
.chartYScale(domain: 0...yMax)                                // yMax = max(price * 1.3, forecastEnd * 1.08)
.chartYAxis { AxisMarks(position: .trailing, values: [0, 500, 1000]) { AxisGridLine(); AxisValueLabel() } }
.chartXAxis { AxisMarks(values: .stride(by: .month)) { AxisValueLabel(format: .dateTime.month(.narrow)) } }
.chartXSelection(value: $scrubDate)                           // scrub bubble: date + value; .sensoryFeedback(.selection) per week
```
- Extra trailing axis labels: "1.300" in `dawnText` and the forecast end "1.556" in `pineText`.
- "GEWINNZONE" label at the top-left inside the band.
- Header pill: "↗ Prognose + € 256".

**Monthly bars** (whole ticket year):
- `BarMark(x: .value("Monat", m, unit: .month), y: .value("€", v), width: .fixed(14))` with `.clipShape(Capsule())`.
- Past months: `glacier` gradient. Best month: `dawn` → `dusk`, value label above in `dawnText`.
- Current month: same fill + a 1.4 pt `glacier` outline (via `.annotation(position: .overlay)`), value label "87" with a card-colored text halo.
- Future months: forecast outline only, dashed, label "PROGNOSE" above the group.
- `RuleMark(y: price / 12)` dashed, with a trailing annotation "Soll / € 108".
- Header: "Ø € 105" + "Bestmonat Sept. · € 168".

**Mode split:**
- Donut: `SectorMark(angle: .value("Fahrten", n), innerRadius: .ratio(0.67), angularInset: 1.5).cornerRadius(2)`, 96 × 96, centre "45 % / Zug".
- Beside it, direct-labelled rows (h 25): glyph 15 (mode color) + label 14 medium + bar (h 8, capsule, width relative to the max) + count (`ink2`) + "45 %" (rounded bold).
- Show all modes with n > 0. Hide the donut at accessibility sizes.

**Heatmap** (18 weeks; whole ticket year in landscape):
- `Grid` or `LazyHGrid` of 14 pt cells, gap 3.4, r 4, in the 5-step ramp (0, 1, 2, 3, 4+ trips).
- Day labels "Mo / Mi / Fr / So" and month labels "Jun Jul Aug Sep Okt".
- Legend "weniger ▢▢▢▢▢ mehr".
- Footer (hairline top): "**38** Reisetage · **61** Fahrten · Längste Serie **9** Tage".
- Tapping a cell shows that day's trips in a popover.

### 8.18 Achievement medal (Gipfelbuch)
- 56 circle with `medal.*` gradient and white glyph 24 (`percent`, `mountain.2.fill`, `leaf.fill`, `flag.fill`, `train.side.front.car`). Shadow `shadowMedal`. Label 11 semibold `ink2`, 2 lines max.
- **Locked:** `fillTertiary` disc, `ink3` glyph, progress ring (2.4 pt `glacier`, trimmed from 12 o'clock), and "73 %" below in `ink3`.
- **Unlock:** `.symbolEffect(.bounce)` + sparkle `PhaseAnimator` + `.sensoryFeedback(.success)`. Show a toast "Neu im Gipfelbuch: Halbzeit".
- Catalogue (12): Erste Fahrt, Basislager (25 %), Halbzeit (50 %), Gipfelgrat (75 %), Break-even, Höhenweg (+ € 100), 50 Fahrten, 100 Fahrten, Arlberg-Profi (10× über den Arlberg), 500 kg CO₂, Serie 7 Tage, Alle Öffis (≥ 4 Verkehrsmittel).
- The whole layer can be switched off in Einstellungen → Darstellung. There is no streak flame in the navigation bar.

### 8.19 Toasts & confirmations
- **Undo toast:** glass capsule h 48, inset 16, sits 10 pt above the tab bar.
  - Content: `checkmark.circle.fill` (pine) + "Fahrt gespeichert · +3,8 %" + trailing text button "Rückgängig" (`glacierText`).
  - Auto-dismiss after 4 s; swipe down to dismiss. Transition `.move(edge: .bottom).combined(with: .opacity)` with `.spring(duration: 0.4, bounce: 0.2)`.
  - VoiceOver announces it via `AccessibilityNotification.Announcement`.
- **Break-even celebration** (once per ticket year):
  - The hero flag turns gold, a `Canvas` sparkle burst plays for 0.9 s, and the sun glow brightens +30 %.
  - Then a medium-detent sheet: summit illustration, "Gipfel erreicht!", "Dein KlimaTicket hat sich am 14. Dez. rentiert. Ab jetzt fährst du gratis." Buttons: primary "Teilen", tertiary "Weiter".
- **Update banner:** see §9.9.
- **Errors:** inline `footnote` in system red under the field, or an `.alert` for sync and auth failures with a plain German message ("Anmeldung fehlgeschlagen. Bitte versuch es noch einmal.").

### 8.20 Empty states
A shared pattern: a mini summit illustration (static `SummitHero` at scale 0.7, p = 0), a title (`title3` bold), one line of `subheadline` `ink2`, and one primary or secondary action.

| Where | Title | Line | Action |
|---|---|---|---|
| Übersicht, no trips | "Servus! Dein Gipfel wartet." | "Erfasse deine erste Fahrt – wir rechnen mit." | Primary "Erste Fahrt erfassen" |
| Übersicht, no ticket | "Welches Ticket hast du?" | "Wähle dein KlimaTicket, dann geht's los." | Primary "Ticket hinzufügen" |
| Fahrten | "Noch keine Fahrten" | "Tipp: Lege deine Pendelstrecke als Favorit an." | Secondary "Favorit anlegen" |
| Statistik (< 3 trips) | Skeleton charts at 30 % opacity | "Ab 3 Fahrten siehst du hier Trends." | — |
| Search, no results | "Nichts gefunden" | "Versuch einen anderen Stations- oder Liniennamen." | — |

### 8.21 Sign-in buttons
- All three are **52 pt capsules**, equal width (full width − 40) and equal height, stacked with 10 pt gap, in the order **Apple, Google, Microsoft**. Offering Sign in with Apple satisfies App Store guideline 4.8. Logo leading the label, both centred as a group.
- **Apple:** `SignInWithAppleButton(.signIn, onRequest:onCompletion:)` with `.signInWithAppleButtonStyle(scheme == .dark ? .white : .black)`, `.frame(height: 52)`, `.clipShape(Capsule())`. The system localizes the label to "Mit Apple anmelden".
- **Google** (GoogleSignIn-iOS SDK behind a custom button):
  - Dark theme: fill `#131314`, 1 pt stroke `#8E918F`, label `#E3E3E3`.
  - Light theme: fill `#FFFFFF`, stroke `#747775`, label `#1F1F1F`.
  - Official multicolor "G" asset (19 pt), label "Mit Google anmelden", Roboto Medium if bundled, otherwise SF Pro Medium.
- **Microsoft** (MSAL behind a custom button):
  - Dark: fill `#2F2F2F`, label `#FFFFFF`. Light: fill `#FFFFFF`, 1 pt stroke `#8C8C8C`, label `#5E5E5E`.
  - Official four-square logo (`#F25022 #7FBA00 #00A4EF #FFB900`, 18 pt), label "Mit Microsoft anmelden", Semibold.
  - *Brand review note:* Microsoft's published button is rectangular. If review objects, use r 6 for Microsoft only.
- Below the buttons: "Ohne Konto fortfahren" (tertiary, `glacier`; local-only SwiftData, sync can be enabled later). Legal `caption2` `ink3` with tappable "Nutzungsbedingungen" / "Datenschutzerklärung" in `ink2` (`AttributedString` links).
- **Loading:** the tapped button shows a `ProgressView` in place of its logo, and the others are disabled.

### 8.22 Tab bar
```swift
TabView(selection: $tabProxy) {
    Tab("Übersicht", systemImage: "mountain.2", value: .home)   { HomeView() }
    Tab("Fahrten",   systemImage: "train.side.front.car", value: .trips) { TripsView() }
    Tab("Statistik", systemImage: "chart.bar", value: .stats)   { StatsView() }
    Tab("Ticket",    systemImage: "ticket", value: .ticket)     { TicketView() }
    Tab(value: .add, role: .search) { Color.clear } label: { Label("Fahrt hinzufügen", systemImage: "plus") }
}
.tint(.glacier)
.tabBarMinimizeBehavior(.onScrollDown)
// tabProxy: Binding that, when set to .add, presents the add sheet (with zoom source) and keeps the previous tab.
```
- Selected icons use the `.fill` variants (system).
- Fallback if the search-role slot ever misbehaves: a 4-tab `TabView` + an overlay `Button` (62 circle, `.glassEffect(.regular.interactive(), in: .circle)`) aligned to the bar's trailing edge inside a `GlassEffectContainer`. Set VoiceOver sort priority so "Fahrt hinzufügen" comes after the tabs.

---

## 9. Screens

All screens: `NavigationStack` over `AlpineSky`. Large title with an **eyebrow** above it (custom header row in the scroll content; the navigation bar shows the inline title when collapsed). Content insets 16 for cards and 20 for text.

### 9.1 Onboarding (4 pages, `TabView(.page)`, page dots under the subtitle; always on the `onboarding` mesh)
1. **Willkommen + Anmeldung** (mock 05)
   - App icon 64 (r 15) at y 78 + "KlimaBilanz" 15 semibold `ink2`.
   - Summit scene (H 244) at p 0.73 with demo data. Three floating glass chips with ±4 pt `PhaseAnimator` float, staggered 0.8 s:
     - "Break-even / 14. Dez." (flag tile `#FF9E7A → #D9573A`)
     - "Amortisiert / 73 %" (percent tile `#6CB6FF → #5B5FD6`)
     - "CO₂ gespart / 612 kg" (leaf tile `#5FD3A2 → #1E7F62`)
   - Headline 31 / 36 bold "Hat sich dein Ticket" + line 2 "schon rentiert?" in the gradient `#8CCBFF → #B9A8FF → #FFB896`.
   - Subtitle 16 / 22 `ink2`: "Erfasse deine Fahrten – wir zeigen dir den Tag, ab dem du gratis fährst."
   - Dots, then the sign-in stack (§8.21), "Ohne Konto fortfahren", legal.
   - Signing in or skipping advances to page 2.
2. **Ticket wählen**
   - Title "Welches Ticket hast du?". A segmented control "Österreich / Regional".
   - Österreich list: SurfaceCards with a radio button: KlimaTicket Ö Klassik (€ 1.300 default), Jugend, Senior, Spezial. Prices come from the core tariff file; any family add-on is a toggle under the selected card, not a separate type.
   - Regional: a horizontally scrolling chip row with region crests drawn as plain colored squircles, no official logos (Tirol, Vorarlberg/VMOBIL, Salzburg, OÖ, Steiermark, Kärnten, NÖ/Wien/Bgld (VOR), …).
   - Last row: "Anderes Ticket – Preis selbst eingeben".
   - CTA "Weiter".
3. **Kaufdatum & Preis**
   - Title "Seit wann gilt dein Ticket?".
   - Grouped form: "Gültig ab" (graphical `DatePicker`), "Gültig bis" (auto +1 year −1 day, read-only with an edit link), "Bezahlt" (€ field, pre-filled), "Inhaber" (optional name for the Begleitkarte).
   - Live preview card: mini summit at p 0 with "Dein Gipfel: € 1.300 · Break-even, sobald du € 1.300 an Fahrten erreicht hast".
   - CTA "Weiter".
4. **Benachrichtigungen**
   - Permission primer: three rows with icon tiles: "Verlängerung – 14 Tage vor Ablauf", "Gipfel erreicht – wenn sich dein Ticket rentiert", "Wochenrückblick – sonntags, optional".
   - Primary "Mitteilungen erlauben" (calls `UNUserNotificationCenter.requestAuthorization`), tertiary "Später".
   - Finishes with a zoom transition into Übersicht. The hero counts up from 0 on the first appearance.

### 9.2 Übersicht (mocks 01 / 01c)
Vertical structure (mock y in pt):
1. Header 62–126: eyebrow "KlimaTicket Ö Klassik · noch 114 Tage" + large title "Übersicht". Trailing glass avatar 44 (initials on a gradient `#5FA8EC → #6A70DA → #D9826E`) with a 12 pt `dawn` dot when an update is available. The avatar opens Einstellungen as a sheet.
2. Hero numeral at 134 (§8.1), verdict + sub.
3. Mountain 262–396.
4. BilanzCard at 390 (§8.3).
5. Favorites row, 10 pt below the card (§8.9).
6. Section "Letzte Fahrten" + "Alle" (switches to the Fahrten tab).
7. Recents `SurfaceCard`: the last 3 trips (§8.7 compact). Tapping a row pushes the trip detail with a zoom transition.
8. Bottom padding for the tab bar is automatic (safe area).

Behavior:
- The hero shrinks on scroll. The mountain parallaxes at 0.5×, and the numeral scales to 0.8 and fades by 40 % over the first 120 pt of scroll (`.visualEffect` with the scroll geometry).
- Pull to refresh triggers sync (if signed in).
- **Update banner:** when a new version is available, a glass capsule appears under the header: `arrow.down.circle.fill` "Version 1.3 verfügbar" + "Ansehen" → §9.9. Dismissible, it reappears after 3 days.

### 9.3 Fahrten (mock 07) + detail
- Header: eyebrow "87 Fahrten · € 946 Wert", title "Fahrten". Toolbar: filter (`line.3.horizontal.decrease`, a menu for time range, mode, Hin + Rück only, edited prices only) and export (`square.and.arrow.down` → §9.8 export sheet).
- Search: `.searchable(text:placement: .navigationBarDrawer(displayMode: .always), prompt: "Station, Linie oder Datum")`, rendered as a glass search field. Tokens: mode, month.
- Filter chips row (§8.8).
- Sections per month: header "Oktober" + "8 Fahrten · € 87,00", then a `SurfaceCard` of list rows (§8.7 list variant) with swipe actions.
- Sticky month headers use a soft top edge.
- **Fahrt detail** (push, zoom from the row):
  - Hero card: big route (stations 22 semibold, route glyph 16 wide) + mode tile 44 + plate + "Railjet Xpress · 101 km · ca. 1 h 12 min".
  - Value block: `priceNumeral` "€ 49,80" + "2 × € 24,90 · Hin + Rück" + "angepasst" badge if edited.
  - Contribution: "+3,8 % amortisiert" (mini impact bar, `pine`) and "≈ 25 kg CO₂ gespart".
  - Grouped info: Datum & Uhrzeit, Verkehrsmittel, Linie, Notiz.
  - Actions: "Bearbeiten" (opens the add sheet in edit mode), "Erneut erfassen", "Als Favorit speichern" (star), "Löschen" (destructive with confirmation).

### 9.4 Fahrt hinzufügen (mock 02; also used for edit)
- Presentation: `.sheet` with `.presentationDetents([.large])`, `.presentationBackground { AlpineSky(variant: .sheet) }`, corner radius 38 (system). Zoom transition from the "+" (`.navigationTransition(.zoom(sourceID: "add", in: ns))`).
- Toolbar:
  - Leading: `Button(role: .close)` (iOS 26 glass xmark).
  - Principal: "Neue Fahrt" / "Fahrt bearbeiten".
  - Trailing: a star toggle "Als Favorit merken" (`star` / `star.fill` gold).
  - **No toolbar ✓**: there is a single save action at the bottom.
- Content (`ScrollView`, 8 pt gaps):
  1. **Favorites chips** (`fchip`, h 34): the selected chip uses `glacierSoft` bg, 1.5 pt `glacier` 55 % stroke, `glacierText` label and a gold star. The others are glass with an outline star. Tapping one fills every field.
  2. **Route group:**
     - "Von" row: hollow 14 pt glacier ring + `caption` "Von" + `stationName`.
     - Dashed connector (2 pt, 6 pt dash, `ink3`), separator.
     - "Nach" row: dawn dot with a 4 pt halo.
     - Swap glass circle 46 at the trailing side, vertically centred between the rows.
     - Meta strip (h 36, top hairline): solid plate + **"Railjet Xpress"** + " · 101 km · ca. 1 h 12 min".
     - Tapping a station pushes a search screen: `.searchable`, local station index, recents, favorites, "In der Nähe" (CoreLocation, optional).
  3. **Mode picker** (§8.8).
  4. **Datum row** (§8.12).
  5. **Price estimate card** (§8.13).
  6. **Impact bar card** (§8.14).
- Bottom: `.safeAreaInset(edge: .bottom)` with the primary CTA "✓ Fahrt speichern │ € 49,80" over a 110 pt fade (`sheetBg` 0 → 100 % at 50 %).
- **Save:** `.sensoryFeedback(.success)`, then the sheet dismisses into the "+" (zoom). The Übersicht hero animates 73 → 77 % and the undo toast appears. A round trip creates two linked Fahrten (Hin, Rück) shown as one row.
- **Validation:** Von ≠ Nach; price > 0. The CTA is disabled until valid, with an inline hint under the route card.

### 9.5 Statistik (mocks 03, 03b, 03c)
- Header: eyebrow "Ticketjahr 2026/27 · Tag 251 von 365", title "Statistik". Toolbar: share (exports a summary image).
- Segmented "Woche · Monat · Quartal · Ticketjahr".
- Cards (12 pt gap):
  1. Kumulierter Wert (§8.17)
  2. Wert pro Monat
  3. Verkehrsmittel
  4. Aktivität (heatmap)
  5. Top-Strecken: 3 rows, each with mode tile 34, route, "RJX · 101 km", value + "18×"; "Alle" pushes the full list.
  6. Gipfelbuch preview: 5 medals, "3 von 12" link → §9.7.
- Every chart has an `AXChartDescriptor` (Audio Graphs) and a "Als Tabelle anzeigen" accessibility action.

### 9.6 Ticket (mocks 04)
- Header: eyebrow "Aktiv · Ticketjahr 2026/27", title "Ticket". Toolbar: share; ellipsis menu (Ticket bearbeiten, Original importieren, Ticketjahr wechseln, Neues Ticketjahr anlegen).
- Begleitkarte (§8.15) + note.
- Validity card (§8.16).
- Reminder row: bell tile (`#FFA77F → #E2694A`) + "Verlängerung erinnern" / "17. Jänner 2027 · 14 Tage vorher" + toggle. This schedules a `UNCalendarNotificationTrigger`; the lead time can be 7, 14 or 30 days.
- Details card, in this order:
  - "Pro Fahrt bisher" with `pineSoft` chip "↓ € 0,91" + **€ 14,94**
  - "Kosten pro Tag" **€ 3,56**
  - "Kaufpreis" **€ 1.300,00**
  - "Tickettyp", "Region", "Gültig" (scroll)
- Past ticket years: a horizontal pager of passes (`TabView(.page)`) above the details. A past year shows its final result.

### 9.7 Erfolge (Gipfelbuch)
- Pushed from Statistik (or the profile). Title "Gipfelbuch", eyebrow "3 von 12 erreicht".
- Sections "Erreicht" and "Unterwegs" (locked, sorted by progress), in a 3-column grid of medals (§8.18) with 20 pt row gaps.
- Tapping a medal opens a detail sheet (medium detent): big medal 96, title, description ("Du hast die Hälfte deines Ticketpreises zurückgeholt."), date achieved or progress ("noch € 29"), and "Teilen".

### 9.8 Einstellungen (sheet from the avatar; `Form` with `.formStyle(.grouped)` over the `calm` mesh)
- **Konto:**
  - Avatar row: name, e-mail, provider badge ("Angemeldet mit Apple" etc.).
  - "Abmelden".
  - "Konto löschen" (destructive, required by App Store guideline 5.1.1(v); confirmation + re-auth).
  - Without an account: the sign-in stack (§8.21).
- **Ticket:** Tickettyp, Preis, Gültig ab / bis, Inhaber, Original-Ticket (import PDF or photo, or a link).
- **Berechnung:**
  - "Preisbasis" (2. Klasse / 1. Klasse).
  - "Ermäßigung" (keine / Vorteilscard / …), which affects the Normalpreis estimate.
  - "Kilometergeld" (€ 0,50/km default, editable).
  - "Prognose basiert auf" (letzte 30 Tage / gesamtes Ticketjahr).
- **Synchronisierung:** status row ("Synchronisiert · vor 2 Min." with a `checkmark.icloud` / `exclamationmark.icloud` glyph), "Jetzt synchronisieren", toggle "Über Mobilfunk".
- **Updates:**
  - "Automatisch nach Updates suchen" (toggle, default on).
  - "Kanal" (Stabil / Beta).
  - "Installierte Version 1.2.0 (45)", "Zuletzt geprüft: heute, 08:12".
  - Button "Jetzt prüfen" → shows §9.9 if newer.
- **Darstellung:**
  - "Erscheinungsbild" (System / Hell / Dunkel).
  - "Gipfelbuch & Erfolge anzeigen" (toggle).
  - "Haptisches Feedback" (toggle).
  - "Animierter Himmel" (toggle; automatically off under Reduce Motion / Low Power, shown with an explanation).
  - "App-Symbol" (Standard / Dunkel / Getönt follow the system; optional alternate icons).
- **Mitteilungen:** Verlängerung (lead time), Gipfel erreicht, Wochenrückblick (day and time).
- **Daten:**
  - "Exportieren" → sheet with formats: CSV (Fahrten), PDF Jahresbericht (styled summary using this design system), JSON-Backup.
  - "Importieren" (JSON / CSV).
  - "Alle Daten löschen" (destructive).
- **Über:** Version, "Was ist neu", Feedback (mail), Bewerten, Datenschutz, Nutzungsbedingungen, Lizenzen, independence disclaimer (§1.4).

### 9.9 "Update verfügbar" sheet
- Medium + large detents, `sheet` mesh background.
- App icon 72 + "KlimaBilanz 1.3" (`title2` bold) + "Neu seit 1.2.0 · 12 MB" (`ink2`).
- "Was ist neu" as a bulleted list rendered from release-notes Markdown (`AttributedString(markdown:)`), with max height and scrolling.
- Primary "Jetzt aktualisieren": opens the configured install source (AltStore / SideStore source deep link, or the download URL). Tertiary "Später". Footnote toggle "Beta-Versionen erhalten".
- Triggered by:
  - the background check (`BGAppRefreshTask`, at most daily) when auto-check is on → avatar dot + banner (§9.2);
  - "Jetzt prüfen" in Einstellungen.
- A **mandatory** update (min-version flag in the feed) shows the same sheet without "Später" and with `interactiveDismissDisabled()`.

### 9.10 Widgets (mocks 08 / 09; WidgetKit, App Intents)
- **Background:** `.containerBackground(for: .widget) { MeshGradient(widgetDark / widgetLight) + sun glow }`. In accented / tinted rendering (`widgetRenderingMode == .accented`) the mesh is removed, the route gets `.widgetAccentable()` and everything else turns monochrome.
- **systemSmall** (170 × 170):
  - Numeral "73" (44 thin rounded) + "%" (19).
  - "noch **€ 354**" (12.5 semibold).
  - Mini summit 170 × 84 at the bottom (scale 0.62, no huts, topo or mid ridge).
  - Tap → Übersicht.
- **systemMedium** (364 × 170):
  - Top-left: "73 %" (46) + "Noch € 354".
  - Top-right: "BREAK-EVEN" (dawn) / "14. Dez." (18 bold rounded) / "in 66 Tagen".
  - Summit across the bottom (364 × 110, sx 214).
  - Bottom-right: an interactive glass capsule `Button(intent: LogFavoriteTripIntent(favorite: top))` "+ St. Anton ⇄ Innsbruck". It logs the trip without opening the app, then reloads timelines.
- **accessoryCircular:** `Gauge(value: 0.73) { Image(systemName: "mountain.2.fill") } currentValueLabel: { Text("73") }` with `.gaugeStyle(.accessoryCircular)`. Profit: the gauge is full and the label reads "+156".
- **accessoryRectangular:** "⛰ 73 % amortisiert" (13 bold), a linear bar (h 5), and "Break-even 14. Dez." (12.5 semibold, 75 %). Profit: "Rentiert · + € 156".
- **accessoryInline:** "⛰ noch € 354 · 14. Dez." (profit: "⛰ + € 156 gespart").
- **Timeline:** entries at midnight + after every save (`WidgetCenter.shared.reloadAllTimelines()`). Data comes from the App Group store. Placeholder uses `.redacted(reason: .placeholder)` over the summit.
- **Control Center / Action button (optional):** `ControlWidgetButton` "Fahrt erfassen" → opens the add sheet.

---

## 10. Motion & haptics

**Springs**
- Default `.spring(duration: 0.45, bounce: 0.15)`.
- Snappy UI (chips, toggles, picker thumb) `.snappy(duration: 0.3)`.
- Hero route `.smooth(duration: 1.4)` on first appearance, `.spring(duration: 0.6, bounce: 0.15)` on updates.
- Sheets and zoom: system.

| Moment | Animation | Haptic (`.sensoryFeedback`) |
|---|---|---|
| App launch / first appearance of Übersicht | Numeral counts 0 → 73 (`.numericText`, 1.0 s); route trims 0 → p; climber rides along; milestone dots pop (scale 0.6 → 1, staggered 80 ms) | none |
| Value change (save, delete, undo) | Numerals `.contentTransition(.numericText(value:))`; route and climber spring to the new p; impact flash on the new route segment (`dawn` glow 0.6 s) | `.success` on save; `.impact(weight: .light)` on undo |
| Passing a milestone (25 / 50 / 75 %) | The dot turns filled with `.symbolEffect(.bounce)`-like scale 1 → 1.4 → 1 | `.levelChange` |
| Break-even crossing | Flag dawn → gold (0.5 s), `Canvas` sparkle burst (0.9 s, 24 particles in `gold` / `dawn2`), sun glow +30 %, then the celebration sheet | `.success`, then 0.15 s later `.impact(weight: .heavy)` |
| Quick-add from a favorite | The chip's "+" turns into a checkmark (`symbolEffect(.replace)`), chip scale 0.96 → 1, toast slides in | `.success` |
| Mode selection | Thumb slides (`matchedGeometryEffect`, snappy) | `.selection` |
| Swap stations | Swap icon rotates 180° (`.bouncy`), station labels cross-move (`matchedGeometryEffect`) | `.impact(weight: .light)` |
| Toggle Hin + Rück | Price numeral `.numericText` 24,90 → 49,80; impact bar re-animates | system toggle haptic |
| Chart scrubbing | Selection rule + value bubble follow the finger | `.selection` per week crossed |
| Tab switch | System glass morph | system |
| Open trip detail / pass / add sheet | `.navigationTransition(.zoom(sourceID:in:))` + `.matchedTransitionSource(id:in:)` | none |
| Swipe delete | System; confirm dialog for round trips | `.impact(weight: .rigid)` on delete |
| Error (validation, auth) | Field shake (3 × 6 pt, 0.3 s) | `.error` |
| Ticket tilt | Foil / seal follow roll and pitch (interpolating spring) | none |
| Medal unlock | `.symbolEffect(.bounce)` + sparkle `PhaseAnimator` | `.success` |
| Onboarding chips | ±4 pt float, `PhaseAnimator`, 3 s cycle, staggered | none |
| Mesh sky | Middle-row drift, 19 / 23 s sine | none |

**Reduce Motion:** no count-up (values appear instantly with a 0.2 s crossfade), no mesh drift, no star twinkle, no tilt / parallax, no chip float, no sparkle burst (flag simply recolors). Zoom transitions are replaced by system crossfades. Springs become `.easeInOut(duration: 0.2)`.

---

## 11. Accessibility

- **Dynamic Type** (test up to AX5):
  - All text uses text styles or `@ScaledMetric(relativeTo:)` with sensible caps: hero ≤ 150, plates ≤ 14, chart axes ≤ 13.
  - Up to XXXL: layouts as designed.
  - AX1+: BilanzCard rows stack. Mini stats become a vertical list. The favorites row becomes a vertical list of full-width chips. Trip rows wrap stations to multiple lines and move the value under the stations. Mode picker labels hide (icon + VoiceOver label). The donut is hidden (bars remain).
  - The hero mountain keeps its height; labels inside it hide at AX3+, and the verdict carries the information.
  - Implement with `ViewThatFits` and `@Environment(\.dynamicTypeSize)` (`.isAccessibilitySize`).
- **VoiceOver:**
  - Hero = one element (§8.1). BilanzCard = three elements (forecast, buffer, stats summary), plus a car element with its hint.
  - Trip rows: combined labels + custom actions (Erneut erfassen, Als Favorit, Löschen).
  - Favorite chips: label "St. Anton nach Innsbruck, 24 Euro 90", hint "Doppeltippen erfasst die Fahrt sofort". A second action "Bearbeiten und erfassen".
  - Charts use `AXChartDescriptor` with series "Wert" and "Prognose" and the ticket price as a threshold.
  - Heatmap: one element per week ("Woche ab 28. September: 4 Reisetage, 6 Fahrten").
  - Pass: "Begleitkarte, kein Fahrschein. KlimaTicket Ö Klassik, Inhaber Lukas Feuerstein, gültig bis 31. Jänner 2027. 73 Prozent amortisiert."
  - Decorative layers (sky, stars, topo, glow) are `.accessibilityHidden(true)`.
  - Currency is read naturally ("354 Euro"); use `.accessibilityLabel` with spelled-out text where formatting glyphs confuse ("≈" → "ungefähr").
- **Reduce Transparency:** §6 fallbacks; glass is handled by the system.
- **Increase Contrast:** high-contrast asset variants (§3.7); hero weight `.thin` → `.light`; hairlines 2 px; trail opacity +20 %.
- **Bold Text:** hero weight → `.regular`; `.light` numerals → `.regular`.
- **Differentiate Without Color:** modes always carry glyph + label / plate. Forecast is dotted and actual is solid. The heatmap uses a lightness ramp plus counts in VoiceOver. Positive and negative values carry "+" / "−" and ✓ / ⚠︎ glyphs.
- **Smart Invert:** `.accessibilityIgnoresInvertColors()` on the pass, app icon, medals and mode tiles.
- **Minimum targets:** 44 × 44 (§5.4). Focus order follows the visual order; the "+" tab comes last.
- **Localization readiness:** strings in a String Catalog (de-AT source). No text baked into images. Allow +30 % width; German compounds can wrap; never truncate amounts.

---

## 12. Numbers shown in the UI (display rules)
Calculations live in the core package; the UI must present them this way:
- **Amortisation** p = Σ trip values / ticket price. Percent rule in §4.3.
- **Remaining** = price − value (≥ 0). **Trips remaining** ≈ remaining / Ø value per trip over the last 30 days (fallback: whole year), rounded up and shown with "≈".
- **Forecast break-even date** = today + ceil(remaining / pace).
  - Pace = value over the last 30 days ÷ 30. Fallback to the year average if there are fewer than 5 trips in 30 days.
  - Show "Prognose" and the countdown "in N Tagen". If the date is after `validUntil`, use the behind state (§2).
- **Buffer** = validUntil − forecast date ("48 Tage vor Ablauf").
- **Plan:** planValue = price × elapsedDays / totalDays; delta = value − planValue → "€ 52 vor Plan" / "€ 40 hinter Plan".
- **Car comparison** = km × Kilometergeld (setting, default € 0,50/km). "Günstiger seit" = the first date the cumulative car cost reached the ticket price.
- **Cost per trip** = price / trip count; delta vs. the first day of the current month ("↓ € 0,91").
- **Cost per day** = price / validity days ("€ 3,56").
- **CO₂ saved** = Σ km × (car factor − mode factor), with factors from the core (Umweltbundesamt). Shown in kg with no decimals.
- **Year-end forecast** = value + pace × days left → "Prognose € 1.556 · + € 256".

Reference data used in all mocks: ticket € 1.300, valid 01.02.2026–31.01.2027, today Fr. 09.10.2026 (day 251 / 365, 114 days left), 87 trips, € 946 (72.8 %), remaining € 354 ≈ 33 trips, forecast Mo 14.12.2026 (in 66 days, 48 days before expiry), 4.812 km, 612 kg CO₂, car € 2.406 (cheaper since 18.07.), € 14,94 per trip, € 3,56 per day. Monthly: F 62 · M 88 · A 94 · M 101 · J 86 · J 142 · A 118 · S 168 · O 87 (Σ 946). Modes: Zug 39 · S-Bahn 23 · Bus 16 · Tram 5 · U-Bahn 4. Profit state: 12.01.2027, € 1.456 (112 %), + € 156, 123 trips.

---

## 13. SF Symbols map

| Purpose | Symbol |
|---|---|
| Tabs | `mountain.2` · `train.side.front.car` · `chart.bar` · `ticket` · `plus` (selected variants `.fill`) |
| Modes | `train.side.front.car`, `s.circle.fill`, `bus.fill`, `tram.fill`, `u.square.fill`, `ferry.fill`, `cablecar.fill` |
| Stats | `point.topleft.down.to.point.bottomright.curvepath` (km), `leaf.fill` (CO₂), `car.fill` (Auto), `percent`, `flag.fill` / `flag.checkered` |
| Actions | `arrow.up.arrow.down` (swap), `arrow.left.arrow.right` (Hin + Rück), `star` / `star.fill`, `pencil`, `trash`, `square.and.arrow.up`, `square.and.arrow.down`, `line.3.horizontal.decrease`, `magnifyingglass`, `ellipsis`, `xmark`, `checkmark`, `info.circle` |
| Status | `checkmark.circle.fill`, `exclamationmark.triangle.fill`, `arrow.up.right`, `arrow.down`, `bell.fill`, `checkmark.icloud`, `arrow.down.circle.fill`, `doc.fill`, `calendar`, `clock` |

Weights: UI glyphs `.medium`; tab and toolbar glyphs follow the system; glyphs inside tiles `.semibold`.

---

## 14. Mock vs. native: known deviations
- **Fonts:** Inter and Nunito stand in for SF Pro and SF Pro Rounded. SF Rounded is narrower and crisper, so expect slightly tighter numerals. Keep the sizes and re-check line breaks on device.
- **Glass:** CSS backdrop blur is capped near 16 px in headless Chrome and has no lensing or refraction. The real Liquid Glass (tab bar, toolbar, chips) will look livelier. Content cards are intentionally unblurred (§6), so they render as designed.
- **Icons:** hand-drawn SVGs approximate SF Symbols. Use the names in §13.
- **Mesh:** the mocks interpolate the 3 × 3 mesh with Catmull-Rom in OKLab. SwiftUI `MeshGradient(.perceptual)` is close; tune per device if banding appears (add the grain overlay).
- **Status bar, Dynamic Island, home indicator, tab bar and sheets** are system components. Do not re-implement them.

## 15. Build checklist (definition of done for UI)
- [ ] Tokens in the Asset Catalog with Dark + High Contrast variants; no hard-coded hex values in views.
- [ ] Summit hero: monotonic route; climber x exactly proportional to p; all six states (§2); 120 fps on iPhone 13 or newer; static under Reduce Motion.
- [ ] Glass only on navigation and controls; no glass on glass; content cards unblurred.
- [ ] Every number formatted in `de_AT`; January reads "Jänner" / "Jän.".
- [ ] Single save action in the add sheet; no duplicated "Neue Fahrt" CTA on Übersicht.
- [ ] Begleitkarte: no code, no "Vorzeigen", note visible.
- [ ] Light-mode accent text uses the `…Text` variants only.
- [ ] Dynamic Type to AX5, VoiceOver labels, Audio Graphs, Reduce Motion / Transparency / Increase Contrast verified.
- [ ] Widgets in full color, accented and vibrant modes; the interactive quick-add works.
- [ ] Sign-in buttons follow §8.21 in light and dark; account deletion exists.
