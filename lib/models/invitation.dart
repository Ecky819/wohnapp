import 'package:cloud_firestore/cloud_firestore.dart';

enum InvitationRole { tenantUser, contractor }

class Invitation {
  final String code;
  final String tenantId;
  final InvitationRole role;
  final bool used;
  final DateTime? expiresAt;
  final String createdBy;
  /// Pre-assigned unit for self-registration QR codes.
  final String? unitId;
  final String? unitName;

  const Invitation({
    required this.code,
    required this.tenantId,
    required this.role,
    required this.used,
    required this.createdBy,
    this.expiresAt,
    this.unitId,
    this.unitName,
  });

  factory Invitation.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Invitation(
      code: doc.id,
      tenantId: d['tenantId'] as String? ?? '',
      role: d['role'] == 'contractor'
          ? InvitationRole.contractor
          : InvitationRole.tenantUser,
      used: d['used'] as bool? ?? false,
      createdBy: d['createdBy'] as String? ?? '',
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      unitId: d['unitId'] as String?,
      unitName: d['unitName'] as String?,
    );
  }

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isValid => !used && !isExpired;

  String get roleString =>
      role == InvitationRole.contractor ? 'contractor' : 'tenant_user';

  String get roleLabel =>
      role == InvitationRole.contractor ? 'Handwerker' : 'Mieter';
}
