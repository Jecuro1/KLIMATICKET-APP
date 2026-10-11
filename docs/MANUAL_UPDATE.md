# Manuell aktualisieren – mit der .ipa-Datei

Du willst KlimaBilanz ohne Store-Quelle aktualisieren, nur mit der `.ipa`-Datei auf dem iPhone? Das geht – mit einer
ehrlichen Einschränkung vorweg:

> **iOS installiert keine `.ipa`-Datei von selbst.** Weder Safari noch die Dateien-App noch KlimaBilanz selbst können
> eine `.ipa` öffnen und installieren – Apple erlaubt das nicht. Installieren kann sie nur eine **Sideload-App**
> (SideStore oder AltStore) oder – mit einem bezahlten Apple-Entwicklerkonto – ein **direkter Installationslink**
> ([Direkt installieren](DIREKT_INSTALLIEREN.md)). KlimaBilanz holt dir die richtige Datei, prüft sie und gibt sie
> mit einem Tipp an SideStore oder AltStore weiter.

## In der App: Einstellungen › Updates › Manuell aktualisieren

Den gleichen Weg findest du im Update-Fenster unter den Neuerungen („Manuell aktualisieren“).

1. **Herunterladen.** Die App lädt die neueste `.ipa` aus dem GitHub-Release (`update.json` → `downloadURL`). Der Ring
   zeigt den Fortschritt, darunter stehen MB und die Restzeit.
   - **Pausieren / Fortsetzen:** Geladene Daten bleiben erhalten – auch wenn die Verbindung abbricht oder du die App
     schließt. „Fortsetzen“ macht dort weiter, wo es aufgehört hat. Ist der Download-Link inzwischen abgelaufen, beginnt
     die App einmal automatisch von vorn.
   - Der Download läuft weiter, wenn du die Seite verlässt.
2. **Prüfen.** Nach dem Download vergleicht die App **Größe und SHA-256-Prüfsumme** mit dem Update-Manifest
   (`size`, `sha256` in `update.json`, von `scripts/make_release_metadata.py` aus der fertigen `.ipa` berechnet).
   Stimmt etwas nicht, wird die Datei gelöscht und du lädst sie neu. „Geprüft: SHA-256 stimmt“ heißt: Die Datei ist
   genau die aus dem Release.
3. **Installieren** – drei Möglichkeiten:
   - **„In SideStore öffnen“** (bzw. „In AltStore öffnen“): öffnet das Teilen-Menü mit der Datei. Tippe in der
     App-Reihe auf **SideStore** oder **AltStore** – der Store signiert die Datei und installiert sie **über die alte
     Version. Deine Fahrten, Tickets und Einstellungen bleiben.**
   - **„In Dateien sichern“**: legt die Datei in der Dateien-App ab (z. B. *Auf meinem iPhone* oder iCloud Drive), zum
     Installieren später – siehe die drei Schritte unten.
   - **„Direkt in SideStore/AltStore installieren“** (ohne Umweg): Der Store lädt die Datei selbst
     (`sidestore://install?url=…` bzw. `altstore://install?url=…`). Schnell, aber ohne die Prüfung in KlimaBilanz – die
     macht dann der Store anhand der Quelle.

Die geladene Datei liegt im Cache der App (`Caches/ManualUpdate/`). Sobald die neue Version installiert ist, räumt
KlimaBilanz sie beim nächsten Start weg; „Datei löschen“ entfernt sie sofort.

## Später installieren – in 3 Schritten

1. **Dateien öffnen:** In der Dateien-App die gesicherte `KlimaBilanz-<Version>-<Build>.ipa` suchen.
2. **Teilen:** Datei gedrückt halten → **Teilen**.
3. **SideStore wählen:** In der App-Reihe auf **SideStore** (oder AltStore) tippen. Fehlt der Eintrag: ganz rechts auf
   **Mehr** tippen und SideStore einblenden.

## Keine Sideload-App installiert?

Ohne SideStore oder AltStore kann iOS die Datei nicht öffnen – die Dateien-App zeigt dann nur „Kann nicht geöffnet
werden“. Dann hast du zwei Wege:

| Weg | Kosten | Was du brauchst |
|-----|--------|-----------------|
| **SideStore** ([sidestore.io](https://sidestore.io)) | gratis | einmalig einen Computer zum Einrichten, deine Apple-ID; danach alles am iPhone. Apps müssen alle 7 Tage in SideStore aufgefrischt werden (geht ohne Computer). |
| **AltStore** ([altstore.io](https://altstore.io)) | gratis | AltServer auf Mac/PC im selben WLAN zum Auffrischen alle 7 Tage. |
| **Direkt installieren** ([Anleitung](DIREKT_INSTALLIEREN.md)) | 99 €/Jahr (Apple Developer Program) | Dein iPhone wird registriert; Updates installiert iOS dann selbst über einen `itms-services`-Link – **ganz ohne Zusatz-App**. In der App: „Jetzt installieren“. |

Tipp: Wenn SideStore oder AltStore ohnehin installiert ist, füge KlimaBilanz dort einmal als **Quelle** hinzu
(Einstellungen › Updates). Dann erkennt der Store jede neue Version selbst, und ein Tipp auf „Aktualisieren“ genügt –
der manuelle Weg ist dann nur noch die Rückfallebene.

## Gut zu wissen

- **Welche Version habe ich?** Einstellungen › Updates zeigt Version und Build. Builds aus dem `main`-Zweig tragen die
  Versionsnummer des letzten Releases mit höherer Build-Nummer – sie gelten deshalb nicht als „veraltet“.
- **„Was ist neu“** im Update-Fenster stammt aus `docs/release-notes/<Version>.md` (Zeilen mit `- `) des Releases.
- **Die Datei ist unsigniert.** Das ist Absicht: SideStore/AltStore signieren sie beim Installieren mit deiner
  Apple-ID. Ohne diesen Schritt startet sie auf keinem iPhone.
- **Sideloadly / Xcode:** Die gesicherte `.ipa` lässt sich auch dort am Computer installieren.

## Fehlerbehebung

| Meldung | Was hilft |
|---------|-----------|
| „Keine Verbindung“ / „Verbindung unterbrochen“ | Online gehen und „Fortsetzen“ tippen – die geladenen Daten bleiben. |
| „Der Download-Server hat nicht geantwortet“ | Später noch einmal; GitHub-Releases sind selten länger nicht erreichbar. |
| „Die Datei war beschädigt“ | Neu laden. Passiert es wieder, ist das Release unvollständig hochgeladen – bitte melden. |
| „Zu wenig Speicherplatz“ | Etwa 50 MB frei machen (Datei + Zwischenspeicher) und erneut laden. |
| SideStore fehlt im Teilen-Menü | Teilen-Menü → **Mehr** → SideStore einschalten; oder in SideStore unter „Meine Apps“ auf **+** tippen und die Datei aus Dateien wählen. |
| SideStore: „App-Berechtigungen stimmen nicht überein“ | Die Quelle in SideStore aktualisieren (nach unten ziehen) und es noch einmal versuchen. |
