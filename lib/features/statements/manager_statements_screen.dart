import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/annual_statement.dart';
import '../../repositories/annual_statement_repository.dart';
import '../../router.dart';
import '../../user_provider.dart';

class ManagerStatementsScreen extends ConsumerWidget {
  const ManagerStatementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantId =
        ref.watch(currentUserProvider).valueOrNull?.tenantId ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Jahresabrechnungen')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.send_outlined),
        label: const Text('Abrechnung senden'),
        onPressed: () async {
          final created =
              await context.push<bool>(AppRoutes.createStatement);
          if (created == true && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Abrechnung erfolgreich zugestellt.')),
            );
          }
        },
      ),
      body: tenantId.isEmpty
          ? const Center(child: Text('Nicht angemeldet.'))
          : _StatementsList(tenantId: tenantId),
    );
  }
}

class _StatementsList extends ConsumerWidget {
  const _StatementsList({required this.tenantId});
  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stmtsAsync =
        ref.watch(managerStatementsProvider(tenantId));

    return stmtsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (stmts) {
        if (stmts.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.description_outlined,
                    size: 48, color: Colors.grey),
                SizedBox(height: 12),
                Text('Noch keine Abrechnungen versandt.',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          itemCount: stmts.length,
          itemBuilder: (_, i) => _StatementTile(stmt: stmts[i]),
        );
      },
    );
  }
}

class _StatementTile extends StatelessWidget {
  const _StatementTile({required this.stmt});
  final AnnualStatement stmt;

  static final _fmt = DateFormat('dd.MM.yyyy HH:mm');
  static final _currency = NumberFormat.currency(locale: 'de_DE', symbol: '€');

  Color _statusColor(StatementStatus s) {
    switch (s) {
      case StatementStatus.acknowledged:
        return Colors.green;
      case StatementStatus.sent:
        return Colors.orange;
      case StatementStatus.draft:
        return Colors.grey;
    }
  }

  IconData _statusIcon(StatementStatus s) {
    switch (s) {
      case StatementStatus.acknowledged:
        return Icons.verified_outlined;
      case StatementStatus.sent:
        return Icons.mark_email_read_outlined;
      case StatementStatus.draft:
        return Icons.edit_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              _statusColor(stmt.status).withValues(alpha: 0.12),
          child: Icon(_statusIcon(stmt.status),
              color: _statusColor(stmt.status), size: 20),
        ),
        title: Text(
          '${stmt.year} · ${stmt.recipientName}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stmt.unitName.isNotEmpty)
              Text(stmt.unitName,
                  style: const TextStyle(fontSize: 12)),
            if (stmt.totalTenantCosts > 0)
              Text(_currency.format(stmt.totalTenantCosts),
                  style: const TextStyle(fontSize: 12)),
            if (stmt.acknowledgedAt != null)
              Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 12, color: Colors.green),
                  const SizedBox(width: 3),
                  Text(
                    'Bestätigt ${_fmt.format(stmt.acknowledgedAt!)}',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.green),
                  ),
                ],
              )
            else if (stmt.sentAt != null)
              Text(
                'Zugestellt ${_fmt.format(stmt.sentAt!)}',
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.picture_as_pdf_outlined),
          tooltip: 'PDF öffnen',
          onPressed: () => launchUrl(Uri.parse(stmt.pdfUrl)),
        ),
        isThreeLine: true,
      ),
    );
  }
}
