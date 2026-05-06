import Anthropic from "@anthropic-ai/sdk";
import * as admin from "firebase-admin";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const sendgridApiKey = defineSecret("SENDGRID_API_KEY");

admin.initializeApp();

const db = admin.firestore();

// ─── Status-Labels ────────────────────────────────────────────────────────────

const STATUS_LABELS: Record<string, string> = {
  open: "Offen",
  in_progress: "In Bearbeitung",
  done: "Erledigt",
};

// ─── Trigger: notifications/{notifId} created ────────────────────────────────

/**
 * Fires whenever a new document is written to /notifications.
 * Looks up the target user's FCM token and sends a push notification.
 * Marks the notification as sent (or failed) afterwards.
 */
export const sendTicketStatusNotification = onDocumentCreated(
  { document: "notifications/{notifId}", region: "europe-west3" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as {
      type: string;
      ticketId: string;
      newStatus: string;
      targetUserId: string;
      sent: boolean;
    };

    if (data.type !== "ticket_status_changed" || data.sent) return;

    const { ticketId, newStatus, targetUserId } = data;

    try {
      const token = await getFcmToken(targetUserId);
      if (!token) {
        await snap.ref.update({ sent: false, error: "no_fcm_token" });
        return;
      }

      const ticketDoc = await db.collection("tickets").doc(ticketId).get();
      const ticketTitle = (ticketDoc.data()?.title as string | undefined) ?? "Ticket";
      const statusLabel = STATUS_LABELS[newStatus] ?? newStatus;

      await sendPush(
        token,
        "Ticket aktualisiert",
        `„${ticketTitle}" ist jetzt: ${statusLabel}`,
        { ticketId, newStatus, type: "ticket_status_changed" }
      );

      await snap.ref.update({
        sent: true,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info(`Status notification sent to ${targetUserId} for ticket ${ticketId}`);
    } catch (err) {
      logger.error("sendTicketStatusNotification failed", err);
      await snap.ref.update({ sent: false, error: String(err) });
    }
  }
);

// ─── Helper: fetch FCM token for a user ──────────────────────────────────────

async function getFcmToken(uid: string): Promise<string | null> {
  const doc = await db.collection("users").doc(uid).get();
  return (doc.data()?.fcmToken as string | undefined) ?? null;
}

async function sendPush(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<void> {
  await admin.messaging().send({
    token,
    notification: { title, body },
    data,
    android: {
      notification: { channelId: "ticket_updates", priority: "high" },
    },
    apns: {
      payload: { aps: { sound: "default", badge: 1 } },
    },
  });
}

// ─── Trigger: ticket_assigned notification ────────────────────────────────────

/**
 * Sends a push notification to the assigned contractor when a ticket is
 * assigned to them. Triggered by a new document in /notifications with
 * type == "ticket_assigned".
 */
export const sendTicketAssignedNotification = onDocumentCreated(
  { document: "notifications/{notifId}", region: "europe-west3" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as {
      type: string;
      ticketId: string;
      ticketTitle: string;
      targetUserId: string;
      sent: boolean;
    };

    if (data.type !== "ticket_assigned" || data.sent) return;

    const { ticketId, ticketTitle, targetUserId } = data;

    try {
      const token = await getFcmToken(targetUserId);
      if (!token) {
        await snap.ref.update({ sent: false, error: "no_fcm_token" });
        return;
      }

      await sendPush(
        token,
        "Neues Ticket zugewiesen",
        `Dir wurde das Ticket „${ticketTitle}" zugewiesen.`,
        { ticketId, type: "ticket_assigned" }
      );

      await snap.ref.update({
        sent: true,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info(`Assignment notification sent to ${targetUserId}`);
    } catch (err) {
      logger.error("sendTicketAssignedNotification failed", err);
      await snap.ref.update({ sent: false, error: String(err) });
    }
  }
);

// ─── Trigger: new_comment notification ───────────────────────────────────────

/**
 * Notifies ticket creator and assigned contractor when a new comment is added.
 * Triggered by a new document in /notifications with type == "new_comment".
 */
export const sendNewCommentNotification = onDocumentCreated(
  { document: "notifications/{notifId}", region: "europe-west3" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as {
      type: string;
      ticketId: string;
      ticketTitle: string;
      authorName: string;
      targetUserId: string;
      sent: boolean;
    };

    if (data.type !== "new_comment" || data.sent) return;

    const { ticketId, ticketTitle, authorName, targetUserId } = data;

    try {
      const token = await getFcmToken(targetUserId);
      if (!token) {
        await snap.ref.update({ sent: false, error: "no_fcm_token" });
        return;
      }

      await sendPush(
        token,
        `Neuer Kommentar von ${authorName}`,
        `Ticket „${ticketTitle}": ${authorName} hat kommentiert.`,
        { ticketId, type: "new_comment" }
      );

      await snap.ref.update({
        sent: true,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info(`Comment notification sent to ${targetUserId}`);
    } catch (err) {
      logger.error("sendNewCommentNotification failed", err);
      await snap.ref.update({ sent: false, error: String(err) });
    }
  }
);

// ─── Trigger: tickets/{ticketId} status change ───────────────────────────────

/**
 * Alternative: directly watch ticket status changes instead of relying on
 * the client writing to /notifications. This is more robust — the notification
 * is sent even if the client crashes or goes offline.
 */
export const onTicketStatusChanged = onDocumentUpdated(
  { document: "tickets/{ticketId}", region: "europe-west3" },
  async (event) => {
    const before = event.data?.before.data() as Record<string, unknown> | undefined;
    const after = event.data?.after.data() as Record<string, unknown> | undefined;

    if (!before || !after) return;

    // Only react to status changes
    if (before.status === after.status) return;

    const ticketId = event.params.ticketId;
    const newStatus = after.status as string;
    const createdBy = after.createdBy as string;
    const ticketTitle = after.title as string ?? "Ticket";

    try {
      const userDoc = await db.collection("users").doc(createdBy).get();
      const fcmToken = userDoc.data()?.fcmToken as string | undefined;

      if (!fcmToken) {
        logger.warn(`No FCM token for ticket creator ${createdBy}`);
        return;
      }

      const statusLabel = STATUS_LABELS[newStatus] ?? newStatus;

      await admin.messaging().send({
        token: fcmToken,
        notification: {
          title: "Ticket aktualisiert",
          body: `„${ticketTitle}" ist jetzt: ${statusLabel}`,
        },
        data: { ticketId, newStatus, type: "ticket_status_changed" },
        android: {
          notification: { channelId: "ticket_updates", priority: "high" },
        },
        apns: {
          payload: { aps: { sound: "default", badge: 1 } },
        },
      });

      logger.info(`Direct notification sent for ticket ${ticketId} → ${newStatus}`);
    } catch (err) {
      logger.error("onTicketStatusChanged: failed to send notification", err);
    }
  }
);

// ─── Callable: analyzeTicket (KI Routing) ────────────────────────────────────

/**
 * Analysiert einen Ticket-Text (+ optionale Bild-URL) mit Claude Haiku und gibt
 * strukturierte Routing-Informationen zurück:
 * - ticketCategory: 'damage' | 'maintenance'
 * - tradeCategory:  'plumbing' | 'electrical' | 'heating' | 'general'
 * - priority:       'normal' | 'high'
 * - reasoning:      kurze Begründung auf Deutsch
 * - confidence:     0.0 – 1.0
 */
export const analyzeTicket = onCall(
  {
    region: "europe-west3",
    secrets: [anthropicApiKey],
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Nicht angemeldet.");
    }

    const { title, description, imageUrl } = request.data as {
      title: string;
      description: string;
      imageUrl?: string;
    };

    if (!title && !description) {
      throw new HttpsError("invalid-argument", "Titel oder Beschreibung fehlt.");
    }

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });

    // Build message content — add image if provided
    type ContentBlock =
      | { type: "text"; text: string }
      | { type: "image"; source: { type: "url"; url: string } };

    const content: ContentBlock[] = [];

    if (imageUrl) {
      content.push({
        type: "image",
        source: { type: "url", url: imageUrl },
      });
    }

    content.push({
      type: "text",
      text: `Du bist ein Experte für Wohnungsverwaltung. Analysiere folgende Schadensmeldung und antworte NUR mit validem JSON.

Titel: ${title}
Beschreibung: ${description}

Gib folgende Felder zurück:
{
  "ticketCategory": "damage" oder "maintenance",
  "tradeCategory": "plumbing", "electrical", "heating" oder "general",
  "priority": "normal" oder "high",
  "reasoning": "Kurze Begründung auf Deutsch (max. 15 Wörter)",
  "confidence": Zahl zwischen 0.0 und 1.0
}

Regeln:
- priority = "high" bei: Wasserausbruch, Stromausfall, Gasgeruch, Sicherheitsrisiko, bewohnte Wohnung unbenutzbar
- ticketCategory = "maintenance" bei geplanten Wartungen, Inspektionen, Routinearbeiten
- tradeCategory nach Gewerk: Sanitär→plumbing, Elektro→electrical, Heizung→heating, alles andere→general
- confidence niedrig wenn Beschreibung unklar`,
    });

    try {
      const response = await client.messages.create({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 256,
        messages: [{ role: "user", content }],
      });

      const text =
        response.content[0].type === "text" ? response.content[0].text : "";

      // Extract JSON (Claude sometimes wraps it in markdown)
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        throw new HttpsError("internal", "KI-Antwort konnte nicht geparst werden.");
      }

      const result = JSON.parse(jsonMatch[0]) as {
        ticketCategory: string;
        tradeCategory: string;
        priority: string;
        reasoning: string;
        confidence: number;
      };

      logger.info("analyzeTicket result", { title, result });
      return result;
    } catch (err) {
      logger.error("analyzeTicket failed", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "KI-Analyse fehlgeschlagen.");
    }
  }
);

// ─── Trigger: statement created → E-Mail + ERP-Webhook ───────────────────────

/**
 * Fires whenever a new Jahresabrechnung is created.
 * 1. Sends a notification e-mail to the recipient via SendGrid.
 * 2. Posts a JSON webhook to the ERP endpoint configured in the tenant doc.
 */
export const onStatementCreated = onDocumentCreated(
  {
    document: "statements/{statementId}",
    region: "europe-west3",
    secrets: [sendgridApiKey],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data() as Record<string, unknown>;
    const statementId = event.params.statementId;

    const tenantId = data.tenantId as string;
    const recipientId = data.recipientId as string;
    const recipientName = data.recipientName as string;
    const year = data.year as number;
    const pdfUrl = data.pdfUrl as string | undefined;

    // ── 1. Load tenant config ──────────────────────────────────────────────
    const [tenantSnap, userSnap] = await Promise.all([
      db.collection("tenants").doc(tenantId).get(),
      db.collection("users").doc(recipientId).get(),
    ]);

    const tenantData = tenantSnap.data() ?? {};
    const userData = userSnap.data() ?? {};

    const orgName = (tenantData.name as string | undefined) ?? "Ihre Hausverwaltung";
    const recipientEmail = userData.email as string | undefined;
    const erpWebhookUrl = tenantData.erpWebhookUrl as string | undefined;
    const erpWebhookSecret = tenantData.erpWebhookSecret as string | undefined;

    // ── 2. Send e-mail via SendGrid ────────────────────────────────────────
    const sgKey = sendgridApiKey.value();
    if (sgKey && recipientEmail) {
      try {
        const totalCosts = calcTotalCosts(data);
        const advancePayments = (data.advancePayments as number | undefined) ?? 0;
        const balance = totalCosts - advancePayments;
        const balanceLabel = balance >= 0
          ? `Nachzahlung: ${formatEur(balance)}`
          : `Rückerstattung: ${formatEur(Math.abs(balance))}`;

        const html = `
<div style="font-family:Arial,sans-serif;max-width:600px;color:#222">
  <h2 style="color:#4f46e5">${orgName}</h2>
  <p>Guten Tag ${recipientName},</p>
  <p>Ihre <strong>Jahresabrechnung ${year}</strong> liegt bereit.</p>
  <table style="border-collapse:collapse;width:100%;margin:16px 0">
    <tr><td style="padding:6px 0;color:#666">Ergebnis</td>
        <td style="padding:6px 0;font-weight:bold">${balanceLabel}</td></tr>
    <tr><td style="padding:6px 0;color:#666">Gesamtkosten Anteil</td>
        <td style="padding:6px 0">${formatEur(totalCosts)}</td></tr>
    <tr><td style="padding:6px 0;color:#666">Geleistete Vorauszahlungen</td>
        <td style="padding:6px 0">${formatEur(advancePayments)}</td></tr>
  </table>
  ${pdfUrl ? `<p><a href="${pdfUrl}" style="background:#4f46e5;color:#fff;padding:10px 20px;border-radius:6px;text-decoration:none">PDF herunterladen</a></p>` : ""}
  <p>Bitte bestätigen Sie den Empfang in der App.</p>
  <p style="color:#888;font-size:12px">Gemäß § 556 BGB wird Datum und Uhrzeit Ihrer Bestätigung als rechtssicherer Zustellnachweis gespeichert.</p>
  <hr style="border:none;border-top:1px solid #eee;margin:24px 0">
  <p style="color:#aaa;font-size:11px">${orgName} · automatisch generiert</p>
</div>`;

        const resp = await fetch("https://api.sendgrid.com/v3/mail/send", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${sgKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            personalizations: [{ to: [{ email: recipientEmail, name: recipientName }] }],
            from: { email: "noreply@wohnapp.de", name: orgName },
            subject: `Jahresabrechnung ${year} – ${orgName}`,
            content: [{ type: "text/html", value: html }],
          }),
        });

        if (resp.ok) {
          logger.info(`Statement email sent to ${recipientEmail} for ${statementId}`);
        } else {
          logger.warn(`SendGrid returned ${resp.status} for ${statementId}`);
        }
      } catch (err) {
        logger.error("onStatementCreated: email failed", err);
      }
    } else if (!sgKey) {
      logger.info("SENDGRID_API_KEY not set – skipping email");
    }

    // ── 3. Fire ERP webhook ────────────────────────────────────────────────
    if (erpWebhookUrl) {
      try {
        const payload = {
          event: "statement.created",
          statementId,
          tenantId,
          recipientId,
          recipientName,
          year,
          data,
        };
        const headers: Record<string, string> = {
          "Content-Type": "application/json",
          "User-Agent": "Wohnapp/1.0",
        };
        if (erpWebhookSecret) {
          headers["X-Webhook-Secret"] = erpWebhookSecret;
        }
        const resp = await fetch(erpWebhookUrl, {
          method: "POST",
          headers,
          body: JSON.stringify(payload),
          signal: AbortSignal.timeout(10_000),
        });
        logger.info(`ERP webhook fired → ${erpWebhookUrl} : ${resp.status}`);
      } catch (err) {
        logger.error("onStatementCreated: ERP webhook failed", err);
      }
    }
  }
);

// ─── Trigger: invoice status changed → ERP-Webhook ───────────────────────────

/**
 * When a manager approves or rejects an invoice, POST the event to the
 * tenant's ERP webhook so the accounting system can react immediately.
 */
export const onInvoiceStatusChanged = onDocumentUpdated(
  { document: "invoices/{invoiceId}", region: "europe-west3" },
  async (event) => {
    const before = event.data?.before.data() as Record<string, unknown> | undefined;
    const after = event.data?.after.data() as Record<string, unknown> | undefined;
    if (!before || !after) return;
    if (before.status === after.status) return;

    const newStatus = after.status as string;
    if (newStatus !== "approved" && newStatus !== "rejected") return;

    const tenantId = after.tenantId as string;
    const tenantSnap = await db.collection("tenants").doc(tenantId).get();
    const erpWebhookUrl = tenantSnap.data()?.erpWebhookUrl as string | undefined;
    const erpWebhookSecret = tenantSnap.data()?.erpWebhookSecret as string | undefined;

    if (!erpWebhookUrl) return;

    try {
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
        "User-Agent": "Wohnapp/1.0",
      };
      if (erpWebhookSecret) headers["X-Webhook-Secret"] = erpWebhookSecret;

      await fetch(erpWebhookUrl, {
        method: "POST",
        headers,
        body: JSON.stringify({
          event: `invoice.${newStatus}`,
          invoiceId: event.params.invoiceId,
          tenantId,
          data: after,
        }),
        signal: AbortSignal.timeout(10_000),
      });
      logger.info(`ERP webhook invoice.${newStatus} fired for ${event.params.invoiceId}`);
    } catch (err) {
      logger.error("onInvoiceStatusChanged: webhook failed", err);
    }
  }
);

// ─── Helper: compute total tenant costs from positions array ─────────────────

function calcTotalCosts(data: Record<string, unknown>): number {
  const positions = (data.positions as Array<Record<string, unknown>> | undefined) ?? [];
  return positions.reduce((sum, p) => {
    const total = (p.totalCost as number | undefined) ?? 0;
    const pct = (p.tenantPercent as number | undefined) ?? 0;
    return sum + total * pct / 100;
  }, 0);
}

function formatEur(amount: number): string {
  return new Intl.NumberFormat("de-DE", {
    style: "currency",
    currency: "EUR",
  }).format(amount);
}

// ─── Callable: analyzeInvoice (KI-Rechnungsprüfung) ──────────────────────────

/**
 * Prüft eine eingereichte Handwerker-Rechnung auf Plausibilität.
 * Gibt zurück:
 * - verdict:      'ok' | 'suspicious' | 'overpriced'
 * - reasoning:    Begründung auf Deutsch
 * - suggestedMin: untere Preisgrenze für diesen Auftragstyp (€)
 * - suggestedMax: obere Preisgrenze (€)
 * - flags:        Liste konkreter Auffälligkeiten (leer wenn ok)
 * - confidence:   0.0 – 1.0
 */
export const analyzeInvoice = onCall(
  {
    region: "europe-west3",
    secrets: [anthropicApiKey],
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Nicht angemeldet.");
    }

    const { ticketTitle, ticketCategory, tradeCategory, contractorName, amount, positions } =
      request.data as {
        ticketTitle: string;
        ticketCategory: string;
        tradeCategory: string;
        contractorName: string;
        amount: number;
        positions: Array<{ description: string; amount: number }>;
      };

    if (!ticketTitle || amount == null) {
      throw new HttpsError("invalid-argument", "Pflichtfelder fehlen.");
    }

    const client = new Anthropic({ apiKey: anthropicApiKey.value() });

    const tradeLabelMap: Record<string, string> = {
      plumbing: "Sanitär / Klempner",
      electrical: "Elektro",
      heating: "Heizung / HLS",
      general: "Allgemeines Handwerk",
    };
    const tradeLabel = tradeLabelMap[tradeCategory] ?? tradeCategory;

    const positionLines =
      positions.length > 0
        ? positions.map((p) => `  - ${p.description}: ${p.amount.toFixed(2)} €`).join("\n")
        : "  (keine einzelnen Positionen angegeben)";

    const prompt = `Du bist ein Sachverständiger für Handwerkerleistungen in Deutschland. Prüfe folgende Rechnung auf Plausibilität.

Auftrag: ${ticketTitle}
Kategorie: ${ticketCategory === "maintenance" ? "Wartung/Inspektion" : "Schadensbehebung"}
Gewerk: ${tradeLabel}
Auftragnehmer: ${contractorName}
Gesamtbetrag: ${amount.toFixed(2)} €
Positionen:
${positionLines}

Typische Marktpreise Deutschland 2024 (netto):
- Elektro: 65–95 €/Std, Kleinreparatur 120–350 €, mittlere Arbeit 350–1.200 €
- Sanitär: 70–100 €/Std, Kleinreparatur 150–400 €, mittlere Arbeit 400–1.500 €
- Heizung/HLS: 80–120 €/Std, Wartung 100–250 €, Reparatur 300–2.000 €
- Allgemein: 50–80 €/Std, Kleinreparatur 100–300 €, mittlere Arbeit 300–1.000 €
Material: typisch 30–50 % des Arbeitspreises, bei Teileersatz bis 70 %.

Antworte NUR mit validem JSON:
{
  "verdict": "ok" | "suspicious" | "overpriced",
  "reasoning": "Begründung auf Deutsch (max. 30 Wörter)",
  "suggestedMin": Zahl (€, plausible Untergrenze für diesen Auftrag),
  "suggestedMax": Zahl (€, plausible Obergrenze),
  "flags": ["Auffälligkeit 1", ...] oder [],
  "confidence": Zahl 0.0–1.0
}

Regeln:
- "ok": Betrag liegt innerhalb der plausiblen Spanne, keine auffälligen Positionen
- "suspicious": einzelne Positionen wirken überhöht oder fehlen Detailangaben bei hohem Betrag
- "overpriced": Gesamtbetrag übersteigt die plausible Spanne deutlich (>40 %)
- confidence niedrig wenn zu wenig Kontext vorhanden`;

    try {
      const response = await client.messages.create({
        model: "claude-haiku-4-5-20251001",
        max_tokens: 300,
        messages: [{ role: "user", content: prompt }],
      });

      const text =
        response.content[0].type === "text" ? response.content[0].text : "";

      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        throw new HttpsError("internal", "KI-Antwort konnte nicht geparst werden.");
      }

      const result = JSON.parse(jsonMatch[0]) as {
        verdict: string;
        reasoning: string;
        suggestedMin: number;
        suggestedMax: number;
        flags: string[];
        confidence: number;
      };

      logger.info("analyzeInvoice result", { ticketTitle, amount, result });
      return result;
    } catch (err) {
      logger.error("analyzeInvoice failed", err);
      if (err instanceof HttpsError) throw err;
      throw new HttpsError("internal", "KI-Rechnungsprüfung fehlgeschlagen.");
    }
  }
);
