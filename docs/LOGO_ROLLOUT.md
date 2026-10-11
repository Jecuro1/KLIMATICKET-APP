# Logo-Paket ausrollen (Skigebiets- und Regionslogos)

Stand 11. Okt. 2026. Ergänzt `docs/LOGO_SPEC.md` (§3 Auslieferung). Dieses Dokument sagt, was in der App schon fertig ist, was noch auf
das Logo-Paket wartet und wie das Paket auf Cloudflare kommt.

## Was schon in der App ist

- **Landeswappen** von 8 Ländern liegen im App-Bundle (`App/Resources/Assets.xcassets/Wappen`, gemeinfreie amtliche Werke). Sie erscheinen
  überall, wo eine Landesmarke steht (Suchzeilen, Routenkarte, Haltestellen-Detail). Niederösterreich hat kein Wappen: dort bleibt das eigene Wegzeichen.
- **Eigene Wegzeichen** (Skipass-Badge, Region-Chip, Linienschilder) sind der Ersatz, wenn ein Logo fehlt.
- **Download, Prüfung, Cache und Notbremsen** (`LogoPackStore`): Die App lädt das Paket erst beim ersten Bedarf (Suche mit Skigebiet, Haltestellen-Detail),
  prüft die ganze Datei und jedes Bild per SHA-256, installiert atomar in „Application Support“ und nimmt den Ordner aus dem Backup.
- **Schalter in der App:** Einstellungen › Darstellung › „Offizielle Logos & Wappen“ (Standard an). Aus heißt eigene Wegzeichen und kein Download.
- **Fernschalter** (ohne App-Update): `enabled`, `revoked`, `armsDisabled`, `armsEnabled` im Block `logos` der Remote-Config.

## Was vom Paket abhängt

Solange das Paket nicht online ist (oder der Worker den Block `logos` nicht ausliefert), zeigt die App **keine** Skigebiets- oder Regionslogos
und keine Gebietsleiste im Haltestellen-Detail. Alles andere funktioniert. Es gibt keinen Fehler und keine Meldung.

## Der Weg des Pakets

```
build_logo_pack.py  →  pack-2026100901.zip  →  Cloudflare R2  →  Worker-Variable LOGOS_CONFIG_JSON  →  GET /v1/config  →  App
```

1. **Paket bauen** (privater Logo-Arbeitsordner, nie im Repo): `python3 -I build_logo_pack.py`. Das ergibt `pack-<Version>.zip` und `config-<Version>.json`.
2. **Zip nach R2** (unveränderliche Datei):
   `wrangler r2 object put klimabilanz-static/logos/v1/pack-2026100901.zip --file pack-2026100901.zip --content-type application/zip --cache-control "public, max-age=31536000, immutable"`
3. **Config setzen:** Der Inhalt von `config-<Version>.json` (der Teil hinter `"logos":`) kommt als Variable `LOGOS_CONFIG_JSON` in den Worker
   (`wrangler secret put LOGOS_CONFIG_JSON` oder als Variable im Cloudflare-Dashboard). Der Worker reicht das JSON unverändert als Feld `logos`
   in `GET /v1/config` weiter (Code: `backend/src/routes/meta.ts`). Ist die Variable leer oder kein JSON-Objekt, fehlt das Feld und die App bleibt bei den eigenen Badges.
4. **Prüfen:** `GET <Worker>/v1/config` zeigt `logos.pack.url`. Die App holt die Config höchstens einmal pro Minute und lädt das Paket beim nächsten Bedarf.

Beispiel des Blocks (Werte aus `config-<Version>.json`, die URL ist die echte Domain des R2-Buckets):

```json
{ "enabled": true,
  "pack": { "schema": 1, "version": 2026100901, "url": "https://static.<domain>/logos/v1/pack-2026100901.zip",
            "sha256": "<sha256 der Zip-Datei>", "bytes": 2668266 },
  "revoked": [], "armsDisabled": [], "armsEnabled": [] }
```

## Ehrlich: was geht nur am Computer

Der Schritt 1 und 2 (`python3 -I build_logo_pack.py` und `wrangler r2 object put`) laufen in einem Terminal und brauchen einen Computer (oder
eine Cloud-Sitzung mit den Logo-Dateien). **Vom iPhone allein ist das nicht machbar.** Zwei Wege:

- **Mit Computer:** Die Befehle oben ausführen. Danach ist alles Weitere im Cloudflare-Dashboard am iPhone möglich: Variable `LOGOS_CONFIG_JSON`
  ändern (neue Version, Notbremse) und im Bucket-Browser eine Datei austauschen oder löschen.
- **Ohne Computer:** Du gibst Claude (der Lead-Sitzung) die Cloudflare-Zugangsdaten als Geheimnis (API-Token mit „R2 bearbeiten“ und „Workers Skripte bearbeiten“,
  dazu Account-ID und Bucket-Name). Dann lädt Claude das Paket einmal hoch und setzt die Variable. Das Token danach in Cloudflare widerrufen.

## Notbremse (Abmahnung, Beschwerde)

| Fall | Maßnahme | Wirkung |
|---|---|---|
| Marke X soll weg | `"revoked": ["x"]` in `LOGOS_CONFIG_JSON` | Bilder werden auf den Geräten beim nächsten Abruf gelöscht und nicht mehr gezeigt |
| Ein Land beschwert sich | `"armsDisabled": ["T"]` | Wappen dieses Landes verschwindet, die Landesmarke zeigt wieder die Streifen |
| Alles aus | `"enabled": false` | keine Logos und keine Wappen, kein Download |
| Niederösterreich stimmt zu | Paket mit `--arms AT-3` neu bauen, `"armsEnabled": ["NÖ"]` und `"NÖ"` aus `armsDisabled` | NÖ-Wappen aus dem Paket |

Danach das Zip aus R2 löschen und eine neue Paketversion ohne die Marke bauen (14 Tage alte Zips dürfen liegen bleiben).

## Rechtlicher Hinweis (Kurzfassung, keine Rechtsberatung)

- **Landeswappen:** Die neutrale Kennzeichnung „Haltestelle liegt in …“ ist in B, K, OÖ, S, T, V und W zulässig; in der Steiermark nur das kleine Wappen,
  in Wien nur der Kreuzschild. Niederösterreich verlangt vorherige Zustimmung (Brief liegt vor), bis dahin eigenes Wegzeichen.
- **Marken:** Skigebiets- und Regionslogos sind Marken ihrer Inhaber. Sie werden nur beschreibend, unverändert, klein, mit Copyright-Zeile und
  Link gezeigt, ohne Partnerschafts-Anschein und ohne Werbung. 9 Marken mit ausdrücklicher Lizenz- oder Genehmigungspflicht sind im Paket zurückgehalten.
- **Nicht gezeigt:** App-Symbol, App-Name, Store-Seite, Screenshots, Push, Teilen-Bilder, Widgets, Live Activities, Kartenpins und die Fahrtenliste.
- **Texte in der App:** Im Haltestellen-Detail steht „Logos © {Inhaber} – Marken der jeweiligen Inhaber, nur zur Ortsangabe. Landeswappen: amtliche Werke,
  nur zur geografischen Zuordnung. KlimaBilanz ist kein Angebot der Länder, Skigebiete oder Tourismusverbände.“ Derselbe Sinn steht unter
  Einstellungen › Über › Datenquellen › „Zeichen, Logos und Wappen“.
- **Der Inhaber trägt das Risiko** (Entscheidung vom 9. Okt. 2026). Takedown-Wünsche werden über `revoked` ohne App-Update umgesetzt.

## Nie ins Repo

Skigebiets-, Regions- und Markenlogos und das Paket selbst gehören **nicht** ins Repo (`.gitignore`: `*.logopack.zip`, `logo-pack/`, `brands/`).
Die CI prüft das mit `tools/check_no_brand_logos.py` („Trademark guard“). Vor jedem Push lokal:
`python3 tools/check_no_brand_logos.py .` muss „0 hit(s)“ melden.

## Test ohne echtes Paket

In Debug-Builds gibt es ein **synthetisches** Paket aus einfarbigen Flächen mit dem Wort „DEMO“ (`App/Sources/DesignSystem/Logos/DemoLogoPack.swift`).
Die Screenshot-Szenen `stationSearchLogos` und `stopDetailWarthLogos` zeigen damit, wie Zeilen und Gebietsleiste mit Logos aussehen.
Die Paket-Logik (Zip, Prüfsummen, Resolver) testet `Packages/KlimaCore/Tests/KlimaCoreTests/LogoPackTests.swift` mit demselben Prinzip.
