# Performance-Baseline

Stand: 12. November 2026. Gemessen vom CI-Job `perf` ([ios.yml](../.github/workflows/ios.yml)), Simulator, Release-Build, nur Demo-Daten und
Demo-Fahrplan – nie ein Zugriff auf die ÖBB. Regel dieses Pakets: **erst messen, dann beheben, dann aufteilen.** Ohne eine Zahl aus
diesem Dokument wird nichts optimiert.

## 1. Messaufbau

| | |
|---|---|
| Lauf 1 (Baseline, bestehende fünf Bildschirme) | [Lauf 383](https://github.com/Jecuro1/KLIMATICKET-APP/actions/runs/43234095971), Commit `d5b5df1`, 12.11.2026 |
| Lauf 2 (neue Bildschirme dazu, sonst derselbe Code) | [Lauf 387](https://github.com/Jecuro1/KLIMATICKET-APP/actions/runs/43239296214), Commit `9601e35`, 12.11.2026 |
| Runner | GitHub-gehosteter `macos-26`, arm64-VM (geteilt, ohne echte GPU) |
| Xcode / Simulator | 26.6 / iPhone 17 Pro, iOS 26.5 |
| Konfiguration | Schema `KlimaBilanzPerf`, Release, `-KBPerf YES -KBDemo YES` (Demo-Jahr, 79 Fahrten) und `-KBPerfTrips 1500` (+1 500 Fahrten) |
| Rohdaten | [docs/perf/baseline-383.json](perf/baseline-383.json), [docs/perf/run-387.json](perf/run-387.json) (der Teil von `perf-summary.json`, den `scripts/perf_compare.py` liest; Artefakte `perf-383` und `perf-387` laufen nach 30 Tagen ab) |

Drei Quellen liefern Zahlen: **Wischen** (XCUITest wischt über das Fenster, die App misst), **Tour** (die App scrollt sich selbst mit
2 400 pt/s, `PerfTour`; läuft unter dem Profiler `sample`) und **Profil** (`/usr/bin/sample`, 1 ms, Hauptthread je Tour-Phase,
`scripts/perf_profile.py`). Die Bildschirme der Kartenseite (Zug-Radar, Atlas) haben keine Scroll-Ansicht; ihre Drags sieht ein
passiver Pan-Beobachter des Monitors (`TouchObserver` in `PerfFrameMonitor.swift`). Der Start der Bildschirme steht unter
„Bildschirmwechsel“. Karten laden Kacheln von Apple (MapKit); alles andere kommt aus den Demo-Daten.

## 2. Messgröße und Bewertungsband

`PerfFrameMonitor` (`App/Sources/Services/Diagnostics/`), im Wortlaut seines Kopfkommentars:

> A frame interval above 1.5 × the expected duration is a hitch, its excess is hitch time; hitch time ratio = hitch ms per scrolled
> second (Apple: < 5 good, 5–10 noticeable, ≥ 10 critical).

Es ist dieselbe Größe wie Apples *Hitch Time Ratio* (ms Verzögerung pro s Animation), mit drei Unterschieden: Ein Frame zählt erst ab
dem 1,5-fachen der erwarteten Dauer (Apple zählt jede Verspätung), die Frames kommen von einem `CADisplayLink` (nicht vom
Render-Server) und der Simulator läuft mit 60 Hz ohne GPU. **Apples absolute Bänder gelten deshalb hier nicht:** Schon der ruhigste
Bildschirm (Gipfelbuch, 14–37 ms/s) liegt über dem „kritisch“-Wert von 10, und alle 26 gemessenen Zeilen wären „kritisch“. Das
Band wird aus der Verteilung der Messungen abgeleitet:

| Band | Hitch-Ratio auf diesem Runner | Wer liegt dort |
|---|---|---|
| gut | bis 60 ms/s | Gipfelbuch, Haltestelle (Wischen 49,1; die Tour mit 60,1 liegt an der Grenze), Verbindungsdetail (Tour) |
| spürbar | 60 bis 250 ms/s | Fahrplan, Verbindungen, Meine Routen, Verbindungsdetail (Wischen), Ticket, Übersicht, Fahrten (Wischen) |
| kritisch | über 250 ms/s | Statistik, Fahrten (Tour), Atlas, Zug-Radar, Karte mit Ebenen |

Die Grenzen 60 und 250 liegen in den Lücken der gemessenen Verteilung (Lauf 2, 26 Zeilen: nichts zwischen 60,1 und 93,8, nichts zwischen
216,3 und 291,1); die Zuordnung oben gilt für die Werte von Lauf 2. Sie sind **relativ**: Sie ordnen die Bildschirme auf diesem Runner und sagen nichts über ein iPhone. Der Hänger-Wächter
(`HangWatchdog`, Hauptthread länger als 250 ms) hat seine eigene Grenze und bleibt unverändert.

## 3. Lauf 1: Baseline der bestehenden Bildschirme

App-Start (von der App gemessen, Median):

| Daten | Starts | Prozessstart → erstes Bild | App.init → erstes Bild | längster Frame danach (4 s) | Ruckeln danach |
|---|---:|---:|---:|---:|---:|
| +1 500 Fahrten | 5 | 5200 ms | 1926 ms | 908 ms | 1829 ms |
| Demo-Jahr | 11 | 3932 ms | 1322 ms | 842 ms | 1504 ms |

LaunchTrace `perf+0` (11 Starts, Median ms seit App.init): app.init 28 → relations.built 338 → stations.built 392 → state.services 402 → app.ready 403 → root.task 1435 → root.appear 1438 → auth.loaded 3934

LaunchTrace `perf+1500` (11 Starts, Median ms seit App.init): app.init 24 → relations.built 938 → state.services 956 → app.ready 956 → stations.built 973 → root.task 1924 → root.appear 1926 → auth.loaded 4427

Scrollen (Spalte „Bewertung“ nach dem Band aus §2):

| Bildschirm | Daten | Quelle | Hitch-Ratio | Hitches (≥ 3 Frames) | längster Frame | Bildrate | Scrollzeit | Bewertung |
|---|---|---|---:|---:|---:|---:|---:|---|
| Fahrten | +1 500 Fahrten | Wischen (XCUITest) | 208.7 ms/s | 531 (88) | 166 ms | 47 fps | 63.4 s | spürbar |
| Fahrten | +1 500 Fahrten | Tour (2 400 pt/s) | 719.6 ms/s | 194 (155) | 185 ms | 17 fps | 15.1 s | kritisch |
| Fahrten | Demo-Jahr | Wischen (XCUITest) | 227.9 ms/s | 545 (104) | 207 ms | 46 fps | 61.6 s | spürbar |
| Gipfelbuch | +1 500 Fahrten | Tour (2 400 pt/s) | 37.2 ms/s | 2 (0) | 50 ms | 58 fps | 1.7 s | gut |
| Gipfelbuch | Demo-Jahr | Wischen (XCUITest) | 30.7 ms/s | 37 (8) | 92 ms | 58 fps | 30.0 s | gut |
| Statistik | +1 500 Fahrten | Wischen (XCUITest) | 474.8 ms/s | 740 (182) | 396 ms | 31 fps | 46.4 s | kritisch |
| Statistik | +1 500 Fahrten | Tour (2 400 pt/s) | 465.3 ms/s | 188 (47) | 349 ms | 32 fps | 14.2 s | kritisch |
| Statistik | Demo-Jahr | Wischen (XCUITest) | 417.4 ms/s | 703 (157) | 146 ms | 34 fps | 45.0 s | kritisch |
| Ticket | +1 500 Fahrten | Wischen (XCUITest) | 325.6 ms/s | 429 (96) | 337 ms | 40 fps | 41.8 s | kritisch |
| Ticket | +1 500 Fahrten | Tour (2 400 pt/s) | 234.4 ms/s | 36 (6) | 105 ms | 46 fps | 3.9 s | spürbar |
| Ticket | Demo-Jahr | Wischen (XCUITest) | 213.3 ms/s | 295 (71) | 224 ms | 47 fps | 42.6 s | spürbar |
| Übersicht | +1 500 Fahrten | Wischen (XCUITest) | 309.0 ms/s | 353 (77) | 337 ms | 41 fps | 33.2 s | kritisch |
| Übersicht | +1 500 Fahrten | Tour (2 400 pt/s) | 162.5 ms/s | 16 (0) | 47 ms | 50 fps | 1.8 s | spürbar |
| Übersicht | Demo-Jahr | Wischen (XCUITest) | 315.3 ms/s | 348 (83) | 210 ms | 41 fps | 33.3 s | kritisch |

Bildschirmwechsel:

| nach | Daten | Wechsel | erstes Bild (Median / max) | längster Frame | Ruckeln (Median) |
|---|---|---:|---:|---:|---:|
| Fahrten | +1 500 Fahrten | 7 | 1990 / 3470 ms | 264 ms | 629 ms |
| Fahrten | Demo-Jahr | 6 | 717 / 2083 ms | 224 ms | 245 ms |
| Gipfelbuch | +1 500 Fahrten | 1 | 1554 / 1554 ms | 149 ms | 669 ms |
| Gipfelbuch | Demo-Jahr | 1 | 1686 / 1686 ms | 3193 ms | 3176 ms |
| Statistik | +1 500 Fahrten | 7 | 3248 / 7196 ms | 1496 ms | 1226 ms |
| Statistik | Demo-Jahr | 6 | 1791 / 5605 ms | 1155 ms | 830 ms |
| Ticket | +1 500 Fahrten | 7 | 2051 / 3853 ms | 1052 ms | 1079 ms |
| Ticket | Demo-Jahr | 6 | 906 / 2325 ms | 846 ms | 928 ms |
| Übersicht | +1 500 Fahrten | 5 | 1532 / 1768 ms | 293 ms | 462 ms |
| Übersicht | Demo-Jahr | 4 | 631 / 735 ms | 257 ms | 443 ms |

Speicher:

| Bildschirm | Daten | Spitze |
|---|---|---:|
| Fahrten | +1 500 Fahrten | 363 MB |
| Fahrten | Demo-Jahr | 289 MB |
| Gipfelbuch | +1 500 Fahrten | 171 MB |
| Gipfelbuch | Demo-Jahr | 185 MB |
| Statistik | +1 500 Fahrten | 500 MB |
| Statistik | Demo-Jahr | 356 MB |
| Ticket | +1 500 Fahrten | 530 MB |
| Ticket | Demo-Jahr | 364 MB |
| Übersicht | +1 500 Fahrten | 381 MB |
| Übersicht | Demo-Jahr | 308 MB |

Hänger über 250 ms (Watchdog, Summe über den ganzen Lauf):


| Bildschirm | Daten | Anzahl | längster | gesamt |
|---|---|---:|---:|---:|
| Fahrten | +1 500 Fahrten | 9 | 7150 ms | 26841 ms |
| Statistik | +1 500 Fahrten | 14 | 5574 ms | 25251 ms |
| Statistik | Demo-Jahr | 12 | 5037 ms | 19852 ms |
| Ticket | +1 500 Fahrten | 10 | 2095 ms | 12556 ms |
| Übersicht | +1 500 Fahrten | 12 | 1714 ms | 9814 ms |
| Ticket | Demo-Jahr | 8 | 2041 ms | 8068 ms |
| Gipfelbuch | Demo-Jahr | 5 | 2112 ms | 5246 ms |
| Fahrten | Demo-Jahr | 4 | 1978 ms | 4429 ms |
| Übersicht | Demo-Jahr | 7 | 560 ms | 2929 ms |
| Gipfelbuch | +1 500 Fahrten | 1 | 1179 ms | 1179 ms |

Tab-Runde:

| Daten | Dauer | CPU | Speicher-Spitze |
|---|---:|---:|---:|
| +1 500 Fahrten | 20.94 s | 13.65 s | 474 MB |
| Demo-Jahr | 16.00 s | 8.32 s | 373 MB |

XCTest-Start: 7,096 s (4 Starts, Streuung 2,8 %).

## 4. Lauf 2: die neuen Bildschirme (Scotty-Ersatz)

Scrollen und Panen (die neuen Zeilen: Atlas, Fahrplan, Haltestelle, Karte mit Ebenen, Meine Routen, Verbindungen, Verbindungsdetail, Zug-Radar):

| Bildschirm | Daten | Quelle | Hitch-Ratio | Hitches (≥ 3 Frames) | längster Frame | Bildrate | Scrollzeit | Bewertung |
|---|---|---|---:|---:|---:|---:|---:|---|
| Atlas | Demo-Jahr | Wischen (XCUITest) | 368.0 ms/s | 73 (16) | 82 ms | 37 fps | 5.0 s | kritisch |
| Fahrplan | +1 500 Fahrten | Tour (2 400 pt/s) | 93.8 ms/s | 1 (1) | 51 ms | 54 fps | 0.4 s | spürbar |
| Fahrplan | Demo-Jahr | Wischen (XCUITest) | 160.2 ms/s | 219 (22) | 58 ms | 50 fps | 29.4 s | spürbar |
| Fahrten | +1 500 Fahrten | Wischen (XCUITest) | 139.1 ms/s | 348 (37) | 185 ms | 51 fps | 60.4 s | spürbar |
| Fahrten | +1 500 Fahrten | Tour (2 400 pt/s) | 556.2 ms/s | 215 (100) | 137 ms | 26 fps | 13.9 s | kritisch |
| Fahrten | Demo-Jahr | Wischen (XCUITest) | 172.6 ms/s | 447 (53) | 225 ms | 50 fps | 61.4 s | spürbar |
| Gipfelbuch | +1 500 Fahrten | Tour (2 400 pt/s) | 30.7 ms/s | 3 (0) | 39 ms | 58 fps | 1.7 s | gut |
| Gipfelbuch | Demo-Jahr | Wischen (XCUITest) | 13.7 ms/s | 18 (2) | 75 ms | 59 fps | 28.9 s | gut |
| Haltestelle | +1 500 Fahrten | Tour (2 400 pt/s) | 60.1 ms/s | 25 (5) | 79 ms | 56 fps | 9.4 s | spürbar |
| Haltestelle | Demo-Jahr | Wischen (XCUITest) | 49.1 ms/s | 213 (0) | 48 ms | 57 fps | 78.3 s | gut |
| Karte mit Ebenen | Demo-Jahr | Wischen (XCUITest) | 291.1 ms/s | 64 (18) | 115 ms | 42 fps | 5.9 s | kritisch |
| Meine Routen | Demo-Jahr | Wischen (XCUITest) | 93.9 ms/s | 137 (14) | 63 ms | 54 fps | 32.7 s | spürbar |
| Statistik | +1 500 Fahrten | Wischen (XCUITest) | 345.2 ms/s | 612 (105) | 294 ms | 39 fps | 44.3 s | kritisch |
| Statistik | +1 500 Fahrten | Tour (2 400 pt/s) | 329.7 ms/s | 163 (37) | 227 ms | 40 fps | 14.5 s | kritisch |
| Statistik | Demo-Jahr | Wischen (XCUITest) | 311.6 ms/s | 572 (87) | 84 ms | 41 fps | 41.5 s | kritisch |
| Ticket | +1 500 Fahrten | Wischen (XCUITest) | 174.7 ms/s | 298 (31) | 152 ms | 49 fps | 40.2 s | spürbar |
| Ticket | +1 500 Fahrten | Tour (2 400 pt/s) | 118.3 ms/s | 22 (2) | 51 ms | 53 fps | 3.7 s | spürbar |
| Ticket | Demo-Jahr | Wischen (XCUITest) | 216.3 ms/s | 352 (55) | 167 ms | 47 fps | 41.9 s | spürbar |
| Verbindungen | +1 500 Fahrten | Tour (2 400 pt/s) | 100.6 ms/s | 10 (0) | 38 ms | 54 fps | 1.8 s | spürbar |
| Verbindungen | Demo-Jahr | Wischen (XCUITest) | 188.4 ms/s | 279 (52) | 169 ms | 49 fps | 45.3 s | spürbar |
| Verbindungsdetail | +1 500 Fahrten | Tour (2 400 pt/s) | 19.7 ms/s | 2 (1) | 50 ms | 59 fps | 2.5 s | gut |
| Verbindungsdetail | Demo-Jahr | Wischen (XCUITest) | 149.9 ms/s | 219 (29) | 166 ms | 51 fps | 37.3 s | spürbar |
| Zug-Radar | Demo-Jahr | Wischen (XCUITest) | 370.4 ms/s | 144 (52) | 92 ms | 37 fps | 11.3 s | kritisch |
| Übersicht | +1 500 Fahrten | Wischen (XCUITest) | 179.8 ms/s | 255 (23) | 147 ms | 49 fps | 32.0 s | spürbar |
| Übersicht | +1 500 Fahrten | Tour (2 400 pt/s) | 190.7 ms/s | 16 (1) | 96 ms | 48 fps | 2.1 s | spürbar |
| Übersicht | Demo-Jahr | Wischen (XCUITest) | 188.6 ms/s | 253 (29) | 167 ms | 49 fps | 31.4 s | spürbar |

Bildschirmwechsel:

| nach | Daten | Wechsel | erstes Bild (Median / max) | längster Frame | Ruckeln (Median) |
|---|---|---:|---:|---:|---:|
| Atlas | +1 500 Fahrten | 1 | 2267 / 2267 ms | 390 ms | 1367 ms |
| Atlas | Demo-Jahr | 1 | 1730 / 1730 ms | 542 ms | 1381 ms |
| Fahrplan | +1 500 Fahrten | 3 | 866 / 1421 ms | 97 ms | 345 ms |
| Fahrplan | Demo-Jahr | 3 | 1037 / 1248 ms | 654 ms | 158 ms |
| Fahrten | +1 500 Fahrten | 7 | 1617 / 2564 ms | 129 ms | 184 ms |
| Fahrten | Demo-Jahr | 6 | 753 / 1977 ms | 228 ms | 143 ms |
| Gipfelbuch | +1 500 Fahrten | 1 | 945 / 945 ms | 147 ms | 741 ms |
| Gipfelbuch | Demo-Jahr | 1 | 1217 / 1217 ms | 1450 ms | 1678 ms |
| Haltestelle | +1 500 Fahrten | 1 | 3669 / 3669 ms | 1398 ms | 1508 ms |
| Haltestelle | Demo-Jahr | 1 | 1032 / 1032 ms | 172 ms | 828 ms |
| Karte mit Ebenen | +1 500 Fahrten | 1 | 942 / 942 ms | 764 ms | 1367 ms |
| Karte mit Ebenen | Demo-Jahr | 1 | 863 / 863 ms | 987 ms | 1429 ms |
| Meine Routen | +1 500 Fahrten | 1 | 347 / 347 ms | 28 ms | 12 ms |
| Meine Routen | Demo-Jahr | 1 | 546 / 546 ms | 195 ms | 239 ms |
| Statistik | +1 500 Fahrten | 7 | 2478 / 7929 ms | 1071 ms | 507 ms |
| Statistik | Demo-Jahr | 6 | 1573 / 5000 ms | 359 ms | 427 ms |
| Ticket | +1 500 Fahrten | 7 | 1773 / 3590 ms | 766 ms | 783 ms |
| Ticket | Demo-Jahr | 6 | 914 / 2453 ms | 748 ms | 686 ms |
| Verbindungen | +1 500 Fahrten | 2 | 632 / 693 ms | 1102 ms | 1031 ms |
| Verbindungen | Demo-Jahr | 2 | 376 / 751 ms | 1530 ms | 1184 ms |
| Verbindungsdetail | +1 500 Fahrten | 1 | 1541 / 1541 ms | 888 ms | 1329 ms |
| Verbindungsdetail | Demo-Jahr | 1 | 895 / 895 ms | 262 ms | 840 ms |
| Zug-Radar | +1 500 Fahrten | 1 | 5809 / 5809 ms | 258 ms | 1062 ms |
| Zug-Radar | Demo-Jahr | 1 | 765 / 765 ms | 1225 ms | 1424 ms |
| Übersicht | +1 500 Fahrten | 5 | 1440 / 1575 ms | 226 ms | 301 ms |
| Übersicht | Demo-Jahr | 4 | 575 / 935 ms | 262 ms | 299 ms |

Speicher:

| Bildschirm | Daten | Spitze |
|---|---|---:|
| Atlas | +1 500 Fahrten | 218 MB |
| Atlas | Demo-Jahr | 295 MB |
| Fahrplan | +1 500 Fahrten | 150 MB |
| Fahrplan | Demo-Jahr | 147 MB |
| Fahrten | +1 500 Fahrten | 368 MB |
| Fahrten | Demo-Jahr | 288 MB |
| Gipfelbuch | +1 500 Fahrten | 170 MB |
| Gipfelbuch | Demo-Jahr | 223 MB |
| Haltestelle | +1 500 Fahrten | 206 MB |
| Haltestelle | Demo-Jahr | 210 MB |
| Karte mit Ebenen | +1 500 Fahrten | 237 MB |
| Karte mit Ebenen | Demo-Jahr | 292 MB |
| Meine Routen | +1 500 Fahrten | 137 MB |
| Meine Routen | Demo-Jahr | 134 MB |
| Statistik | +1 500 Fahrten | 444 MB |
| Statistik | Demo-Jahr | 343 MB |
| Ticket | +1 500 Fahrten | 443 MB |
| Ticket | Demo-Jahr | 364 MB |
| Verbindungen | +1 500 Fahrten | 163 MB |
| Verbindungen | Demo-Jahr | 205 MB |
| Verbindungsdetail | +1 500 Fahrten | 236 MB |
| Verbindungsdetail | Demo-Jahr | 242 MB |
| Zug-Radar | +1 500 Fahrten | 192 MB |
| Zug-Radar | Demo-Jahr | 286 MB |
| Übersicht | +1 500 Fahrten | 386 MB |
| Übersicht | Demo-Jahr | 307 MB |

XCTest (Drags über das Fenster, Uhr und Speicher):


| Bildschirm | Dauer der Drags | Speicher-Spitze | Test |
|---|---:|---:|---|
| Atlas | 17.05 s | 301 MB | passed |
| Verbindungsdetail | 21.90 s | 197 MB | passed |
| Fahrplan | 19.06 s | 137 MB | passed |
| Verbindungen | 48.41 s | 196 MB | passed |
| Karte mit Ebenen | 16.20 s | 292 MB | passed |
| Zug-Radar | 14.50 s | 288 MB | passed |
| Meine Routen | 23.87 s | 132 MB | passed |
| Haltestelle | 35.26 s | 206 MB | passed |

Alle 20 Tests liefen durch, 0 Fehler (Dauer 39 Minuten). XCTest-Start in diesem Lauf: 4,402 s.

## 5. Hauptthread-Hotspots (Profil, Lauf 1, +1 500 Fahrten)

Die fünf größten Posten, über alle Tour-Phasen aufsummiert (5,5 s belegter Hauptthread, ohne den Messcode `PerfTour` und
`PerfFrameMonitor`). Das Profil schreibt jedes 1-ms-Sample der innersten App-Funktion auf dem Stack zu; was SwiftUI, Charts oder
CoreAnimation selbst tun, steht unter „ohne App-Frame“.

| # | Posten | ms | Anteil |
|---|---|---:|---:|
| 1 | SwiftUI-Graph (`AttributeGraph`: `UpdateStack::update`, `propagate_dirty`, `Subgraph::update`), als CPU-Blatt | 745 | 14 % |
| 2 | `objc_msgSend` | 213 | 4 % |
| 3 | Swift Charts (Statistik) | 84 | 2 % |
| 4 | `StatsSavingsCard.wedgePath(proxy:)` (die einzige App-Funktion über 20 ms) | 24 | 0,4 % |
| 5 | `WorkCarChart.wedgePath(points:proxy:)` | 23 | 0,4 % |

Von den 5 478 ms Hauptthreadzeit hängen **4 933 ms (90 %) an keiner App-Funktion**: Es ist die Arbeit von SwiftUI, UIKit und
CoreAnimation. Der Hauptthread war beim Scrollen belegt zu: Statistik 39 % (2 098 ms in 5,3 s), Fahrten 31 %, Gipfelbuch 6 %,
Ticket 10 %, Übersicht 8 %. Beim Öffnen eines Tabs waren es 17 bis 195 ms. Lauf 2 ergänzt die Bildschirme der Karten- und
Fahrplanseite:

| Phase | Hauptthread belegt | App-Anteil |
|---|---|---|
| Zug-Radar öffnen (erstes Mal im Prozess) | 3 168 ms in 3,6 s | 1 955 ms in `CUIStructuredThemeStore lookupAssetForKey:`: SF-Symbol-Vektorglyphen (`Image.NamedImageProvider.vectorInfo`) werden beim ersten Gebrauch aus dem Katalog des Simulators geladen (dazu 508 ms `read`, 187 ms `getdirentries64`). Kein App-Code, kalter Dateicache des Runners |
| Zug-Radar mit Ebenen, Scrollen | 479 ms in 10,2 s | 162 ms davon wartet MapKit auf `CAMetalLayer nextDrawable` (Render-Server, kein App-Code) |
| Haltestelle öffnen | 903 ms in 2,2 s | `StopDetailView.tripStats` 45 ms, davon 41 ms das Holen **aller** Fahrten durch `@Query` (+1 500 Fahrten); `MetaFlowLayout` 16 ms; der Rest Laufzeit-Erstkosten (Protokoll-Suche 75 ms, Symbolkatalog 35 ms) |
| Fahrplan / Verbindungen öffnen | 155 / 237 ms | `PlannerHomeView.body` 21 / 43 ms (31 + 12 ms in zwei Auswertungen), im Profil ganz innerhalb von SwiftData: das `@Query` über alle Fahrten (+1 500 Fahrten) |
| Atlas öffnen / Scrollen | 49 / 101 ms | nichts |
| Meine Routen öffnen / Scrollen | 104 / 218 ms | nichts |

Datenabhängig ist nur eine App-Funktion: `Analytics.make`. Bei +1 500 Fahrten kostet ein Aufruf Ø 23,3 ms (78 Aufrufe, Maximum
121 ms; nur 14 davon rechnen wirklich, Ø 31,9 ms, die übrigen sind Treffer im Memo für Ø rund 17 ms, fast alles Lesen der SwiftData-
Eigenschaften für den Schlüssel), beim Demo-Jahr Ø 3,7 ms. Das Memo-Verfahren ist exakt (Schlüssel: Zeitraum, Tag, je Fahrt Id, Datum,
`updatedAt`); eine billigere Schlüsselbildung, die nicht dasselbe liest, würde Ergebnisse veralteter Eingaben liefern.

## 6. Was die Messung nicht hergibt (Störgrößen)

- **Der Runner schwankt stark.** Lauf 1 und 2 haben denselben App-Code auf den bestehenden Bildschirmen; die Hitch-Ratio unterschied
  sich um bis zu 50 % (Übersicht Wischen 315 → 189, Ticket +1 500 Fahrten Wischen 326 → 175, Gipfelbuch 31 → 14), der XCTest-Start um 38 %
  (7,10 → 4,40 s), der Prozessstart bis zum ersten Bild um 44 % (3 932 → 2 215 ms). Ein einzelner Vergleich zeigt Änderungen unter
  50 % nicht verlässlich; `scripts/perf_compare.py` verwendet deshalb 50 % als Toleranz.
- **XCUITest läuft auf dem Hauptthread der App mit:** Jede Abfrage des Accessibility-Baums blockiert ihn (große Bäume: Statistik mit
  Charts, Fahrtenliste). Die Hänger von 2 bis 7 s und die „erstes Bild“-Zeiten über 1 s in der Wischen-Spalte stammen zu einem
  unbekannten Teil daher: Das Profil der Tour (ohne XCUITest) zeigt für dieselben Tab-Wechsel 17 bis 195 ms belegten Hauptthread.
- **Die Touren laufen unter `sample`** (1-kHz-Stack-Aufnahme) und der Profiler bremst den Hauptthread; die Tour-Spalte ist deshalb
  höher als sie ohne Profiler wäre.
- **Der Simulator rendert in Software.** Die Hauptthread-Auslastung beim Scrollen (6 bis 39 %) reicht nicht, um 17 bis 26 fps
  (Fahrten, Tour) zu erklären; der Rest liegt im Render-Server. Das bestätigt `CAMetalLayer nextDrawable` im Zug-Radar.
- **Erste Benutzung von Symbolen und Protokollen** (`swift_conformsToProtocolMaybeInstantiateSuper`, SF-Symbol-Katalog) ist beim
  ersten Mal in einem Prozess teuer und danach gecacht.

Folge für den Vergleich vorher/nachher: Die Hitch-Ratio taugt für Unterschiede ab etwa Faktor 2 (und für die Rangfolge der
Bildschirme). Für kleinere Änderungen braucht es mehrere Läufe oder ein Gerät.

## 7. Lauf 1 gegen Lauf 2 (derselbe Code, nur der Messaufbau ist erweitert)

Das ist der zweite `[perf]`-Lauf. Er sagt, wie weit zwei Läufe ohne Codeänderung auseinanderliegen. Toleranz 50 %, nur Bildschirme aus
beiden Läufen:

### Scrollen: Hitch Time Ratio (ms Ruckeln pro s Scrollen, kleiner ist besser)

| Bildschirm · Daten · Quelle | vorher | nachher | Differenz | Urteil |
|---|---:|---:|---:|---|
| Fahrten · +1 500 Fahrten · touch | 208.7 ms/s | 139.1 ms/s | -69.5 | gleich |
| Fahrten · +1 500 Fahrten · tour | 719.6 ms/s | 556.2 ms/s | -163.5 | gleich |
| Fahrten · Demo-Jahr · touch | 227.9 ms/s | 172.6 ms/s | -55.3 | gleich |
| Gipfelbuch · +1 500 Fahrten · tour | 37.2 ms/s | 30.7 ms/s | -6.5 | gleich |
| Gipfelbuch · Demo-Jahr · touch | 30.7 ms/s | 13.7 ms/s | -17.1 | besser |
| Statistik · +1 500 Fahrten · touch | 474.8 ms/s | 345.2 ms/s | -129.6 | gleich |
| Statistik · +1 500 Fahrten · tour | 465.3 ms/s | 329.7 ms/s | -135.6 | gleich |
| Statistik · Demo-Jahr · touch | 417.4 ms/s | 311.6 ms/s | -105.8 | gleich |
| Ticket · +1 500 Fahrten · touch | 325.6 ms/s | 174.7 ms/s | -150.9 | gleich |
| Ticket · +1 500 Fahrten · tour | 234.4 ms/s | 118.3 ms/s | -116.1 | gleich |
| Ticket · Demo-Jahr · touch | 213.3 ms/s | 216.3 ms/s | +3.0 | gleich |
| Übersicht · +1 500 Fahrten · touch | 309.0 ms/s | 179.8 ms/s | -129.2 | gleich |
| Übersicht · +1 500 Fahrten · tour | 162.5 ms/s | 190.7 ms/s | +28.2 | gleich |
| Übersicht · Demo-Jahr · touch | 315.3 ms/s | 188.6 ms/s | -126.7 | gleich |

### Bildschirmwechsel: Zeit bis zum ersten Bild

| nach · Daten | vorher | nachher | Differenz | Urteil |
|---|---:|---:|---:|---|
| Fahrten · +1 500 Fahrten | 1990 ms | 1617 ms | -373 | gleich |
| Fahrten · Demo-Jahr | 717 ms | 753 ms | +36 | gleich |
| Gipfelbuch · +1 500 Fahrten | 1554 ms | 945 ms | -609 | gleich |
| Gipfelbuch · Demo-Jahr | 1686 ms | 1217 ms | -469 | gleich |
| Statistik · +1 500 Fahrten | 3248 ms | 2478 ms | -769 | gleich |
| Statistik · Demo-Jahr | 1791 ms | 1573 ms | -219 | gleich |
| Ticket · +1 500 Fahrten | 2051 ms | 1773 ms | -277 | gleich |
| Ticket · Demo-Jahr | 906 ms | 914 ms | +8 | gleich |
| Übersicht · +1 500 Fahrten | 1532 ms | 1440 ms | -92 | gleich |
| Übersicht · Demo-Jahr | 631 ms | 575 ms | -55 | gleich |

### Bildschirmwechsel: längster Frame danach

| nach · Daten | vorher | nachher | Differenz | Urteil |
|---|---:|---:|---:|---|
| Fahrten · +1 500 Fahrten | 264 ms | 129 ms | -135 | besser |
| Fahrten · Demo-Jahr | 224 ms | 228 ms | +4 | gleich |
| Gipfelbuch · +1 500 Fahrten | 149 ms | 147 ms | -3 | gleich |
| Gipfelbuch · Demo-Jahr | 3193 ms | 1450 ms | -1743 | besser |
| Statistik · +1 500 Fahrten | 1496 ms | 1071 ms | -425 | gleich |
| Statistik · Demo-Jahr | 1155 ms | 359 ms | -796 | besser |
| Ticket · +1 500 Fahrten | 1052 ms | 766 ms | -286 | gleich |
| Ticket · Demo-Jahr | 846 ms | 748 ms | -98 | gleich |
| Übersicht · +1 500 Fahrten | 293 ms | 226 ms | -67 | gleich |
| Übersicht · Demo-Jahr | 257 ms | 262 ms | +6 | gleich |

### Start: App.init bis erstes Bild

| Daten | vorher | nachher | Differenz | Urteil |
|---|---:|---:|---:|---|
| +1 500 Fahrten | 1926 ms | 1073 ms | -854 | gleich |
| Demo-Jahr | 1322 ms | 727 ms | -595 | gleich |

### Speicher: Spitze je Bildschirm

| Bildschirm · Daten | vorher | nachher | Differenz | Urteil |
|---|---:|---:|---:|---|
| Fahrten · +1 500 Fahrten | 363 MB | 368 MB | +5 | gleich |
| Fahrten · Demo-Jahr | 289 MB | 288 MB | -1 | gleich |
| Gipfelbuch · +1 500 Fahrten | 171 MB | 170 MB | -0 | gleich |
| Gipfelbuch · Demo-Jahr | 185 MB | 223 MB | +39 | gleich |
| Statistik · +1 500 Fahrten | 500 MB | 444 MB | -56 | gleich |
| Statistik · Demo-Jahr | 356 MB | 343 MB | -13 | gleich |
| Ticket · +1 500 Fahrten | 530 MB | 443 MB | -87 | gleich |
| Ticket · Demo-Jahr | 364 MB | 364 MB | -0 | gleich |
| Übersicht · +1 500 Fahrten | 381 MB | 386 MB | +5 | gleich |
| Übersicht · Demo-Jahr | 308 MB | 307 MB | -1 | gleich |

### Hänger über 250 ms (Watchdog): Gesamtdauer

| Bildschirm · Daten | vorher | nachher | Differenz | Urteil |
|---|---:|---:|---:|---|
| Statistik · +1 500 Fahrten | 25251 ms | 25071 ms | -181 | gleich |
| Fahrten · +1 500 Fahrten | 26841 ms | 13769 ms | -13072 | gleich |
| Statistik · Demo-Jahr | 19852 ms | 11875 ms | -7977 | gleich |
| Ticket · +1 500 Fahrten | 12556 ms | 11287 ms | -1269 | gleich |
| Ticket · Demo-Jahr | 8068 ms | 8212 ms | +144 | gleich |
| Übersicht · +1 500 Fahrten | 9814 ms | 5420 ms | -4394 | gleich |
| Fahrten · Demo-Jahr | 4429 ms | 3290 ms | -1139 | gleich |
| Gipfelbuch · +1 500 Fahrten | 1179 ms | 2735 ms | +1556 | schlechter |
| Gipfelbuch · Demo-Jahr | 5246 ms | 1280 ms | -3966 | besser |
| Übersicht · Demo-Jahr | 2929 ms | – | – | entfernt |

1 Wert(e) schlechter als vorher:
- Hänger über 250 ms (Watchdog): Gesamtdauer: Gipfelbuch · +1 500 Fahrten

## 8. Befunde und Entscheidungen

Entscheidungsregel: Ein Bildschirm bekommt einen Codefix, wenn er im Band „kritisch“ liegt **und** das Profil einer App-Funktion
mindestens 10 % seiner belegten Hauptthreadzeit zuschreibt (sonst wäre der Fix geraten), oder wenn der Hauptthread länger als 250 ms
**durch App-Code** blockiert (nicht durch XCUITest, den Simulator-Dateicache oder MapKit).

| Bildschirm | Band | Profil | Entscheidung |
|---|---|---|---|
| Statistik | kritisch (312 bis 475) | 39 % belegt, aber nur rund 6 % davon in App-Funktionen (Chart-Overlays von `StatsSavingsCard` 43 ms, `WorkCarChart` 25 ms, `MetaPurposeCard.donut` 14 ms, `StatsTicketComparisonCard` 12 ms); der Rest ist SwiftUI/Charts | **kein Codefix.** Die größte einzelne App-Position belegt 2 % der Hauptthreadzeit; eine Änderung läge unter der Messstreuung. Die Charts wachsen beim ersten Sichtbarwerden absichtlich (`StatsGrowOnView`) |
| Fahrten | kritisch nur in der Tour (556 bis 720), beim Wischen spürbar | 31 % belegt, rund 2 % App (`TripsView.monthSection`/`row` 16 ms, `TripListRow.body` 13 ms) | **kein Codefix.** `TripsView.swift` ist laut Auftrag gesperrt (andere Pakete hängen daran); die Zeilen-Funktionen liegen bei 2 % |
| Atlas, Zug-Radar, Karte mit Ebenen | kritisch (291 bis 370, je eine Messung) | 49 bis 479 ms Hauptthread; keine App-Funktion; MapKit wartet auf den Render-Server | **kein Codefix.** Ursache liegt im Simulator-Rendern der Karte; auf dem Gerät messen |
| Zug-Radar, erstes Öffnen | Hänger 3,2 s | 1,96 s Symbol-Katalog im kalten Simulator | **kein Codefix** (kein App-Code). Auf dem Gerät nachmessen |
| Ticket, Übersicht | spürbar | 8 bis 10 % belegt, Rest SwiftUI | kein Fix nötig nach Regel |
| Fahrplan, Verbindungen, Verbindungsdetail, Meine Routen, Haltestelle, Gipfelbuch | gut bis spürbar | nichts Auffälliges | kein Fix nötig |
| Haltestelle öffnen, Fahrplan öffnen | – | `@Query` über alle Fahrten: 41 ms (`StopDetailView.tripStats`) bzw. 31 und 12 ms je Auswertung (`PlannerHomeView.body`), jeweils vollständig innerhalb von SwiftData (Profil bestätigt), bei +1 500 Fahrten | **offen, nicht angefasst.** Der Fix wäre ein `@Query`-Prädikat auf die Stations-Ids bzw. eine begrenzte Abfrage. SwiftData-Prädikate mit optionalen Strings und `contains` werden erst zur Laufzeit geprüft (sie lassen sich auf Linux nicht testen); ein Fehler würde die Ansicht zum Absturz bringen. Der Gewinn (ein Frame beim Öffnen, nur bei Pendlern mit sehr vielen Fahrten) rechtfertigt das nicht ohne einen Lauf auf macOS |
| `Analytics.make` bei vielen Fahrten | – | Treffer Ø 17 ms bei +1 500 Fahrten | **offen, nicht angefasst.** Eine billigere Schlüsselbildung ändert die Semantik des Memos (siehe §5); ein Weg ohne Semantikänderung ist nicht in Sicht |

Das Ergebnis dieses Pakets ist deshalb **kein Codefix**: Die Baseline zeigt keine App-Funktion, deren Beseitigung über der
Messstreuung läge. Ein Fix, den die Messung nicht stützt, wäre Raten und würde in jedem Vergleich als Rauschen erscheinen. Was
wirklich schwer wiegt (SwiftUI-Graph-Updates, Render-Last der Glas-Karten, Karten-Frames), lässt sich auf dem CI-Simulator nicht
verlässlich verbessern, weil er in Software rendert.

## 9. Nicht verifizierbar in CI

- **Verhalten auf dem Gerät** bei 60 und 120 Hz (ProMotion: erwartete Frame-Dauer 8,3 ms), Thermik und Drosselung: Die
  Simulator-Zahlen sind relativ zueinander brauchbar, nicht absolut.
- **Speicher der Widget-Extension** (Grenze rund 30 MB): im CI nicht messbar, hier ungemessen.
- **Startzeit eines sideloaded Builds** auf dem iPhone (hier: 2,2 bis 3,9 s Prozessstart bis zum ersten Bild im Simulator, davon
  1,3 s ab `App.init`).
- **Karten:** Kacheln, Metal-Rendering und Annotationen in realer Menge (das Radar zeigt in der Demo 4 Fahrzeuge, echt sind es
  Hunderte); die Obergrenze der Annotationen ist ungeprüft.

Empfehlung für den nächsten Schritt: Auf einem iPhone mit Instruments (*Animation Hitches*, *SwiftUI*) die Statistik und die
Fahrtenliste messen und das Radar mit einer echten Fahrzeugmenge; MetricKit (`MXAnimationMetric`) sammelt Hitch-Zahlen aus dem
Alltag und die Diagnose-Seite der App zeigt sie bereits an.

## 10. Neu messen

```
# Lauf auslösen: Commit-Nachricht mit [perf], oder Actions › iOS › Run workflow mit perf = true (rund 55 bis 95 Minuten)
# Artefakt perf-<Lauf> laden, dann zwei Läufe nebeneinander legen:
python3 scripts/perf_compare.py docs/perf/baseline-383.json <neu>/perf-summary.json
```

Vor jeder Behauptung „besser“: Streuung beachten (§6), im Zweifel zwei Läufe nehmen. Die Hitch-Zahlen eines Bildschirms sind
nur mit demselben Datensatz (Demo-Jahr oder +1 500 Fahrten) und derselben Quelle (Wischen oder Tour) vergleichbar.
