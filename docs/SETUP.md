# KlimaBilanz – Einrichtung

Diese Anleitung erklärt, wie du die App aufs iPhone bekommst, Logins mit Apple/Google/Microsoft
aktivierst und Updates einrichtest. Alles Technische passiert über GitHub Actions –
du brauchst keinen Mac.

---

## 1. App installieren (.ipa)

Jeder Build auf GitHub erzeugt eine `.ipa`-Datei:

- **Actions › iOS › letzter Lauf › Artifacts** → `KlimaBilanz-<Version>-<Build>` herunterladen (ZIP mit der `.ipa`).
- Bei Versionen (Tag `v1.0.0` usw.) liegt die `.ipa` zusätzlich unter **Releases**.

Die `.ipa` ist **unsigniert** (nur mit `ldid` und den Sideload-Entitlements vorsigniert: App *und* Widget-Extension
bekommen die App Group). iOS installiert Apps nur signiert – das übernimmt ein Sideloading-Tool mit deiner Apple-ID:

| Tool | Kosten | Updates | Hinweis |
|------|--------|---------|---------|
| **AltStore** (altstore.io) | gratis | ✅ über Quelle: neue Version wird erkannt, ein Tipp auf „Aktualisieren“ | Signatur mit kostenloser Apple-ID 7 Tage gültig, AltStore erneuert sie automatisch |
| **SideStore** (sidestore.io) | gratis | ✅ über Quelle: wie AltStore | wie AltStore, ohne Computer zum Erneuern |
| **Sideloadly** (sideloadly.io) | gratis | Hinweis in der App, Neuinstallation per Kabel | einfach per Kabel vom PC/Mac |
| **Apple Developer Program** (99 €/Jahr) | kostenpflichtig | ✅ TestFlight / App Store | volle Funktionen inkl. „Mit Apple anmelden“, 1 Jahr gültig |

> AltStore und SideStore benennen die App Group beim Signieren in `group.com.knitelarlberg.klimabilanz.<TEAMID>` um.
> Die App findet die richtige Gruppe selbst (AltStore-Info.plist bzw. eingebettetes Provisioning-Profil) –
> Widgets und App teilen sich die Daten also auch bei SideStore.

> „Mit Apple anmelden“ benötigt eine Signatur mit dem **bezahlten** Apple Developer Program.
> Mit einer kostenlosen Apple-ID (AltStore/SideStore/Sideloadly) funktionieren Google- und
> Microsoft-Login sowie die lokale Nutzung trotzdem.

## 2. Updates

Neue Versionen werden automatisch erkannt – ein Tipp, und die App ist aktuell; **Tarife und Ticketpreise
aktualisieren sich von selbst** (ohne App-Update). Die App prüft beim Start und alle paar Stunden und zeigt bei einer
neuen Version ein Update-Fenster. Wohin „Jetzt aktualisieren“ führt, hängt davon ab, wie die App installiert wurde
(erkennt die App selbst – AltStore und SideStore hinterlegen beim Installieren eine Kennung in der App):

| Installiert über | Neue Version erkennen | Aktualisieren |
|------------------|-----------------------|---------------|
| **AltStore** mit Quelle | AltStore prüft die Quelle und zeigt ein Badge bzw. eine Mitteilung; dazu das Update-Fenster der App | Tipp auf **Aktualisieren** in AltStore – oder „Jetzt aktualisieren“ in der App übergibt die neue `.ipa` an AltStore |
| **SideStore** mit Quelle | wie AltStore | „Jetzt aktualisieren“ übergibt die neue `.ipa` an SideStore, oder Tipp auf **Aktualisieren** in SideStore |
| **Sideloadly** / anderes | Update-Fenster der App | `.ipa` herunterladen und neu installieren |
| **TestFlight** | TestFlight-App (Mitteilung) | in TestFlight auf **Aktualisieren** tippen – oder dort „Automatische Updates“ einschalten |
| **App Store** | App Store (Versionsabgleich über `itunes.apple.com/lookup`) | im App Store bzw. automatisch, wenn App-Updates in den iOS-Einstellungen aktiv sind |

> AltStore und SideStore installieren Updates **nicht unbemerkt im Hintergrund** – im Hintergrund erneuern sie nur
> die 7-Tage-Signatur. Ein neues Update bestätigst du immer mit einem Tipp auf „Aktualisieren“.

Damit das funktioniert, müssen die Update-Dateien **öffentlich** erreichbar sein (dieses Repo ist privat):

1. Lege ein **öffentliches** Repository an, z. B. `Jecuro1/klimabilanz-releases`.
2. Erzeuge ein Fine-grained Personal Access Token mit *Contents: Read & Write* nur für dieses Repo und
   speichere es hier unter **Settings › Secrets and variables › Actions › Secrets** als `RELEASES_TOKEN`.
3. Setze unter **Variables**:
   - `PUBLIC_RELEASES_REPO` = `Jecuro1/klimabilanz-releases`
   - `PUBLIC_DOWNLOAD_BASE_URL` = `https://github.com/Jecuro1/klimabilanz-releases/releases/latest/download`
   - `UPDATE_MANIFEST_URL` = `https://github.com/Jecuro1/klimabilanz-releases/releases/latest/download/update.json`
   - `TARIFFS_URL` = `https://github.com/Jecuro1/klimabilanz-releases/releases/latest/download/tariffs.json` *(optional – steht auch in `update.json`)*
   - `MINIMUM_SUPPORTED_VERSION` = z. B. `1.0.0` *(optional – ältere Versionen sehen ein Update-Fenster, das sich nicht wegwischen lässt)*
4. Neue Version veröffentlichen: in `project.yml` `MARKETING_VERSION` erhöhen, Release-Notizen in
   `docs/release-notes/<Version>.md` (Zeilen mit `- `) eintragen und einen Tag pushen: `git tag v1.1.0 && git push --tags`.

CI baut dann die `.ipa`, erstellt `update.json` (In-App-Updater) und `altstore-source.json`
(AltStore/SideStore). In AltStore/SideStore einmal **Quelle hinzufügen** (Link aus der App unter
*Einstellungen › Updates*) – ab dann erkennt der Store jede neue Version, und ein Tipp auf „Aktualisieren“ genügt.

`altstore-source.json` wird vollständig aus der fertigen `.ipa` abgeleitet (`scripts/make_release_metadata.py`):
Version und Build aus der `Info.plist`, `size` und `sha256` der Datei sowie `appPermissions` – alle Entitlements von App
und Widget (per `ldid -e` aus den signierten Binaries) und alle `…UsageDescription`-Texte. Genau das prüfen AltStore
und SideStore vor der Installation; weicht etwas ab, verweigern sie das Update. Die `.ipa` wird deshalb über die
unveränderliche Tag-URL (`…/releases/download/v1.1.0/…`) verlinkt. Neue Berechtigungen (z. B. ein weiteres Entitlement)
brauchen keine Handarbeit in der Quelle – aber eine eigene `App/Supporting/<Extension>-Sideload.entitlements` je
App-Extension, sonst bricht der CI-Schritt „Package .ipa“ ab.

**Fehlerbehebung**

- *AltStore/SideStore: „App-Berechtigungen stimmen nicht überein“ / Prüfsumme falsch* → Quelle in AltStore/SideStore
  aktualisieren (nach unten ziehen); Quelle und `.ipa` müssen aus demselben Release stammen.
- *Widgets bleiben leer* → die App einmal öffnen: Sie ermittelt die (umbenannte) App Group beim Start selbst und
  schreibt die Widget-Daten dorthin.

## 3. Login mit Apple, Google & Microsoft (Supabase)

Ohne Einrichtung läuft die App vollständig lokal. Für Konten + Sync zwischen Geräten:

1. Kostenloses Projekt auf **supabase.com** anlegen.
2. **SQL Editor** → nacheinander ausführen (jeweils ganzen Dateiinhalt einfügen und *Run*):
   1. `supabase/migrations/0001_init.sql` – Tabellen + Row Level Security,
   2. `supabase/migrations/0002_sync_hardening.sql` – Sync-Absicherung: Server-Revision als Abgleich-Cursor,
      „neueste Änderung gewinnt“ (veraltete Schreibzugriffe werden ignoriert), Rechte pro Befehl, kein Löschen
      durch die App (nur „Papierkorb“ über `deleted_at`), Kaskade bei Kontolöschung.

   Mit der Supabase CLI geht beides auf einmal: `supabase link --project-ref <projekt>` und `supabase db push`.
   Beide Dateien dürfen mehrfach ausgeführt werden (immer in dieser Reihenfolge). **Wichtig:** App-Versionen ab
   diesem Stand brauchen `0002` – ohne sie meldet die Synchronisierung „Die Cloud-Datenbank ist nicht auf dem neuesten
   Stand“. Ältere App-Builds synchronisieren nach `0002` nicht mehr (bitte alle Geräte aktualisieren).
   Unter **Project Settings › Data API › Max Rows** (ältere Dashboards: *Project Settings › API*) den Standardwert
   (1000) lassen oder jedenfalls nicht unter 500 setzen – die App lädt in Seiten zu je 500 Einträgen.
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
6. **Konto löschen** (Pflicht für den App Store, Richtlinie 5.1.1(v)): die Edge Function
   `supabase/functions/delete-account` einmal deployen – mit der Supabase CLI im Repo-Ordner:
   ```bash
   supabase login
   supabase link --project-ref <projekt>
   supabase functions deploy delete-account --no-verify-jwt --use-api
   ```
   (`--use-api` bündelt die Funktion auf den Supabase-Servern – so brauchst du kein Docker.) Ohne CLI geht es auch im
   Dashboard: **Edge Functions › Deploy a new function › Via Editor**, Name `delete-account`, den Inhalt von
   `index.ts` einfügen, deployen und danach in den Einstellungen der Funktion die JWT-Prüfung („Verify JWT“) ausschalten.
   `--no-verify-jwt` ist Absicht: Die Funktion prüft das Token selbst (über den Auth-Server, funktioniert auch mit
   den neuen JWT-Signing-Keys) und löscht immer nur das Konto, zu dem das Token gehört. `SUPABASE_URL` und
   `SUPABASE_SERVICE_ROLE_KEY` stellt Supabase automatisch bereit. Hast du den alten *service_role*-Key deaktiviert,
   hinterlege stattdessen einen Secret Key: `supabase secrets set KB_SECRET_KEY=sb_secret_…`.
   Beim Löschen entfernt die Datenbank alle Tickets, Fahrten, Favoriten und Vorteile des Kontos (ON DELETE CASCADE);
   andere Geräte des Kontos werden spätestens nach einer Stunde abgemeldet. Die Daten auf dem iPhone, auf dem gelöscht
   wurde, bleiben lokal erhalten.
7. Neuen Build starten (Actions › iOS › *Run workflow*). Fertig – die Login-Buttons sind aktiv.

**Gut zu wissen**

- **Abmelden** meldet nur dieses Gerät ab; dein iPad o. Ä. bleibt angemeldet. Die Daten bleiben auf dem iPhone.
- **Kontowechsel:** Die Daten auf dem iPhone gehören zu dem Konto, mit dem sie zuletzt abgeglichen wurden. Meldet sich
  ein *anderes* Konto an, pausiert die Synchronisierung, bis du entscheidest: Daten dieses iPhones ins neue Konto
  übernehmen oder durch die Daten des neuen Kontos ersetzen. Nichts wird ungefragt in ein fremdes Konto hochgeladen.
- **Uhrzeit:** Abgleich-Reihenfolge und Konflikte entscheidet der Server. Geht die Uhr eines Geräts mehr als
  10 Minuten vor, verwendet der Server für dessen Änderungen seine eigene Zeit.

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
