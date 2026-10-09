# KlimaBilanz – Originallogos & Landeswappen: Auslieferung und Einbau (LOGO_SPEC)

> Ergänzt `docs/ENRICH_SPEC.md` und das Design-Dokument `BADGE_SPEC.md` („Wegzeichen“). Stand 9. Okt. 2026.
> **Repo-Kopie:** Diese Datei enthält nur Text, keine Logos und keine Bilder. Pfade, die im Repo landen, sind als
> Repo-Pfade angegeben (`Packages/…`, `App/…`, `tools/…`). Alle übrigen relativen Pfade (`brands/`, `raw/`, `package/`,
> `mockups/`, `freigabe/`, `arms/`, `xcassets/`, `swift/`, `build_logo_pack.py`, `brand_status.json`, `coverage.csv`) beziehen sich
> auf den **privaten Logo-Arbeitsordner** `logos/` außerhalb des Repos; was dort Logos zeigt, darf nie ins Repo (§1).
> **Vorrang:** Diese Spezifikation ersetzt ENRICH_SPEC D10, §1.10.3, §1.10.4, den Text „Zeichen und Namen“ in §1.10.2 und den
> Wappen-Teil von AT-U6. Die eigenen Wegzeichen bleiben überall der Fallback.
> Entscheidung des Inhabers: Originallogos von Skigebieten und Regionen sowie Landeswappen werden gezeigt; er trägt das Risiko.
> Diese Spezifikation setzt das mit möglichst wenig Angriffsfläche um. Keine Rechtsberatung.

## 0. Auf einen Blick

| Thema | Entscheidung |
|---|---|
| **Landeswappen** (8 Länder) | Liegen **im App-Bundle** (`Assets.xcassets/Wappen`, 27 Bildsätze, 567 KB) und dürfen ins öffentliche Repo, weil sie gemeinfrei sind (amtliche Werke, § 7 UrhG). Für Chips gibt es pixelgenaue PNGs @2x/@3x, ab 24 pt PDF-Vektoren. **Niederösterreich ist nicht dabei**: bis zur schriftlichen Zustimmung zeigt die App das eigene Wegzeichen, danach kommt das Wappen über das Logo-Paket. |
| **Skigebiets- und Regionslogos** (113 von 122) | Kommen **nie ins Repo**. Sie liegen nur im **Logo-Paket** `pack-2026100901.zip` (2,67 MB, WebP verlustfrei, Zip ohne Kompression) auf dem eigenen Cloudflare (R2). Die App lädt das Paket beim ersten Bedarf, prüft es per SHA-256 und speichert es in Application Support. |
| **Zurückgehalten** (9 Marken) | Diese Marken gehen erst nach Zustimmung ins Paket, weil ihre veröffentlichten Bedingungen das ausdrücklich verlangen: Ötztal, Sölden, Gurgl, Seefeld, Montafon, Kitzbühel sowie die Landesmarken Kärnten, Steiermark und Oberösterreich (`brand_status.json`). Bis dahin zeigt die App das eigene Badge. |
| **Fallback** | Fehlt das Paket, ist eine Marke gesperrt, eine Datei defekt oder ein Remote-Schalter aus, erscheint überall das eigene Wegzeichen (Skipass-Badge, Region-Chip, Landesmarke) in gleicher Größe, ohne dass sich das Layout verschiebt. |
| **Notbremse** | In der Remote-Config: `revoked` (Marke sofort weg, Dateien werden gelöscht), `armsDisabled` (Wappen eines Landes aus), `enabled:false` (alles aus). Nichts davon braucht ein App-Update. |
| **Zeilen** | Höchstens **ein** Gebietszeichen je Zeile. Quadratische Marken erscheinen als Logo-Kachel (16 pt) mit unserem Namen daneben, gut lesbare Wortmarken allein (14 pt hoch, höchstens 66 pt breit), alle anderen als eigenes Badge. |
| **Haltestellen-Detail** | Die neue **Gebietsleiste** im Hero hat höchstens zwei Zellen: links das Skigebiet, rechts den lokalsten Tourismusverband, darunter je eine kleine Beschriftung. Dazu kommt der Bundesland-Chip mit Wappen. |
| **Freigaben** | 114 fertige Anfrage-Briefe (Text + einseitiges PDF mit Vorschau) und `Kontakte.csv` liegen in `freigabe/out/`. Zuerst senden: NÖ-Landesregierung, Ski Arlberg, St. Anton, Lech Zürs, Warth-Schröcken. |

---

## 1. Was wohin gehört

| Ort | Inhalt | Darf öffentlich sein? |
|---|---|---|
| **GitHub-Repo / App-Bundle** | `xcassets/Wappen/` → `App/Resources/Assets.xcassets/Wappen/`. Code: `swift/LogoPack.swift` → `Packages/KlimaCore/Sources/KlimaCore/Logos/LogoPack.swift`, `swift/LogoViews.swift` → `App/Sources/DesignSystem/Logos/LogoViews.swift` (enthält **keine** Logodaten). Das Feld `logos` in der Remote-Config wird im Code nur gelesen. | ja |
| **Cloudflare R2** (öffentlicher Lesezugriff, nicht verlinkt) | `logos/v1/pack-<version>.zip` | technisch abrufbar, aber nicht im Repo |
| **Remote-Config** (Worker `GET /v1/config` → Block `logos`; Wert in KV/Secret, **nicht** im Repo) | URL, sha256, Größe, `revoked`, `armsDisabled`, `armsEnabled` | ja (keine Logos) |
| **Nur lokal / privat** | `brands/`, `raw/`, `package/`, `mockups/` (zeigen echte Logos), `freigabe/out/pdf` (enthält Logos), `build_logo_pack.py` samt Ausgabe | **nein** |

**Schutz vor Versehen:** `tools/check_no_brand_logos.py <repo>` (im Logo-Arbeitsordner) vergleicht jede Bild-, PDF- und Zip-Datei im Checkout mit 700 bekannten Logo-Hashes und
bricht bei einem Treffer ab. Heute gibt es 0 Treffer, sowohl im Repo als auch in `xcassets/`. Für die CI des öffentlichen Repos reicht die exportierte
Hash-Liste `package/brand_logo_hashes.txt`; sie enthält nur Hashes und keine Logos:
`python3 check_no_brand_logos.py . --hashes brand_logo_hashes.txt`. Zusätzlich gehören `*.logopack.zip`, `logo-pack/` und `brands/` in `.gitignore`.

Der alte Ordner `package/logo-pack-v1/` und `logo-pack-v1.zip` (7,2 MB, PNG und SVG) sind **überholt** und sollen nicht hochgeladen werden.

---

## 2. Logo-Paket: Format

### 2.1 Aufbau (`pack-2026100901.zip`, 2.668.266 Bytes, 257 Einträge)

```
manifest.json                 Schema 1 (§2.2), 84 KB, als erster Eintrag
b/<brand>/s.webp              Zeilen-Logo: 60 px hoch (20 pt @3x), höchstens 360 px breit
b/<brand>/l.webp              Hero-Logo: höchstens 144 px hoch (48 pt @3x), höchstens 600 px breit
b/<brand>/sd.webp, ld.webp    offizielle Dunkelmodus-Variante (15 Marken)
arms/AT-3-chip@3x.png …       optional: Landeswappen aus dem Paket (NÖ nach Zustimmung, §3.6)
```

- **WebP verlustfrei** (ImageIO dekodiert das ab iOS 14), Alphakanal, keine Neueinfärbung und kein Nachzeichnen. Wo der Inhaber nur eine kleine
  Rastergrafik anbietet (16 Marken), wird **nicht hochskaliert**: `l` ist dann höchstens so hoch wie die Originaldatei.
- **Zip ohne Kompression** (Methode 0, kein Zip64, keine Verschlüsselung, UTF-8-Namen, feste Zeitstempel). Bilder lassen sich ohnehin nicht weiter
  packen, und der Leser in Swift kommt mit rund 50 Zeilen und ohne Abhängigkeit aus (`StoredZip`). Pfade mit `..` oder `/` am Anfang werden abgelehnt.
- **Größenbudget 3 MB** wird beim Bauen geprüft. Heute: 2,67 MB mit 113 Marken, 2,83 MB, wenn alle 122 dabei sind. Wird es enger, gibt es zwei Auswege:
  `l` als verlustbehaftetes WebP mit Qualität 95 (etwa −50 %), oder das Paket enthält nur noch das Manifest und die Bilder werden einzeln mit sha256 geladen.
- **Reproduzierbar:** Gleiche Eingaben und gleiches `SOURCE_DATE_EPOCH` ergeben dieselbe sha256 (geprüft).

### 2.2 `manifest.json`

| Feld | Bedeutung |
|---|---|
| `schema` | `1`. Die App lehnt unbekannte Schemata ab und behält dann das installierte Paket bzw. die eigenen Badges. |
| `packVersion` | Ganzzahl `YYYYMMDDnn`, steigt immer. Muss zur Remote-Config passen. |
| `minApp`, `imageFormat`, `scale` | `"1.0.0"`, `"webp"`, `3` |
| `brands[]` | je Marke: `id`, `level` (`ski` · `region` · `ort` · `lift` · `land`), `name`, `owner`, `attribution` („Logo © …“), `web`, `states`, `match` (`tags` · `gkz` · `state`), `tags` {`ski`:[…], `region`:[…]}, `gkz`[] (nur bei `match:gkz`), `localities`[] (optional), `img` {`s`,`l`,`sd`?,`ld`?: {`f`,`w`,`h`,`sha256`}}, `aspect`, `compact` (`tile` · `logo` · `none`), `hero` (bool), `selfPlate` (bool), `plate` {`light`,`dark`}, `status` |
| `byTag` | `{"ski": {"ski-arlberg": "ski_arlberg", …}, "region": {"bregenzerwald": "bregenzerwald", …}}` – Zuordnung von den Haltestellen-Tags (`enrich/tags/out/tags_app.json`) zu den Marken |
| `byGkz` | `{"80239": ["warth_schroecken"], "70621": ["st_anton_arlberg", "arlberger_bergbahnen"], …}` – nur für Marken ohne Tag (Orts-Tourismusverbände, Liftgesellschaften, Dachregionen) |
| `byState` | `{"V": "vorarlberg_tourismus", "T": "tirol_werbung", …}` – Landes-Tourismus, nur für „Über diese Haltestelle“ |
| `held[]` | zurückgehaltene Marken mit Grund (zur Information; die App braucht das nicht) |
| `arms` | `{"AT-3": {"chip": {f, hPt, sha256}, "chip-m": …, "detail": …}}` – leer, bis NÖ zustimmt |

Beispiel (gekürzt): `{"id":"ski_arlberg","level":"ski","name":"Ski Arlberg","attribution":"Logo © Ski Arlberg","match":"tags","tags":{"ski":["ski-arlberg"]},"img":{"s":{"f":"b/ski_arlberg/s.webp","w":60,"h":60,"sha256":"9ec3…"},"l":{…144×144…}},"aspect":1.0,"compact":"tile","hero":true,"selfPlate":true,"plate":{"light":false,"dark":false},"status":"pending"}`

### 2.3 Bauen: `build_logo_pack.py`

```
python3 -I build_logo_pack.py                                   # nächste Version, WebP, „hold“-Marken ausgelassen
python3 -I build_logo_pack.py --version 2026100902 --base-url https://static.<domain>/logos/v1
python3 -I build_logo_pack.py --include-held                    # Inhaber entscheidet, auch „hold“ auszuliefern
python3 -I build_logo_pack.py --arms AT-3                       # NÖ-Wappen mitliefern (erst nach Zustimmung)
```

- **Eingaben:** `brands/manifest.json`, `brands/<id>/logo@3x.png`, `logo_large.png` und die `logo_dark*`-Dateien, `brands/municipality_index.json`,
  `brand_status.json` (Freigabestatus: `pending` · `requested` · `granted` · `hold` · `denied` · `revoked`) und `tags_app.json` zur Prüfung der Zuordnung.
- **Kuratierte Tabellen im Skript:** `X` legt für jede der 122 Marken die Ebene und die Zuordnung zu den Tags fest. Doppelte Zuordnungen und
  Tag-IDs, die es nicht gibt, brechen den Build ab. `PLATE_DARK_OVERRIDE` und `HERO_OFF` sind Korrekturen aus der Sichtprüfung
  (`mockups/review/review_1–4.png`: jedes Logo als Chip und als Hero-Zelle, hell und dunkel).
- **Ausgaben:** `package/logo-pack/v1/pack-<v>.zip`, `config-<v>.json` (der fertige `logos`-Block), `stage/<v>/` (entpackt zur Kontrolle) und `build_report.json`.
- **Ablauf beim Hochladen:** Neue Version bauen → Zip hochladen (unveränderlich) → `logos.pack` in der Remote-Config umstellen. Alte Zips bleiben
  14 Tage liegen, damit Geräte mit älterem Config-Stand nicht ins Leere laden.

---

## 3. Auslieferung

### 3.1 Cloudflare (für den Cloudflare-Workflow)

- **R2-Bucket** (z. B. `klimabilanz-static`) mit eigener Domain (`static.<domain>`), öffentlich lesbar, ohne Verzeichnisliste. Pfad: `/logos/v1/pack-<v>.zip`.
  `wrangler r2 object put klimabilanz-static/logos/v1/pack-2026100901.zip --file pack-2026100901.zip --content-type application/zip --cache-control "public, max-age=31536000, immutable"`
- Kein Link von einer Website und kein Eintrag im Repo. Die URL steht nur in der Remote-Config.
- Cloudflare Pages wäre ebenso möglich (`/logos/v1/…`). R2 ist aber einfacher, weil sich eine Datei ohne neuen Deploy austauschen und sperren lässt.
- Die Takedown-Kette funktioniert ohne Store-Review und ohne App-Update: Marke in `revoked` eintragen → Datei aus R2 löschen → neue Paketversion ohne diese Marke.

### 3.2 Remote-Config: Block `logos`

Kommt als zusätzliches Feld in `GET /v1/config` (Worker, `docs/CLOUDFLARE_BACKEND.md` §3.3; der Wert steht in KV oder einer Env-Variable `LOGOS_CONFIG_JSON`,
`Cache-Control: max-age=300`). Fallback: dieselbe JSON-Datei statisch unter `/logos/config.json`.

```json
{ "logos": {
    "enabled": true,
    "pack": { "schema": 1, "version": 2026100901,
              "url": "https://static.<domain>/logos/v1/pack-2026100901.zip",
              "sha256": "e11996581ca615c2f4a1cf8cc43ba474e622edd3732993b8b7ebe6557a9cab8d", "bytes": 2668266 },
    "revoked": [],
    "armsDisabled": [],
    "armsEnabled": [] } }
```

Fehlt der Block oder ist er ungültig, gilt `LogoConfig.default` = Logos an, kein Paket, `armsDisabled: ["NÖ"]`.
Beispiele: Abmahnung von Marke X → `"revoked":["x"]`. Ein Land beschwert sich → `"armsDisabled":["T"]`. Niederösterreich stimmt zu → Paket mit `--arms AT-3` bauen und `"armsEnabled":["NÖ"]` setzen.

### 3.3 Ablauf in der App

```
Start ─▶ installiertes Paket aus Application Support/LogoPack/<v>/ laden (wenn vorhanden) ─▶ Resolver aktiv
Remote-Config (bestehender /v1/config-Abruf, höchstens alle 12 h) ─▶ LogoPackStore.apply(config)
Erster Bedarf (Suchzeile mit Skigebiet/Region, Haltestellen-Detail, Karten-Callout) ─▶ ensurePack()
   ├─ config.pack.version == installiert → nichts zu tun
   └─ sonst Download (URLSession, Mobilfunk erlaubt, kein WLAN nötig, NICHT im Datensparmodus, Timeout 60 s)
        ─▶ Bytes + sha256 der ganzen Datei prüfen ─▶ manifest.json lesen (schema, packVersion)
        ─▶ jede Datei gegen ihre sha256 prüfen ─▶ in .staging-<v>/ schreiben ─▶ atomar zu <v>/ umbenennen
        ─▶ aktivieren, alte Versionen löschen, Ordner vom Backup ausnehmen (isExcludedFromBackup)
   Fehler ─▶ eigene Badges bleiben; neuer Versuch beim nächsten Config-Abruf (exponentielles Backoff, höchstens 1 × je 12 h)
```

- Beim Start wird **nicht** geladen. Wer nie sucht und nie ein Haltestellen-Detail öffnet, lädt nie etwas.
- Belegt etwa 2,7 MB auf dem Gerät. Im RAM hält ein `NSCache` höchstens 120 dekodierte Bilder; WebP wird mit `UIImage(data:scale:3)` dekodiert.
- Kommt ein Logo erst später an, blendet es über 0,2 s über das eigene Badge, ohne Layoutsprung (bei „Bewegung reduzieren“ ohne Animation).
- **Einstellung** unter Einstellungen › Darstellung: „Offizielle Logos & Wappen“ (standardmäßig an). Aus heißt eigene Wegzeichen und kein Download.

### 3.4 Referenzcode (geprüft)

- `swift/LogoPack.swift` → `Packages/KlimaCore/Sources/KlimaCore/Logos/LogoPack.swift` (KlimaCore, nur Foundation): `LogoConfig`, `LogoPackManifest`, `StoredZip`, `LogoPackInstaller` (der Hasher wird hereingereicht,
  in der App CryptoKit), `BrandResolver` und `StopBrands` (`heroCells`, `rowBrand`), `Landeswappen.assetName`.
  Kompiliert mit Swift 6.3 im Modus `-swift-version 6` ohne Warnung. Der Linux-Test `swift/main.swift` installiert das echte Paket
  (sha256 der ganzen Datei und einzeln aller 256 Bilder geprüft), weist eine manipulierte Datei ab und löst alle 39.711 Haltestellen auf (Ergebnisse in §7).
- `swift/LogoViews.swift` → `App/Sources/DesignSystem/Logos/LogoViews.swift` (App, SwiftUI): `LogoPackStore` (`@Observable`, Download, Cache, Schalter), `StateMarkW`, `BrandChip`, `GebietsLeiste`.
  Mit `Wegzeichen.swift` aus dem Design-Workflow durch `tools/typecheck/run.sh --target app` geprüft: **0 Fehler** (mit SIL).
  Drei Zeilen nutzen Darwin-API, die den Foundation-Stubs des Linux-Harness fehlen (`URLSessionConfiguration.allowsConstrainedNetworkAccess`,
  `.allowsExpensiveNetworkAccess`, `.waitsForConnectivity` setzen). Für die Prüfung wurden sie auskommentiert; sie bleiben im Code.
  Vor dem Einbau sollten sie in `tools/typecheck/Stubs/FoundationShim_ObjC` ergänzt werden.

### 3.5 Landeswappen im App-Bundle

**Empfohlenes Format:**
- **Chips:** PNG @2x/@3x, pixelgenau auf 14 bzw. 18 pt Höhe gerendert. Das ist scharf, braucht in langen Listen keine Vektor-Rasterung zur Laufzeit
  (Burgenland-SVG 336 KB) und umgeht die Probleme mit `<use>` in Xcode-SVGs (Kärnten, NÖ).
- **Ab 24 pt:** PDF-Vektor, Single Scale, „Preserve Vector Data“, Rendering „Original“.

Erzeugt mit `tools/build_arms_xcassets.py`, Ergebnis in `xcassets/Wappen/`. Den Ordner nach `App/Resources/Assets.xcassets/` kopieren; er hat
„Provides Namespace“, also `Image("Wappen/AT-8-chip")`. Dazu gibt es `xcassets/wappen_index.json` mit Quelle und Gesetz je Land.

| Land (App-Code) | Asset-Namen | Variante |
|---|---|---|
| Burgenland (`B`) | `Wappen/AT-1-chip`, `Wappen/AT-1-chip-m`, `Wappen/AT-1` | einziges Wappen (Adler ab etwa 20 pt nur noch als Silhouette) |
| Kärnten (`K`) | `Wappen/AT-2-chip`, `Wappen/AT-2-chip-m`, `Wappen/AT-2`, `Wappen/AT-2-full` | Schild; `-full` mit Helm erst ab etwa 96 pt |
| Niederösterreich (`NÖ`) | – (nicht im Bundle) | eigenes Wegzeichen; nach Zustimmung `arms.AT-3` aus dem Paket |
| Oberösterreich (`OÖ`) | `Wappen/AT-4-chip`, `Wappen/AT-4-chip-m`, `Wappen/AT-4`, `Wappen/AT-4-full` | Schild ohne Erzherzogshut (laut § 3 zulässig) |
| Salzburg (`S`) | `Wappen/AT-5-chip`, `Wappen/AT-5-chip-m`, `Wappen/AT-5`, `Wappen/AT-5-full` | Schild; `-full` ab etwa 64 pt |
| Steiermark (`ST`) | `Wappen/AT-6-chip`, `Wappen/AT-6-chip-m`, `Wappen/AT-6` | **nur kleines Landeswappen** (Schild und Panther) |
| Tirol (`T`) | `Wappen/AT-7-chip`, `Wappen/AT-7-chip-m`, `Wappen/AT-7` | einziges Wappen |
| Vorarlberg (`V`) | `Wappen/AT-8-chip`, `Wappen/AT-8-chip-m`, `Wappen/AT-8` | einziges Wappen |
| Wien (`W`) | `Wappen/AT-9-chip`, `Wappen/AT-9-chip-m`, `Wappen/AT-9` | **nur Kreuzschild**, nie die Form mit Adler |

`-chip` ist 14 pt hoch (33–42 px @3x), `-chip-m` 18 pt. Das Bundeswappen wird nicht verwendet.

### 3.6 Niederösterreich nach der Zustimmung

1. Antwort ablegen, `brand_status.json` → `"_arms_AT-3": {"status":"granted", "date":…, "ref":…}`.
2. `build_logo_pack.py --arms AT-3`: Wappen 14, 18 und 64 pt @3x landen im Paket unter `manifest.arms`.
3. Remote-Config `"armsEnabled":["NÖ"]` (und `"NÖ"` aus `armsDisabled` entfernen). `StateMarkW` nimmt dann das Paketbild statt des Wegzeichens.
   Diesen Zweig ergänzt die Integration in `LogoPackStore.wappenAsset`; das Bundle bleibt unverändert.

---

## 4. Einbau ins Wegzeichen-System

### 4.1 Welche Marken gehören zu einer Haltestelle (`BrandResolver`)

Eingaben aus `tags_app.json`: GKZ, Bundesland, Name und Aliase, `ski` (+conf), `skiAlliance`, `region[]` (+conf).

1. **Skigebiet** = `byTag.ski[tags.ski]` bei conf ≥ 70 (dieselbe Schwelle wie Skipass-Badge und Schneehaube).
2. **Regionen** = `byTag.region[tags.region]` bei conf ≥ 80, nach conf sortiert, ohne Doppelte und ohne die Skigebietsmarke.
3. **Lokal** = `byGkz[GKZ]`, also Orts-Tourismusverbände und Dachregionen ohne Tag. Hat eine Marke `localities`, muss der Haltestellenname einen
   dieser Orte enthalten (Groß-/Kleinschreibung und Akzente egal). Liftgesellschaften (`lift`) kommen getrennt.
   Sortiert nach Anzahl der Gemeinden (die lokalste zuerst).
4. **Land** = `byState[Bundesland]`, erscheint nur in „Über diese Haltestelle“.
5. **Skiverbund** (`skiAlliance`, z. B. Ski amadé) erscheint nur in der Skigebiets-Karte („Teil von …“), nie in Zeilen.
6. Gesperrte (`revoked`) und nicht ausgelieferte Marken gibt es für den Resolver nicht. An ihrer Stelle steht das eigene Badge aus den Tags.

`heroCells` = [Skigebiet] + erste Marke mit `hero` aus (lokal + Regionen), höchstens 2. `rowBrand` = Skigebiet, sonst die erste Region; bei `compact == none` → nil (eigenes Badge).

### 4.2 Landesmarke mit Wappen (`StateMarkW`)

| Stil | Höhe | Inhalt | Einsatz |
|---|---|---|---|
| `compact` | 18 pt, Ecken 6 | Wappen 14 pt (`-chip`) + 3–4 pt Abstand + Kürzel 10,5 bold (`VB`, `TI` …) | Suchzeilen, Favoriten, Routenkarte |
| `full` | 26 pt, Ecken 9 | Wappen 18 pt (`-chip-m`) + Name 12,5 semibold | Detail-Hero, „Über diese Haltestelle“ |
| `mini` | 16 pt | Wappen 12 pt + Kürzel 9,5 | Abfahrten („über Steeg TI“), Linienzeilen (Tirol ⇄ Vorarlberg) |

- Chip-Fläche wie bisher (Tinte 5,5 %). Das Wappen bekommt **keinen eigenen Rand, keine Maske und keine Tönung** (`renderingMode(.original)`).
  Die Haarlinie der weißen Schilde (Tirol, Vorarlberg) ist Teil der amtlichen Datei.
- Wappen und Text bleiben getrennte Elemente mit Abstand, damit nichts zu einem „Abzeichen“ verschmilzt (Salzburg § 2 Abs 5).
- Im Dunkelmodus braucht es keine Unterlage: Die Schildfarben tragen, nur schwarze Konturen verschwinden (geprüft im Board).
- **Fallback** (NÖ, `armsDisabled`, Einstellung aus): das bisherige `StateMark` mit Landesfarben-Streifen (BADGE_SPEC §2.2) in gleicher Größe.

### 4.3 Zeilen (Suchvorschläge, 18-pt-Zeile) – `BrandChip`

| `compact` | Darstellung | Beispiele |
|---|---|---|
| `tile` (Seitenverhältnis ≤ 1,3; 22 Marken) | Logo-Kachel 16 × 16 pt + unser Name 11,5 semibold, ohne Rahmen | Ski Arlberg, Silvretta Montafon, KitzSki, Golm, Warth-Schröcken |
| `logo` (gut lesbare Wortmarke, ≥ 2,2 : 1; 55 Marken) | Logo allein, 14 pt hoch, höchstens 66 pt breit | SkiWelt, Stubaier Gletscher, Zillertal, St. Anton |
| `none` (36 Marken) | eigenes Skipass-Badge (Gipfelfarbe + Glyphe) bzw. Region-Text-Chip | Silvretta Arena, Serfaus-Fiss-Ladis, Bregenzerwald |

- Es gilt die Reihenfolge: Landesmarke → Gebietszeichen (Skigebiet vor Region) → Abstand → Plaketten. Pro Zeile gibt es höchstens **ein** Gebietszeichen.
- **Abbau bei Platzmangel** (ersetzt BADGE_SPEC §4.1 ②): ① Region weglassen → ② bei `tile` den Namen weglassen (nur Kachel); bei `logo` auf das
  eigene `SkiPassBadge(.iconOnly)` wechseln → ③ Plaketten auf 3, 2, 1 + „+k“ → ④ Gemeinde weglassen.
- Platten (§4.5) werden auch im Chip angewendet: Kachel auf Firn 4 pt Radius, Wortmarke auf Platte mit 5 pt Radius und 12 pt Logo-Höhe.
- Mockup: `mockups/01-search-warth-*.png`. Warth Dorfplatz zeigt Vorarlberg-Wappen · Ski-Arlberg-Kachel · 110 852 ❄. Petersbaumgarten und
  Warth/Neunkirchen (NÖ) zeigen das eigene Wegzeichen und den Text-Chip „Wiener Alpen“ (dessen Logo hat `compact: none`).

### 4.4 Haltestellen-Detail

Reihenfolge im Hero:

1. Kachel und Titel (unverändert).
2. Badge-Zeile: `StateMarkW(.full)` · Region-Chip(s) ohne Hero-Logo · Ortsmarken · KlimaTicket.
3. **Gebietsleiste** (`GebietsLeiste`): ein Balken mit Radius 18, hell `#FFFFFF` mit Haarlinie, dunkel Weiß 5,5 % mit Glasrand.
   - Höchstens 2 gleich breite Zellen, getrennt durch eine Haarlinie (12 pt Einzug).
   - Logo zentriert: quadratisch 36 pt, breit höchstens 30 pt hoch und 132 pt breit.
   - Darunter die Beschriftung 10 pt, Laufweite 0,09 em, Tinte 3: SKIGEBIET · TOURISMUSVERBAND · REGION.
   - Jede Zelle ist ein Button und führt zur Skigebiets-Karte bzw. zur Regionskarte mit Link „Website öffnen ↗“.
4. Linienzeilen (unverändert).

Weiter unten:

- **Skigebiets-Karte** (BADGE_SPEC §2.3): Das Originallogo steht als 46-pt-Kachel links neben „SKIGEBIET · ARLBERG / Ski Arlberg“.
  Optional folgt „Lifte im Ort: [Logo der Liftgesellschaft]“ auf einer dunklen Pille; das passt zu Weiß-Logos wie den Arlberger Bergbahnen.
  Die Zeile „kein offizielles Logo“ wird ersetzt durch „Logo © Ski Arlberg · Website ↗“.
- **Über diese Haltestelle:** Bundesland = `StateMarkW(.full)`. Neue Zeile **Tourismus** mit den kompakten Chips (Größe m) aller lokalen und
  regionalen Marken plus Landes-Tourismus.
- **Quellen-Fußzeile:** „Logos © {Inhaber, …} – Marken der jeweiligen Inhaber, nur zur Ortsangabe. Landeswappen: amtliche Werke, nur zur
  geografischen Zuordnung. KlimaBilanz ist kein Angebot der Länder, Skigebiete oder Tourismusverbände.“ Derselbe Text steht im Impressum.

### 4.5 Hell / Dunkel

| Fall | Hell | Dunkel | Anzahl |
|---|---|---|---|
| Logo trägt sich selbst (z. B. Ski Arlberg, Golm) | ohne Platte | ohne Platte | Rest |
| Offizielle Dunkel-Variante (`sd`/`ld`) | Normalvariante | Dunkel-Variante ohne Platte (z. B. Lech Zürs, Wilder Kaiser) | 15 |
| Dunkles oder sattes Logo (`plate.dark`) | ohne Platte | **Firn-Platte** `#EEF2F7`, eng um das Logo (Innenabstand 4/7 pt, Radius 9) | 47 |
| Nur Weiß-Logo (`plate.light`) | **Nacht-Platte** `#1C2433` | ohne Platte | 5 |
| Gefüllte quadratische Marke (`selfPlate`) | ohne Platte, keine Rundung | ohne Platte, keine Rundung | 1 |

- Bei **erhöhtem Kontrast** bekommt jede Platte einen 1-pt-Rand (Tinte 30 %). Bei **Transparenz reduzieren** ist die Gebietsleiste deckend (`Theme.sheetBackground`).
- Mockup-Prüfung: Alle 113 Marken liegen in `mockups/review/` als Chip und als Hero-Zelle, hell und dunkel.

### 4.6 Barrierefreiheit

| Element | VoiceOver |
|---|---|
| Landesmarke | „Bundesland Tirol“ (das Wappenbild selbst ist ausgeblendet) |
| Logo-Kachel / Wortmarke | „Skigebiet Ski Arlberg“, „Tourismusverband St. Anton am Arlberg“, auch wenn nur das Logo sichtbar ist |
| Gebietsleiste | je Zelle ein Button: „Skigebiet Ski Arlberg, Taste“; Hinweis „Zeigt Infos zum Skigebiet“ |
| Suchzeile | unverändert (BADGE_SPEC §5): „…, Vorarlberg, Skigebiet Ski Arlberg, Linien: …“ |

- **Dynamic Type:** Die Chip-Logos wachsen mit `@ScaledMetric` von 14 bis höchstens 20 pt, die Leisten-Logos von 36 bis 48 pt. Ab `accessibility1`
  stehen die Zellen der Leiste untereinander.
- Farbe trägt nie allein Bedeutung: Jedes Logo hat ein Label, jedes Wappen den Ländernamen oder das Kürzel daneben.

### 4.7 Wo Logos und Wappen **nicht** erscheinen

- App-Symbol, App-Name, Startbildschirm, Store-Screenshots und -Texte, Werbung, Website, Push-Texte, Teilen-Bilder. Das wäre „Führung“ bzw. Werbung mit fremden Marken.
- Widgets, Live Activities und Sperrbildschirm (zu klein; dort bleiben die eigenen Wegzeichen).
- Kartenpins (Schneehaube statt Logo) und die Fahrtenliste.
- Logos nie mit eigenen Zeichen kombinieren, nie umfärben, beschneiden, runden oder verzerren.

### 4.8 Änderungen an BADGE_SPEC

- §1, Zeilen „Ski Arlberg u. a.“ und „Landeswappen“: ersetzt durch diese Spezifikation. Name, Gipfelfarbe und Glyphe bleiben der Fallback.
- §2.2: `StateMarkW` mit Wappen, die Streifen bleiben Fallback. §2.3 Skipass-Karte: Logo-Kachel und Copyright-Zeile wie in §4.4.
- §4.1: Abbau-Leiter wie in §4.3. §4.4: Gebietsleiste als Schritt 2b.

---

## 5. Rechtliche Leitplanken (Kurzfassung)

- **Landeswappen** (Details in `arms/manifest.json` → `legal_note`, Gesetzestexte in `arms/legal/`):
  - Die neutrale Kennzeichnung („Haltestelle liegt in …“) ist eine zulässige „Verwendung“ in B, K, OÖ, S, T, V und W.
    In der Steiermark gilt das nur für das kleine Wappen, in Wien nur für den Kreuzschild.
  - **NÖ** erlaubt die Verwendung nicht allgemein → schriftlich anfragen (Brief liegt bereit).
- **Marken:**
  - Die Nutzung ist rein beschreibend, unverändert, klein, mit Copyright-Zeile und Link, ohne Partnerschafts-Anschein und ohne Werbung.
  - 9 Marken mit ausdrücklicher Lizenz- oder Genehmigungspflicht sind zurückgehalten.
  - Bei KitzSki („nur im Zusammenhang mit der Bewerbung von KitzSki“) ist die Nutzung als Ortsangabe ein Grenzfall: ausgeliefert, aber Anfrage mit Priorität.
- **Notbremsen:** `revoked`, `armsDisabled`, `enabled` (§3.2) und die Einstellung in der App. In Tirol wird erst nach einem Untersagungsbescheid
  gestraft; der Schalter macht eine sofortige Einstellung möglich.
- **Impressum:** „Landeswappen dienen nur der geografischen Zuordnung. Skigebiets- und Regionslogos sind Marken ihrer Inhaber und werden nur zur
  Ortsangabe gezeigt. KlimaBilanz ist kein Angebot der Länder, der Republik, der KlimaTicket-Betreiber, der Skigebiete oder Tourismusverbände.
  Takedown-Wünsche an {E-Mail} – Umsetzung ohne App-Update.“

---

## 6. Mockups (402 × 874 pt @3x; „full“ = ganze Seite; Board 860 pt @2x)

Alle mit den **echten** Dateien: Wappen-PNGs aus `xcassets/Wappen`, Logos aus `package/logo-pack/stage/2026100901`.
Erzeugen: `cd mockups/src && python3 screens_logos.py && PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers node ../../../enrich/design/src/render.mjs ../html/jobs.json`

| Datei | Inhalt |
|---|---|
| `mockups/01-search-warth-light.png` / `-dark.png` | Suche „warth“: Warth Dorfplatz und Steffisalp (VB-Wappen · Ski-Arlberg-Kachel · 110 852 ❄), Warth (Ort), Petersbaumgarten Bahnhof und Warth/Neunkirchen (NÖ → Wegzeichen, „Wiener Alpen“ als Text), Jägeralpe |
| `mockups/02-stop-warth-light.png` / `-dark.png` | Detail Warth Dorfplatz: Vorarlberg-Wappen, Bregenzerwald, KlimaTicket, Gebietsleiste Ski Arlberg · Warth-Schröcken, Linien, Live-Abfahrten mit Tirol-Mini-Wappen |
| `mockups/02-stop-warth-full-*.png` | ganze Seite: Linien mit Mini-Wappen T/V, Skipass-Karte mit Ski-Arlberg-Logo, KlimaTicket, „Über“ mit Wappen und Tourismus-Chips (Warth-Schröcken, Bregenzerwald, Vorarlberg), Quellen mit Copyright-Zeile |
| `mockups/03-stop-stanton-light.png` / `-dark.png` | Detail St. Anton am Arlberg Bahnhof: Tirol-Wappen, P+R, barrierefrei, Gebietsleiste Ski Arlberg · St. Anton am Arlberg (dunkel: Firn-Platte), Fernverkehr, Nachtzug, Bus |
| `mockups/03-stop-stanton-full-*.png` | ganze Seite: Skipass-Karte mit „Lifte im Ort: Arlberger Bergbahnen“ (Weiß-Logo), Tourismus-Chips St. Anton · Tirol |
| `mockups/00-logo-system-light.png` / `-dark.png` | System-Board: alle 9 Landesmarken (3 Größen, NÖ als Fallback), Zeilenregeln, sechs Gebietsleisten (Warth, St. Anton, Ischgl, Mayrhofen, Lech, Hinterglemm), Platten-Regeln, VoiceOver, Fallback-Kette |
| `mockups/review/review_1–4.png` | QA: alle 113 Marken als Chip und Hero-Zelle, hell und dunkel |

---

## 7. Abdeckung

**Paket 2026100901:** 113 Marken ausgeliefert, nämlich 49 Skigebiete, 51 Regionen, 6 Orts-Tourismusverbände, 1 Liftgesellschaft und 6 Landes-Tourismusmarken.
Dazu kommen 9 zurückgehaltene Marken.

- Formate: 92 Logos als SVG-Quelle, 30 als PNG/JPG, 16 davon nur in kleiner Auflösung.
- Darstellung: 15 offizielle Dunkel-Varianten, 102 für die Gebietsleiste geeignet.
- Zeilen: 22 als Kachel, 55 als Wortmarke, 36 mit eigenem Badge.
- Wappen: 8 von 9 Ländern im Bundle.

| Bundesland | Skigebiete (Logo) | Orte / Lifte | Regionen | Landes-Tourismus | Wappen |
|---|---|---|---|---|---|
| Vorarlberg | Silvretta Montafon, OK Bergbahnen, Golm, Damüls Mellau, Diedamskopf, Sonnenkopf | Lech Zürs, Warth-Schröcken | Bregenzerwald, Alpenregion Bludenz, Kleinwalsertal, Klostertal, Brandnertal, Bodensee-Vorarlberg · *Montafon (hold)* | Vorarlberg | ✓ |
| Tirol | Ski Arlberg, SkiWelt, Mayrhofner Bergbahnen, Zillertal Arena, KitzSki, Kappl & See, Ski Juwel, Lienzer Bergbahnen, Hochzillertal, Großglockner Resort, Nordkette, Silvretta Arena, Venet, Serfaus-Fiss-Ladis, Ehrwalder Alm, Nauders, Galtür, Hintertuxer Gl., Kaunertaler Gl., Pitztaler Gl., Stubaier Gl., Kühtai · *Sölden, Gurgl (hold)* | St. Anton, Mayrhofen, Tux-Finkenberg · Arlberger Bergbahnen | Innsbruck, Zillertal, Osttirol, Kufsteinerland, Silberregion Karwendel, Imst, Wilder Kaiser, Hall-Wattens, Hohe Salve, Kitzbüheler Alpen, Alpbachtal, Paznaun–Ischgl, Reutte, Achensee, Zugspitz Arena, Stubai, Pitztal, Lechtal, PillerseeTal, Tiroler Oberland, Tannheimer Tal, Kaunertal, Kaiserwinkl · *Ötztal, Seefeld, Kitzbühel (hold)* | Tirol | ✓ |
| Salzburg | Snow Space, Skicircus, Skigastein, Schmittenhöhe, Katschberg, Kitzsteinhorn, Obertauern, Ski amadé (Verbund) | Wagrain-Kleinarl | Salzburger Sportwelt, Stadt Salzburg, Tennengau, Lungau, Seenland, Saalfelden Leogang, Zell am See-Kaprun, Gastein, NP Hohe Tauern, Hochkönig, Wolfgangsee, Großarltal, Rauris, Saalbach Hinterglemm, Saalachtal | SalzburgerLand | ✓ |
| Kärnten | Nassfeld, Gerlitzen, Turracher Höhe, Mölltaler Gletscher | – | Wörthersee, Nassfeld-Pressegger See/Lesachtal/Weissensee, Millstätter See–Bad Kleinkirchheim–Nockberge | *Kärnten (hold)* | ✓ |
| Steiermark | Planai (4-Berge), Kreischberg, Stuhleck, Lachtal | – | Schladming-Dachstein | *Steiermark (hold)* | ✓ (kleines) |
| Oberösterreich | Hinterstoder, Dachstein Krippenstein, Hochficht, Wurzeralm | – | Salzkammergut | *Oberösterreich (hold)* | ✓ |
| Niederösterreich | Hochkar | – | Wiener Alpen, Donau NÖ (Wachau) | Niederösterreich | **– (Anfrage)** |
| Burgenland | – | – | – | Burgenland | ✓ |
| Wien | – | – | – | Wien | ✓ (Kreuzschild) |

Komplette Liste mit Format, Platten, Hero-Eignung, Status und Haltestellenzahl: `coverage.csv`.

**Haltestellen** (Auflösung aller 39.711 mit `BrandResolver`):

| Kennzahl | Wert |
|---|---|
| Haltestellen mit Skigebiets-Tag (conf ≥ 70) | 3.626 |
| davon mit Skigebiets-**Logo** | 2.154 (der Rest: Skigebiet ohne Logo, z. B. kleine Lifte, Axamer Lizum, St. Johann, oder zurückgehalten) |
| mit irgendeinem Gebiets-Logo | 9.587 |
| mit Logo in der **Suchzeile** | 5.725 |
| mit **Gebietsleiste** | 8.602 |

Nach Land:

| Land | Haltestellen mit Gebiets-Logo |
|---|---|
| Tirol | 3.361 / 3.922 |
| Salzburg | 2.170 / 2.712 |
| Vorarlberg | 760 / 2.140 (Montafon zurückgehalten) |
| NÖ | 920 / 8.984 |
| Kärnten | 882 / 3.419 |
| OÖ | 877 / 5.828 |
| Steiermark | 617 / 8.996 |
| Burgenland, Wien | nur Wappen |

**Lücken:**
- **Fehlen ganz:** Zauberberg Semmering (statt dessen Wiener Alpen), Axamer Lizum, St. Johann in Tirol, Laterns, Patscherkofel, Hochoetz,
  Fuschlsee, Hochkönig Bergbahnen (statt dessen das Logo der Region Hochkönig), eigene Lift-Logos für Bad Kleinkirchheim.
- **Nur kleine Auflösung:** Mayrhofner Bergbahnen, Kitzbüheler Alpen, Klostertal, Golm, Wörthersee, Wolfgangsee.
  Zillertal wurde aus der Fußzeile eines Partners übernommen und sollte nachgeladen werden.
- **Nicht in der Gebietsleiste** (Text im Logo zu klein): Bregenzerwald, Alpenregion Bludenz, Millstätter See–BKK, Wörthersee. Sie erscheinen als Text-Chip.
- **Sonnenkopf:** Die Tags weisen dem Logo heute keine Haltestellen zu (Tag-Konfidenz < 70); die Zuordnung sollte geprüft werden.

---

## 8. Freigabe-Anfragen

- `freigabe/Freigabe-Anfrage_Vorlage.md` ist die einseitige Vorlage: Variante A für Skigebiet oder Tourismusverband (Logo),
  Variante B für die Landesregierung (Wappen), dazu die Kontaktliste mit Priorität 1 und 2.
- `freigabe/out/briefe/NNN_<id>.txt` enthält 114 fertige E-Mail-Texte mit Empfänger, Haltestellenzahl, Gemeinden, Inhaber und Website.
  Wo die Website Bedingungen nennt, sind sie zitiert. Marken mit „hold“ bekommen den Zusatz „zeigen bis zur Zustimmung nur den Namen“ und
  „unterzeichnen gerne eine Vereinbarung“. Marken desselben Inhabers sind zusammengefasst (Ötztal/Sölden/Gurgl, Alpenregion/Klostertal/Brandnertal …).
- `freigabe/out/pdf/NNN_<id>.pdf` enthält dieselben Briefe als je **eine A4-Seite** mit Vorschau des Logos in Zeile und Leiste, hell und dunkel.
  Diese PDFs enthalten Logos und bleiben deshalb privat.
- `freigabe/out/Kontakte.csv` (Semikolon, UTF-8 mit BOM) hat 122 Zeilen: Priorität, Typ, Empfänger, E-Mail, Kontaktseite, Status,
  zitierte Bedingungen, Haltestellen, Marken und Brief.
- Absender einmal in `freigabe/absender.json` eintragen, dann `python3 -I build_freigabe.py`. Antworten in `brand_status.json` eintragen und das Paket neu bauen.

**Zuerst senden (Priorität 1 und 2):**

| Prio | Empfänger | E-Mail | Betrifft |
|---|---|---|---|
| 1 | Amt der NÖ Landesregierung, LAD1 | post.lad1@noel.gv.at · 02742/9005-12001 | Landeswappen NÖ (Pflicht vor Anzeige) |
| 1 | Ski Arlberg (Marketing-Verbund) | marketing@skiarlberg.at · marketing@abbag.com · marketing@warth.co.at | Ski Arlberg |
| 1 | TVB St. Anton am Arlberg | info@stantonamarlberg.com | St. Anton am Arlberg |
| 1 | Lech-Zürs Tourismus GmbH | info@lechzuers.com | Lech Zürs am Arlberg |
| 1 | TVB Warth-Schröcken | info@warth-schroecken.at | Warth-Schröcken |
| 1 | Arlberger Bergbahnen AG | marketing@abbag.com | Arlberger Bergbahnen |
| 1 | Alpenregion Bludenz Tourismus GmbH | info@alpenregion.at | Klostertal, Alpenregion Bludenz, Brandnertal |
| 1 | Klostertaler Bergbahnen | info@sonnenkopf.com | Sonnenkopf |
| 2 | Ötztal Tourismus | info@oetztal.com · bergbahnen@obergurgl.com | Ötztal, Sölden, Gurgl (Lizenzvertrag) |
| 2 | Montafon Tourismus GmbH | info@montafon.at | Montafon (Registrierung) |
| 2 | TVB Seefeld | region@seefeld.com | Region Seefeld (schriftliche Genehmigung) |
| 2 | Kitzbühel Tourismus | presse@kitzbuehel.com | Kitzbühel (vorher anfragen) |
| 2 | Kärnten Werbung GmbH | info@kaernten.at | Landesmarke Kärnten |
| 2 | Steirische Tourismus und Standortmarketing GmbH | info@steiermark.com | Landesmarke Steiermark |
| 2 | Oberösterreich Tourismus GmbH | logo@oberoesterreich.at | Landesmarke Oberösterreich |

Die Landesregierungen der anderen 8 Länder müssen nicht angefragt werden; ihre Kontakte stehen in `Kontakte.csv` (Priorität 4).

---

## 9. Nächste Schritte

1. **Cloudflare-Workflow:**
   - R2-Bucket und Domain einrichten und `pack-2026100901.zip` hochladen.
   - Den `logos`-Block in `/v1/config` aufnehmen (KV oder Env); `config-2026100901.json` mit der echten Domain ist die Vorlage.
2. **App-Integration:**
   - `xcassets/Wappen` und die beiden Swift-Dateien übernehmen. `LogoPackStore` als Environment-Objekt am Root anhängen und
     `apply(config:)` an den bestehenden Config-Abruf hängen.
   - `StateMark` → `StateMarkW` umstellen und `SkiPassBadge` in Zeilen in `BrandChip` einbetten (Fallback = bisheriges Badge).
   - Gebietsleiste ins Haltestellen-Detail einbauen.
   - Unit-Tests in KlimaCore: `StoredZip` (Fixture-Zip ohne Logos), `BrandResolver` mit den Fällen Warth und St. Anton aus §7.
3. **Freigaben:** Absender eintragen, Priorität 1 und 2 versenden, Antworten in `brand_status.json` eintragen und neu bauen.
4. **Pflege:** Zillertal und die Logos mit nur kleiner Auflösung neu beschaffen, die Lücken aus §7 schließen und die Sonnenkopf-Zuordnung prüfen.
