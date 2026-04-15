import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Background handler — must be top-level
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message: ${message.messageId}');
}

// ─── Android notification channel ─────────────────────────────────────────────

const _kAndroidChannel = AndroidNotificationChannel(
  'ticket_updates',
  'Ticket-Updates',
  description: 'Benachrichtigungen zu Statusänderungen, Zuweisungen und Kommentaren.',
  importance: Importance.high,
);

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // ── iOS / Android permissions ──────────────────────────────────────────
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // ── Background handler ─────────────────────────────────────────────────
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // ── Local notifications setup (needed for foreground on Android) ───────
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_kAndroidChannel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false, // already requested above via FCM
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _localNotifications.initialize(settings: initSettings);

    // ── iOS: show notification banner while app is in foreground ───────────
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // ── Foreground FCM messages → local notification ───────────────────────
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // ── Token management ───────────────────────────────────────────────────
    await _saveFcmToken();
    _messaging.onTokenRefresh.listen(_updateFcmToken);
  }

  // ─── Foreground handler ──────────────────────────────────────────────────

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _kAndroidChannel.id,
          _kAndroidChannel.name,
          channelDescription: _kAndroidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data['ticketId'],
    );
  }

  // ─── Token helpers ───────────────────────────────────────────────────────

  Future<void> _saveFcmToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final token = await _messaging.getToken();
    if (token == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'fcmToken': token});
    debugPrint('FCM token saved: $token');
  }

  Future<void> _updateFcmToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'fcmToken': token});
  }

  // ─── Notification writers (called by app code) ───────────────────────────

  static Future<void> notifyStatusChange({
    required String ticketId,
    required String newStatus,
    required String createdBy,
  }) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'type': 'ticket_status_changed',
      'ticketId': ticketId,
      'newStatus': newStatus,
      'targetUserId': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
      'sent': false,
    });
  }

  static Future<void> notifyAssignment({
    required String ticketId,
    required String ticketTitle,
    required String contractorId,
  }) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (contractorId == currentUid) return;

    await FirebaseFirestore.instance.collection('notifications').add({
      'type': 'ticket_assigned',
      'ticketId': ticketId,
      'ticketTitle': ticketTitle,
      'targetUserId': contractorId,
      'createdAt': FieldValue.serverTimestamp(),
      'sent': false,
    });
  }

  static Future<void> notifyNewComment({
    required String ticketId,
    required String ticketTitle,
    required String authorName,
    required String createdBy,
    String? assignedTo,
  }) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final targets = <String>{createdBy, if (assignedTo != null) assignedTo}
      ..remove(currentUid);

    final batch = FirebaseFirestore.instance.batch();
    final col = FirebaseFirestore.instance.collection('notifications');

    for (final uid in targets) {
      batch.set(col.doc(), {
        'type': 'new_comment',
        'ticketId': ticketId,
        'ticketTitle': ticketTitle,
        'authorName': authorName,
        'targetUserId': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'sent': false,
      });
    }

    await batch.commit();
  }
}
