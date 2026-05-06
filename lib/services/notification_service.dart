import 'dart:async';

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

// ─── Android notification channels ───────────────────────────────────────────

const _kTicketChannel = AndroidNotificationChannel(
  'ticket_updates',
  'Ticket-Updates',
  description: 'Benachrichtigungen zu Statusänderungen, Zuweisungen und Kommentaren.',
  importance: Importance.high,
);

const _kMaintenanceChannel = AndroidNotificationChannel(
  'maintenance_alerts',
  'Wartungshinweise',
  description: 'Benachrichtigungen zu überfälligen oder bald fälligen Gerätewartungen.',
  importance: Importance.high,
);

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  // Emits route paths that the app should navigate to on notification tap.
  static final _navController = StreamController<String>.broadcast();
  static Stream<String> get onNavigateTo => _navController.stream;

  Future<void> init() async {
    // ── iOS / Android permissions ──────────────────────────────────────────
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // ── Background handler ─────────────────────────────────────────────────
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // ── Android notification channels ──────────────────────────────────────
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_kTicketChannel);
    await androidPlugin?.createNotificationChannel(_kMaintenanceChannel);

    // ── Local notifications init ───────────────────────────────────────────
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Maintenance alert tap → open Digital Twin
        if (details.payload == 'maintenance_alert') {
          _navController.add('/buildings');
        }
      },
    );

    // ── iOS: show notification banner while app is in foreground ───────────
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // ── Foreground FCM messages → local notification ───────────────────────
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // ── Background tap: app was in background, user taps notification ──────
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      if (msg.data['type'] == 'maintenance_alert') {
        _navController.add('/buildings');
      }
    });

    // ── Terminated tap: app was killed, user taps notification ─────────────
    final initial = await _messaging.getInitialMessage();
    if (initial?.data['type'] == 'maintenance_alert') {
      _navController.add('/buildings');
    }

    // ── Token management ───────────────────────────────────────────────────
    await _saveFcmToken();
    _messaging.onTokenRefresh.listen(_updateFcmToken);
  }

  // ─── Foreground handler ──────────────────────────────────────────────────

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final isMaintenance = message.data['type'] == 'maintenance_alert';
    final channel = isMaintenance ? _kMaintenanceChannel : _kTicketChannel;

    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
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
      payload: isMaintenance ? 'maintenance_alert' : message.data['ticketId'],
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
