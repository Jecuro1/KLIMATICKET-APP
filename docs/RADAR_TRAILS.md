# Spuren auf dem Radar (radartrail)

Stand 2026-11-19. Teil der zweiten Radar-Welle (radar2). Code: `App/Sources/Features/Radar/Trail/`,
`Packages/KlimaCore/Sources/KlimaCore/Live/Radar/Trail/`, Tests in `Packages/KlimaCore/Tests/KlimaCoreTests/Live/Radar/Trail/`. Eingebunden nur über die
Naht der zweiten Welle (`Radar2/Radar2Seam.swift`, `docs/RADAR_MODES.md` §13) und eine Zeile im `ScreenshotRouter`. Regeln für Live-Daten:
`docs/OEBB_LIVE.md` §2, §R11 (hier §R11.6).

## 1. Was eine Spur ist – und was nicht

Solange das Radar offen ist, merkt es sich im Arbeitsspeicher, wo die ÖBB-Auskunft jedes Fahrzeug **berechnet** hat, und zeichnet das als Linie hinter
dem Fahrzeug: hinten blass, vorne kräftig, auf einer hellen Kontur, in der Farbe des Verkehrsmittels. Im Fahrtblatt zeigt eine kleine Linie, wie sich
die Verspätung „seit du zuschaust“ bewegt hat.

- **Kein GPS-Verlauf.** Die Punkte sind die Positionen, die die Auskunft aus Fahrplan und Echtzeit-Meldungen rechnet (wie jeder Marker des Radars).
  Springt ein Fahrzeug, weil eine neue Verspätungsmeldung es auf seiner Strecke zurücksetzt, springt auch die Spur – das hat die Auskunft so gesagt.
- **Keine Aufzeichnung der ÖBB.** Es gibt keinen „Verlauf“ vom Server; die Spur besteht nur aus den Antworten, die *dieses iPhone* bekommen hat,
  seit das Radar offen ist. Vorher, an anderen Orten der Karte und in Lücken (offline, Hintergrund, Zeitreise) gibt es nichts.
- **Keine Anfrage.** Spuren schicken nichts, fragen nichts nach und verbrauchen nichts vom Budget des Radars (24 je Minute).

Wahl in „Filter & Darstellung“ › Darstellung › **Spuren**: „Aus“, „Ausgewählte und meine“ (Standard), „Alle im Ausschnitt“; **Länge** 5, 10 (Standard)
oder 20 Minuten.

## 2. Woher die Punkte kommen

- Jede Antwort, die die Live-Schleife übernimmt (`RadarModel.fetch` → `Radar2Parts.didMerge`, beide Ebenen der Abfrage – breite und Stadt-Ebene, §R11.4), gibt jedem Fahrzeug
  darin **einen Punkt zur Anfragezeit** (`RadarQuery.when`, die Zeit, für die die Positionen gelten), nicht zur Ankunftszeit der Antwort.
- Eine langsame Antwort kommt manchmal nach einer jüngeren: ihr Punkt wird zeitlich **dazwischen** eingefügt und ersetzt nie einen jüngeren.
  Zweimal derselbe Moment (ein Fahrzeug an einer Kachelgrenze) behält den ersten.
- **Steht ein Fahrzeug** (höchstens 20 m vom vorigen Punkt, gleiche Verspätung, gleicher Ausfall-Stand), wird nur der vorige Punkt verlängert: ein
  stehendes Fahrzeug kostet einen Punkt und zeichnet keine Spur.
- **Warum die Spur am Marker endet:** Das Radar zeichnet jedes Fahrzeug 20 bis 120 s hinter der Uhr (`RadarEstimate`, gleitend zwischen den letzten
  zwei Antworten). Die jüngste Antwort liegt also *vor* dem Marker. Die Spur lässt jeden Punkt weg, der jünger ist als der gezeichnete Moment, und
  endet genau am Marker: hält er an der jüngsten Antwort, zählt sie mit; solange er gleitet, ist der Moment der, für den sein Punkt auf der Strecke
  zwischen den beiden Antworten steht, zwischen denen er gleitet (`RadarTrailGeometry.drawnMoment`). So bleibt auch eine Antwort einer anderen Kachel
  weg, die zwischen diesen beiden liegt und schon vor dem Marker ist (mit der Pünktlichkeit fragt das Radar ganz Österreich und den Ausschnitt; die
  Zeit „vor der jüngsten Antwort“ des ersten Baus hätte dort einen Sporn über den Marker hinaus gezeichnet, Review). Nie eine Linie über den Marker
  hinaus (`RadarTrailGeometryTests`, `RadarTrailReviewTests`).
- **Lücken:** liegen zwei Punkte mehr als 150 s auseinander (offline, Stromsparmodus, Hintergrund, Zeitreise, eine Kachel ohne Antwort), bricht die
  Linie ab. Auch der Marker wird nicht über eine solche Lücke verbunden.
- **Ausgedünnt für den Zoom** (Douglas–Peucker): Punkte, die weniger als 2 Bildschirmpunkte (mindestens 10 m) von der Linie abweichen, fallen weg,
  höchstens 30 Punkte je Stück; der Zoom zählt in halben Oktaven, damit kleine Zoomschritte die Linie nicht neu rechnen. Ein Stück kürzer als 6
  Bildschirmpunkte wird nicht gezeichnet (der Marker würde es verdecken).

## 3. Speicher und Datenschutz

- **Nur im Arbeitsspeicher.** Kein Punkt wird je in eine Datei, in die Einstellungen, in eine Sicherung, ein Protokoll, ein Teilen-Blatt oder eine
  Anfrage geschrieben. Gespeichert wird nur die Wahl (`radar.trail.v1`, je Gerät, wie jede App-Einstellung in der iPhone-Sicherung; in Screenshot-
  und Perf-Starts weder gelesen noch geschrieben).
- **Wächter:** `RadarTrailSourceGuardTests` durchsucht beide Ordner dieser Funktion (App und KlimaCore) ohne Kommentare und schlägt fehl bei
  `FileManager`, `write(to:`, `Data(contentsOf:`, `URLSession`, `NSKeyedArchiver`, `Logger(`, `os_log`, `NSLog`, `print(`, `ShareLink`,
  `fileExporter`, Teilen-, iCloud- und Anfrage-Typen (`RadarService`, `TimetableService`, `HafasClient`, `claimSlot`, `RequestThrottle`) sowie
  `UserDefaults`/`@AppStorage` außerhalb von `RadarTrailSettingStore.swift`.
- **Fenster:** die gewählte Länge plus 2 Minuten (für den Anfang der Verspätungslinie); ältere Punkte fallen bei jeder Antwort weg, ein Stand, der
  davor begann, behält nur seinen Teil im Fenster.
- **Harte Obergrenzen** (getestet): 70 Punkte je Fahrt (20 Minuten + 2 bei 20 s sind 66), 4 000 Fahrten, 50 000 Punkte; darüber gehen die
  Fahrten zuerst, die am längsten in keiner Antwort mehr waren. Ein Punkt belegt 24 Byte (Koordinaten als `Float`, unter einem Meter genau).
  Obergrenze nach `MemoryLayout`, Wachstum der Arrays doppelt gerechnet: 4,2 MB; im Dauerlauf (1 000 Fahrzeuge, alle 20 s eine Antwort, 30 Minuten,
  20-Minuten-Fenster) höchstens 2,4 MB (`RadarTrailRecorderTests`).
- **Gelöscht:** Radar geschlossen (das Modell gehört zur Radar-Ansicht und geht mit ihr; keine Aufgabe hält es fest, `[weak self]`), Zugriff zu –
  keine Zustimmung, „Live-Fahrplan“ aus, Notschalter, Funktionen › Offline-Modus (`Radar2Hooks` → `end(.accessClosed)`), Wahl „Aus“ (löscht und
  nimmt nichts mehr auf). Ein ausgeschaltetes Verkehrsmittel nimmt seine Spuren sofort mit (`didRemove(products:)`).
- **Behalten:** offline (wie die Zeitreise beim Unterbrechen; gezeichnet wird dann nichts, §7) und im Hintergrund, solange iOS die App lebt – es kommt
  nichts dazu, und beendet iOS den Prozess, ist alles weg.

## 4. Welche Spuren

| Wahl | gezeichnet | Grenzen |
|---|---|---|
| Aus | keine; nichts wird aufgenommen | – |
| Ausgewählte und meine | das gewählte Fahrzeug (zuerst), das verfolgte („Live verfolgen“), die Fahrzeuge gemerkter Linien („Meine Fahrzeuge“, `RadarMineModel.remembers`; die Fußzeile sagt es: „„Meine“ sind das Fahrzeug, das du live verfolgst, und die Fahrzeuge deiner gemerkten Linien.“) | höchstens 12 |
| Alle im Ausschnitt | jedes einzeln gezeichnete Fahrzeug | Karte höchstens 0,5° hoch (etwa 55 km) und höchstens 60 Einzelmarker; sonst „mine“ und ein Hinweis mit dem Grund, der gilt: „Für alle Spuren ist die Karte zu weit.“ (zuerst, Heranzoomen hilft zuerst) oder „Zu viele Fahrzeuge für alle Spuren.“, dann „Gezeigt werden deine.“ (nur wenn welche gezeichnet sind) und „Zoom näher heran.“ |

Nur **Einzelmarker** bekommen eine Spur: eine Gruppe hat keinen Marker, an dem eine Linie enden könnte. Die Spur des gewählten Fahrzeugs ist 5 pt
breit, die anderen 4 pt, die Kontur 5 pt breiter (weiß 85 %, im dunklen Kartenstil 30 %); die ältere Hälfte (nach der Zeit) 45 %, die jüngere voll,
ältere Stücke vor einer Lücke blass. Zuerst alle Konturen, dann die blassen, dann die kräftigen Linien: eine kreuzende Spur deckt nie die Farbe einer
anderen mit ihrer Kontur zu. Spuren sind Overlays und liegen damit immer unter den Markern, mit der Pünktlichkeit über den Sechsecken
(`.aboveRoads`, nach ihnen deklariert). Keine Animation, kein `TimelineView`: Bewegung reduzieren ändert nichts.

**Kosten:** höchstens 60 Spuren mit je drei Overlays. Die ausgedünnten Linien liegen je Fahrt im Modell, bis eine neue Antwort, ein anderer Moment oder
ein anderer Zoom kommt; bei jedem Neuaufbau der Marker (1 s in der Stadt) kommt nur der Marker-Punkt dazu – MapKit ersetzt dabei aber Kontur und
jüngere Hälfte jeder Spur. Ob das Schwenken mit 60 Spuren ruckelt, zeigt nur ein Gerät (§11); wenn ja, wird „Alle“ auf 20 begrenzt und die Fußzeile
sagt „höchstens 20 Spuren“.

## 5. Verspätung, seit du zuschaust

- Im Fahrtblatt unter den Knöpfen: „Verspätung, seit du zuschaust“, darunter z. B. „+3 → +5 Min · steigt“, „+4 Min · gleich“, „+6 → +2 Min · sinkt“,
  „pünktlich → +5 Min · steigt“, „+3 → +4 Min · etwa gleich“, „+3 Min → fällt aus“ und „Seit 14:21 · aus den Antworten, die dieses iPhone bekommen hat“.
- Werte: die Verspätung, die das Fahrzeug zum Moment jeder Antwort hatte (`RadarDelay.currentDelay`, die des nächsten Halts), in ganzen Minuten wie
  die Marker. Gleiche Nachbarn werden zusammengelegt (Anfang und Ende jedes gleichen Stücks bleiben, die Linie bleibt flach, solange die Verspätung
  gleich war); Antworten ohne Echtzeit werden übersprungen; eine Antwort mit Ausfall beendet die Reihe.
- **Trend** vom ersten zum letzten Wert: ab +2 Minuten „steigt“, ab −2 „sinkt“, sonst „gleich“ (gleiche Werte) oder „etwa gleich“.
- **Nur mit genug Daten:** mindestens drei Momente mit Verspätung über mindestens zwei Minuten (ein Stand zählt mit Anfang und Ende); sonst fehlt die
  Zeile ganz – kein leeres Versprechen.
- Die Linie ist 44 pt hoch bei jeder Schriftgröße, in `Theme.summit`, ein heller Streifen in `Theme.positive` (12 %) markiert „pünktlich“ (unter
  5 Minuten, die Schwelle der Marker), erster und letzter Wert stehen darunter. Die Linie steht bei jeder Schriftgröße unter dem Text, so breit wie
  die Karte (neben dem Text brach die Zeile in den ersten Screenshots in fünf Zeilen um). VoiceOver liest die Zeile als einen Satz: „Verspätung seit
  14 Uhr 21 von 3 auf 5 Minuten gestiegen.“

## 6. Warum keine zweite Zeitreise

Die Zeitreise bietet −30 Minuten, berechnet. Die Punkte dieser Funktion fließen bewusst **nicht** in sie ein:

1. **Andere Aussage.** Die Zeitreise sagt für jeden Zug „Berechnet aus dem Fahrplan und den Verspätungen von jetzt. Das ist keine Aufzeichnung.“ Ein
   Spur-Punkt ist die Position der Auskunft für *ihren* Moment mit der Echtzeit *jenes* Moments. Gemischt würden manche Züge der einen, ihre
   Nachbarn der anderen Quelle folgen, der Satz wäre für manche falsch, und die Regel durchgezogen/gestrichelt bräuchte eine dritte Bedeutung.
2. **Andere Abdeckung.** Spuren kennen nur die Kacheln, die du angesehen hast, dafür jedes Verkehrsmittel; die Zeitreise kennt ganz Österreich, nur
   Züge. „Bessere“ Positionen in einer Stadt und gerechnete anderswo wären eine unsichtbare Qualitätsgrenze.
3. **Keine Ersparnis.** Die Zeitreise fragt Österreich zu festen 20-Minuten-Punkten; ein paar aufgenommene Kacheln ersetzen keine davon.
4. **Geprüfte Bedeutung.** `RadarTimeline` liest ein fehlendes Fahrzeug in einer vollständigen Antwort als „zu dieser Minute nicht unterwegs“;
   Kachel-Antworten sind Teilbilder und bräuchten eine neue Art Momentaufnahme in einer fremden Datei – für wenig Gewinn.

Darum: keine Zeitachse, kein Schieber (der „Rückblick“ des alten Plans entfällt). Ist die Zeitreise weg von „Jetzt“, sind die Spuren ausgeblendet (das
Bild zeigt eine andere Zeit; die Zeitreise zeichnet ihre eigene, berechnete Spur) und es kommt nichts dazu (die Live-Schleife pausiert). Zurück bei
„Jetzt“ sind die Spuren wieder da; die fehlenden Minuten sind eine Lücke, nie eine Linie.

## 7. Zusammenspiel

| Zustand | Aufnahme | Spuren | Zeile unter der Statuskarte |
|---|---|---|---|
| Radar, Zug-Ebene an | nimmt auf | ja | „Spuren seit 14:21 · berechnete Positionen, kein GPS-Verlauf“, sobald eine gezeichnet ist |
| Pünktlichkeit an | nimmt auf (beide Ebenen der Abfrage) | ja, über den Sechsecken, bis zu den Punkten | wie oben |
| Zeitreise offen bei „Jetzt“ | nimmt auf | ja | wie oben |
| Zeitreise weg von „Jetzt“ | ruht (es kommt nichts) | nein | „Spuren gibt es nur bei „Jetzt“.“ – nur wenn eine Spur zurückkäme (bei „Alle“: irgendeine, sonst die des gewählten oder verfolgten Fahrzeugs) |
| Cockpit offen | ruht | – | – |
| Stromsparmodus | ruht (außer „Jetzt aktualisieren“) | ja, der letzte Stand | wie oben |
| offline | ruht, **behält** | nein (offline zeichnet das Radar keine Marker) | – |
| Zug-Ebene aus | nimmt mit der Pünktlichkeit weiter auf | nein | – |
| Zugriff zu (Zustimmung, Schalter, Notschalter, Offline-Modus) | **gelöscht** | – | – |
| Radar zu | **weg** | – | – |
| Hintergrund | ruht, behält (solange iOS die App lebt) | – | – |

**Cockpit:** öffnet sich die Cockpit-Ansicht für einen Zug, bekommt sie dessen aufgenommene Positionen der letzten drei Minuten vor der Antwort, mit
der sie startet, als frühere Antworten mit (`RadarTrailRecorder.headStart`, getestet in `RadarTrailRecorderTests`: nur dieser Zug, nur jünger als drei
Minuten, nur davor). So schätzt sie die Geschwindigkeit sofort statt erst nach zwei eigenen Antworten; bisher hatten das nur die Demo-Szenen. Mit „Aus“ gibt es
nichts mitzugeben, und das Cockpit startet wie bisher mit einer Antwort.

„seit“ ist der älteste Moment, den die gezeichneten Linien zeigen (`RadarTrailGeometry.oldestMoment`): nie früher als die gewählte Länge vor dem
Marker – ein Stand, der davor begann, zählt erst ab dort (`RadarTrailGeometry.window`). Der erste Bau nahm „jetzt minus Länge“; die Marker stehen aber
20 bis 120 s hinter der Uhr und halten im Stromsparmodus ihre letzte Antwort, die Linien reichten dann weiter zurück, als die Zeile sagte (Review).
Ohne gezeichnete Linie gilt der spätere von erster Antwort und jetzt minus Länge. VoiceOver: „Spuren zeigen die
Positionen, die dieses iPhone seit 14 Uhr 21 bekommen hat. Berechnet, kein GPS-Verlauf.“ Die Linien selbst sind für VoiceOver Dekoration; die Zeile
trägt die Bedeutung, und nie die Farbe allein.

## 8. Texte

Alle in `RadarTrailText` (KlimaCore, getestet in `RadarTrailTextTests` und `RadarDelaySeriesTests`): Abschnitt „Spuren“ mit „Aus“, „Ausgewählte und
meine“, „Alle im Ausschnitt“, „Länge“ mit „5 Min“, „10 Min“, „20 Min“, Fußzeile „Eine Spur zeigt, wo die Auskunft das Fahrzeug berechnet hat, seit das
Radar offen ist. Das Radar merkt sich das nur im Arbeitsspeicher und vergisst es beim Schließen.“; die Zeilen aus §4, §5 und §7. Zeiten 24 h in
Europe/Vienna. Nie „GPS“ ohne „kein“, nie „live gesehen“, „echt“ oder „Aufzeichnung“.

## 9. Demo und Screenshots

Nur synthetisch, kein Netz, keine Systemabfrage. In Demo- und Screenshot-Starts bekommt jedes synthetische Fahrzeug (`demo|…`) bei der ersten
Antwort seiner Kachel zwanzig erfundene Minuten davor (`RadarTrailDemo`): die Strecken-Züge von `DemoScotty` früher auf ihrer Linie (vor der Abfahrt
stehen sie am ersten Bahnhof: ein Punkt, keine Spur), REX 92 mit einer wachsenden Verspätung (pünktlich in Wien abgefahren, dann Minute für Minute bis
zu den +9 seiner Haltestellenliste), die Stadtflotten von radarmodes zu früheren Zeiten (sie fahren nach der Uhr; gerechnet abseits des Hauptthreads).
Echte Fahrten (ohne `demo|`) bekommen nie eine erfundene Vorgeschichte.

Szenen (`RadarTrailScreenshotHost`, eine Zeile im `ScreenshotRouter`):

| Szene | Inhalt |
|---|---|
| `radarTrails` | Westbahn Amstetten–Wien, nur die Zug-Ebene, Länge 20 Minuten: RJX 66 gewählt, REX 92 verfolgt, beide Spuren enden am Marker |
| `radarTrailsCity` | Wien nah mit allen Verkehrsmitteln (radarmodes' Wien-Szene), „Alle im Ausschnitt“, 5 Minuten |
| `radarTrailsTooMany` | dieselbe Westbahn mit „Alle“: zu weit für alle, der Hinweis und nur „deine“ |
| `radarTrailSheet` | Fahrtblatt von REX 92 (mit seinen eigenen Demo-Halten) und der steigenden Verspätungslinie |
| `radarTrailsSettings` | der Abschnitt „Spuren“, wie er die Darstellung-Seite beendet (eine CI-Szene kann das Formular eines Blatts nicht ans Ende rollen) |
| `radarTrailsAX5` | die drei Zeilen unter der Statuskarte bei der größten Schrift, über der Karte |
| `radarTrailSheetAX5` | die Zeile des Fahrtblatts bei der größten Schrift |

## 10. Geprüft / nicht geprüft

Geprüft (Linux, `swift test --filter "RadarTrail|RadarDelaySeries"`, 63 Tests, davon 6 aus dem Review in `RadarTrailReviewTests`): Reihenfolge, Einfügen älterer Antworten, Verdichtung bei 19/21 m und bei
Verspätungswechsel, Fenster auf die Sekunde, Entfernen nach Verkehrsmittel, Löschen, alle drei Obergrenzen, Dauerlauf und Speichergrenze; Ende am
Marker, Lücke 150/151 s, Ausdünnung (Ecke bleibt, 5-m-Zittern geht, 10-m-Untergrenze, höchstens 30 Punkte, Breitengrad-Maßstab), Hälften, Sichtbarkeit;
Auswahl (aus, deine bis 12, alle bis 0,5° und 60), Einstellung mit unbekannten Werten, wann gezeichnet, offline/zu, die Zeile unter der Statuskarte;
Verspätungsreihe (zeigbar, zusammengelegt, Stand, Trend-Schwellen, Ausfall, ohne Echtzeit) und jeder Text; der Quellen-Wächter; der Vorlauf des
Cockpits. Linux-Typprüfung der App
ohne Fehler; drei CI-Screenshot-Läufe hell und dunkel (§9, Runs 44587469508, 44594871293, 44604769653). Was sie zeigten und änderten: die Westbahn
mit Stations-Blasen war unlesbar (jetzt nur die Zug-Ebene, 20 Minuten RJX 66 von Wien bis vor Amstetten, die Spur endet am Marker); die Verspätungszeile
brach neben der Linie in fünf Zeilen um (jetzt volle Breite, die Linie darunter so breit wie die Karte); das Fahrtblatt sagte „Pünktlich“ über einer
Linie bis +9, weil der Demo-Fahrplan jede Fahrt mit derselben Musterfahrt beantwortet (die Szene gibt REX 92 jetzt seine eigenen Halte); der Hinweis
„Zu viele Fahrzeuge“ stand über drei Zügen (jetzt nennt er den Grund, der gilt: „Für alle Spuren ist die Karte zu weit.“); bei AX5 schwebte das Symbol
der Zeile neben dem Text (jetzt ohne Symbol). Auf der Radar-Ansicht selbst liegt die Zeile bei AX5 unter der großen Statuskarte (dort rollt die
untere Fläche); die AX5-Szenen zeigen die Zeilen und die Fahrtblatt-Zeile darum für sich.

**Review (2026-11-19):** der Moment, an dem die Spur endet, ist jetzt der des Markers selbst (eine Antwort einer anderen Kachel zwischen den beiden,
zwischen denen er gleitet, zeichnete einen Sporn über ihn hinaus); „seit“ ist der älteste gezeichnete Moment statt „jetzt minus Länge“ (die Linien
reichen bei 20 bis 120 s Rückstand der Marker weiter zurück); der Zoom-Maßstab ist immer endlich (ein `NaN` hätte in `Int(…)` die App beendet); alle
480 Zustände des Radar-Tors (Ebenen, Zugriff, Nur-Züge, aktiv, Cockpit, Zeitreise offen/weg) mal den drei Wahlen: gezeichnet nur mit Markern, bei
„Jetzt“ und mit der Wahl an, ohne neue Antworten nur, wo niemand die Karte sieht (Cockpit, App nicht aktiv), offline und zu nie, die Zeile spricht nie
von Spuren ohne Marker. Die Demo-Fahrt REX 92 fährt nach Amstetten und heißt jetzt auch so (das Fahrtblatt sagte „Richtung Wiener Neustadt Hbf“ über
Halten nach Westen). Beide Demo-Züge der Westbahn-Szene sind Züge in derselben Farbe auf derselben Strecke: die Spur von REX 92 (sechs Minuten seit
Wien) liegt unter seinem Marker und dem der S 45 und ist im Bild nicht von der Spur des RJX 66 zu unterscheiden.

Nicht geprüft: echte Antworten über eine lange Sitzung (Sprünge durch Verspätungsmeldungen, wie oft Kachelgrenzen doppelte Momente liefern);
MapKit-Kosten mit 60 Spuren beim Schwenken; der Speicher auf einem Gerät; ob iOS die App im Hintergrund lange genug lebt, dass die Lücke sichtbar wird.

## 11. Geräte-Checkliste

1. Wien, alle Verkehrsmittel, „Alle im Ausschnitt“, fünf Minuten lang schwenken und zoomen: flüssig? Wenn nicht: „Alle“ auf 20 begrenzen (§4).
2. Länge 20 Minuten, Radar 25 Minuten offen: Speicheranzeige in Xcode bleibt flach (Obergrenze 4,2 MB).
3. Einen Zug wählen, eine Minute warten: die Spur endet genau am Marker, auch während er gleitet; nie eine Linie vor dem Marker.
4. App 10 Minuten in den Hintergrund, zurück: Lücke, keine Linie über die fehlenden Minuten.
5. Flugmodus: keine Marker, keine Spuren; Flugmodus aus: Spuren mit Lücke wieder da.
6. „Live-Fahrplan“ aus und wieder an: keine Spur mehr von vorher.
7. Zeitreise weg von „Jetzt“: keine Live-Spur, die Zeile „Spuren gibt es nur bei „Jetzt““; zurück: Spuren mit Lücke.
8. Fahrtblatt eines Busses nach fünf Minuten Radar: die Verspätungslinie stimmt mit den Markerfarben überein; VoiceOver liest einen Satz.
9. „Aus“: Spuren und Fahrtblatt-Zeile weg; wieder an: beginnt leer.
10. Einen Zug zwei Minuten auf dem Radar ansehen, dann „Cockpit“: die Geschwindigkeit steht sofort da und passt zur Bewegung auf der Karte.
