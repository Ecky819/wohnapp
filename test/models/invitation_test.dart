import 'package:flutter_test/flutter_test.dart';
import 'package:wohnapp/models/invitation.dart';

Invitation _make({
  bool used = false,
  DateTime? expiresAt,
  InvitationRole role = InvitationRole.tenantUser,
}) =>
    Invitation(
      code: 'ABCD1234',
      tenantId: 'tenant_1',
      role: role,
      used: used,
      createdBy: 'manager_1',
      expiresAt: expiresAt,
    );

void main() {
  group('Invitation.isExpired', () {
    test('null expiresAt → not expired', () {
      expect(_make().isExpired, isFalse);
    });
    test('future expiresAt → not expired', () {
      expect(
        _make(expiresAt: DateTime.now().add(const Duration(days: 1))).isExpired,
        isFalse,
      );
    });
    test('past expiresAt → expired', () {
      expect(
        _make(expiresAt: DateTime.now().subtract(const Duration(seconds: 1)))
            .isExpired,
        isTrue,
      );
    });
  });

  group('Invitation.isValid', () {
    test('unused + not expired → valid', () {
      expect(_make().isValid, isTrue);
    });
    test('used → invalid', () {
      expect(_make(used: true).isValid, isFalse);
    });
    test('expired → invalid', () {
      expect(
        _make(expiresAt: DateTime.now().subtract(const Duration(seconds: 1)))
            .isValid,
        isFalse,
      );
    });
  });

  group('Invitation.roleString', () {
    test('tenantUser → tenant_user', () {
      expect(_make().roleString, 'tenant_user');
    });
    test('contractor → contractor', () {
      expect(_make(role: InvitationRole.contractor).roleString, 'contractor');
    });
  });

  group('Invitation.roleLabel', () {
    test('tenantUser → Mieter', () {
      expect(_make().roleLabel, 'Mieter');
    });
    test('contractor → Handwerker', () {
      expect(_make(role: InvitationRole.contractor).roleLabel, 'Handwerker');
    });
  });
}
