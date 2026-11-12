# Tarifstand – wie aktuell sind die Preise in der App?

> Das Versprechen der App ist „lohnt sich mein Ticket?“. Dafür müssen die Preise stimmen – auch rund um den Fahrplanwechsel
> (zweiter Sonntag im Dezember: 14.12.2025, 13.12.2026, 12.12.2027, …) und den Jahreswechsel, ohne auf eine neue App-Version zu
> warten. Die App **zeigt** deshalb, wie aktuell ihre Preise sind, **warnt**, wenn sie veraltet sein können, und kann die
> Relationspreis-Tabelle (die exakten ÖBB-Standardticket-Preise) wie die Tarife aus der Ferne aktualisieren.
> **Kein Ticketverkauf, keine Kaufempfehlung, kein ÖBB-Zugriff:** die Aktualisierung spricht nur mit dem Repository-Host des
> Eigentümers (GitHub), höchstens einmal pro 24 Stunden, mit einem schlichten GET und ohne personenbezogene Daten.

Code: `Packages/KlimaCore/Sources/KlimaCore/Tariff/` (Rechenkern, Linux-Tests in `Tests/KlimaCoreTests/Tariff/`),
`App/Sources/Services/Tariff/` (Download, CryptoKit, Zwischenspeicher), `App/Sources/Features/Ticket/TariffNoticeBanner.swift`
(Hinweis und Details), `App/Sources/Features/Settings/SetTarifstandRows.swift` (Zeilen in Einstellungen).

## 1. Was die App zeigt

**Hinweis im Ticket-Tab** (über der Gültigkeitskarte, eine Karte, ein Element für VoiceOver mit dem Hinweis „Doppeltippen für
Details“, Symbol und Text – nie nur Farbe, bricht bei größter Schrift um). Er erscheint nur, wenn der Zustand nicht „aktuell“ ist:

| Zustand (`TariffFreshness.State`) | Wann | Text |
|---|---|---|
| `newYear` | ab 1. Jänner, wenn **kein** Produkt der Familie KlimaTicket Ö einen Preiseintrag (`validFrom` oder `priceHistory`) ab dem 1. Jänner des laufenden Jahres hat | „Die Preise in der App stammen noch aus 2026 – Für 2027 sind noch keine KlimaTicket-Preise eingetragen; die App aktualisiert sich, sobald neue Preise vorliegen“ |
| `upcomingChange(Datum)` | ab 1. Dezember, solange der Tarifstand **nicht** nach dem 1. Dezember aktualisiert wurde (`updatedAt` ≥ 1.12. oder `relationsPack.validFrom` ≥ Tag des Fahrplanwechsels) | vor dem Wechsel „Fahrplanwechsel am 13.12. – Preise können sich ändern; …“, ab dem Wechsel „Seit dem Fahrplanwechsel am 13.12. – Preise können sich geändert haben; …“ |
| `stale(since:)` | der neueste Eintrag des Fahrpreisindex (`fareIndex`; ohne Index das Katalogdatum `updatedAt`) ist älter als 13 Monate | „Fahrpreise von September 2025 – Preise können abweichen; …“ |
| `current` | sonst | kein Hinweis |

Vorrang: `newYear`, dann `upcomingChange`, dann `stale`. Alle Tage zählen in Europe/Vienna. **Ein Hinweis nennt nie einen konkreten
neuen Preis** – er sagt nur, dass es einen geben kann und dass die App ihn von selbst lädt. Die Details (Tippen auf den Hinweis)
nennen nur, was der geladene Katalog enthält (z. B. „Aufschlag von 3,5 % auf den Normalpreis – so ist es im Tarifstand
hinterlegt“, wenn `fareIndex` einen Eintrag zum Tag des Wechsels hat).

`lastCheck` (letzter erfolgreicher Blick auf den Update-Server) ändert den Zustand **nicht**: „kein neuerer Katalog“ heißt nicht „die
Preise stimmen“.

**Einstellungen › Preisberechnung › Tarifstand** zeigt „Fahrpreise gültig ab 14.12.2025 · Ticketpreise Stand 1.1.2026 · zuletzt
geprüft 12.11.2026“ (Datum der benutzten Relationspreis-Tabelle, neuester KlimaTicket-Ö-Preiseintrag bis heute, letzter Blick auf
den Update-Server – ein fehlendes Datum fällt weg), ein Schild „Hinweis“, wenn der Zustand nicht „aktuell“ ist, und die Detailseite.
**Jetzt prüfen** erzwingt einen Blick (Tarife und Relationspreise, ohne die 12/24-Stunden-Grenze, aber nur mit höherer Version) und
antwortet **Aktuell**, **Aktualisiert**, **Kein Netz** oder **Fehlgeschlagen** (Server antwortet unbrauchbar); danach eine Haptik und
eine VoiceOver-Ansage. Die alten Zeilen „Tarif-Stand“ und „Tarife aktualisieren“ unter „Updates“ sind darin aufgegangen.

## 2. Der Katalog: `relationsPack` (optional, additiv)

`tariffs.json` (gebündelt und als Release-Anlage `tariffs.json` im neuesten Release) kann einen Block tragen; alte Dateien ohne ihn
dekodieren unverändert, alte App-Versionen ignorieren ihn:

```json
"relationsPack": {"url": "relations-pack.bin", "sha256": "…64 Hex…", "version": 1, "validFrom": "2025-12-14", "bytes": 633597}
```

- `url`: absolut (`https`) oder – wie hier – relativ zum Tarifdokument; sie muss auf demselben Host liegen (bei GitHub: `github.com`
  und `raw.githubusercontent.com` gelten als ein Host), sonst wird nichts geladen.
- `version`: wächst monoton; die App lädt nur, wenn sie höher ist als die der Tabelle, die sie benutzt (gebündelt: `version` in
  `relations-points.json`, fehlt sie: 1).
- `validFrom`: ab diesem Tag benutzt die App das Paket; vorher gilt die alte Tabelle (ein Paket zum Fahrplanwechsel kann vorab
  geladen werden).

`scripts/build_tariffs.py` übernimmt den Block aus `data/relations_pack_info.json` (geschrieben von
`scripts/build_relations_pack.py`) und hebt `CATALOG_VERSION` auf 5. `updatedAt` ist das **Prüfdatum** (das neuere von
`generatedAt` in `data/klimaticket_products.json` und einem optionalen `updatedAt` in `data/fare_model.json`) – es nur dann
vorziehen, wenn die Preise wirklich mit den amtlichen Quellen verglichen wurden: Ab dem 1. Dezember verschwindet damit der
Hinweis zum Fahrplanwechsel.

## 3. Das Paket `relations-pack.bin` („KBRP“)

Eine Datei mit Punkten (Haltestellen-IDs wie `stations.json`) und Preisen, Little Endian:

```
 0 "KBRP" | 4 u16 Format (1) | 6 u16 Flags (0) | 8 u32 Datenversion | 12 u32 gültig ab (yyyymmdd)
16 u32 Punkte | 20 u32 Relationen | 24 u32 Länge Punkte (gepackt) | 28 u32 Länge Punkte (roh)
32 u32 Länge Preise (gepackt) | 36 u32 CRC-32 Punkte | 40 u32 CRC-32 Preise | 44 u32 0
48 Abschnitt Punkte: rohes DEFLATE von {"source": …, "points": [{"name", "stationID"}]}
   Abschnitt Preise: rohes DEFLATE von Relationen × (u16 A, u16 B, u16 Preis in 10-Cent-Einheiten)
```

Eine Relation steht **einmal** (A < B), streng aufsteigend nach (A, B): das ist „symmetrisch“ – ein Preis gilt in beide Richtungen, es
gibt keinen zweiten, womöglich anderen. Gebaut wird sie mit `python3 scripts/build_relations_pack.py` aus den gebündelten Dateien
(`relations-points.json`, `relations.bin`) nach `data/relations-pack.bin`; `--check DATEI` prüft eine Datei. `scripts/make_release_metadata.py`
kopiert sie beim Release neben `tariffs.json` nach `dist/` (und bricht ab, wenn Hash oder Größe nicht zum Katalog passen);
`ios.yml` hängt sie an das Release.

**Prüfung vor dem Einbau** (`RelationPackValidator`, alle müssen bestehen, sonst bleibt die benutzte Tabelle):
Größe ≤ 8 MB und genau wie im Katalog · SHA-256 wie im Katalog · Magic „KBRP“, Format 1 · Datenversion und Gültigkeitstag wie im
Katalog · beide Abschnitte entpacken und passen zu ihrer CRC-32 · Haltestellen-IDs eindeutig · Relationen kanonisch und sortiert ·
Preis zwischen 1 und 30 000 Einheiten (nicht 0, nicht 65 535 = Klemmwert des Bauskripts) · Anzahl der Relationen innerhalb ±25 %
der benutzten Tabelle · Preisniveau: Median des Verhältnisses Paket/Tabelle auf bis zu 4 000 gemeinsamen Relationen zwischen
0,7 und 1,5 (fängt eine falsche Einheit ab).

**Ablauf** (`RelationPackUpdater`, in KlimaCore und mit Stub-Downloader getestet; die App ergänzt CryptoKit und URLSession):
höchstens ein Versuch pro 24 Stunden (der Versuch zählt, auch wenn er scheitert) · nur wenn die Version höher ist · nur auf dem
Host des Tarifdokuments · Datei und Meta (`relations-pack.bin`, `relations-pack-meta.json` in Application Support) werden
atomar geschrieben · beim Start wird das Paket **erneut** geprüft; eine beschädigte oder von der gebündelten Tabelle eingeholte
Zwischenablage wird gelöscht · bei **jedem** Fehler (kein Netz, falscher Hash, falsches Format) bleibt die gebündelte Tabelle.
`RelationPriceTable.preferred(bundled:pack:today:)` nimmt das Paket, wenn seine Version höher ist **und** `validFrom` nicht in der
Zukunft liegt.

**Keine doppelte Preiserhöhung:** `catalog.fareIndex` (z. B. +3,5 % ab 13.12.2026) wird auf Relationspreise nur noch **relativ zur
Gültigkeit der benutzten Tabelle** angewendet (`TariffCatalog.fareFactor(on:relativeTo:)`). Mit der gebündelten Tabelle (14.12.2025)
ändert sich nichts; ein Paket ab 13.12.2026 enthält die Erhöhung schon und bekommt sie nicht noch einmal aufgeschlagen (Fahrten
davor werden auf das alte Niveau zurückgerechnet).

## 4. Was der Eigentümer tun muss

**Fahrplanwechsel (13.12.2026):** neue Relationspreise von oebb.at prüfen → Tabelle bauen (`scripts/build_relations.py`, siehe §5),
`RELATIONS_VERSION` erhöhen → `python3 scripts/build_relations_pack.py --version 2 --valid-from 2026-12-13` → in
`data/fare_model.json` den Eintrag in `fareIndex` für den 13.12. entfernen oder auf den geprüften Wert setzen, `"updatedAt"` auf
den Prüftag setzen → `python3 scripts/build_tariffs.py` (`CATALOG_VERSION` erhöhen) → committen. Damit der Server die Dateien
ausliefert, **ohne neue App-Version**: `tariffs.json` und `relations-pack.bin` dem neuesten Release anhängen
(`gh release upload <tag> App/Resources/tariffs.json data/relations-pack.bin --clobber`) – die App liest sie unter
`…/releases/latest/download/`. Der Hinweis verschwindet, sobald der Katalog `updatedAt` ≥ 1.12. trägt.

**Jahreswechsel (1.1.2027):** KlimaTicket-Preise 2027 nur eintragen, wenn sie auf klimaticket.at oder vom Ministerium veröffentlicht
sind (Quelle ins Commit): in `data/klimaticket_products.json` je Produkt eine neue Zeile `status: "current"` mit
`validFrom: "2027-01-01"` und `sourceUrl`, die 2026-Zeile auf `historic`; dann `build_tariffs.py`. **Auch unveränderte Preise
brauchen den Eintrag**, sonst zeigt die App weiter „stammen noch aus 2026“.

## 5. Datenaufgaben – Stand (12.11.2026)

1. **Die 7 fehlenden Ursprünge** (Judenburg, Knittelfeld, Seefeld in Tirol, Selzthal, Spittal-Millstättersee, Wels, Wels Hbf) in
   `data/oebb_relation_prices.json`: **nicht erledigt.** `python3 scripts/build_relations.py` erzeugt ohne die Forschungsdatei
   `pairs_all.json` (`$PAIRS_ALL`, 210 000 Relationen, nicht im Repository) nur 28 432 Relationen statt der 178 013 der gebündelten
   `relations.bin` – das Skript reproduziert die gebündelte Datei also nicht byte-genau, und eine Neugenerierung würde
   Preise verlieren. Die Entfernungsrechnung (`FareEstimator`) bleibt für diese Ursprünge in Kraft. Voraussetzung: `pairs_all.json`
   (oder dessen Quelle, die ÖBB-Relationspreistabellen auf oebb.at, nicht die Live-API nach `docs/OEBB_LIVE.md` §2) liegt vor.
2. **KlimaTicket-Preise 2027:** **nicht eingetragen.** klimaticket.at nennt (Abruf 12.11.2026, über einen Zusammenfassungsdienst
   gelesen, von Hand gegenzuprüfen) eine Preiserhöhung „ab 1. Jänner 2027“, auf 2 % begrenzt, nur für Tickets mit Gültigkeitsbeginn ab
   diesem Tag – aber **keine Eurobeträge** (<https://www.klimaticket.at/>). Medien nennen für das Ö Classic 1.428 € (<https://exxpress.at/economy/klimaticket-wird-teurer-das-zahlen-pendler-ab-1-jaenner-2027/>),
   Beträge für Jugend/Senior/Spezial/Familie fehlen. Eine Quelle mit Beträgen ist nicht zitierbar, also bleibt `data/` unverändert und der
   Hinweis „Die Preise in der App stammen noch aus 2026“ erklärt es ab 1. Jänner.
3. **Paket veröffentlichen:** erledigt – `data/relations-pack.bin` (Version 1, gültig ab 14.12.2025, 633 597 Byte) ist die gebündelte
   Tabelle im Download-Format, `tariffs.json` verweist darauf. Version 1 = gebündelte Version: **die App lädt es nicht**, bis eine
   höhere Version veröffentlicht ist.

## 6. Geprüft und nicht geprüft

Linux (`swift test --filter Tariff`): Fahrplanwechsel 2025–2030 (zweiter Sonntag, immer ein Sonntag 1990–2100), Zustandswechsel um
den 1. Dezember und den 1. Jänner in Europe/Vienna mit eingesetzter Uhr (auch UTC-Grenze), Vorrang, 13-Monate-Grenze, Struktur der
gebündelten `tariffs.json` (80 Produkte, eindeutige IDs, Preise > 0, `validFrom` streng aufsteigend – schlägt bei vertauschter
Reihenfolge fehl), alter Katalog ohne `relationsPack`, Validator (falscher Hash, zu groß, falsche Magic/Format, Ausreißer bei Anzahl
und Preis, Kanonik, beschädigte Abschnitte, akzeptiert die gebündelte Tabelle und die veröffentlichte Datei), Updater mit
Stub-Downloader (gültiges Paket ersetzt, ungültiges nie, kein Netz lässt alles unberührt, 24 h, Version, Host), keine doppelte
Erhöhung.

**Nur auf dem Gerät prüfbar / ungeprüft:** der echte Download vom Repository-Host, der Austausch bei laufender App, der erste Start
ohne Netz, ob amtliche 2027-Preise schon vorliegen, und die Richtigkeit jedes neuen Preises gegen die amtliche Preisliste (Mensch).
Gerätetest: Flugmodus an, „Jetzt prüfen“ → „Kein Netz“, Zahlen unverändert; online → „Aktuell“.

**Grenzen:** „Aktuell“ heißt nur, dass kein neuerer Katalog und kein neueres Paket existieren. Läuft ein Weg über Zwischenhalte, von
denen einzelne nicht in der Tabelle stehen, mischt die Schätzung Tabellen- und Entfernungspreise; nach einem Paket mit eingerechneter
Erhöhung wird der Entfernungsanteil dieser seltenen Wege um die Erhöhung zu niedrig geschätzt (`FareEstimator+Via`).
