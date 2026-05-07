import Anthropic from "@anthropic-ai/sdk";
import * as admin from "firebase-admin";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { onCall, HttpsError, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
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
  data: Record<string, string>,
  channelId = "ticket_updates"
): Promise<void> {
  await admin.messaging().send({
    token,
    notification: { title, body },
    data,
    android: {
      notification: { channelId, priority: "high" },
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

// ─── Trigger: invoice status changed → ERP + SAP Webhook ─────────────────────

/**
 * Fires when a manager approves or rejects an invoice.
 * Posts the event in parallel to:
 *  1. ERP webhook (generic, configurable)
 *  2. SAP webhook (SAP Business One / S4HANA middleware)
 *
 * SAP payload follows the SAP Business One Service Layer schema for
 * vendor invoices (APInvoices) so it can be forwarded by a middleware
 * without transformation.
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

    const invoiceId = event.params.invoiceId;
    const tenantId = after.tenantId as string;
    const tenantSnap = await db.collection("tenants").doc(tenantId).get();
    const tenantData = tenantSnap.data() ?? {};

    const webhookPromises: Promise<void>[] = [];

    // ── 1. ERP webhook ────────────────────────────────────────────────────
    const erpUrl = tenantData.erpWebhookUrl as string | undefined;
    if (erpUrl) {
      webhookPromises.push(
        _postWebhook({
          url: erpUrl,
          secret: tenantData.erpWebhookSecret as string | undefined,
          secretHeader: "X-Webhook-Secret",
          payload: {
            event: `invoice.${newStatus}`,
            invoiceId,
            tenantId,
            data: after,
          },
          label: "ERP",
          invoiceId,
        })
      );
    }

    // ── 2. SAP webhook ────────────────────────────────────────────────────
    const sapUrl = tenantData.sapWebhookUrl as string | undefined;
    if (sapUrl && newStatus === "approved") {
      const positions = (after.positions as Array<Record<string, unknown>> | undefined) ?? [];
      const sapPayload = _buildSapInvoicePayload({
        invoiceId,
        after,
        tenantData,
        positions,
      });
      webhookPromises.push(
        _postWebhook({
          url: sapUrl,
          secret: tenantData.sapWebhookSecret as string | undefined,
          secretHeader: "Authorization",
          secretPrefix: "Bearer ",
          payload: sapPayload,
          label: "SAP",
          invoiceId,
        })
      );
    }

    await Promise.all(webhookPromises);
  }
);

// ── SAP Business One / S4HANA payload builder ─────────────────────────────────

function _buildSapInvoicePayload(params: {
  invoiceId: string;
  after: Record<string, unknown>;
  tenantData: Record<string, unknown>;
  positions: Array<Record<string, unknown>>;
}): Record<string, unknown> {
  const { invoiceId, after, tenantData, positions } = params;
  const now = new Date();
  const dateStr = now.toISOString().split("T")[0]; // YYYY-MM-DD

  // SAP Business One Service Layer schema for AP Invoice
  return {
    // Metadata
    DocType: "dDocument_Service",
    DocDate: dateStr,
    DocDueDate: dateStr,
    Comments: `Wohnapp Rechnung ${invoiceId} – ${after.ticketTitle ?? ""}`,
    NumAtCard: invoiceId.substring(0, 16),

    // Supplier / Vendor
    CardCode: after.contractorId ?? "",
    CardName: after.contractorName ?? "",

    // Cost center / Company
    ProjectCode: tenantData.sapCostCenter ?? "",
    BranchID: tenantData.sapCompanyDb ?? "",

    // Currency
    DocCurrency: "EUR",
    DocTotal: after.amount ?? 0,

    // Line items
    DocumentLines: positions.length > 0
      ? positions.map((p, i) => ({
          LineNum: i,
          ItemDescription: p.description ?? `Position ${i + 1}`,
          Quantity: 1,
          UnitPrice: p.amount ?? 0,
          Currency: "EUR",
          COGSCostingCode: tenantData.sapCostCenter ?? "",
          AccountCode: "6300", // Instandhaltungsaufwand
        }))
      : [{
          LineNum: 0,
          ItemDescription: (after.ticketTitle as string | undefined) ?? "Handwerkerrechnung",
          Quantity: 1,
          UnitPrice: after.amount ?? 0,
          Currency: "EUR",
          COGSCostingCode: tenantData.sapCostCenter ?? "",
          AccountCode: "6300",
        }],

    // Wohnapp-Referenz als User-Defined Fields
    U_WohnappInvoiceId: invoiceId,
    U_WohnappTenantId: after.tenantId ?? "",
    U_WohnappTicketId: after.ticketId ?? "",
  };
}

// ── Generischer Webhook-Versand ───────────────────────────────────────────────

async function _postWebhook(params: {
  url: string;
  secret?: string;
  secretHeader: string;
  secretPrefix?: string;
  payload: Record<string, unknown>;
  label: string;
  invoiceId: string;
}): Promise<void> {
  const { url, secret, secretHeader, secretPrefix = "", payload, label, invoiceId } = params;

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "User-Agent": "Wohnapp/1.0",
  };
  if (secret) headers[secretHeader] = `${secretPrefix}${secret}`;

  try {
    const resp = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10_000),
    });
    logger.info(`${label} webhook fired for invoice ${invoiceId} → ${resp.status}`);
  } catch (err) {
    logger.error(`${label} webhook failed for invoice ${invoiceId}`, err);
  }
}

// ─── Scheduled: tägl. Wartungsalert-Check (08:00 Europe/Berlin) ──────────────

/**
 * Läuft täglich um 08:00 Uhr (Europe/Berlin).
 * Scannt alle Geräte, berechnet nextServiceDue und schickt eine
 * gruppierte Push-Benachrichtigung an alle Manager des betroffenen Mandanten.
 *
 * Throttling:
 *   • überfällig  → max. 1× pro Tag pro Gerät
 *   • bald fällig → max. 1× pro Woche pro Gerät
 *
 * Schreibt `lastMaintenanceAlertSentAt` zurück auf das Gerät-Dokument.
 */
export const checkMaintenanceAlerts = onSchedule(
  {
    schedule: "0 8 * * *",
    timeZone: "Europe/Berlin",
    region: "europe-west3",
  },
  async () => {
    const nowMs = Date.now();
    const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
    const oneDayMs = 24 * 60 * 60 * 1000;
    const sevenDaysMs = 7 * oneDayMs;

    const devicesSnap = await db.collection("devices").get();

    const alertsByTenant: Record<
      string,
      { overdue: string[]; dueSoon: string[] }
    > = {};
    const deviceUpdates: Promise<FirebaseFirestore.WriteResult>[] = [];

    for (const doc of devicesSnap.docs) {
      const data = doc.data();
      const tenantId = data.tenantId as string | undefined;
      if (!tenantId) continue;

      const lastServiceAt = (
        data.lastServiceAt as admin.firestore.Timestamp | undefined
      )?.toDate();
      const installedAt = (
        data.installedAt as admin.firestore.Timestamp | undefined
      )?.toDate();
      const baseDate = lastServiceAt ?? installedAt;
      if (!baseDate) continue;

      const intervalMonths =
        (data.serviceIntervalMonths as number | undefined) ??
        _defaultIntervalMonths(data.category as string | undefined);

      const nextServiceDue = _addMonths(baseDate, intervalMonths);
      const nextMs = nextServiceDue.getTime();

      const isOverdue = nextMs < nowMs;
      const isDueSoon = !isOverdue && nextMs < nowMs + thirtyDaysMs;
      if (!isOverdue && !isDueSoon) continue;

      // Throttle: skip if already alerted recently
      const lastAlertAt = (
        data.lastMaintenanceAlertSentAt as
          | admin.firestore.Timestamp
          | undefined
      )?.toDate();
      if (lastAlertAt) {
        const msSince = nowMs - lastAlertAt.getTime();
        if (isOverdue && msSince < oneDayMs) continue;
        if (isDueSoon && msSince < sevenDaysMs) continue;
      }

      const deviceName = (data.name as string | undefined) ?? "Gerät";
      if (!alertsByTenant[tenantId]) {
        alertsByTenant[tenantId] = { overdue: [], dueSoon: [] };
      }
      if (isOverdue) {
        alertsByTenant[tenantId].overdue.push(deviceName);
      } else {
        alertsByTenant[tenantId].dueSoon.push(deviceName);
      }

      deviceUpdates.push(
        doc.ref.update({
          lastMaintenanceAlertSentAt:
            admin.firestore.FieldValue.serverTimestamp(),
        })
      );
    }

    await Promise.all(deviceUpdates);

    for (const [tenantId, alerts] of Object.entries(alertsByTenant)) {
      const managersSnap = await db
        .collection("users")
        .where("tenantId", "==", tenantId)
        .where("role", "==", "manager")
        .get();

      const { title, body } = _buildAlertMessage(alerts);

      for (const managerDoc of managersSnap.docs) {
        const fcmToken = managerDoc.data().fcmToken as string | undefined;
        if (!fcmToken) continue;

        try {
          await sendPush(
            fcmToken,
            title,
            body,
            { type: "maintenance_alert", tenantId },
            "maintenance_alerts"
          );
          logger.info(
            `Maintenance alert sent to ${managerDoc.id} for tenant ${tenantId}`
          );
        } catch (err) {
          logger.error(
            `Failed to send maintenance alert to ${managerDoc.id}`,
            err
          );
        }
      }
    }

    logger.info(
      `checkMaintenanceAlerts done. Tenants alerted: ${Object.keys(alertsByTenant).length}`
    );
  }
);

// ─── HTTP: IoT Sensor Webhook ─────────────────────────────────────────────────

/**
 * Empfängt Sensor-Messwerte von beliebigen IoT-Systemen (HomeAssistant,
 * MQTT-Bridge, eigene Geräte) per HTTP POST.
 *
 * Auth: Header `X-Api-Key` muss mit dem `iotWebhookKey` des Mandanten
 * in Firestore übereinstimmen.
 *
 * Request-Body:
 * {
 *   tenantId: string,
 *   readings: Array<{
 *     sensorType: string,   // temperature|humidity|co2|water_leak|smoke|energy_kwh|custom
 *     value: number,
 *     unit: string,         // °C | % | ppm | kWh | ...
 *     deviceId?: string,    // optional – Link zum Device-Dokument
 *     unitId?: string,      // optional – Wohnungs-ID
 *     label?: string        // optional – Anzeigename
 *   }>,
 *   source?: string,        // homeassistant | mqtt | custom
 *   timestamp?: string      // ISO-8601, default: jetzt
 * }
 *
 * Bei Schwellwert-Überschreitung wird automatisch ein Wartungs-Ticket angelegt
 * (max. 1× pro Gerät und Sensor-Typ innerhalb von 24 Stunden).
 */
export const receiveIotData = onRequest(
  { region: "europe-west3" },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    // ── API-Key-Prüfung ───────────────────────────────────────────────────
    const apiKey = req.headers["x-api-key"] as string | undefined;
    if (!apiKey) {
      res.status(401).json({ error: "X-Api-Key header missing" });
      return;
    }

    const body = req.body as {
      tenantId?: string;
      readings?: Array<{
        sensorType: string;
        value: number;
        unit: string;
        deviceId?: string;
        unitId?: string;
        label?: string;
      }>;
      source?: string;
      timestamp?: string;
    };

    const { tenantId, readings, source, timestamp } = body;

    if (!tenantId || !Array.isArray(readings) || readings.length === 0) {
      res.status(400).json({ error: "tenantId and readings are required" });
      return;
    }

    // Verify key against tenant document
    const tenantSnap = await db.collection("tenants").doc(tenantId).get();
    if (!tenantSnap.exists) {
      res.status(404).json({ error: "Tenant not found" });
      return;
    }
    const storedKey = tenantSnap.data()?.iotWebhookKey as string | undefined;
    if (!storedKey || storedKey !== apiKey) {
      res.status(403).json({ error: "Invalid API key" });
      return;
    }

    // ── Messwerte speichern ───────────────────────────────────────────────
    const ts = timestamp ? new Date(timestamp) : new Date();
    const firestoreTs = admin.firestore.Timestamp.fromDate(ts);
    const batch = db.batch();
    const readingRefs: FirebaseFirestore.DocumentReference[] = [];

    for (const r of readings) {
      const ref = db.collection("sensor_readings").doc();
      batch.set(ref, {
        tenantId,
        sensorType: r.sensorType,
        value: r.value,
        unit: r.unit,
        ...(r.deviceId ? { deviceId: r.deviceId } : {}),
        ...(r.unitId ? { unitId: r.unitId } : {}),
        ...(r.label ? { label: r.label } : {}),
        ...(source ? { source } : {}),
        timestamp: firestoreTs,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      readingRefs.push(ref);
    }

    await batch.commit();

    // ── Schwellwert-Prüfung ───────────────────────────────────────────────
    const alertPromises: Promise<void>[] = [];

    for (const r of readings) {
      if (!r.deviceId) continue;

      // Load device from the correct subcollection path
      // Devices are stored under units/{unitId}/devices/{deviceId}
      // We do a collectionGroup query to find by ID across all units
      const deviceSnap = await db
        .collectionGroup("devices")
        .where("tenantId", "==", tenantId)
        .get()
        .then((s) => s.docs.find((d) => d.id === r.deviceId));

      if (!deviceSnap) continue;

      const deviceData = deviceSnap.data();
      const thresholds = deviceData.sensorThresholds as
        | Record<string, { min?: number; max?: number }>
        | undefined;

      if (!thresholds?.[r.sensorType]) continue;

      const { min, max } = thresholds[r.sensorType];
      const breached =
        (min !== undefined && r.value < min) ||
        (max !== undefined && r.value > max);

      if (!breached) continue;

      // Throttle: max one alert per device per sensor per 24h
      const lastAlerts = deviceData.lastSensorAlert as
        | Record<string, admin.firestore.Timestamp>
        | undefined;
      const lastAlert = lastAlerts?.[r.sensorType];
      const oneDayMs = 24 * 60 * 60 * 1000;
      if (lastAlert && Date.now() - lastAlert.toMillis() < oneDayMs) continue;

      alertPromises.push(
        _createThresholdTicket({
          tenantId,
          deviceId: r.deviceId,
          deviceName: deviceData.name as string ?? "Gerät",
          unitId: r.unitId ?? (deviceData.unitId as string | undefined),
          unitName: deviceData.unitName as string | undefined,
          sensorType: r.sensorType,
          value: r.value,
          unit: r.unit,
          min,
          max,
          deviceRef: deviceSnap.ref,
        })
      );
    }

    await Promise.all(alertPromises);

    logger.info(
      `receiveIotData: ${readings.length} readings written for tenant ${tenantId}`
    );
    res.status(200).json({ ok: true, written: readings.length });
  }
);

async function _createThresholdTicket(params: {
  tenantId: string;
  deviceId: string;
  deviceName: string;
  unitId?: string;
  unitName?: string;
  sensorType: string;
  value: number;
  unit: string;
  min?: number;
  max?: number;
  deviceRef: FirebaseFirestore.DocumentReference;
}): Promise<void> {
  const {
    tenantId, deviceId, deviceName, unitId, unitName,
    sensorType, value, unit, min, max, deviceRef,
  } = params;

  const sensorLabels: Record<string, string> = {
    temperature: "Temperatur",
    humidity: "Luftfeuchtigkeit",
    co2: "CO₂",
    water_leak: "Wasserleck",
    smoke: "Rauchmelder",
    energy_kwh: "Energieverbrauch",
  };
  const label = sensorLabels[sensorType] ?? sensorType;

  const direction =
    min !== undefined && value < min ? "zu niedrig" : "zu hoch";
  const limit = min !== undefined && value < min ? min : max;

  const title = `${label}-Alarm: ${value} ${unit} (Grenzwert: ${limit} ${unit})`;
  const description =
    `Gerät: ${deviceName}\n` +
    `Messwert ${direction}: ${value} ${unit}\n` +
    (unitName ? `Wohnung: ${unitName}\n` : "") +
    `Sensor-Typ: ${sensorType}`;

  await db.collection("tickets").add({
    title,
    description,
    status: "open",
    priority: value !== undefined && sensorType === "water_leak" ? "high" : "normal",
    category: "maintenance",
    tenantId,
    createdBy: "system_iot",
    ...(unitId ? { unitId } : {}),
    ...(unitName ? { unitName } : {}),
    deviceId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    source: "iot_threshold",
  });

  // Update throttle timestamp
  await deviceRef.update({
    [`lastSensorAlert.${sensorType}`]: admin.firestore.FieldValue.serverTimestamp(),
  });

  logger.info(
    `Threshold ticket created for device ${deviceId} sensor ${sensorType}: ${value} ${unit}`
  );
}

function _defaultIntervalMonths(category: string | undefined): number {
  switch (category) {
    case "heating":
      return 12;
    case "plumbing":
      return 24;
    case "electrical":
      return 24;
    default:
      return 12;
  }
}

function _addMonths(date: Date, months: number): Date {
  const result = new Date(date);
  result.setMonth(result.getMonth() + months);
  return result;
}

function _buildAlertMessage(alerts: {
  overdue: string[];
  dueSoon: string[];
}): { title: string; body: string } {
  const overdueCount = alerts.overdue.length;
  const dueSoonCount = alerts.dueSoon.length;
  const total = overdueCount + dueSoonCount;

  const plural = (n: number, word: string) =>
    `${n} ${word}${n !== 1 ? "en" : ""}`;

  if (overdueCount > 0 && dueSoonCount === 0) {
    const names = alerts.overdue.slice(0, 2).join(", ");
    const suffix =
      overdueCount > 2 ? ` und ${overdueCount - 2} weitere` : "";
    return {
      title: `${plural(overdueCount, "Wartung")} überfällig`,
      body:
        overdueCount === 1
          ? `${names} benötigt sofort eine Wartung.`
          : `${names}${suffix} sind überfällig.`,
    };
  }

  if (dueSoonCount > 0 && overdueCount === 0) {
    const names = alerts.dueSoon.slice(0, 2).join(", ");
    const suffix = dueSoonCount > 2 ? ` und ${dueSoonCount - 2} weitere` : "";
    return {
      title: `${plural(dueSoonCount, "Wartung")} bald fällig`,
      body:
        dueSoonCount === 1
          ? `${names} wird in weniger als 30 Tagen fällig.`
          : `${names}${suffix} bald fällig.`,
    };
  }

  return {
    title: `${total} Wartungshinweise`,
    body: `${overdueCount} überfällig, ${dueSoonCount} bald fällig.`,
  };
}

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
