# Wohnapp — Betriebssystem für Wohnungsverwaltung

Eine Flutter-App (iOS + Android) für Wohnungsverwaltungen, Mieter und Handwerker.
Der End-to-End-Prozess: **Schadensmeldung → Handwerker → Rechnung → Buchhaltung → Versicherung.**

---

## Inhaltsverzeichnis

1. [Produktvision](#1-produktvision)
2. [Rollen & Nutzergruppen](#2-rollen--nutzergruppen)
3. [Alle Features im Überblick](#3-alle-features-im-überblick)
4. [Screens & Navigation](#4-screens--navigation)
   - [Manager-App](#manager-app)
   - [Mieter-App](#mieter-app)
   - [Handwerker-App](#handwerker-app)
5. [Design-System & Theming](#5-design-system--theming)
6. [Technische Architektur](#6-technische-architektur)
7. [Für das Design-Team](#7-für-das-design-team)
8. [Setup & Entwicklung](#8-setup--entwicklung)
9. [IoT / Smart Home Integration](#9-iot--smart-home-integration)
10. [Cloud Functions deployen](#10-cloud-functions-deployen)

---

## 1. Produktvision

**Keine "Mieter-App" — ein Betriebssystem für Wohnungsverwaltung.**

Der Markt ist fragmentiert: E-Mail, Telefon, WhatsApp und Buchhaltung laufen parallel und unverbunden. Wohnapp schließt genau diese Lücke — vom ersten Klick des Mieters bis zur fertig gebuchten Rechnung in DATEV oder SAP.

**USP:** Der vollständige digitale Prozess in einer App:

Mieter meldet Schaden → KI analysiert + routet → Handwerker erhält Auftrag
→ Handwerker setzt Termin → Mieter sieht Status in Echtzeit
→ Handwerker lädt Rechnung hoch → KI prüft Plausibilität
→ Manager gibt frei → DATEV / SAP Export automatisch

---

## 2. Rollen & Nutzergruppen

Die App hat **drei Rollen** — jede Rolle sieht eine andere Oberfläche:

| Rolle | Deutsch | Was sie tun |

| `manager` | **Verwalter / Manager** | Tickets verwalten, Handwerker zuweisen, Rechnungen prüfen, Berichte erstellen |
| `contractor` | **Handwerker** | Aufträge annehmen/ablehnen, Termine setzen, Rechnungen einreichen |
| `tenant_user` | **Mieter** | Schäden melden, Status verfolgen, Jahresabrechnung einsehen |

Zusätzlich gibt es anonyme **Gäste** (QR-Code-Scan ohne Login).

---

## 3. Alle Features im Überblick

### Ticket-System (Schadensmeldung & Wartung)

- Mieter melden Schäden per App oder QR-Code (ohne Login)
- KI analysiert Titel + Beschreibung automatisch: Kategorie, Gewerk, Dringlichkeit
- Manager sieht alle Tickets im Board mit Filtern (Status, Priorität)
- Volltextsuche über alle Tickets
- Infinite-Scroll-Pagination (kein Laden aller Tickets auf einmal)
- Tickets haben drei Typen: **Schaden**, **Wartung**, **Versicherungsfall**
- Bilder-Upload (mehrere Fotos pro Ticket)
- Dokumenten-Anhang (PDF)
- Kommentar-System mit Push-Benachrichtigungen
- Aktivitäts-Log (wer hat wann was gemacht)
- Archivierung statt Löschen (Audit-Trail)

### Handwerker-Marktplatz

- Manager weist Handwerker einem Ticket zu
- KI schlägt passendes Gewerk vor (Sanitär, Elektro, Heizung, Allgemein)
- Handwerker kann Auftrag **annehmen** oder **ablehnen**
- Handwerker setzt **Terminvorschlag** → Mieter sieht Termin in Echtzeit
- Status-Stepper für Mieter: Gemeldet → In Bearbeitung → Termin → Erledigt

### Rechnungssystem

- Handwerker lädt Rechnung (PDF) direkt im Ticket hoch
- **KI-Rechnungsprüfung**: Vergleich mit Marktpreisen, Plausibilitäts-Check
- Manager gibt Rechnung frei oder lehnt mit Begründung ab
- **DATEV-Export**: EXTF-Format (Buchungsstapel), direkt importierbar
- **SAP-Export**: Journal-Entry CSV (Data Transfer Workbench) + REST-Webhook
- Automatischer Webhook-Versand an ERP/SAP bei Freigabe
- Status: Ausstehend → Freigegeben → Abgelehnt → Exportiert

### Digital Twin (Gebäude & Wohnungen)

- Gebäude mit Wohnungen verwalten
- Geräte pro Wohnung erfassen (Heizung, Sanitär, Elektro, Allgemein)
- Wartungsintervalle pro Gerät konfigurierbar
- **Predictive Maintenance**: Automatischer Alarm wenn Wartung überfällig
- Reparaturhistorie je Wohnung
- QR-Code pro Wohnung für Gast-Schadensmelder
- **Live-Sensordaten** (wenn IoT-Integration aktiv): Temperatur, Feuchtigkeit, CO₂ etc.

### Betriebskostenabrechnung (§ 556 BGB)

- Manager erstellt Jahresabrechnung mit Kostenpositionen
- PDF-Generierung direkt in der App
- Digitale Zustellung an Mieter
- Mieter bestätigt Empfang (rechtssicherer Nachweis mit Zeitstempel)
- Status: Entwurf → Zugestellt → Bestätigt
- Automatische E-Mail-Benachrichtigung via SendGrid

### Versicherungsfall-Modul

- Tickets können als Versicherungsfall markiert werden
- Workflow: Gemeldet → In Prüfung → Genehmigt/Abgelehnt → Reguliert
- Felder: Versicherungsgesellschaft, Policennummer, Schadennummer, Selbstbeteiligung, geschätzter/genehmigter Schaden, Gutachter
- Dokument-Upload für Gutachten
- Automatische Statusanzeige im Ticket-Detail

### Energieverbrauch-Tracking

- Manuelle Zählerablese-Erfassung pro Wohnung (Strom, Gas, Wasser, Wärme)
- Verbrauchsberechnung aus Differenz der Ablesungen
- Übersicht nach Zählertyp (Tab-Navigation)
- CSV-Import für Massenimport historischer Daten
- CSV-Export für Heizkostenabrechnung und DATEV

### Analytik & Reporting

- **Bar-Chart**: Tickets pro Monat (letzte 6 Monate)
- **Donut-Chart**: Status-Verteilung (Offen / In Bearbeitung / Erledigt)
- **Linien-Chart**: Ø Bearbeitungszeit pro Monat
- Handwerker-Auslastung (Fortschrittsbalken)
- Analytics-Export als CSV (alle Daten in einer Datei)

### White-Label & Mandantenfähigkeit

- Jede Verwaltungsgesellschaft = eigener Mandant
- Eigenes Logo (Upload, max 2 MB)
- Primärfarbe frei wählbar mit Live-Vorschau
- Kontaktdaten, Adresse, Bankverbindung (SEPA) pro Mandant
- Dynamisches App-Theming — alle Farben passen sich automatisch an
- Onboarding-Flow für neue Mandanten (2-Schritt-Setup)

### Bulk-Import

- CSV-Import für Gebäude + Wohnungen
- CSV-Import für Einladungen (Mieter + Handwerker gleichzeitig)
- Template wird in der App angezeigt

### KI-Features

- **Ticket-Routing**: Foto + Text → automatisch Kategorie, Gewerk, Priorität (Claude Haiku)
- **Rechnungsprüfung**: Vergleich mit deutschen Marktpreisen 2024 (Claude Haiku)
- **KI-Assistent** (Vorschläge, Begründungen) direkt im UI sichtbar

### QR / NFC-System

- Jede Wohnung hat einen QR-Code
- Mieter scannt → Schadensmeldung ohne App-Login (anonymer Gast-Flow)
- Link enthält unitId + tenantId für automatische Zuordnung

### Push-Benachrichtigungen

- Ticket-Statusänderung → Push an Mieter
- Ticket-Zuweisung → Push an Handwerker
- Neuer Kommentar → Push an alle Beteiligten
- Wartungsalert → Push an Manager
- Pro User einstellbar (Opt-out pro Typ)
- Separater Android-Channel für Wartungshinweise

### Benachrichtigungseinstellungen

- Jeder User stellt selbst ein, welche Pushes er erhält
- Rollenspezifisch: Manager sieht andere Optionen als Mieter oder Handwerker
- Einstellung direkt im Profil (Toggle-Switches, sofort gespeichert)

### Kalender

- Termine aller Wartungstickets in Kalenderansicht
- Handwerker-Terminvorschläge erscheinen automatisch

### IoT / Smart Home Integration

- Sensor-Daten von beliebigen Geräten (HomeAssistant, MQTT, eigene Hardware)
- Webhook-Empfang über Cloud Function
- Live-Anzeige im Digital Twin (Temperatur, Luftfeuchtigkeit, CO₂, Energie etc.)
- Automatische Wartungs-Tickets bei Schwellwert-Überschreitung
- API-Key-Verwaltung in den Mandanten-Einstellungen

### Einladungssystem

- Manager lädt Mieter und Handwerker per Code ein
- Mieter registriert sich mit Code → automatisch der richtigen Wohnung zugeordnet
- Handwerker wählt bei Registrierung seine Fachgebiete

### Offline-Unterstützung

- Firestore-Offline-Persistenz aktiviert
- Offline-Banner wenn keine Internetverbindung
- Änderungen werden automatisch synchronisiert wenn wieder online

---

## 4. Screens & Navigation

### Manager-App

#### Dashboard / Ticket-Board (`/manager`)

Das Herzstück der Manager-App.

- Liste aller Tickets mit Infinite Scroll (20 pro Seite)
- Filter-Bar: Alle / Offen / In Bearbeitung / Erledigt
- Volltextsuche (Titel, Beschreibung, Wohnungsname)
- Jedes Ticket zeigt: Titel, Status-Badge, Kategorie-Icon, Wohnung, Datum
- Swipe oder Tap → Ticket-Detail
- FAB: „Ticket anlegen"
- Overflow-Menü: Analytics, Kalender, Export, Mieter, Digital Twin, Einladungen, Jahresabrechnungen, Mandanten-Einstellungen, Bulk-Import, Energieverbrauch, Profil
- Rechnungs-Button mit Badge (Anzahl ausstehender Rechnungen)
- Predictive-Maintenance-Banner wenn Geräte Wartung brauchen

#### Ticket-Detail (`/ticket/:id`)

- Foto-Galerie (antippbar, Vollbild)
- Status-Timeline (Stepper)
- Termin-Banner wenn Handwerker Termin gesetzt hat
- Handwerker-Info-Card (Name, Telefon, Kontakt)
- Metadaten: Typ, Erstellt, Wohnung, Geplant, Priorität, Gewerk
- Dokument-Anhänge (antippbar, öffnet Browser/Viewer)
- **Versicherungsfall-Sektion** (wenn Typ = Versicherungsfall): Status-Chip + Kerndaten + Button „Verwalten"
- Handwerker-Aktionskarte (Annehmen / Ablehnen / Termin setzen)
- Status-Buttons (Manager + Handwerker)
- Rechnungen (hochladen / prüfen / freigeben)
- Kommentar-Bereich mit Avatar
- Aktivitäts-Log

#### Ticket anlegen (`/manager/create-ticket`)

- Titel + Beschreibung
- KI-Analyse-Button → automatische Vorschläge für Kategorie + Priorität
- Kategorie: Schaden / Wartung / Versicherungsfall
- Bei Versicherungsfall: Versicherungsgesellschaft + Policennummer
- Priorität: Normal / Hoch
- Wohnung auswählen (Gebäude-Dropdown → Wohnungs-Dropdown)
- Geplantes Datum (nur Wartung)
- Bilder-Upload (mehrere)
- Dokumente-Upload
- Routing-Vorschlag (KI): zeigt empfohlenen Handwerker mit Begründung
- Handwerker direkt zuweisen oder Vorschlag übernehmen

#### Versicherungsfall verwalten (`/ticket/:id/insurance-claim`)

- Status-Stepper: Gemeldet → In Prüfung → Genehmigt/Abgelehnt → Reguliert
- Workflow-Buttons zum Weiterschalten
- Felder: Versicherungsgesellschaft, Policennummer, Schadennummer
- Beträge: Selbstbeteiligung, Geschätzter Schaden, Genehmigter Betrag
- Datum: Schadensmeldung, Reguliert am
- Gutachter: Name + Link zum Gutachten
- Interne Notizen

#### Analytics (`/analytics`)

- Bar-Chart: Tickets pro Monat
- Donut-Chart: Status-Verteilung mit interaktiven Segmenten
- Linien-Chart: Ø Bearbeitungszeit pro Monat
- Kategorie-Karten: Schäden vs. Wartungen
- Handwerker-Auslastung mit Farbskala (grün/orange/rot)
- Download-Button: Export als CSV

#### Digital Twin — Gebäude (`/buildings`)

- Liste aller Gebäude (Accordion)
- Jedes Gebäude zeigt seine Wohnungen
- Tap auf Wohnung → Wohnungsdetail

#### Wohnungsdetail (`/unit/:id`)

- Wohnungsdaten: Gebäude, Etage, Fläche, Baujahr
- Mieter-Zuweisung
- **Live-Sensordaten** (wenn IoT aktiv): Grid-Karten mit Typ, Wert, Zeitstempel
- Geräte-Liste (Accordion): Kategorie-Icon, Name, Wartungsstatus, Fälligkeitsdatum
- Gerät hinzufügen (FAB)
- Reparaturhistorie (Tickets der Wohnung)
- QR-Code anzeigen / teilen

#### Kalender (`/calendar`)

- Monatsansicht aller geplanten Wartungstermine
- Tap auf Tag → Liste der Tickets

#### Export (`/export`)

- Tab 1 „Tickets": Filter, Vorschau, CSV-Export, PDF-Export
- Tab 2 „DATEV": Datumsfilter, Rechnungs-Liste, DATEV EXTF-CSV-Export
- Tab 3 „SAP": Datumsfilter, Rechnungs-Liste, SAP Journal-Entry CSV-Export

#### Energieverbrauch (`/energy`)

- 4 Tabs: Strom / Gas / Wasser / Wärme
- Pro Tab: Zusammenfassungs-Karte (Anzahl Wohnungen, Gesamtverbrauch)
- Pro Wohnung: Letzte Ablesung, Verbrauch-Chip (∆), ausklappbare Einzel-Ablesungen
- FAB: Ablesung hinzufügen (Bottom Sheet)
- Import-Button (AppBar): CSV hochladen
- Export-Button (AppBar): CSV mit Verbrauchsberechnung

#### Mieter-Verwaltung (`/tenants`)

- Liste aller Mieter des Mandanten
- Wohnungs-Zuordnung anzeigen und ändern

#### Jahresabrechnungen (`/statements`)

- Liste aller erstellten Abrechnungen
- Status-Chips (Entwurf / Zugestellt / Bestätigt)
- Neue Abrechnung erstellen

#### Mandanten-Einstellungen (`/tenant-settings`)

- **Logo**: Upload, Vorschau, Löschen
- **Branding**: Live-Vorschau (Farbe + Name + Logo)
- Unternehmensname, Primärfarbe (Hex)
- Kontaktdaten: E-Mail, Telefon, Adresse
- Bankverbindung: IBAN, BIC, Kontoinhaber (für Abrechnungen)
- **ERP-Integration**: Webhook-URL, Secret
- **DATEV**: Beraternummer, Mandantennummer
- **SAP**: Webhook-URL, API-Key, Company Database, Kostenstelle
- **IoT / Smart Home**: API-Key generieren, Webhook-URL anzeigen, Copy-Button

#### Bulk-Import (`/bulk-import`)

- Tab Wohnungen: CSV-Template anzeigen, Datei hochladen
- Tab Einladungen: CSV-Template anzeigen, Datei hochladen
- Fortschrittsanzeige beim Import

#### Einladungen (`/manager/invitations`)

- Liste aller versendeten Einladungs-Codes
- Code mit Status (Offen / Verwendet)
- Neue Einladung erstellen (Rolle + E-Mail)

#### Onboarding (`/onboarding`)

- Nur für neue Manager ohne Mandant
- Schritt 1: Organisationsname, E-Mail, Adresse, Primärfarbe
- Schritt 2: Erstes Gebäude + erste Wohnung anlegen

#### Profil (`/profile`)

- Name, E-Mail, Rolle
- Wohnungs-Zuordnung (Mieter)
- Fachgebiete (Handwerker — Filter-Chips)
- **Benachrichtigungseinstellungen**: Rollenspezifische Toggle-Switches
- Abmelden (löscht FCM-Token)

---

### Mieter-App

#### Home (`/tenant`)

- Willkommens-Banner mit Name
- Status-Karten: Offene Tickets, Letzte Aktivität
- Schnellzugriff: Schaden melden, Meine Tickets
- Aktive Tickets mit Status-Stepper
- Handwerker-Info wenn Termin gesetzt

#### Ticket anlegen

- Titel + Beschreibung
- Bilder-Upload
- Wohnung automatisch vorbelegt

#### Meine Tickets (`/tenant/tickets`)

- Liste aller eigenen Tickets
- Status-Filter

#### Meine Jahresabrechnungen (`/my-statements`)

- Liste aller Abrechnungen für diesen Mieter
- PDF-Vorschau/Download
- Empfang bestätigen

---

### Handwerker-App

#### Home (`/contractor`)

- Liste aller zugewiesenen Tickets
- Filter: Alle / Offen / In Bearbeitung / Erledigt
- Ticket-Karte: Titel, Wohnung, Priorität, Termin
- FAB: Nicht vorhanden (nur reagieren, nicht anlegen)

#### Ticket-Detail

- Gleicher Screen wie Manager, aber eingeschränkte Aktionen:
  - **Annehmen** → Status wechselt zu „In Bearbeitung"
  - **Ablehnen** → Zuweisung wird zurückgezogen
  - **Termin setzen** → Datum-Picker
  - **Erledigt markieren**
  - **Rechnung hochladen** (PDF, mit Positionen)
  - Kommentare schreiben

---

### Gemeinsame Screens

#### Login (`/login`)

- E-Mail + Passwort
- Link zu Registrierung

#### Registrierung (`/register?code=XXX`)

- Mit Einladungs-Code vorbelegt
- Name, E-Mail, Passwort
- Bei Handwerker: Fachgebiete wählen

#### Gast-Schadensmeldung (`/guest-report?unitId=&tenantId=&unitName=`)

- Kein Login nötig (QR-Code-Flow)
- Titel + Beschreibung + Fotos
- Wohnungsname wird automatisch aus URL-Parameter befüllt

---

## 5. Design-System & Theming

### Farben

Das gesamte Farbschema basiert auf der **Primärfarbe des Mandanten** (gespeichert als Hex-Wert in Firestore). Die App generiert daraus automatisch ein vollständiges Material-3-Theme.

Standard-Primärfarbe: `#6366F1` (Indigo)

Feste Farben im UI (mandantenunabhängig):

- Status **Offen**: `Colors.orange`
- Status **In Bearbeitung**: `Colors.blue`
- Status **Erledigt**: `Colors.green`
- Priorität **Hoch**: `Colors.red`
- Claim **Abgelehnt**: `Colors.red`
- Claim **Reguliert**: `Colors.purple`

### Typografie

Material 3 Standard — keine Custom Fonts aktuell.

### Icons

Ausschließlich `Icons.*_outlined` (Outlined-Variante) für konsistentes Bild.

Wichtige Icons:

| Feature | Icon |

| Ticket / Schaden | `report_problem_outlined` |
| Wartung | `build_circle_outlined` |
| Versicherungsfall | `security_outlined` |
| Gebäude | `apartment_outlined` |
| Handwerker | `engineering_outlined` |
| Rechnung | `receipt_long_outlined` |
| Strom | `bolt_outlined` |
| Gas | `local_fire_department_outlined` |
| Wasser | `water_drop_outlined` |
| Wärme | `thermostat_outlined` |
| Sensor | `sensors_outlined` |
| KI-Analyse | `auto_awesome_outlined` |

### Komponenten-Muster

- **Cards**: `Card` mit `Padding(EdgeInsets.all(16))` — kein Elevation-Overdrive
- **Buttons**: Primary-Aktionen → `FilledButton`, Sekundär → `OutlinedButton`, Destruktiv → `TextButton(style: red)`
- **Status-Badges**: `Container` mit `BorderRadius.circular(20)` + `color.withValues(alpha: 0.12)` + farbiger Text
- **Empty States**: Zentriert, Icon + Titel + Subtitle (`EmptyState`-Widget)
- **Error States**: Zentriert, roter Text + Retry (`ErrorState`-Widget)
- **Loading**: `CircularProgressIndicator()` zentriert
- **Snackbars**: Erfolg = neutral, Fehler = `backgroundColor: Colors.red`

### Dark Mode

Voll unterstützt. `ThemeMode.system` — folgt automatisch dem Gerät.

### Responsive

Aktuell primär für Smartphone (360–430 px Breite) optimiert. Tablet-Layout noch nicht implementiert.

---

## 6. Technische Architektur

### Stack

| Schicht | Technologie |

| Frontend | Flutter 3.x, Dart |
| State Management | Riverpod 2.x |
| Navigation | GoRouter |
| Backend | Firebase (Firestore, Storage, Functions, Messaging) |
| KI | Anthropic Claude Haiku (via Cloud Functions) |
| E-Mail | SendGrid (Jahresabrechnungen) |
| Charts | fl_chart |
| PDF | pdf + printing |
| CSV | csv-Package |

### Datenbankstruktur (Firestore)

tenants/{tenantId}
  name, primaryColorHex, logoUrl, contactEmail, contactPhone, address
  bankIban, bankBic, bankAccountHolder
  erpWebhookUrl, erpWebhookSecret
  datevConsultantNumber, datevClientNumber
  sapWebhookUrl, sapWebhookSecret, sapCompanyDb, sapCostCenter
  iotWebhookKey

users/{uid}
  email, name, role, tenantId, fcmToken
  specializations[]          ← Handwerker-Fachgebiete
  unitId                     ← Mieter-Wohnungs-Zuordnung
  notificationPreferences{}  ← Push-Einstellungen

buildings/{buildingId}
  tenantId, name, address

units/{unitId}
  tenantId, buildingId, name, floor, area, buildYear

  devices/{deviceId}
    tenantId, unitId, unitName, name, category
    installedAt, lastServiceAt, warrantyUntil, serviceIntervalMonths
    sensorThresholds{}         ← IoT-Schwellwerte
    lastMaintenanceAlertSentAt
    lastSensorAlert{}

invitations/{code}
  tenantId, role, unitId, createdBy, used, usedAt

tickets/{ticketId}
  tenantId, title, description, status, priority, category
  createdBy, assignedTo, assignedToName
  unitId, unitName
  imageUrl, imageUrls[], documents[]
  createdAt, closedAt, scheduledAt, archived
  insuranceClaim{}             ← Versicherungsfall-Daten

  comments/{commentId}
    authorId, authorName, text, createdAt

  activity/{entryId}
    actorId, type, detail, createdAt

invoices/{invoiceId}
  tenantId, ticketId, ticketTitle
  contractorId, contractorName
  amount, status, positions[]
  pdfUrl, rejectionReason
  createdAt, approvedAt

statements/{statementId}
  tenantId, unitId, unitName
  recipientId, recipientName
  year, periodStart, periodEnd
  positions[], advancePayments
  pdfUrl, status
  createdAt, sentAt, acknowledgedAt, acknowledgedBy

notifications/{notifId}
  type, ticketId, targetUserId, sent, createdAt

sensor_readings/{readingId}
  tenantId, unitId, deviceId
  sensorType, value, unit, timestamp, source

energy_readings/{readingId}
  tenantId, unitId, unitName
  type, value, readingDate
  meterNumber, note, createdBy, createdAt

### Cloud Functions (alle in `europe-west3`)

| Function | Trigger | Was sie tut |

| `sendTicketStatusNotification` | Firestore: `/notifications` created | FCM-Push bei Statusänderung |
| `sendTicketAssignedNotification` | Firestore: `/notifications` created | FCM-Push bei Zuweisung |
| `sendNewCommentNotification` | Firestore: `/notifications` created | FCM-Push bei Kommentar |
| `onTicketStatusChanged` | Firestore: `/tickets` updated | Direkter FCM-Push (robuster Fallback) |
| `analyzeTicket` | HTTP Callable | KI-Routing via Claude Haiku |
| `analyzeInvoice` | HTTP Callable | KI-Rechnungsprüfung via Claude Haiku |
| `onStatementCreated` | Firestore: `/statements` created | E-Mail via SendGrid + ERP-Webhook |
| `onInvoiceStatusChanged` | Firestore: `/invoices` updated | ERP-Webhook + SAP-Webhook bei Freigabe |
| `checkMaintenanceAlerts` | Scheduled (täglich 08:00) | Wartungsalerts an Manager |
| `receiveIotData` | HTTP Request | IoT-Sensor-Daten empfangen + speichern |

### Storage-Struktur

tickets/{uid}/{ticketId}/img_N.jpg     ← Ticket-Fotos
tickets/{uid}/{ticketId}/docs/{name}   ← Ticket-Dokumente
invoices/{uid}/{filename}.pdf          ← Rechnungs-PDFs
statements/{tenantId}/{filename}.pdf   ← Abrechnungs-PDFs
logos/{tenantId}/logo.{ext}            ← Mandanten-Logo

---

## 7. Für das Design-Team

### Was noch fehlt (offen für Design)

1. **App-Icon** — wird benötigt für iOS (AppStore) und Android (PlayStore)
   - iOS: 1024×1024 px, kein Transparenz-Layer, keine abgerundeten Ecken (iOS rundet selbst)
   - Android: 512×512 px Adaptive Icon (Vordergrund + Hintergrund getrennt)

2. **Bundle-ID / App-ID festlegen**
   - iOS: z.B. `de.wohnapp.app`
   - Android: z.B. `de.wohnapp.app`

3. **Splash Screen** — aktuell Standard-Flutter (weiß)

4. **Onboarding-Screens** — die allererste App-Öffnung (kein technisches Onboarding, sondern Marketing: „Was kann die App?") existiert noch nicht

5. **Illustrationen für Empty States** — aktuell nur Icons + Text

6. **Logo** — das Wohnapp-Produkt-Logo (für Einstellungen, ggf. Splash)

### Primärfarbe anpassen

Die App-Primärfarbe ist derzeit `#6366F1` (Indigo). Sie kann in `main.dart` als Fallback geändert werden — jeder Mandant überschreibt sie ohnehin mit seiner eigenen Farbe.

### Schriftart wechseln

Aktuell: System-Default (SF Pro auf iOS, Roboto auf Android). Custom Font → `pubspec.yaml` unter `flutter.fonts` eintragen.

### Wo Screens zu finden sind

lib/features/
  analytics/         → Analytics-Screen
  auth/              → Register-Screen, QR-Scanner
  calendar/          → Kalender
  dashboard/         → Manager-Home, Mieter-Home, Handwerker-Home
  digital_twin/      → Gebäude, Wohnungsdetail, QR-Code
  energy/            → Energieverbrauch
  invitations/       → Einladungen
  invoices/          → Rechnungsdetail
  onboarding/        → Onboarding-Wizard
  profile/           → Profil + Benachrichtigungseinstellungen
  reporting/         → Export (Tickets, DATEV, SAP)
  settings/          → Mandanten-Einstellungen, Bulk-Import
  statements/        → Jahresabrechnungen
  tenants/           → Mieter-Verwaltung
  tickets/           → Ticket-Board, Detail, Erstellen, Versicherungsfall

lib/
  login_screen.dart  → Login
  main.dart          → App-Entry, Theming
  router.dart        → Alle Routen

lib/widgets/
  app_state_widgets.dart  → EmptyState, ErrorState, LoadingState
  tenant_logo.dart         → TenantLogoAvatar (Logo oder Initiale)

---

## 8. Setup & Entwicklung

```bash
# Abhängigkeiten installieren
flutter pub get

# Firebase verbinden (einmalig)
flutterfire configure

# Functions-Abhängigkeiten
cd functions && npm install

# App starten
flutter run

# Analyse
flutter analyze --no-fatal-infos

# Tests
flutter test
```

### Benötigte Secrets (GitHub Actions)

| Secret | Inhalt |

| `GOOGLE_SERVICES_JSON` | `android/app/google-services.json` als base64 |
| `GOOGLE_SERVICES_PLIST` | `ios/Runner/GoogleService-Info.plist` als base64 |

```bash
# base64 erzeugen und in Zwischenablage kopieren
base64 -i android/app/google-services.json | pbcopy
```

### Firebase Secrets setzen (einmalig)

firebase functions:secrets:set ANTHROPIC_API_KEY
firebase functions:secrets:set SENDGRID_API_KEY

---

## 9. IoT / Smart Home Integration

Sensor-Daten beliebiger IoT-Systeme können per HTTP-Webhook übermittelt werden.

**Webhook-URL:**

europe-west3-wohnapp-mvp.cloudfunctions.net/receiveIotData

**Auth:** Header `X-Api-Key: <key>` — Key wird in Mandanten-Einstellungen → IoT generiert.

**Request-Body:**

{
  "tenantId": "dein-tenant-id",
  "readings": [
    {
      "sensorType": "temperature",
      "value": 22.5,
      "unit": "°C",
      "unitId": "wohnung-1",
      "deviceId": "heizung-wohnzimmer"
    }
  ],
  "source": "homeassistant"
}

**Unterstützte Sensor-Typen:** `temperature`, `humidity`, `co2`, `water_leak`, `smoke`, `energy_kwh`, `custom`

### Schwellwert-Alarme

Bei Überschreitung eines konfigurierten Grenzwerts (min/max pro Gerät) wird automatisch ein Wartungs-Ticket angelegt. Max. 1 Ticket pro Gerät und Sensor-Typ innerhalb von 24 Stunden.

### HomeAssistant Beispiel

rest_command:
  wohnapp_sensor:
    url: "europe-west3-wohnapp-mvp.cloudfunctions.net/receiveIotData"
    method: POST
    headers:
      Content-Type: application/json
      X-Api-Key: "api-key"
    payload: >
      {
        "tenantId": "tenant-id",
        "source": "homeassistant",
        "readings": [{
          "sensorType": "{{ sensor_type }}",
          "value": {{ value }},
          "unit": "{{ unit }}",
          "unitId": "{{ unit_id }}"
        }]
      }

### Fehlersuche

| HTTP | Ursache | Lösung |

| `401` | Header fehlt | `X-Api-Key` ergänzen |
| `403` | Key falsch | In Einstellungen neu generieren |
| `404` | tenantId nicht gefunden | Firebase Console → Firestore → `tenants` |
| `400` | `readings` leer | Body prüfen |

---

## 10. Cloud Functions deployen

```bash
cd functions && npm run build

# Alles deployen
firebase deploy

# Nur Functions
firebase deploy --only functions

# Nur Rules + Indexes
firebase deploy --only firestore,storage

# Einzelne Function
firebase deploy --only functions:receiveIotData
firebase deploy --only functions:checkMaintenanceAlerts
```

**Firebase Console:** console.firebase.google.com/project/wohnapp-mvp/overview
