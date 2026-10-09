# Direkt installieren – ohne Computer, ohne Store

Mit dieser Einrichtung installierst du KlimaBilanz und jedes Update **mit einem Tipp direkt aus der App** – ohne
Computer, ohne AltStore/SideStore und ohne App Store. Alles in dieser Anleitung geht **nur mit dem iPhone**.

> **Was technisch geht – und was nicht.** iOS lässt keine App eine `.ipa` selbst installieren, auch nicht über einen
> Datei-Upload. Der nächste echte Weg ist Apples eigene Verteilung für registrierte Geräte („Ad hoc“): Die App öffnet
> einen `itms-services://`-Link, iOS fragt einmal **„Installieren?“**, ersetzt die App an Ort und Stelle und behält
> alle Daten. Dafür braucht es das **Apple Developer Program (99 € pro Jahr)**. Solange es nicht eingerichtet ist,
> ändert sich nichts: Die App, die `.ipa` und die AltStore/SideStore-Quelle funktionieren genau wie bisher.

| Weg | Kosten | Gültig | Update |
|-----|--------|--------|--------|
| **SideStore / AltStore** (wie bisher) | gratis | 7 Tage, der Store erneuert | im Store auf „Aktualisieren“ |
| **Direkt installieren** (diese Anleitung) | 99 €/Jahr | bis zum Ende der Mitgliedschaft | in der App „Jetzt installieren“ → „Installieren“ |
| TestFlight | 99 €/Jahr | 90 Tage je Build | in der TestFlight-App |

**Überblick** (einmalig etwa 30 Minuten, dazu die Wartezeit bei Apple):

1. [Apple Developer Program beitreten](#1-apple-developer-program-beitreten)
2. [App-Store-Connect-API-Schlüssel anlegen](#2-app-store-connect-api-schlüssel-anlegen)
3. [Vier Secrets in GitHub eintragen](#3-secrets-in-github-eintragen)
4. [UDID des iPhones anzeigen](#4-udid-des-iphones-anzeigen)
5. [„Gerät registrieren“ starten](#5-gerät-registrieren-starten)
6. [Release bauen](#6-release-bauen)
7. [Installieren](#7-installieren) – das erste Mal über die Installationsseite, danach in der App

---

## 1. Apple Developer Program beitreten

1. Im App Store die App **„Apple Developer“** laden und öffnen → Tab **Account** → mit deiner Apple-ID anmelden
   (Zwei-Faktor-Authentifizierung muss aktiv sein).
2. **Enroll Now** / **Jetzt registrieren** → als **Einzelperson** → Angaben bestätigen → per In-App-Kauf bezahlen
   (99 € pro Jahr).
3. Warten, bis die E-Mail „Welcome to the Apple Developer Program“ kommt (meist Minuten, manchmal bis 48 Stunden).
4. **Team-ID notieren:** App „Apple Developer“ › **Account** › **Membership details** (Mitgliedschaft) → **Team ID**
   (10 Zeichen, z. B. `A1B2C3D4E5`). Alternativ in Safari auf
   [developer.apple.com/account](https://developer.apple.com/account) → *Membership details*.

## 2. App-Store-Connect-API-Schlüssel anlegen

Mit diesem Schlüssel signiert GitHub die App bei Apple („cloud-managed“): Zertifikat und Profile verwaltet Apple,
in GitHub liegt kein Zertifikat.

1. Safari → [appstoreconnect.apple.com](https://appstoreconnect.apple.com) → anmelden. Zeigt die Seite zu wenig an:
   in der Adressleiste **aA › Desktop-Website anfordern**.
2. **Benutzer und Zugriff** (*Users and Access*) → Tab **Integrationen** (*Integrations*) → **App Store Connect API**
   → **Team-Schlüssel** (*Team Keys*). Beim ersten Mal: **Zugriff anfordern** (*Request Access*) → Bedingungen
   akzeptieren.
3. **+** bzw. **API-Schlüssel generieren** → Name `GitHub KlimaBilanz` → Zugriff (*Access*): **Admin** →
   **Generieren**.
   *Warum Admin:* Der Schlüssel muss iPhones registrieren, Profile erstellen und mit Apples cloudverwaltetem
   Verteilungszertifikat signieren. Mit „App Manager“ fehlt dafür oft eine Berechtigung, und der Export scheitert.
4. Notieren:
   - **Issuer-ID** – steht über der Schlüsselliste (lange ID mit Bindestrichen),
   - **Schlüssel-ID** (*Key ID*) – 10 Zeichen in der Zeile des neuen Schlüssels.
5. In der Zeile **API-Schlüssel laden** (*Download API Key*) → **Laden**. Das geht **nur ein einziges Mal**: Safari legt
   `AuthKey_XXXXXXXXXX.p8` in **Dateien › Downloads** ab. Bewahre die Datei gut auf (z. B. in iCloud Drive) –
   **nie** ins Repo, in ein Issue oder einen Chat kopieren, das Repo ist öffentlich.

## 3. Secrets in GitHub eintragen

**Den Text des Schlüssels kopieren** (Base64 ist auf dem iPhone nicht nötig – der Text genügt):

1. App **Dateien** → **Downloads** → `AuthKey_….p8` lange drücken → **Umbenennen** → hinten `.txt` anhängen
   (`AuthKey_….p8.txt`) → **Fertig**.
2. Die Datei antippen: Der Text erscheint, er beginnt mit `-----BEGIN PRIVATE KEY-----`.
3. Lange auf den Text drücken → **Alles auswählen** → **Kopieren**.
   Lässt sich in der Vorschau nichts markieren: Datei teilen → in **Pages** (oder einem anderen Texteditor) öffnen
   → dort alles markieren → kopieren.

Zeilenumbrüche, die beim Kopieren verloren gehen, und typografische Gedankenstriche repariert CI selbst
(`scripts/asc_api.py key`). Wichtig ist nur: **alles** von `-----BEGIN PRIVATE KEY-----` bis
`-----END PRIVATE KEY-----`.

**In GitHub eintragen:** Safari → [github.com/Jecuro1/KLIMATICKET-APP](https://github.com/Jecuro1/KLIMATICKET-APP)
→ **Settings** (bei Bedarf **aA › Desktop-Website anfordern**) → **Secrets and variables › Actions** → Tab
**Secrets** → **New repository secret**, viermal:

| Name | Wert |
|------|------|
| `APPLE_TEAM_ID` | Team-ID aus Schritt 1 (gibt es das Secret schon für „Mit Apple anmelden“: gleicher Wert, nichts tun) |
| `ASC_KEY_ID` | Schlüssel-ID aus Schritt 2 |
| `ASC_ISSUER_ID` | Issuer-ID aus Schritt 2 |
| `ASC_KEY_P8` | der kopierte Text des Schlüssels |

Die Secrets sind verschlüsselt und tauchen in keinem Log auf. (`ASC_KEY_BASE64` – Base64 der `.p8`-Datei – geht
weiterhin, falls du es schon gesetzt hast; `ASC_KEY_P8` hat Vorrang.)

**Optional**, Tab **Variables** → **New repository variable**:

| Name | Wert | Wozu |
|------|------|------|
| `TESTFLIGHT` | `false` | Kein TestFlight-Upload. Ohne diese Variable lädt CI jeden Release-Build zusätzlich zu TestFlight hoch – das klappt erst, wenn die App in App Store Connect angelegt ist (§4 in [SETUP.md](SETUP.md)); bis dahin steht im Lauf nur ein Hinweis, das Release kommt trotzdem. |
| `OTA_BASE_URL` | `https://<Worker-Adresse>/v1/ota` | Nur falls die Installation aus GitHub hängen bleibt (siehe [Fehlerbehebung](#fehlerbehebung)). |

## 4. UDID des iPhones anzeigen

Apple installiert Ad-hoc-Apps nur auf iPhones, deren Geräte-ID (UDID) im Konto registriert ist. Die UDID verrät iOS
keiner App und keiner Website – außer über ein kurzes Konfigurationsprofil. Das liefert dein eigenes Backend
(Cloudflare Worker, [SETUP.md §3](SETUP.md#3-konten--sync-eigenes-backend-bei-cloudflare)); es speichert nichts.

1. In **Safari** öffnen: `https://<Worker-Adresse>/v1/udid`
   (die Worker-Adresse steht in der Zusammenfassung des Laufs *Actions › Backend*, z. B.
   `https://klimabilanz-api.<subdomain>.workers.dev`; mit eigener Domain deine Domain).
2. Safari fragt „Diese Website versucht, ein Konfigurationsprofil zu laden …“ → **Erlauben** → **Schließen**.
3. App **Einstellungen** → ganz oben **Profil geladen** (oder *Allgemein › VPN & Geräteverwaltung* →
   „KlimaBilanz – Geräte-ID anzeigen“) → **Installieren** → Code eingeben → **Installieren**.
   iOS zeigt „Nicht überprüft“ – das ist normal, das Profil ist nicht signiert. **Es bleibt nichts installiert:**
   iOS schickt nur die UDID und das Modell an den Worker.
4. Safari öffnet sich mit deiner UDID → **UDID kopieren** → weiter mit „Gerät registrieren“ öffnen.

**Ohne eigenes Backend:** Seiten wie `get.udid.io` oder `udid.tech` funktionieren genauso (Profil laden →
installieren → UDID wird angezeigt) – dann sieht aber ein fremder Anbieter deine UDID.

## 5. „Gerät registrieren“ starten

1. GitHub-App oder Safari → Repo → **Actions** → links **Gerät registrieren** → **Run workflow**.
2. **udid**: einfügen · **name**: z. B. `Marcels iPhone` → grüner Knopf **Run workflow**.
3. Nach etwa einer Minute grün: „iPhone registriert.“ (bzw. „war schon registriert“ – zweimal starten schadet nicht).

UDID und Name erscheinen **nicht** im Log (das Repo und seine Logs sind öffentlich): Der Lauf verbirgt beide, bevor
er irgendetwas ausgibt. Weitere iPhones: Schritte 4–5 wiederholen (Apple erlaubt 100 iPhones pro Mitgliedsjahr).

## 6. Release bauen

Ab jetzt baut **jedes Release** zusätzlich die Ad-hoc-Version für alle registrierten iPhones – wie bisher per
Versions-Tag oder sofort: **Actions › iOS › Run workflow** → `release_tag` = nächste Version (z. B. `v1.0.5`) →
**Run workflow** (dauert etwa 30–40 Minuten).

In der Zusammenfassung des Laufs steht unter **Signierter Build**, was geklappt hat, z. B.
„Direkt installieren ✅ Ad-hoc-.ipa für 1 registrierte(s) iPhone(s)“. Das Release enthält dann zusätzlich
`KlimaBilanz-<Version>-adhoc.ipa`, `manifest.plist`, `AppIcon-57.png` und `AppIcon-512.png`, und `update.json`
nennt die Installationsadresse (`otaManifestURL`) – daran erkennt die App, dass sie direkt installieren kann.

## 7. Installieren

### Das erste Mal (Umstieg von SideStore/AltStore)

AltStore und SideStore geben der App beim Signieren eine eigene Kennung (`…klimabilanz.<TEAMID>`). Die direkt
installierte App ist deshalb eine **zweite** KlimaBilanz-App – deine Daten ziehst du einmal um:

1. In der **bisherigen** App: *Einstellungen › Daten › Backup sichern* → in Dateien speichern
   (oder mit Konto angemeldet sein, *Einstellungen › Konto* – dann kommt alles per Sync).
2. Installationsseite in **Safari** öffnen:
   - mit GitHub Pages (einmalig einschalten: Repo › **Settings › Pages** › *Deploy from a branch* › `main` ›
     `/docs` › **Save**): `https://jecuro1.github.io/KLIMATICKET-APP/install/`
   - oder diese Adresse in die Safari-Adressleiste einfügen:
     `itms-services://?action=download-manifest&url=https://github.com/Jecuro1/KLIMATICKET-APP/releases/latest/download/manifest.plist`
3. **KlimaBilanz installieren** → iOS fragt „„github.com“ möchte „KlimaBilanz“ installieren“ → **Installieren**.
   Die App erscheint auf dem Home-Bildschirm.
4. Neue App öffnen → *Einstellungen › Daten › Backup wiederherstellen* (oder anmelden) → prüfen, ob alles da ist
   → die alte AltStore/SideStore-App löschen.

### Jedes weitere Update

Die App meldet die neue Version → **Jetzt installieren** → iOS fragt **Installieren** → KlimaBilanz schließt sich,
lädt das Update (Fortschritt am App-Symbol) → danach wieder öffnen. **Deine Daten bleiben.** Unter
*Einstellungen › Updates* steht „Direkt installieren · Aktiv“.

### Was iOS dabei (nicht) verlangt

- **Kein „Vertrauen“** unter *Einstellungen › Allgemein › VPN & Geräteverwaltung* – das brauchen nur
  Unternehmens-Apps und Apps, die mit einer kostenlosen Apple-ID signiert sind.
- **Kein Entwicklermodus:** Seit iOS 16 verlangt iOS den Entwicklermodus nur für *entwicklungssignierte* Apps (Xcode,
  AltStore, SideStore). Ad-hoc-Builds sind verteilungssigniert und starten ohne ihn. Meldet iOS beim Öffnen trotzdem
  „Entwicklermodus erforderlich“, war der Build kein Ad-hoc-Build (dann bietet CI ihn auch nicht an); notfalls
  *Einstellungen › Datenschutz & Sicherheit › Entwicklermodus* → ein → Neustart.
- **Keine 7-Tage-Erneuerung** wie bei SideStore. Die Installation gilt, bis die Mitgliedschaft endet – jedes Release
  bringt ein frisches Profil mit. Endet die Mitgliedschaft, startet die direkt installierte App nicht mehr:
  rechtzeitig verlängern oder zurück zu SideStore (vorher Backup).

## Fehlerbehebung

- **„App kann nicht installiert werden“ / „Integrität kann nicht überprüft werden“** – das iPhone steht nicht im Profil
  dieses Builds: Schritt 5 für dieses iPhone ausführen, dann ein neues Release (Schritt 6). Die Zusammenfassung des
  iOS-Laufs zeigt, für wie viele iPhones der Build ist.
- **Kein „Jetzt installieren“ in der App** – entweder hat das Release keinen Ad-hoc-Build (Zusammenfassung des
  iOS-Laufs, Abschnitt *Signierter Build*), oder du nutzt noch die AltStore/SideStore-App: Die bleibt bei ihrem Store
  (sonst entstünde jedes Mal eine zweite App); umsteigen wie in [Schritt 7](#das-erste-mal-umstieg-von-sidestorealtstore).
- **Die Installation bleibt bei „Warten …“ stehen oder meldet „Verbindung zu github.com nicht möglich“** – GitHub
  leitet Release-Downloads auf einen Speicher-Server weiter. iOS folgt dem normalerweise; falls nicht: Variable
  `OTA_BASE_URL` = `https://<Worker-Adresse>/v1/ota` setzen (Schritt 3) und ein neues Release bauen. Dann liefert dein
  Worker `manifest.plist`, `.ipa` und Symbole ohne Weiterleitung aus. Installationsseite dafür:
  `…/install/?manifest=https://<Worker-Adresse>/v1/ota/latest/manifest.plist`.
- **Signierter Build rot markiert** (Annotation im iOS-Lauf; das normale Release kommt trotzdem):
  „API-Schlüssel nicht lesbar“ → `ASC_KEY_P8` neu einfügen, komplett mit BEGIN/END-Zeilen ·
  „HTTP 401“ → Schlüssel-ID, Issuer-ID und Schlüssel gehören nicht zusammen · „HTTP 403“ oder Signierfehler beim
  Export → Schlüssel mit Zugriff **Admin** neu anlegen · „TestFlight: Upload fehlgeschlagen“ → App in App Store Connect
  anlegen oder Variable `TESTFLIGHT` = `false`.
- **„Gerät registrieren“ rot** – „Secrets fehlen“: Namen genau wie in Schritt 3 · „keine gültige UDID“: noch einmal
  über Schritt 4 kopieren · „HTTP 409“: Geräte-Limit des Mitgliedsjahres erreicht.

## Technik (für Neugierige)

- **CI** (`.github/workflows/ios.yml`, Schritt *Signed build*, `scripts/signed_build.sh`): Nur wenn `APPLE_TEAM_ID`,
  `ASC_KEY_ID`, `ASC_ISSUER_ID` und `ASC_KEY_P8` (oder `ASC_KEY_BASE64`) gesetzt sind. Ein Archiv, daraus
  (a) TestFlight-Upload (`app-store-connect`, abschaltbar mit `TESTFLIGHT=false`) und – nur bei Releases –
  (b) Ad-hoc-Export (`release-testing`) mit automatischer Cloud-Signierung
  (`-allowProvisioningUpdates -authenticationKeyPath/-ID/-IssuerID`) für App **und** Widget. Vorher löscht
  `scripts/asc_api.py refresh-adhoc` Ad-hoc-Profile, denen ein registriertes iPhone fehlt (Profile lassen sich nicht
  ändern) – der Export erstellt sie mit allen Geräten neu; `check-ipa` vergleicht danach die Geräteliste. Ein Fehler
  ist eine Annotation und eine Zeile in der Zusammenfassung, **nie** ein abgebrochenes Release.
- **Release metadata:** `scripts/make_ota_manifest.py` prüft, dass die `.ipa` wirklich ad hoc signiert ist (Geräteliste,
  kein `get-task-allow`), und schreibt `manifest.plist` (`software-package`, `display-image` 57 px,
  `full-size-image` 512 px, `bundle-identifier`, `bundle-version`, `title`). Erst dann bekommt `update.json`
  `otaManifestURL` (unveränderliche Tag-Adresse bzw. `OTA_BASE_URL/<tag>`). Die unsignierte `.ipa` und die
  AltStore/SideStore-Quelle bleiben unverändert.
- **„Gerät registrieren“** (`.github/workflows/register-device.yml`): App Store Connect API (`POST /v1/devices`,
  idempotent; deaktivierte Geräte werden wieder aktiviert), JWT ES256 mit `openssl`, nur Python-Standardbibliothek.
- **Worker** (`backend/src/routes/device.ts`): `GET /v1/udid` (Profil „Profile Service“, fragt nur UDID und Modell),
  `POST /v1/udid/callback` (→ 301 auf die Ergebnisseite), `GET /v1/udid/done` (Seite mit Kopier-Knopf),
  `GET /v1/ota/<tag>/<datei>` (leitet nur `manifest.plist`, die Ad-hoc-`.ipa` und die zwei Symbole dieses Repos durch).
  Keine Datenbank, keine Speicherung; Workers Logs entfernen Query-Strings.
- **App:** erkennt am eingebetteten Profil (Geräteliste, kein `get-task-allow`) und an der unveränderten Bundle-ID,
  dass sie selbst ad hoc installiert ist (`KlimaCore.ProvisioningKind`, `DirectInstall`), und öffnet dann
  `itms-services://?action=download-manifest&url=<otaManifestURL>`.
- **Datenschutz:** Die UDID landet nur in deinem Apple-Konto. Weder Worker noch Repo noch Logs speichern sie.

**Getestet ohne Apple-Konto:** Schlüssel-Einlesen (zerstörte Zeilenumbrüche, Base64), ES256-Token mit Wegwerfschlüssel
gegen `openssl` verifiziert, Geräte-Registrierung und Profil-Auffrischung gegen ein nachgebautes App Store Connect,
`manifest.plist` aus Test-`.ipa`s, der Ablauf von `signed_build.sh` mit nachgebautem `xcodebuild`, alle Worker-Routen,
die App per Typecheck. **Erst mit Konto prüfbar:** Apples Antworten selbst (Rollen, Cloud-Signierung des Ad-hoc-Exports,
ob Xcode die Profile wie erwartet neu erstellt) und die Installation auf dem iPhone.
