# KlimaBilanz – Einrichtung

Diese Anleitung erklärt, wie du die App aufs iPhone bekommst, Logins mit Apple/Google/Microsoft
aktivierst und automatische Updates einrichtest. Alles Technische passiert über GitHub Actions –
du brauchst keinen Mac.

---

## 1. App installieren (.ipa)

Jeder Build auf GitHub erzeugt eine `.ipa`-Datei:

- **Actions › iOS › letzter Lauf › Artifacts** → `KlimaBilanz-<Version>-<Build>` herunterladen (ZIP mit der `.ipa`).
- Bei Versionen (Tag `v1.0.0` usw.) liegt die `.ipa` zusätzlich unter **Releases**.

Die `.ipa` ist **unsigniert**. iOS installiert Apps nur signiert – das übernimmt ein Sideloading-Tool
mit deiner Apple-ID:

| Tool | Kosten | Auto-Updates | Hinweis |
|------|--------|--------------|---------|
| **AltStore** (altstore.io) | gratis | ✅ über Quelle | Signatur mit kostenloser Apple-ID 7 Tage gültig, AltStore erneuert automatisch |
| **SideStore** (sidestore.io) | gratis | ✅ über Quelle | wie AltStore, ohne Computer zum Erneuern |
| **Sideloadly** (sideloadly.io) | gratis | ❌ | einfach per Kabel vom PC/Mac |
| **Apple Developer Program** (99 €/Jahr) | kostenpflichtig | ✅ TestFlight | volle Funktionen inkl. „Mit Apple anmelden“, 1 Jahr gültig |

> „Mit Apple anmelden“ benötigt eine Signatur mit dem **bezahlten** Apple Developer Program.
> Mit einer kostenlosen Apple-ID (AltStore/SideStore/Sideloadly) funktionieren Google- und
> Microsoft-Login sowie die lokale Nutzung trotzdem.

## 2. Automatische Updates

Die App prüft beim Start und alle paar Stunden, ob eine neue Version da ist, und zeigt dann ein
Update-Fenster. Zusätzlich aktualisieren sich **Tarife und Ticketpreise automatisch** (ohne App-Update).

Damit das funktioniert, müssen die Update-Dateien **öffentlich** erreichbar sein (dieses Repo ist privat):

1. Lege ein **öffentliches** Repository an, z. B. `Jecuro1/klimabilanz-releases`.
2. Erzeuge ein Fine-grained Personal Access Token mit *Contents: Read & Write* nur für dieses Repo und
   speichere es hier unter **Settings › Secrets and variables › Actions › Secrets** als `RELEASES_TOKEN`.
3. Setze unter **Variables**:
   - `PUBLIC_RELEASES_REPO` = `Jecuro1/klimabilanz-releases`
   - `PUBLIC_DOWNLOAD_BASE_URL` = `https://github.com/Jecuro1/klimabilanz-releases/releases/latest/download`
   - `UPDATE_MANIFEST_URL` = `https://github.com/Jecuro1/klimabilanz-releases/releases/latest/download/update.json`
   - `TARIFFS_URL` = `https://github.com/Jecuro1/klimabilanz-releases/releases/latest/download/tariffs.json` *(optional – steht auch in `update.json`)*
4. Neue Version veröffentlichen: in `project.yml` `MARKETING_VERSION` erhöhen, Release-Notizen in
   `docs/release-notes/<Version>.md` (Zeilen mit `- `) eintragen und einen Tag pushen: `git tag v1.1.0 && git push --tags`.

CI baut dann die `.ipa`, erstellt `update.json` (In-App-Updater) und `altstore-source.json`
(AltStore/SideStore). In AltStore/SideStore einmal **Quelle hinzufügen** (Link aus der App unter
*Einstellungen › Updates*) – danach aktualisiert sich die App im Hintergrund automatisch.

## 3. Login mit Apple, Google & Microsoft (Supabase)

Ohne Einrichtung läuft die App vollständig lokal. Für Konten + Sync zwischen Geräten:

1. Kostenloses Projekt auf **supabase.com** anlegen.
2. **SQL Editor** → Inhalt von `supabase/migrations/0001_init.sql` ausführen (Tabellen + Row Level Security).
3. **Authentication › URL Configuration › Redirect URLs**: `klimabilanz://auth-callback` hinzufügen.
4. **Authentication › Providers**:
   - **Apple:** aktivieren. Für die per AltStore/SideStore installierte App läuft „Mit Apple anmelden“ über den
     Web-Login – dafür im Apple-Developer-Portal eine *Services ID* (z. B. `com.knitelarlberg.klimabilanz.web`) mit
     Return-URL `https://<projekt>.supabase.co/auth/v1/callback` und einen *Sign-in-with-Apple-Key* anlegen und in Supabase
     eintragen. Für signierte TestFlight-Builds zusätzlich die Bundle-ID `com.knitelarlberg.klimabilanz` bei *Client IDs*
     ergänzen (dann nativer Login per Face ID).
   - **Google:** In der Google Cloud Console einen OAuth-Client vom Typ *Web application* anlegen,
     als Redirect-URI `https://<projekt>.supabase.co/auth/v1/callback` eintragen, Client-ID + Secret in Supabase speichern.
   - **Azure (Microsoft):** In Microsoft Entra eine App-Registrierung anlegen („Konten in einem beliebigen
     Organisationsverzeichnis und persönliche Microsoft-Konten“), Redirect-URI
     `https://<projekt>.supabase.co/auth/v1/callback`, Client-Secret erzeugen; in Supabase Client-ID,
     Secret und als URL `https://login.microsoftonline.com/common` eintragen.
5. In GitHub unter **Variables** setzen:
   - `SUPABASE_URL` = `https://<projekt>.supabase.co`
   - `SUPABASE_ANON_KEY` = der *anon/public* Key (ist für Apps vorgesehen und darf öffentlich sein)
6. Neuen Build starten (Actions › iOS › *Run workflow*). Fertig – die Login-Buttons sind aktiv.

## 4. Optional: Signierter Build & TestFlight

Mit Apple Developer Program kann CI signierte Builds erzeugen und direkt zu TestFlight hochladen
(TestFlight installiert Updates automatisch). Die Signierung läuft „cloud-managed“ über einen
App-Store-Connect-API-Schlüssel – keine Zertifikate/Profile nötig:

1. In App Store Connect die App mit Bundle-ID `com.knitelarlberg.klimabilanz` anlegen
   (vorher im Developer-Portal die IDs `com.knitelarlberg.klimabilanz`, `…klimabilanz.widgets` und
   die App Group `group.com.knitelarlberg.klimabilanz` registrieren, „Sign in with Apple“ aktivieren).
2. *Benutzer und Zugriff › Integrationen › App Store Connect API*: Schlüssel mit Rolle **App Manager** erzeugen.
3. GitHub-Secrets: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_BASE64` (`base64 -i AuthKey_XXXX.p8`).
4. Bei jedem Tag `v*` (oder manuellem Lauf) lädt CI den signierten Build zu TestFlight hoch.

## 5. Selbst bauen (Mac)

```bash
brew install xcodegen
xcodegen generate
open KlimaBilanz.xcodeproj
```
Kernlogik testen (auch unter Linux): `swift test --package-path Packages/KlimaCore`
