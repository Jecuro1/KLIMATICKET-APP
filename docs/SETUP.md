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

> „Mit Apple anmelden“ braucht das **bezahlte** Apple Developer Program – nativ (Face ID) nur in signierten Builds,
> als Web-Anmeldung über das eigene Backend (§3) auch in der per AltStore/SideStore installierten App.
> Mit einer kostenlosen Apple-ID funktionieren Google- und Microsoft-Login sowie die lokale Nutzung trotzdem.

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

Die Update-Dateien liegen direkt in den **GitHub Releases dieses (öffentlichen) Repos** – es ist nichts weiter
einzurichten. Die App sucht unter
`https://github.com/Jecuro1/KLIMATICKET-APP/releases/latest/download/update.json`, die AltStore/SideStore-Quelle ist
`…/releases/latest/download/altstore-source.json`. (Nur wenn die Dateien woanders liegen sollen, z. B. bei einem
privaten Repo: Variables `UPDATE_MANIFEST_URL`, `TARIFFS_URL`, `PUBLIC_DOWNLOAD_BASE_URL` bzw. ein separates
öffentliches Release-Repo über `PUBLIC_RELEASES_REPO` + Secret `RELEASES_TOKEN` setzen.)

Optional unter **Settings › Secrets and variables › Actions › Variables**:
   - `MINIMUM_SUPPORTED_VERSION` = z. B. `1.0.0` *(ältere Versionen sehen ein Update-Fenster, das sich nicht wegwischen lässt)*

**Neue Version veröffentlichen:** in `project.yml` `MARKETING_VERSION` erhöhen, Release-Notizen in
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

## 3. Konten & Sync: eigenes Backend bei Cloudflare

Ohne diese Einrichtung läuft die App vollständig **lokal** (alle Funktionen außer Konto und Sync). Für die Anmeldung
mit Apple, Google oder Microsoft und den Abgleich zwischen iPhone, iPad usw. bekommt die App ein kleines eigenes
Backend in **deinem** Cloudflare-Konto:

- einen **Worker** `klimabilanz-api` (das Programm, mit dem die App spricht) und
- eine **D1-Datenbank** `klimabilanz` (speichert Konten und synchronisierte Daten).

Anlegen, Aktualisieren und Bereitstellen erledigt GitHub Actions (Workflow **Backend**). Du klickst nur im Browser –
kein Terminal, kein Mac. Für den Anfang reicht **ein** Anmeldeanbieter; Google ist am schnellsten eingerichtet.

**Kosten:** Die kostenlosen Pläne reichen bei Weitem: Workers Free (100 000 Anfragen pro Tag) und D1 Free (5 GB
Speicher, 5 Mio. gelesene und 100 000 geschriebene Zeilen pro Tag). Google- und Microsoft-Login sind kostenlos, nur
„Mit Apple anmelden“ braucht das bezahlte Apple Developer Program (99 €/Jahr).

**Datenschutz:** Die Datenbank wird mit der **EU-Jurisdiktion** angelegt – die Daten liegen nur in Rechenzentren in
der EU. Der Worker selbst läuft am Cloudflare-Standort, der dem Gerät am nächsten ist. Gespeichert werden nur eine
interne Konto-ID, Anbieter + Anbieter-ID, Name und E-Mail (falls der Anbieter sie liefert) und deine Tickets,
Fahrten, Favoriten und Vorteile. Passwörter sieht weder die App noch das Backend; Anmeldedaten der Anbieter werden
nicht gespeichert (Ausnahme: ein verschlüsseltes Apple-Token, damit „Konto löschen“ den Zugriff bei Apple widerrufen
kann). Es gibt kein Tracking.

> Vorher lief der Cloud-Teil über Supabase. Diese Variante ist entfernt; sie steckt nur noch in der Git-Historie
> (bis Commit `0cb2acd`). Ein altes Supabase-Projekt wird nicht mehr verwendet und kann gelöscht werden. Daten, die
> schon auf einem iPhone sind, übernimmt die App beim ersten Abgleich automatisch in das neue Konto.

### Was du jetzt tun musst – Checkliste

Abhaken von oben nach unten. Die Einzelheiten stehen in den Abschnitten 3.1–3.4; `<subdomain>` ist deine
workers.dev-Subdomain aus Schritt 2.

- [ ] **1. Branch `main`:** Alles liegt direkt in `main` (Standard-Branch, keine Extra-Branches). Darum zeigt GitHub
      unter *Actions* den Knopf **Run workflow** sofort – hier ist nichts zu tun.
- [ ] **2. Cloudflare-Subdomain:** [dash.cloudflare.com](https://dash.cloudflare.com) → links **Workers & Pages**
      (bzw. *Compute (Workers)*) einmal öffnen. Fragt Cloudflare nach einer Subdomain: Namen wählen → bestätigen.
- [ ] **3. Account ID kopieren:** auf derselben Seite rechts *Account details* → **Account ID** → Kopier-Symbol.
- [ ] **4. API-Token erstellen:** Profil-Symbol oben rechts → **My Profile** → **API Tokens** → **Create Token** →
      *Custom token* → **Get started** → Name `KlimaBilanz GitHub Deploy` → vier Zeilen *Permissions*:
      `Account · Workers Scripts · Edit`, `Account · D1 · Edit`, `Account · Account Settings · Read`,
      `User · User Details · Read` → *Account Resources* `Include · <dein Konto>` → *Client IP Address Filtering*
      leer → **Continue to summary** → **Create Token** → Token kopieren (wird nur einmal angezeigt).
- [ ] **5. GitHub-Secrets:** Repo → **Settings › Secrets and variables › Actions** → Tab **Secrets** →
      **New repository secret**: `CLOUDFLARE_API_TOKEN` (Token aus 4) und `CLOUDFLARE_ACCOUNT_ID` (ID aus 3).
- [ ] **6. Backend bereitstellen:** **Actions** → **Backend** → **Run workflow** → *Use workflow from*: Branch
      `main` → **Run workflow**. Nach 1–2 Minuten grün;
      den Lauf öffnen → die **Zusammenfassung** zeigt Worker-Adresse und Rückruf-Adressen.
- [ ] **7. Google (kostenlos):** [console.cloud.google.com](https://console.cloud.google.com) → Projekt `KlimaBilanz`
      anlegen → **Google Auth Platform** → *Get started* (App-Name, Support-E-Mail, Zielgruppe **Extern**) →
      **Audience › Publish app** → **Clients › Create client** → Typ **Web application** →
      *Authorized redirect URIs* → **Add URI**:
      `https://klimabilanz-api.<subdomain>.workers.dev/v1/auth/google/callback` → **Create** → Client-ID und
      Client-Secret kopieren → GitHub-Secrets `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`.
- [ ] **8. Microsoft (kostenlos, optional):** [entra.microsoft.com](https://entra.microsoft.com) →
      **App registrations › New registration** → Name `KlimaBilanz` → Kontotypen „**beliebiges
      Organisationsverzeichnis … und persönliche Microsoft-Konten**“ → Redirect URI Plattform **Web**:
      `https://klimabilanz-api.<subdomain>.workers.dev/v1/auth/microsoft/callback` → **Register** →
      *Application (client) ID* kopieren → **Certificates & secrets › New client secret** → **Value** kopieren →
      GitHub-Secrets `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET` (Ablaufdatum notieren).
- [ ] **9. Apple (optional, nur mit Apple Developer Program 99 €/Jahr):** App ID
      `com.knitelarlberg.klimabilanz` mit *Sign in with Apple*; **Services ID** `com.knitelarlberg.klimabilanz.web` →
      *Sign in with Apple › Configure* → *Domains*: `klimabilanz-api.<subdomain>.workers.dev`, *Return URLs*:
      `https://klimabilanz-api.<subdomain>.workers.dev/v1/auth/apple/callback`; **Keys** → neuer Schlüssel mit
      *Sign in with Apple* → `.p8` herunterladen → GitHub-Secrets `APPLE_SERVICES_ID`, `APPLE_TEAM_ID`,
      `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (ganzer Dateiinhalt), `APPLE_BUNDLE_ID` = `com.knitelarlberg.klimabilanz`.
- [ ] **10. Backend erneut bereitstellen:** **Actions › Backend › Run workflow** (Branch wie in 6; geänderte Secrets
      starten keinen Lauf von selbst). In der Zusammenfassung muss bei deinen Anbietern „aktiv“ stehen.
- [ ] **11. App bauen:** **Actions › iOS › Run workflow** (Branch wie in 6) → die neue `.ipa` aus dem Lauf
      (*Artifacts*) per AltStore/SideStore/Sideloadly installieren.
- [ ] **12. Ausprobieren:** in der App *Einstellungen › Konto* anmelden, ein zweites Gerät mit **demselben Anbieter**
      anmelden, eine Fahrt eintragen → erscheint nach dem Abgleich auf beiden Geräten.

Die Rückruf-Adressen müssen **Zeichen für Zeichen** mit denen aus der Zusammenfassung übereinstimmen (`https://`, kein
`/` am Ende). Mit eigener Domain (§3.5) gelten die Adressen mit deiner Domain.

### 3.1 Cloudflare vorbereiten (einmalig, etwa 5 Minuten)

1. **workers.dev-Subdomain festlegen.** Auf [dash.cloudflare.com](https://dash.cloudflare.com) links
   **Workers & Pages** öffnen (je nach Dashboard-Version unter *Compute (Workers)*). Hast du Workers noch nie benutzt,
   fragt Cloudflare jetzt nach einer **Subdomain** (z. B. `marcel` → später
   `https://klimabilanz-api.marcel.workers.dev`) – festlegen und bestätigen. Hat dein Konto schon eine, ist nichts zu
   tun. Ohne Subdomain bricht der Backend-Workflow mit „Keine workers.dev-Subdomain“ ab.
2. **Account ID kopieren.** Auf derselben Seite rechts unter *Account details* steht die **Account ID** →
   Kopier-Symbol. (Sie ist auch die 32-stellige Zeichenfolge in der Adresszeile direkt nach `dash.cloudflare.com/`.)
3. **API-Token erstellen.** Rechts oben auf das Profil-Symbol → **My Profile** (Profil) → **API Tokens** →
   **Create Token** → ganz unten bei *Custom token* auf **Get started**:
   - **Token name:** `KlimaBilanz GitHub Deploy`
   - **Permissions** – vier Zeilen (mit *+ Add more* weitere Zeilen hinzufügen), genau so:

     | 1. Feld | 2. Feld | 3. Feld | wofür |
     |---|---|---|---|
     | **Account** | **Workers Scripts** | **Edit** | Worker hochladen, seine Secrets setzen, workers.dev-Subdomain lesen |
     | **Account** | **D1** | **Edit** | Datenbank anlegen und aktualisieren |
     | **Account** | **Account Settings** | **Read** | Kontoeinstellungen lesen (braucht das Cloudflare-Werkzeug *Wrangler*) |
     | **User** | **User Details** | **Read** | Token prüfen (braucht Wrangler) |

   - **Account Resources:** *Include* → *dein Konto* (bzw. *All accounts*, wenn du nur eines hast).
   - **Client IP Address Filtering:** leer lassen – GitHub verwendet ständig andere Adressen.
   - **TTL:** leer lassen (oder ein Ablaufdatum wählen – dann den Token rechtzeitig erneuern).
   - **Continue to summary** → **Create Token** → den Token **sofort kopieren**; Cloudflare zeigt ihn nur dieses
     eine Mal an.

   Der Token darf nur Worker und D1 verwalten – er kommt nicht an deine Domains, DNS-Einträge oder andere Dienste.
   Er kann aber **alle** Worker und D1-Datenbanken dieses Cloudflare-Kontos ändern (Cloudflare kennt keine
   Berechtigung für nur einen Worker). Bewahre ihn deshalb nur als GitHub-Secret auf; die Workflows reichen ihn nur
   an die Schritte weiter, die Cloudflare aufrufen, und geben ihn nie aus. Wird er bekannt: unter *API Tokens* →
   **Roll** bzw. **Delete** und das Secret in GitHub ersetzen.

### 3.2 GitHub verbinden und Backend bereitstellen

4. **Secrets eintragen.** Im Repo auf GitHub: **Settings › Secrets and variables › Actions** → Tab **Secrets** →
   **New repository secret**, zweimal:
   - `CLOUDFLARE_API_TOKEN` = der Token aus Schritt 3
   - `CLOUDFLARE_ACCOUNT_ID` = die Account ID aus Schritt 2

   Repository-Secrets bleiben auch in einem **öffentlichen** Repo geheim: Nur GitHub Actions kann sie lesen, in
   Protokollen erscheinen sie als `***`. Schlüssel, Tokens oder `.p8`-Dateien gehören **nie** in eine Datei im Repo.
5. **Backend starten.** **Actions** → links **Backend** → **Run workflow** → Branch `main` → **Run workflow**. Nach 1–2 Minuten ist der Lauf grün. Der erste Lauf
   - legt die Datenbank `klimabilanz` in der EU an,
   - richtet sie ein (Tabellen),
   - erzeugt einmalig den geheimen Signaturschlüssel `SESSION_SIGNING_KEY` (bleibt nur im Worker gespeichert),
   - lädt den Worker hoch und prüft, ob er antwortet.

   Klick danach auf den Lauf: Die **Zusammenfassung** zeigt die Worker-Adresse, welche Anbieter aktiv sind, und die
   **Rückruf-Adressen (Redirect-URLs)**, die du gleich bei Google, Microsoft bzw. Apple einträgst. Sie sehen so aus
   (mit deiner Subdomain):

   | Anbieter | Adresse |
   |---|---|
   | Google | `https://klimabilanz-api.<subdomain>.workers.dev/v1/auth/google/callback` |
   | Microsoft | `https://klimabilanz-api.<subdomain>.workers.dev/v1/auth/microsoft/callback` |
   | Apple | `https://klimabilanz-api.<subdomain>.workers.dev/v1/auth/apple/callback` |

   Die Adressen müssen **Zeichen für Zeichen** übereinstimmen (`https://`, kein `/` am Ende).

   > GitHub zeigt **Run workflow** nur für Workflows im Standard-Branch (`main`) – dort liegt alles.
   > Pushes nach `main`, die das Backend ändern, stellen es außerdem automatisch neu bereit. Andere Branches werden
   > nur getestet, nie bereitgestellt.

### 3.3 Anmeldeanbieter einrichten

Jeder Anbieter ist optional. Die App zeigt nur die Buttons der Anbieter, die auf dem Server eingerichtet sind.
**Nach jeder Änderung an diesen Secrets:** *Actions › Backend › Run workflow* (ein geändertes Secret startet keinen
Lauf von selbst). Löschst du ein Anbieter-Secret in GitHub, entfernt der nächste Lauf es auch aus dem Worker – der
Anbieter ist dann abgeschaltet.

#### Google (kostenlos, etwa 10 Minuten)

1. [console.cloud.google.com](https://console.cloud.google.com) öffnen → oben in der Projektauswahl **Neues Projekt**
   → Name `KlimaBilanz` → **Erstellen** und das Projekt auswählen.
2. Im Menü **Google Auth Platform** öffnen (Suche: „Google Auth Platform“ bzw. *APIs & Dienste › OAuth-Zustimmungsbildschirm*)
   → **Get started / Jetzt starten**:
   - *App-Informationen:* App-Name `KlimaBilanz`, Nutzersupport-E-Mail = deine Adresse,
   - *Zielgruppe:* **Extern**,
   - *Kontaktdaten:* deine E-Mail → Richtlinie bestätigen → **Erstellen**.
3. **Zielgruppe (Audience)** → **App veröffentlichen (Publish app)** → bestätigen. Ohne diesen Schritt können sich
   nur eingetragene Testnutzer anmelden. Eine Überprüfung durch Google ist nicht nötig: Die App fragt nur die
   Standardangaben `openid`, `email` und `profile` ab.
4. **Clients** → **Client erstellen (Create client)**:
   - *Anwendungstyp:* **Webanwendung (Web application)**,
   - *Name:* `KlimaBilanz Backend`,
   - *Autorisierte JavaScript-Quellen:* leer lassen,
   - *Autorisierte Weiterleitungs-URIs (Authorized redirect URIs)* → **URI hinzufügen** → die **Google-Adresse** aus
     der Zusammenfassung, z. B. `https://klimabilanz-api.<subdomain>.workers.dev/v1/auth/google/callback`,
   - **Erstellen**.
5. Im Fenster **Client-ID** und **Clientschlüssel (Client secret)** kopieren – den Schlüssel sofort sichern, Google
   zeigt ihn später nicht mehr vollständig an (sonst einen neuen Schlüssel hinzufügen).
6. GitHub-Secrets: `GOOGLE_CLIENT_ID` = Client-ID (endet auf `.apps.googleusercontent.com`),
   `GOOGLE_CLIENT_SECRET` = Clientschlüssel (beginnt meist mit `GOCSPX-`).
7. *Actions › Backend › Run workflow* – in der Zusammenfassung steht dann „Google: aktiv“.

#### Microsoft (kostenlos, etwa 10 Minuten)

Für die App-Registrierung braucht Microsoft ein **Microsoft-Entra-Verzeichnis** (früher „Azure Active Directory“).
Hast du keines, bekommst du es mit einem kostenlosen Azure-Konto
([azure.microsoft.com/free](https://azure.microsoft.com/free)); Azure fragt dabei zur Identitätsprüfung eine
Kreditkarte ab, die App-Registrierung und die Anmeldungen kosten aber nichts.

1. [entra.microsoft.com](https://entra.microsoft.com) (oder [portal.azure.com](https://portal.azure.com) →
   *Microsoft Entra ID*) öffnen → **App-Registrierungen** (*App registrations*; je nach Version unter *Entra ID*,
   *Identity › Applications* oder *Anwendungen*) → **Neue Registrierung**:
   - *Name:* `KlimaBilanz`,
   - *Unterstützte Kontotypen:* **Konten in einem beliebigen Organisationsverzeichnis (beliebiger Microsoft
     Entra ID-Mandant – mehrinstanzenfähig) und persönliche Microsoft-Konten (z. B. Skype, Xbox)**,
   - *Umleitungs-URI (Redirect URI):* Plattform **Web** → die **Microsoft-Adresse** aus der Zusammenfassung, z. B.
     `https://klimabilanz-api.<subdomain>.workers.dev/v1/auth/microsoft/callback`,
   - **Registrieren**.
2. Auf der **Übersicht** die **Anwendungs-ID (Client)** (*Application (client) ID*) kopieren.
3. **Zertifikate & Geheimnisse › Geheime Clientschlüssel › Neuer geheimer Clientschlüssel** → Beschreibung
   `KlimaBilanz Backend`, Ablauf wählen (höchstens 24 Monate) → **Hinzufügen** → sofort den **Wert** (*Value*)
   kopieren – **nicht** die „Geheime ID“. Den Wert zeigt Microsoft nur jetzt an.
   **Ablaufdatum notieren:** Vorher einen neuen Schlüssel anlegen und das Secret in GitHub ersetzen, sonst funktioniert
   der Microsoft-Login ab dem Ablauftag nicht mehr.
4. GitHub-Secrets: `MICROSOFT_CLIENT_ID` = Anwendungs-ID, `MICROSOFT_CLIENT_SECRET` = der **Wert** aus Schritt 3.
5. *Actions › Backend › Run workflow*.

Bei *API-Berechtigungen* ist nichts zu tun (die voreingestellte Berechtigung genügt). Beim ersten Login zeigt
Microsoft einen Zustimmungsdialog, eventuell mit dem Hinweis „nicht überprüft“ – das ist bei privat registrierten
Apps normal.

#### Apple (nur mit dem bezahlten Apple Developer Program, 99 €/Jahr)

„Mit Apple anmelden“ funktioniert danach **auf zwei Wegen**: als Web-Anmeldung (auch in der per AltStore/SideStore
installierten App) und nativ mit Face ID in signierten Builds (TestFlight/App Store, §4).
Alles passiert auf [developer.apple.com/account](https://developer.apple.com/account) unter
**Certificates, Identifiers & Profiles**:

1. **App ID:** *Identifiers* → die App-ID `com.knitelarlberg.klimabilanz` öffnen (falls es sie noch nicht gibt:
   **+** → *App IDs* → *App* → Bundle ID *Explicit* `com.knitelarlberg.klimabilanz`) → bei *Capabilities*
   **Sign in with Apple** anhaken → **Save**.
2. **Services ID** (für die Web-Anmeldung): *Identifiers* → **+** → **Services IDs** → *Continue* →
   Description `KlimaBilanz Web`, Identifier `com.knitelarlberg.klimabilanz.web` → *Continue* → *Register*. Dann die
   neue Services ID öffnen → **Sign in with Apple** anhaken → **Configure**:
   - *Primary App ID:* `com.knitelarlberg.klimabilanz`,
   - *Domains and Subdomains:* nur der **Hostname** aus der Zusammenfassung, ohne `https://`, z. B.
     `klimabilanz-api.<subdomain>.workers.dev`,
   - *Return URLs:* die **Apple-Adresse**, z. B. `https://klimabilanz-api.<subdomain>.workers.dev/v1/auth/apple/callback`,
   - **Next › Done › Continue › Save**.
3. **Schlüssel:** *Keys* → **+** → Name `KlimaBilanz Sign in with Apple` → **Sign in with Apple** anhaken →
   *Configure* → Primary App ID `com.knitelarlberg.klimabilanz` → *Save* → *Continue* → *Register* →
   **Download** (die Datei `AuthKey_XXXXXXXXXX.p8` lässt sich **nur einmal** herunterladen – gut aufheben, nie ins
   Repo legen) und die **Key ID** (10 Zeichen) notieren.
4. **Team ID:** rechts oben bei deinem Namen bzw. unter *Membership details* (10 Zeichen).
5. GitHub-Secrets:

   | Secret | Wert |
   |---|---|
   | `APPLE_SERVICES_ID` | `com.knitelarlberg.klimabilanz.web` |
   | `APPLE_TEAM_ID` | deine Team ID (wird auch für signierte Builds, §4, verwendet) |
   | `APPLE_KEY_ID` | die Key ID aus Schritt 3 |
   | `APPLE_PRIVATE_KEY` | der **komplette Inhalt** der `.p8`-Datei (mit einem Texteditor öffnen, alles kopieren – inklusive der Zeilen `-----BEGIN PRIVATE KEY-----` und `-----END PRIVATE KEY-----`) |
   | `APPLE_BUNDLE_ID` | `com.knitelarlberg.klimabilanz` (für den nativen Login in signierten Builds) |

6. *Actions › Backend › Run workflow*.

Lehnt Apple die `workers.dev`-Adresse bei *Domains* ab, nimm eine eigene Domain (§3.5).

### 3.4 App bauen

**Actions › iOS › Run workflow.** Der Build holt sich die Backend-Adresse selbst (aus deinem Cloudflare-Konto bzw.
der Variable `API_BASE_URL`) – nichts weiter einzutragen. Nach der Installation zeigt die App die Buttons der
eingerichteten Anbieter. Ohne Cloudflare-Secrets bleibt die Adresse leer und die App läuft wie bisher lokal.

### 3.5 Optional: eigene Domain und weitere Einstellungen

**Eigene Domain** (z. B. `api.deine-domain.at`; die Domain muss in deinem Cloudflare-Konto sein):
1. Cloudflare → *Workers & Pages* → `klimabilanz-api` → **Settings › Domains & Routes › Add › Custom domain** →
   `api.deine-domain.at` → *Add domain* (Cloudflare legt den DNS-Eintrag und das Zertifikat selbst an).
2. GitHub → *Settings › Secrets and variables › Actions* → Tab **Variables** → `API_BASE_URL` =
   `https://api.deine-domain.at` (ohne `/` am Ende).
3. *Actions › Backend › Run workflow* – die Zusammenfassung zeigt jetzt die neuen Rückruf-Adressen. Diese bei
   Google, Microsoft und Apple **zusätzlich bzw. stattdessen** eintragen (bei Apple auch die neue Domain).
4. *Actions › iOS › Run workflow* – die App verwendet ab dem neuen Build die eigene Domain.

Die workers.dev-Adresse bleibt nebenbei erreichbar. Ältere App-Builds verwenden sie weiter.

**Weitere Repository-Variablen** (alle optional, unter *Variables*):

| Variable | Wirkung |
|---|---|
| `API_BASE_URL` | eigene Backend-Adresse (siehe oben) |
| `API_MIN_APP_VERSION` | z. B. `1.1.0`: ältere App-Versionen synchronisieren nicht mehr und bitten um ein Update |
| `BACKEND_KEEP_WORKER_SECRETS` | `true` = Anbieter-Secrets, die nur im Worker (nicht in GitHub) stehen, **nicht** löschen – nur nötig, wenn du Secrets direkt im Cloudflare-Dashboard pflegst |

**Signaturschlüssel:** `SESSION_SIGNING_KEY` erzeugt der erste Lauf und lässt ihn danach in Ruhe. Lösch oder ändere
ihn nicht im Cloudflare-Dashboard – sonst sind alle Geräte abgemeldet (die Daten bleiben erhalten). Nur wer ihn
bewusst austauschen will (z. B. weil er bekannt wurde): im Dashboard unter *Workers & Pages › klimabilanz-api ›
Settings › Variables and Secrets* zuerst ein Secret `SESSION_SIGNING_KEY_PREVIOUS` mit dem **alten** Wert anlegen,
dann `SESSION_SIGNING_KEY` durch einen neuen, zufälligen Wert (mindestens 32 Zeichen) ersetzen. Angemeldete Geräte
bleiben dabei angemeldet. Der Backend-Workflow fasst beide Secrets nie an.

### 3.6 Gut zu wissen

- **Abmelden** meldet nur dieses Gerät ab; dein iPad o. Ä. bleibt angemeldet. Die Daten bleiben auf dem iPhone.
- **Kontowechsel:** Die Daten auf dem iPhone gehören zu dem Konto, mit dem sie zuletzt abgeglichen wurden. Meldet sich
  ein *anderes* Konto an, pausiert die Synchronisierung, bis du entscheidest: Daten dieses iPhones ins neue Konto
  übernehmen oder durch die Daten des neuen Kontos ersetzen. Nichts wird ungefragt in ein fremdes Konto hochgeladen.
  (Einzige Ausnahme: Daten aus der Supabase-Zeit übernimmt das erste Cloudflare-Konto einmalig ohne Nachfrage.)
- **Uhrzeit:** Abgleich-Reihenfolge und Konflikte entscheidet der Server. Geht die Uhr eines Geräts mehr als
  10 Minuten vor, verwendet der Server für dessen Änderungen seine eigene Zeit.
- **Konto löschen** (*Einstellungen › Konto*) entfernt sofort alle Tickets, Fahrten, Favoriten, Vorteile und
  Anmeldungen des Kontos vom Server und widerruft „Mit Apple anmelden“ bei Apple. Andere Geräte des Kontos sind ab
  ihrer nächsten Anfrage abgemeldet. Die Daten auf dem iPhone, auf dem gelöscht wurde, bleiben lokal erhalten.
- **Gleiche E-Mail, anderer Anbieter:** Google, Microsoft und Apple ergeben jeweils ein **eigenes** Konto, auch bei
  derselben E-Mail-Adresse (aus Sicherheitsgründen werden Konten nicht automatisch über die E-Mail verknüpft). Melde
  dich auf allen Geräten mit demselben Anbieter an.
- **Logs:** Cloudflare-Dashboard → *Workers & Pages* → `klimabilanz-api` → *Logs*. Dort stehen nur Pfade,
  Statuscodes und Fehlercodes – keine Tokens, E-Mails oder Inhalte.

### 3.7 Fehlerbehebung

| Meldung / Problem | Lösung |
|---|---|
| Backend-Lauf: „Backend nicht bereitgestellt – CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID fehlen“ | Schritt 4: beide Secrets eintragen (Namen exakt so), dann *Run workflow* |
| „Backend nicht bereitgestellt – Bereitgestellt wird nur von main …“ | Normal für Test-Branches. *Run workflow* auf `main` starten |
| „Keine workers.dev-Subdomain“ | Schritt 1: *Workers & Pages* einmal öffnen und eine Subdomain festlegen |
| „Cloudflare-API-Token: Token ungültig oder ohne Berechtigung …“ / *Authentication error [code: 10000]* | Token neu erstellen (Schritt 3, alle vier Berechtigungen, richtiges Konto) und Secret ersetzen; `CLOUDFLARE_ACCOUNT_ID` prüfen |
| „Die D1-Datenbank … konnte nicht gelesen oder angelegt werden“ | Dem Token fehlt **Account · D1 · Edit** |
| Warnung „Backend-Secrets: … fehlt – diese Anmeldung bleibt deaktiviert“ | Für diesen Anbieter fehlt ein Secret (z. B. nur die Client-ID eingetragen) |
| Google: *Fehler 400: redirect_uri_mismatch* | Weiterleitungs-URI in der Google Console exakt wie in der Zusammenfassung eintragen (Änderungen brauchen bei Google ein paar Minuten) |
| Google: *Zugriff blockiert / App wird getestet* | Schritt 3 bei Google: **App veröffentlichen** |
| Microsoft: *AADSTS50011* | Redirect-URI (Plattform **Web**) exakt wie in der Zusammenfassung eintragen |
| Microsoft: *AADSTS700016* oder *AADSTS50020* | Bei *Unterstützte Kontotypen* „… und persönliche Microsoft-Konten“ wählen (*Authentifizierung* bzw. *Manifest* der App-Registrierung) bzw. `MICROSOFT_CLIENT_ID` prüfen |
| Microsoft: *AADSTS7000215 (invalid client secret)* | Den **Wert** des Clientschlüssels verwenden, nicht die „Geheime ID“ – oder der Schlüssel ist abgelaufen |
| Apple: *invalid_client* | Services ID, Team ID, Key ID und `.p8`-Inhalt prüfen; Return-URL und Domain bei der Services ID kontrollieren |
| In der App fehlen Login-Buttons | Der Anbieter ist auf dem Server nicht eingerichtet (siehe Zusammenfassung des letzten Backend-Laufs); nach dem Eintragen *Run workflow* nicht vergessen |
| App: „Die Anmeldung ist auf dem Server noch nicht eingerichtet.“ | Noch kein Anbieter eingerichtet (§3.3) |
| App: „Der Server ist nicht auf dem neuesten Stand …“ | *Actions › Backend › Run workflow* (aktualisiert Worker und Datenbank) |
| App: „Cloud-Anmeldung ist noch nicht eingerichtet.“ | Die App wurde ohne Backend-Adresse gebaut: nach §3.2 *Actions › iOS › Run workflow* erneut starten |

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
5. Für den nativen Login mit Apple im signierten Build zusätzlich das Secret `APPLE_BUNDLE_ID` setzen und *Actions ›
   Backend › Run workflow* starten (§3.3, Apple).

## 5. Selbst bauen (Mac)

```bash
brew install xcodegen
xcodegen generate
open KlimaBilanz.xcodeproj
```
Kernlogik testen (auch unter Linux): `swift test --package-path Packages/KlimaCore` und
`swift test --package-path Packages/KlimaCloud` (Cloud-Client).

Backend lokal testen (Node 22, kein Cloudflare-Konto nötig – D1 läuft lokal in Miniflare):
```bash
cd backend
npm ci
npm run typecheck && npm test           # Worker-Tests
node --test scripts/*.selftest.mjs      # Deploy-Hilfsskripte
npx wrangler d1 migrations apply DB --local -c wrangler.template.toml   # lokale Datenbank anlegen
npm run dev                             # lokaler Worker auf http://localhost:8787
```
Schnittstelle, Sicherheitsmodell und Datenbankschema: [docs/CLOUDFLARE_BACKEND.md](CLOUDFLARE_BACKEND.md).
