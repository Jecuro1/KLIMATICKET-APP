# KlimaBilanz · Live verfolgen: Remote-Updates per Push (Seam, deaktiviert)

**Status: nicht gebaut. Nur die Schnittstelle ist festgelegt.** Stand 2026-10-14. Gehört zu docs/OEBB_LIVE.md §R8.

## 1. Warum das hier steht

Die „Live verfolgen“-Live-Aktivität wird heute nur aktualisiert, während die App läuft oder wenn iOS eine
Hintergrundaktualisierung gewährt. Das ist ehrlich, aber nicht pünktlich. Remote-Updates per APNs (ActivityKit-Push)
würden die Aktivität auch dann aktualisieren, wenn die App nicht läuft.

Dafür braucht es **einen bezahlten Apple-Developer-Account** (APNs-Schlüssel, Push-Entitlement). Den haben wir nicht.
Deshalb:

- Die App startet jede Live-Aktivität mit `Activity.request(…, pushType: nil)`. Es gibt keinen Push-Token und keinen
  Versand.
- Es wird **kein APNs-Versand** gebaut, auch nicht als Test.
- Diese Datei legt nur die Form des Endpunkts fest, damit ein späterer Umbau klein bleibt.

## 2. Rechtliche Grenze (docs/OEBB_LIVE.md §2)

Die ÖBB-Schnittstellen werden **nur vom Gerät des Nutzers** aus abgefragt, nie von einem Server. Ein Push-Dienst darf
deshalb **keine eigenen Abfragen** bei ÖBB oder VAO machen. Er darf nur Zustände weiterreichen, die das Gerät bereits
selbst geholt hat.

Erlaubt: Gerät holt Daten → Gerät schickt den Zustand an unseren Worker → Worker sendet ihn an den Aktivitäts-Token
dieses einen Geräts.

Nicht erlaubt: Worker fragt ÖBB ab, um Aktivitäten zu füttern (auch nicht „nur für Zug X“).

## 3. Endpunkt (Form, nicht implementiert)

Ort: der bestehende Cloudflare-Worker (docs/CLOUDFLARE_BACKEND.md), Pfad unter `/v1/live/`.

```
POST /v1/live/activity
Content-Type: application/json

{
  "activityPushToken": "<hex, aus Activity.pushTokenUpdates>",
  "event": "update" | "end",
  "staleDate": "2026-10-14T12:11:00Z",
  "contentState": {
    "stage": "riding",
    "nextStopName": "Linz Hbf",
    "nextStopTime": "2026-10-14T10:45:00Z",
    "delayMinutes": 6,
    "platform": "11",
    "progress": 0.5,
    "transferStation": null,
    "transferDeparture": null,
    "updatedAt": "2026-10-14T10:40:00Z"
  }
}
```

- `contentState` ist `FollowLiveState` aus KlimaCore (`Packages/KlimaCore/Sources/KlimaCore/Live/Follow/FollowLiveState.swift`).
  Keine Fahrt-ID, keine Anschrift, kein Konto. Der Token ist die einzige Adresse.
- Antworten: `202 {"accepted": true}` bei Erfolg; `503 {"error": "disabled"}` solange der Schalter aus ist (Standard).
- Rate limit pro Token: höchstens eine Nachricht alle 60 Sekunden, Ende ist immer erlaubt.
- Der Worker speichert nichts über den Versand hinaus. Ein Token wird gelöscht, sobald ein `end` gesendet wurde
  oder das `staleDate` abgelaufen ist.

## 4. Schalter und Geheimnisse

| Name | Wo | Standard |
|---|---|---|
| `LIVE_PUSH_ENABLED` | Worker-Variable | `false` (sonst 503) |
| `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_P8` | Worker-Secrets | nicht im Repo, nie committen |
| `apns-push-type` | APNs-Header | `liveactivity` |
| `apns-topic` | APNs-Header | `com.knitelarlberg.klimabilanz.push-type.liveactivity` |

Die Zugangsdaten gehören in die Cloudflare-Secrets, nicht in das Repository.

## 5. Bedingungen, bevor der Schalter angeht

1. Apple-Developer-Account vorhanden und das Push-Entitlement im Projekt gesetzt.
2. Der Nutzer hat in Einstellungen › Live-Mitteilungen eingeschaltet **und** Live-Aktivitäten für KlimaBilanz erlaubt.
3. Die App sendet den Token nur, wenn `Activity.pushTokenUpdates` einen Wert liefert und der Nutzer das erlaubt hat.
4. Der Worker erfüllt §2 dieser Datei: kein eigener Abruf bei ÖBB oder VAO.
5. Der Abschnitt „Datenschutz“ in der App nennt den Versand über den eigenen Worker.

Bis dahin bleibt der Schalter aus, und die App verlässt sich auf Aktualisierung in der App und auf Hintergrundaktualisierung.
