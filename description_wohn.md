wohnapp — Digitales Betriebssystem für die Wohnungsverwaltung
Produktvision
wohnapp ist eine vollständig integrierte Property-Management-Plattform für Wohnungsbaugesellschaften, Hausverwaltungen und Immobilienunternehmen. Anders als klassische Portallösungen bildet die App den gesamten Prozessketten-Zyklus digital ab — von der Schadensmeldung durch den Mieter über die Handwerker-Beauftragung und Rechnungsprüfung bis zur gesetzeskonformen Nebenkostenabrechnung — in einer einzigen, mandantenfähigen Plattform.

Zielgruppen & Rollen
Die App ist für drei Nutzergruppen gleichzeitig ausgelegt, jede mit eigener, auf ihre Aufgaben zugeschnittener Oberfläche:

Verwalter (Manager)
Mitarbeiterinnen und Mitarbeiter der Verwaltungsgesellschaft. Sie steuern alle Prozesse: Tickets vergeben, Handwerker beauftragen, Rechnungen freigeben, Mietverhältnisse pflegen, Jahresabrechnungen erstellen und Auswertungen abrufen.

Handwerker (Contractor)
Externe oder interne Fachbetriebe. Sie erhalten zugewiesene Aufträge direkt in ihrer App-Ansicht, können Termine bestätigen, Statusupdates geben und Rechnungen als PDF einreichen — ohne E-Mail-Ping-Pong.

Mieter (Tenant)
Bewohnerinnen und Bewohner der verwalteten Objekte. Sie melden Schäden per Foto und Beschreibung, verfolgen den Bearbeitungsstatus in Echtzeit und erhalten Push-Benachrichtigungen bei jedem Statuswechsel.

Kernmodule

1. Schadensmeldung & Ticket-Management
Das Herzstück der App. Mieter erstellen Tickets mit Fotos, Beschreibung und automatischer Wohnungszuordnung. Für Gäste oder neu eingezogene Mieter ohne Account ist eine passwortlose QR-Code-Meldung direkt über die Kamera-App möglich.

Für Verwalter:

Zentrales Ticket-Board mit Echtzeit-Streams, Statusfiltern (Offen / In Bearbeitung / Erledigt) und Volltextsuche über alle Meldungen
Cursor-basierte Pagination für Portfolios mit tausenden Tickets
Einzel- und Massenzuweisung an Handwerker nach Spezialisierung
Kategorisierung: Schaden, Wartung, Versicherungsfall
Prioritätsstufen, interne Notizen, Kommentarfunktion, vollständiger Aktivitätsverlauf
KI-Unterstützung:

Automatische Kategorisierung und Dringlichkeitserkennung beim Eingang
Vorschläge für den passenden Handwerker basierend auf Ticket-Inhalt und Spezialisierung
Texterkennung aus Fotos
Versicherungsschäden:
Direktes Erfassen von Versicherungsfällen aus einem Ticket heraus — inklusive Schadensdokumentation, Schadensart, Versicherungsträger und Bildmaterial.

1. Handwerker-Beauftragung
Ein geschlossenes Auftrags-Ökosystem: Nur vom Verwalter freigegebene Fachbetriebe erhalten Aufträge. Handwerker sehen ausschließlich ihre eigenen zugewiesenen Tickets, können Termine vorschlagen, Status aktualisieren und direkt in der App abrechnen.

Spezialisierungsprofile (Sanitär, Elektro, Heizung, Schlosser etc.)
Terminvergabe mit Kalenderintegration
Direkte Push-Benachrichtigung bei neuer Zuweisung
Statusrückmeldung in Echtzeit für Mieter sichtbar
Handwerker kann Zuweisung ablehnen mit Begründung
3. Rechnungsprüfung & Buchhaltungsexport
Einer der stärksten Differenzierungs-Punkte gegenüber klassischen Lösungen:

Workflow:

Handwerker lädt Rechnung als PDF direkt in der App hoch
KI-gestützte Prüfung: Betrag, Position, Plausibilität gegen den Ticket-Sachverhalt
Verwalter erhält Badge-Benachrichtigung über offene Rechnungen
Genehmigung oder Ablehnung mit Begründung — vollständig nachvollziehbar
Freigegebene Rechnungen werden automatisch DATEV-konform exportiert (CSV)
Integrationen:

DATEV-Export mit konfigurierbarer Beraternummer und Mandantennummer
ERP-Webhook (z. B. SAP) für automatische Buchungsübergabe
Exportiert: Rechnungsdaten, Ticketbezug, Zeitstempel, Genehmigungsstatus
4. Mietverhältnisse & Vertragsverwaltung
Digitale Abbildung bestehender Mietverträge mit allen relevanten Vertragsdaten als Basis für die gesetzeskonforme Nebenkostenabrechnung.

Stammdaten pro Mietverhältnis:

Mieter-Name, E-Mail, optionale Verknüpfung mit dem App-Account
Gebäude- und Wohnungszuordnung
Mietbeginn, Mietende (befristet oder unbefristet), Kaltmiete, Kaution
Status: Aktiv / Kündigung eingegangen / Beendet
Mietvertrag:

Upload des bestehenden Mietvertrags als PDF direkt in der App
Sicherer Download und Austausch jederzeit möglich
Nebenkosten (§556 BGB, BetrKV, HeizkostenVO-konform):

Einzelne Betriebskosten-Positionen nach §2 BetrKV (Wasserversorgung, Müllabfuhr, Hausreinigung, Gartenpflege, Hausversicherung, Hauswart etc.)
Pro Position: monatliche Vorauszahlung + Umlageschlüssel (nach Wohnfläche / pro Einheit / Direktverbrauch)
Heizkosten separat (Pflichtfeld, §§6–9 HeizkostenVO): mindestens 50 % verbrauchsabhängig abzurechnen
Automatische Berechnung der monatlichen Warmmiete (Kaltmiete + Betriebskosten + Heizkosten)
Bulk-Import:
Bestehende Mietverhältnisse können per CSV massenimportiert werden — relevant für Wohnungsbaugesellschaften mit hunderten oder tausenden Einheiten. Gebäude und Wohnungen werden automatisch per Name aufgelöst; nicht zuordenbare Zeilen werden mit Fehlerhinweis übersprungen, ohne den Gesamtimport zu unterbrechen.

1. Gebäude & Digital Twin
Vollständige digitale Abbildung des Immobilienbestands:

Hierarchie: Gebäude → Wohnungen → Geräte/Sensoren
Wohnungsdaten: Etage, Wohnfläche (m²), Zimmeranzahl, Baujahr
Predictive Maintenance: IoT-Geräte (Heizungen, Aufzüge, Lüftungsanlagen) mit Wartungsintervallen. Das Dashboard zeigt automatisch Geräte mit überfälliger oder bald fälliger Wartung — farblich priorisiert nach Dringlichkeit
Energiedaten: Manuelle Zählerablesungen (Strom, Gas, Wasser, Wärme) mit Verlaufsansicht und Verbrauchsvisualisierung
QR-Code pro Wohnung: Jede Wohnungseinheit hat einen eigenen QR-Code für passwortlose Schadensmeldung (ideal für Hauseingänge oder Infoblätter)
6. Jahresabrechnungen (Nebenkostenabrechnung)
Gesetzeskonforme Erstellung der jährlichen Betriebskostenabrechnungen nach §556 BGB:

Erzeugung von Abrechnungen pro Mieter mit allen umlagefähigen Kostenpositionen
Automatische PDF-Generierung mit Verwalter-Branding
Digitale Zustellung: Mieter bestätigt Empfang direkt in der App (Rechtskonformität)
Abrechnungsstatus-Tracking (erstellt / zugestellt / bestätigt)
Export für DATEV und andere Buchhaltungssysteme
7. Mieter-Onboarding per personalisierten QR-Codes
Kein Verwaltungsaufwand beim Einzug neuer Mieter:

Verwalter erstellt Einladung für eine spezifische Wohnung → System generiert einen 8-stelligen Einladungscode
QR-Code zeigt auf die vollständige Registrierungs-URL (direkt mit Kamera-App scannbar)
Mieter registriert sich — der Account wird automatisch der richtigen Wohnung zugewiesen
Ab dem ersten Login sieht der Mieter nur seine eigene Wohnung und seine eigenen Tickets
Bulk-Einladung: CSV-Import mit Name, E-Mail, Rolle und optionaler Wohnungszuordnung — für Einzugswellen ganzer Gebäude geeignet.

1. White-Label & Mandantenfähigkeit
Jede Verwaltungsgesellschaft operiert vollständig isoliert in ihrer eigenen Mandanten-Umgebung:

Eigenes Logo, Primärfarbe und Akzentfarbe — das Theming wird dynamisch über alle App-Oberflächen angewendet
Eigene Kontaktdaten (Impressum, Telefon, E-Mail)
Eigene Bankverbindung (für Abrechnungen)
Eigene Registrierungs-URL für Mieter-QR-Codes
Vollständige Datentrennung: kein Mandant kann Daten eines anderen sehen (Firestore Security Rules + Custom JWT Claims)
9. Analytics & Auswertungen
Ticket-Statistiken: offene / laufende / erledigte Fälle, durchschnittliche Bearbeitungszeit
Handwerker-Performance: Reaktionszeiten, Erledigungsquote
Wartungs-Dashboard: fällige und überfällige Geräte
Energieverbrauch-Visualisierung pro Objekt
Kalenderansicht aller geplanter Wartungen und Handwerkertermine
Technische Plattform
Komponente Technologie
Mobile App Flutter (iOS + Android, eine Codebase)
Backend-as-a-Service Firebase (Firestore, Auth, Storage, Functions)
State Management Riverpod (reaktive Streams, Offline-Support)
KI / NLP Anthropic Claude API (Ticket-Routing, Rechnungsprüfung)
Push Firebase Cloud Messaging (FCM)
Navigation GoRouter (Deep Links, rollenbasierte Redirects)
Buchhaltung DATEV-CSV-Export, ERP-Webhook (SAP-kompatibel)
Datensicherheit Firestore Security Rules, Custom JWT Claims, Ende-zu-Ende Mandantentrennung
Offline-Fähigkeit: Firestore mit persistentem lokalem Cache — die App funktioniert bei schlechter oder fehlender Verbindung und synchronisiert automatisch beim nächsten Netzwerkkontakt.

Compliance & gesetzliche Grundlagen
Die App ist auf die deutschen rechtlichen Anforderungen ausgelegt:

Gesetz Abdeckung
§556 BGB Betriebskostenabrechnung, Vorauszahlungen, Abrechnungspflicht
§2 BetrKV Vollständige Liste umlagefähiger Betriebskosten als Standard-Positionen
§§6–9 HeizkostenVO Heizkosten separat erfasst, Pflicht zur verbrauchsabhängigen Abrechnung
DSGVO Mandantentrennung, keine Datenkreuzkontamination, Firebase EU-Region
Skalierbarkeit
Batch-Writes für Massenimporte (400 Firestore-Operationen pro Batch-Chunk)
Cursor-basierte Pagination im Ticket-Board für Portfolios jeder Größe
Chunk-Uploads mit exponentialem Retry bei schlechter Verbindung
Mehrstufiges Caching verhindert redundante Datenbankabfragen
Geschäftsmodell
Modell Details
SaaS 1–3 € pro Wohneinheit / Monat
Transaktionsgebühr Pro verarbeiteter und freigegebener Rechnung
KI-Premium Erweiterte Auswertungen, Predictive-Maintenance-Alerts
White-Label-Lizenz Einmalig oder jährlich für eigenes Branding
Aktueller Entwicklungsstand
Alle acht Kernfunktionen sind produktionsreif implementiert und in Firebase deployed. Die App befindet sich in der Pre-Release-Phase. Offene Punkte vor dem Store-Release: App-Icon, Bundle-ID-Finalisierung und SAP-Tiefenintegration (Read-back aus SAP nach Buchung).
