import * as admin from "firebase-admin";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

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

