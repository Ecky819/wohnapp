import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:wohnapp/models/app_enums.dart';

void main() {
  // ─── TicketStatus ──────────────────────────────────────────────────────────

  group('TicketStatus.fromString', () {
    test('open round-trips', () {
      expect(TicketStatus.fromString('open'), TicketStatus.open);
    });
    test('in_progress round-trips', () {
      expect(TicketStatus.fromString('in_progress'), TicketStatus.inProgress);
    });
    test('done round-trips', () {
      expect(TicketStatus.fromString('done'), TicketStatus.done);
    });
    test('unknown falls back to open', () {
      expect(TicketStatus.fromString('unknown'), TicketStatus.open);
    });
  });

  group('TicketStatus labels', () {
    test('open label', () => expect(TicketStatus.open.label, 'Offen'));
    test('inProgress label', () => expect(TicketStatus.inProgress.label, 'In Bearbeitung'));
    test('done label', () => expect(TicketStatus.done.label, 'Erledigt'));
  });

  group('TicketStatus colors', () {
    test('open is orange', () {
      expect(TicketStatus.open.color.toARGB32(), Colors.orange.toARGB32());
    });
    test('inProgress is blue', () {
      expect(TicketStatus.inProgress.color.toARGB32(), Colors.blue.toARGB32());
    });
    test('done is green', () {
      expect(TicketStatus.done.color.toARGB32(), Colors.green.toARGB32());
    });
  });

  // ─── UserRole ──────────────────────────────────────────────────────────────

  group('UserRole.fromString', () {
    test('manager round-trips', () {
      expect(UserRole.fromString('manager'), UserRole.manager);
    });
    test('contractor round-trips', () {
      expect(UserRole.fromString('contractor'), UserRole.contractor);
    });
    test('tenant_user round-trips', () {
      expect(UserRole.fromString('tenant_user'), UserRole.tenantUser);
    });
    test('unknown falls back to tenantUser', () {
      expect(UserRole.fromString('other'), UserRole.tenantUser);
    });
  });

  group('UserRole labels', () {
    test('manager label', () => expect(UserRole.manager.label, 'Verwaltung'));
    test('contractor label', () => expect(UserRole.contractor.label, 'Handwerker'));
    test('tenantUser label', () => expect(UserRole.tenantUser.label, 'Mieter'));
  });

  // ─── AgreementStatus ───────────────────────────────────────────────────────

  group('AgreementStatus.fromString', () {
    test('active round-trips', () {
      expect(AgreementStatus.fromString('active'), AgreementStatus.active);
    });
    test('notice_given round-trips', () {
      expect(AgreementStatus.fromString('notice_given'), AgreementStatus.noticeGiven);
    });
    test('ended round-trips', () {
      expect(AgreementStatus.fromString('ended'), AgreementStatus.ended);
    });
    test('unknown falls back to active', () {
      expect(AgreementStatus.fromString('anything'), AgreementStatus.active);
    });
  });

  group('AgreementStatus colors', () {
    test('active is green', () {
      expect(AgreementStatus.active.color.toARGB32(), Colors.green.toARGB32());
    });
    test('noticeGiven is orange', () {
      expect(AgreementStatus.noticeGiven.color.toARGB32(), Colors.orange.toARGB32());
    });
    test('ended is grey', () {
      expect(AgreementStatus.ended.color.toARGB32(), Colors.grey.toARGB32());
    });
  });

  // ─── TicketCategory ────────────────────────────────────────────────────────

  group('TicketCategory.fromString', () {
    test('damage round-trips', () {
      expect(TicketCategory.fromString('damage'), TicketCategory.damage);
    });
    test('maintenance round-trips', () {
      expect(TicketCategory.fromString('maintenance'), TicketCategory.maintenance);
    });
    test('insurance_claim round-trips', () {
      expect(TicketCategory.fromString('insurance_claim'), TicketCategory.insuranceClaim);
    });
    test('unknown falls back to damage', () {
      expect(TicketCategory.fromString('other'), TicketCategory.damage);
    });
  });

  // ─── TicketPriority ────────────────────────────────────────────────────────

  group('TicketPriority.fromString', () {
    test('low round-trips', () {
      expect(TicketPriority.fromString('low'), TicketPriority.low);
    });
    test('normal round-trips', () {
      expect(TicketPriority.fromString('normal'), TicketPriority.normal);
    });
    test('high round-trips', () {
      expect(TicketPriority.fromString('high'), TicketPriority.high);
    });
    test('urgent round-trips', () {
      expect(TicketPriority.fromString('urgent'), TicketPriority.urgent);
    });
    test('unknown falls back to normal', () {
      expect(TicketPriority.fromString('none'), TicketPriority.normal);
    });
  });
}
