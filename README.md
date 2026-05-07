# Wohnapp

**Betriebssystem für Wohnungsverwaltung** — Flutter-App (iOS / Android) mit Firebase-Backend.

End-to-End-Prozess: Schadensmeldung → Handwerker → E-Rechnung → Buchhaltung → Versicherungsfall.

---

## Inhaltsverzeichnis

- [Architektur](#architektur)
- [Setup](#setup)
- [IoT / Smart Home Integration](#iot--smart-home-integration)
  - [Voraussetzungen](#voraussetzungen)
  - [Webhook-Format](#webhook-format)
  - [Unterstützte Sensor-Typen](#unterstützte-sensor-typen)
  - [Schwellwert-Alarme](#schwellwert-alarme)
  - [HomeAssistant](#homeassistant)
  - [MQTT-Bridge (Node-RED)](#mqtt-bridge-node-red)
  - [Eigenes Skript (curl / Python)](#eigenes-skript-curl--python)
  - [Fehlersuche](#fehlersuche)
- [Cloud Functions deployen](#cloud-functions-deployen)

---

## Architektur

| Schicht | Technologie |
|---|---|
| Frontend | Flutter 3, Riverpod, GoRouter |
| Backend | Firebase (Firestore, Storage, Messaging, Functions) |
| KI | Anthropic Claude Haiku (Ticket-Routing, Rechnungsprüfung) |
| Notifications | FCM + flutter_local_notifications |
| Export | DATEV EXTF-CSV, PDF (printing) |

---

## Setup

```bash
flutter pub get
flutterfire configure   # Firebase-Projekt verbinden
cd functions && npm install
```

---

## IoT / Smart Home Integration

Sensordaten von beliebigen IoT-Systemen (HomeAssistant, MQTT-Bridge, eigene Hardware) lassen sich per HTTP-Webhook an die App übermitteln. Die Daten erscheinen live im **Digital Twin** jeder Wohnung. Bei Schwellwert-Überschreitung wird automatisch ein Wartungs-Ticket angelegt.

### Voraussetzungen

1. Cloud Functions deployen (siehe [Cloud Functions deployen](#cloud-functions-deployen))
2. In der App: **Einstellungen → IoT / Smart Home → API-Key generieren**
3. Webhook-URL und API-Key notieren

Die Webhook-URL hat folgendes Format:
```
https://europe-west3-<PROJECT_ID>.cloudfunctions.net/receiveIotData
```

Die `PROJECT_ID` steht in der Firebase Console unter **Projekteinstellungen**.

---

### Webhook-Format

**Methode:** `POST`  
**Content-Type:** `application/json`  
**Header:** `X-Api-Key: <api-key>`

```json
{
  "tenantId": "dein-tenant-id",
  "readings": [
    {
      "sensorType": "temperature",
      "value": 22.5,
      "unit": "°C",
      "unitId": "wohnung-eg-links",
      "deviceId": "heizung-wohnzimmer",
      "label": "Wohnzimmer Temperatur"
    },
    {
      "sensorType": "humidity",
      "value": 68,
      "unit": "%",
      "unitId": "wohnung-eg-links"
    }
  ],
  "source": "homeassistant",
  "timestamp": "2026-05-07T08:00:00Z"
}
```

| Feld | Typ | Pflicht | Beschreibung |
|---|---|---|---|
| `tenantId` | string | ✅ | ID des Mandanten (Firestore-Dokument-ID) |
| `readings` | array | ✅ | Mindestens ein Messwert |
| `readings[].sensorType` | string | ✅ | Sensor-Typ (siehe Tabelle unten) |
| `readings[].value` | number | ✅ | Messwert |
| `readings[].unit` | string | ✅ | Einheit (`°C`, `%`, `ppm`, `kWh`, …) |
| `readings[].unitId` | string | — | ID der Wohnung (für Anzeige im Digital Twin) |
| `readings[].deviceId` | string | — | ID des Geräts (für Schwellwert-Prüfung) |
| `readings[].label` | string | — | Anzeigename (überschreibt Standard-Label) |
| `source` | string | — | Quelle (`homeassistant`, `mqtt`, `custom`) |
| `timestamp` | ISO-8601 | — | Messzeitpunkt, Standard: Serverzeit |

**Antwort:**
```json
{ "ok": true, "written": 2 }
```

---

### Unterstützte Sensor-Typen

| `sensorType` | Anzeige | Standard-Einheit | Icon |
|---|---|---|---|
| `temperature` | Temperatur | °C | 🌡 |
| `humidity` | Luftfeuchtigkeit | % | 💧 |
| `co2` | CO₂ | ppm | 🌿 |
| `water_leak` | Wasserleck | – | 🚨 |
| `smoke` | Rauchmelder | – | 🚨 |
| `energy_kwh` | Energieverbrauch | kWh | ⚡ |
| `custom` | Sensor | beliebig | 📡 |

> Wasserleck und Rauch erzeugen bei Auslösung automatisch ein Ticket mit **hoher Priorität**.

---

### Schwellwert-Alarme

Schwellwerte werden pro Gerät in Firestore konfiguriert. Öffne in der App das Gerät im Digital Twin und setze die Grenzwerte (min / max) pro Sensor-Typ.

**Datenbankstruktur (Firestore):**
```
units/{unitId}/devices/{deviceId}
  sensorThresholds:
    temperature:
      min: 10
      max: 30
    humidity:
      max: 80
```

Wird ein Grenzwert überschritten, legt das System automatisch ein Wartungs-Ticket an:
- Titel: `Temperatur-Alarm: 35 °C (Grenzwert: 30 °C)`
- Kategorie: Wartung
- Throttle: max. **1 Ticket pro Gerät und Sensor-Typ innerhalb von 24 Stunden**

---

### HomeAssistant

**REST-Command in `configuration.yaml`:**

```yaml
rest_command:
  wohnapp_sensor:
    url: "https://europe-west3-<PROJECT_ID>.cloudfunctions.net/receiveIotData"
    method: POST
    headers:
      Content-Type: application/json
      X-Api-Key: "<api-key>"
    payload: >
      {
        "tenantId": "<tenant-id>",
        "source": "homeassistant",
        "readings": [
          {
            "sensorType": "{{ sensor_type }}",
            "value": {{ value }},
            "unit": "{{ unit }}",
            "unitId": "{{ unit_id }}",
            "deviceId": "{{ device_id }}"
          }
        ]
      }
```

**Automation für Temperatur-Sensor (alle 10 Minuten):**

```yaml
automation:
  - alias: "Wohnapp – Temperatur senden"
    trigger:
      - platform: time_pattern
        minutes: "/10"
    action:
      - service: rest_command.wohnapp_sensor
        data:
          sensor_type: "temperature"
          value: "{{ states('sensor.wohnzimmer_temperatur') | float }}"
          unit: "°C"
          unit_id: "wohnung-eg-links"
          device_id: "thermostat-wohnzimmer"
```

**Automation für Wasserleck-Alarm (sofort bei Auslösung):**

```yaml
automation:
  - alias: "Wohnapp – Wasserleck melden"
    trigger:
      - platform: state
        entity_id: binary_sensor.wasserleck_keller
        to: "on"
    action:
      - service: rest_command.wohnapp_sensor
        data:
          sensor_type: "water_leak"
          value: 1
          unit: ""
          unit_id: "keller"
          device_id: "wassersensor-keller"
```

---

### MQTT-Bridge (Node-RED)

Für MQTT-fähige Sensoren (Zigbee, Z-Wave, Shelly, …) kann Node-RED als Bridge eingesetzt werden.

**Beispiel-Flow:**

```json
[
  {
    "id": "mqtt-in",
    "type": "mqtt in",
    "topic": "zigbee2mqtt/+/temperature",
    "name": "Temperatur-Sensor"
  },
  {
    "id": "transform",
    "type": "function",
    "func": "msg.payload = JSON.stringify({\n  tenantId: '<tenant-id>',\n  source: 'mqtt',\n  readings: [{\n    sensorType: 'temperature',\n    value: JSON.parse(msg.payload).temperature,\n    unit: '°C',\n    unitId: msg.topic.split('/')[1]\n  }]\n});\nmsg.headers = {\n  'Content-Type': 'application/json',\n  'X-Api-Key': '<api-key>'\n};\nreturn msg;"
  },
  {
    "id": "http-out",
    "type": "http request",
    "method": "POST",
    "url": "https://europe-west3-<PROJECT_ID>.cloudfunctions.net/receiveIotData"
  }
]
```

---

### Eigenes Skript (curl / Python)

**curl:**
```bash
curl -X POST \
  https://europe-west3-<PROJECT_ID>.cloudfunctions.net/receiveIotData \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: <api-key>" \
  -d '{
    "tenantId": "<tenant-id>",
    "readings": [
      {
        "sensorType": "temperature",
        "value": 21.3,
        "unit": "°C",
        "unitId": "wohnung-1"
      }
    ]
  }'
```

**Python (Raspberry Pi / ESP32-Proxy):**
```python
import requests

WEBHOOK_URL = "https://europe-west3-<PROJECT_ID>.cloudfunctions.net/receiveIotData"
API_KEY     = "<api-key>"
TENANT_ID   = "<tenant-id>"

def send_reading(sensor_type: str, value: float, unit: str,
                 unit_id: str, device_id: str = None):
    payload = {
        "tenantId": TENANT_ID,
        "source": "python",
        "readings": [{
            "sensorType": sensor_type,
            "value": value,
            "unit": unit,
            "unitId": unit_id,
            **({"deviceId": device_id} if device_id else {})
        }]
    }
    r = requests.post(
        WEBHOOK_URL,
        json=payload,
        headers={"X-Api-Key": API_KEY},
        timeout=10
    )
    r.raise_for_status()
    return r.json()

# Beispiel
send_reading("temperature", 22.1, "°C", "wohnung-og-rechts", "sensor-schlafzimmer")
send_reading("humidity",    65,   "%",  "wohnung-og-rechts")
```

---

### Fehlersuche

| HTTP-Status | Ursache | Lösung |
|---|---|---|
| `401` | `X-Api-Key`-Header fehlt | Header ergänzen |
| `403` | API-Key falsch | Key in Einstellungen prüfen / neu generieren |
| `404` | `tenantId` nicht gefunden | Tenant-ID in der Firebase Console prüfen |
| `400` | `readings` leer oder fehlt | Request-Body prüfen |
| `405` | Kein POST-Request | Methode auf POST setzen |

**Tenant-ID ermitteln:**  
Firebase Console → Firestore → Collection `tenants` → Dokument-ID = Tenant-ID

**Logs prüfen:**
```bash
firebase functions:log --only receiveIotData
```

---

## Cloud Functions deployen

```bash
cd functions
npm run build

# Alle Functions deployen
firebase deploy --only functions

# Nur IoT-Webhook deployen
firebase deploy --only functions:receiveIotData

# Wartungsalert-Scheduler deployen
firebase deploy --only functions:checkMaintenanceAlerts
```

> **Secrets setzen** (einmalig):
> ```bash
> firebase functions:secrets:set ANTHROPIC_API_KEY
> firebase functions:secrets:set SENDGRID_API_KEY
> ```
