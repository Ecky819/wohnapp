import 'package:flutter_test/flutter_test.dart';
import 'package:wohnapp/models/app_user.dart';
import 'package:wohnapp/models/ticket.dart';
import 'package:wohnapp/services/routing_service.dart';

AppUser _contractor(String uid, List<String> specs) => AppUser(
      uid: uid,
      email: '$uid@test.de',
      name: uid,
      role: 'contractor',
      tenantId: 'tenant_1',
      specializations: specs,
    );

Ticket _ticket({String? assignedTo, String status = 'open'}) => Ticket(
      id: 'tid',
      title: 'T',
      description: '',
      status: status,
      priority: 'normal',
      tenantId: 'tenant_1',
      createdBy: 'u1',
      category: 'damage',
      assignedTo: assignedTo,
    );

void main() {
  group('RoutingService.detectCategory', () {
    test('detects plumbing keywords', () {
      expect(RoutingService.detectCategory('Wasserhahn tropft', ''), 'plumbing');
    });
    test('detects electrical keywords', () {
      expect(
          RoutingService.detectCategory('Steckdose defekt', 'Strom weg'),
          'electrical');
    });
    test('detects heating keywords', () {
      expect(RoutingService.detectCategory('Heizung kalt', ''), 'heating');
    });
    test('falls back to general for unknown text', () {
      expect(RoutingService.detectCategory('xyz abc', ''), 'general');
    });
    test('picks highest scoring category', () {
      // two plumbing keywords vs one electrical
      expect(
        RoutingService.detectCategory('Rohr undicht Abfluss verstopft Licht',
            ''),
        'plumbing',
      );
    });
  });

  group('RoutingService.rankContractors', () {
    test('category specialist ranks above wrong-category specialist', () {
      // plumber has plumbing specialization → matches
      // electrician has electrical only → does NOT match plumbing
      final plumber = _contractor('plumber', ['plumbing']);
      final electrician = _contractor('electrician', ['electrical']);
      final result = RoutingService.rankContractors(
        category: 'plumbing',
        contractors: [electrician, plumber],
        allTickets: [],
      );
      expect(result.first.user.uid, 'plumber');
    });

    test('within specialists, lower workload ranks first', () {
      final c1 = _contractor('c1', ['plumbing']);
      final c2 = _contractor('c2', ['plumbing']);
      final tickets = [
        _ticket(assignedTo: 'c1'),
        _ticket(assignedTo: 'c1'),
        _ticket(assignedTo: 'c2'),
      ];
      final result = RoutingService.rankContractors(
        category: 'plumbing',
        contractors: [c1, c2],
        allTickets: tickets,
      );
      expect(result.first.user.uid, 'c2');
    });

    test('done tickets do not count towards workload', () {
      final c1 = _contractor('c1', ['electrical']);
      final tickets = [
        _ticket(assignedTo: 'c1', status: 'done'),
        _ticket(assignedTo: 'c1', status: 'done'),
      ];
      final result = RoutingService.rankContractors(
        category: 'electrical',
        contractors: [c1],
        allTickets: tickets,
      );
      expect(result.first.activeTickets, 0);
    });

    test('returns empty list when no contractors', () {
      expect(
        RoutingService.rankContractors(
          category: 'general',
          contractors: [],
          allTickets: [],
        ),
        isEmpty,
      );
    });

    test('isSpecialist is true when specializations is empty (all-rounder)', () {
      final c = _contractor('c1', []);
      final result = RoutingService.rankContractors(
        category: 'heating',
        contractors: [c],
        allTickets: [],
      );
      expect(result.first.isSpecialist, isTrue);
    });
  });

  group('RoutingService.rankContractors — activeTickets count', () {
    test('counts only non-done tickets per contractor', () {
      final c = _contractor('c1', ['plumbing']);
      final tickets = [
        _ticket(assignedTo: 'c1', status: 'open'),
        _ticket(assignedTo: 'c1', status: 'in_progress'),
        _ticket(assignedTo: 'c1', status: 'done'),
      ];
      final result = RoutingService.rankContractors(
        category: 'plumbing',
        contractors: [c],
        allTickets: tickets,
      );
      expect(result.first.activeTickets, 2);
    });
  });
}
