import 'notification_preferences.dart';

class AppUser {
  final String uid;
  final String email;
  final String name;
  final String role;
  final String tenantId;
  /// Contractor specializations, e.g. ['plumbing', 'heating']. Empty = all.
  final List<String> specializations;
  /// Assigned unit id (tenant_user only).
  final String? unitId;
  final NotificationPreferences notificationPreferences;

  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    required this.tenantId,
    this.specializations = const [],
    this.unitId,
    this.notificationPreferences = const NotificationPreferences(),
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      email: map['email'] as String? ?? '',
      name: map['name'] as String? ?? '',
      role: map['role'] as String? ?? 'tenant_user',
      tenantId: map['tenantId'] as String? ?? '',
      specializations: List<String>.from(map['specializations'] ?? []),
      unitId: map['unitId'] as String?,
      notificationPreferences: NotificationPreferences.fromMap(
        map['notificationPreferences'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'email': email,
        'name': name,
        'role': role,
        'tenantId': tenantId,
        'specializations': specializations,
        if (unitId != null) 'unitId': unitId,
      };

  String get roleLabel {
    switch (role) {
      case 'manager':
        return 'Verwaltung';
      case 'contractor':
        return 'Handwerker';
      case 'tenant_user':
        return 'Mieter';
      default:
        return role;
    }
  }
}
