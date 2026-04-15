import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wohnapp/widgets/app_state_widgets.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

void main() {
  group('EmptyState', () {
    testWidgets('shows title', (tester) async {
      await tester.pumpWidget(_wrap(
        const EmptyState(icon: Icons.inbox, title: 'Leer'),
      ));
      expect(find.text('Leer'), findsOneWidget);
    });

    testWidgets('shows subtitle when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        const EmptyState(
          icon: Icons.inbox,
          title: 'Leer',
          subtitle: 'Nichts hier',
        ),
      ));
      expect(find.text('Nichts hier'), findsOneWidget);
    });

    testWidgets('does not show subtitle when omitted', (tester) async {
      await tester.pumpWidget(_wrap(
        const EmptyState(icon: Icons.inbox, title: 'Leer'),
      ));
      expect(find.text('Nichts hier'), findsNothing);
    });

    testWidgets('shows action widget when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        EmptyState(
          icon: Icons.inbox,
          title: 'Leer',
          action: ElevatedButton(
            onPressed: () {},
            child: const Text('Aktion'),
          ),
        ),
      ));
      expect(find.text('Aktion'), findsOneWidget);
    });
  });

  group('ErrorState', () {
    testWidgets('shows message', (tester) async {
      await tester.pumpWidget(_wrap(
        const ErrorState(message: 'Netzwerkfehler'),
      ));
      expect(find.text('Netzwerkfehler'), findsOneWidget);
      expect(find.text('Etwas ist schiefgelaufen'), findsOneWidget);
    });

    testWidgets('shows retry button when onRetry provided', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(_wrap(
        ErrorState(
          message: 'Fehler',
          onRetry: () => tapped = true,
        ),
      ));
      await tester.tap(find.text('Erneut versuchen'));
      expect(tapped, isTrue);
    });

    testWidgets('hides retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(_wrap(
        const ErrorState(message: 'Fehler'),
      ));
      expect(find.text('Erneut versuchen'), findsNothing);
    });
  });
}
