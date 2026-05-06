import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/annual_statement.dart';
import '../../models/statement_position.dart';
import '../../models/tenant.dart';
import '../../repositories/annual_statement_repository.dart';
import '../../repositories/tenant_repository.dart';
import '../../user_provider.dart';

class TenantStatementsScreen extends ConsumerWidget {
  const TenantStatementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProvider).valueOrNull?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Meine Abrechnungen')),
      body: uid.isEmpty
          ? const Center(child: Text('Nicht angemeldet.'))
          : _TenantStatementsList(recipientId: uid),
    );
  }
}

class _TenantStatementsList extends ConsumerWidget {
  const _TenantStatementsList({required this.recipientId});
  final String recipientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stmtsAsync = ref.watch(tenantStatementsProvider(recipientId));
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
                Text('Noch keine Jahresabrechnungen vorhanden.',
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: stmts.length,
          itemBuilder: (_, i) =>
              _TenantStatementCard(stmt: stmts[i]),
        );
      },
    );
  }
}

// ─── Statement card ───────────────────────────────────────────────────────────

class _TenantStatementCard extends ConsumerStatefulWidget {
  const _TenantStatementCard({required this.stmt});
  final AnnualStatement stmt;

  @override
  ConsumerState<_TenantStatementCard> createState() =>
      _TenantStatementCardState();
}

class _TenantStatementCardState
    extends ConsumerState<_TenantStatementCard> {
  bool _expanded = false;

  static final _dateFmt = DateFormat('dd.MM.yyyy HH:mm');
  static final _currency =
      NumberFormat.currency(locale: 'de_DE', symbol: '€');

  AnnualStatement get stmt => widget.stmt;

  Future<void> _acknowledge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Empfang bestätigen'),
        content: Text(
          'Ich bestätige den Empfang der Jahresabrechnung ${stmt.year}.\n\n'
          'Datum und Uhrzeit werden als rechtssicherer Zustellnachweis '
          '(§ 556 BGB) gespeichert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Bestätigen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final uid = ref.read(currentUserProvider).valueOrNull?.uid ?? '';
    await ref
        .read(annualStatementRepositoryProvider)
        .acknowledge(stmt.id, uid);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empfang bestätigt. Danke!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAcknowledged =
        stmt.status == StatementStatus.acknowledged;
    final cs = Theme.of(context).colorScheme;
    final tenant = ref.watch(tenantProvider).valueOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────
          ListTile(
            leading: CircleAvatar(
              backgroundColor: isAcknowledged
                  ? Colors.green.withValues(alpha: 0.12)
                  : cs.primaryContainer,
              child: Icon(
                isAcknowledged
                    ? Icons.verified_outlined
                    : Icons.description_outlined,
                color: isAcknowledged ? Colors.green : cs.primary,
                size: 20,
              ),
            ),
            title: Text(
              'Jahresabrechnung ${stmt.year}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15),
            ),
            subtitle: Text(
              '${DateFormat('dd.MM.yyyy').format(stmt.periodStart)} – '
              '${DateFormat('dd.MM.yyyy').format(stmt.periodEnd)}',
              style:
                  const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            trailing: IconButton(
              icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () =>
                  setState(() => _expanded = !_expanded),
            ),
          ),

          // ── Saldo-Banner ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _BalanceBanner(stmt: stmt, currency: _currency),
          ),

          // ── SEPA Zahlungsinfo (nur bei Nachzahlung) ───────────────
          if (stmt.balance > 0 && tenant?.bankIban != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _SepaCard(stmt: stmt, tenant: tenant!),
            ),

          // ── Expandable: Positionen ────────────────────────────────
          if (_expanded) ...[
            const Divider(height: 1),
            _PositionsBreakdown(stmt: stmt, currency: _currency),
          ],

          // ── Zustellnachweis ───────────────────────────────────────
          if (isAcknowledged && stmt.acknowledgedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 14, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Bestätigt am ${_dateFmt.format(stmt.acknowledgedAt!)}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Actions ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                if (stmt.pdfUrl.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_outlined,
                        size: 16),
                    label: const Text('PDF öffnen'),
                    onPressed: () => launchUrl(
                      Uri.parse(stmt.pdfUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                if (!isAcknowledged) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check_outlined, size: 16),
                      label: const Text('Empfang bestätigen'),
                      onPressed: _acknowledge,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Balance banner ───────────────────────────────────────────────────────────

class _BalanceBanner extends StatelessWidget {
  const _BalanceBanner(
      {required this.stmt, required this.currency});
  final AnnualStatement stmt;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final isNach = stmt.balance > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isNach
            ? Colors.orange.withValues(alpha: 0.1)
            : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isNach
              ? Colors.orange.shade300
              : Colors.green.shade300,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isNach ? 'Nachzahlung' : 'Rückerstattung',
                style: TextStyle(
                  fontSize: 12,
                  color: isNach
                      ? Colors.orange.shade800
                      : Colors.green.shade800,
                ),
              ),
              Text(
                currency.format(stmt.balance.abs()),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isNach
                      ? Colors.red.shade700
                      : Colors.green.shade700,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Kosten: ${currency.format(stmt.totalTenantCosts)}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey)),
              Text(
                  'Vorausz.: ${currency.format(stmt.advancePayments)}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Positions breakdown ──────────────────────────────────────────────────────

class _PositionsBreakdown extends StatelessWidget {
  const _PositionsBreakdown(
      {required this.stmt, required this.currency});
  final AnnualStatement stmt;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kostenaufschlüsselung',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.3),
          ),
          const SizedBox(height: 8),
          ...stmt.positions.map((p) => _PositionRow(
                position: p,
                currency: currency,
              )),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Gesamt Ihr Anteil',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(currency.format(stmt.totalTenantCosts),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _PositionRow extends StatelessWidget {
  const _PositionRow(
      {required this.position, required this.currency});
  final StatementPosition position;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(position.label,
                    style: const TextStyle(fontSize: 13)),
              ),
              Text(
                currency.format(position.tenantAmount),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'Gesamt: ${currency.format(position.totalCost)}  ·  '
                '${position.tenantPercent.toStringAsFixed(1)} %  ·  '
                '${position.distributionKey.label}',
                style: const TextStyle(
                    fontSize: 10, color: Colors.grey),
              ),
              if (position.receiptImageUrls.isNotEmpty) ...[
                const SizedBox(width: 6),
                _ReceiptImagesChip(
                    urls: position.receiptImageUrls,
                    label: position.label),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Receipt images chip ──────────────────────────────────────────────────────

class _ReceiptImagesChip extends StatelessWidget {
  const _ReceiptImagesChip(
      {required this.urls, required this.label});
  final List<String> urls;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        useSafeArea: true,
        builder: (_) => _ReceiptGallery(label: label, urls: urls),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_outlined,
                size: 10,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 3),
            Text(
              '${urls.length} Beleg(e)',
              style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── SEPA payment card ────────────────────────────────────────────────────────

class _SepaCard extends StatelessWidget {
  const _SepaCard({required this.stmt, required this.tenant});
  final AnnualStatement stmt;
  final Tenant tenant;

  static final _currency =
      NumberFormat.currency(locale: 'de_DE', symbol: '€');

  String get _purpose =>
      'Nachzahlung BK ${stmt.year} ${stmt.unitName}'.replaceAll('\n', ' ');

  String get _ibanFormatted {
    final raw = (tenant.bankIban ?? '').replaceAll(' ', '');
    final buf = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(raw[i]);
    }
    return buf.toString();
  }

  // EPC QR code string per EPC069-12 (Giro-Code / GiroCode)
  String get _epcQr {
    final iban = (tenant.bankIban ?? '').replaceAll(' ', '');
    final bic = tenant.bankBic ?? '';
    final holder = tenant.bankAccountHolder ?? '';
    final amount = stmt.balance.toStringAsFixed(2);
    return 'BCD\n002\n1\nSCT\n$bic\n$holder\n$iban\nEUR$amount\n\n\n$_purpose';
  }

  void _copy(BuildContext context, String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label kopiert'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasQrData = (tenant.bankIban?.isNotEmpty ?? false) &&
        (tenant.bankAccountHolder?.isNotEmpty ?? false);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_outlined, size: 15, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'Bitte überweisen Sie',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: cs.primary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SepaRow(
                      label: 'Empfänger',
                      value: tenant.bankAccountHolder ?? '–',
                      onCopy: () => _copy(
                          context, tenant.bankAccountHolder ?? '', 'Empfänger'),
                    ),
                    const SizedBox(height: 6),
                    _SepaRow(
                      label: 'IBAN',
                      value: _ibanFormatted,
                      onCopy: () => _copy(context,
                          (tenant.bankIban ?? '').replaceAll(' ', ''), 'IBAN'),
                    ),
                    if (tenant.bankBic?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 6),
                      _SepaRow(
                        label: 'BIC',
                        value: tenant.bankBic!,
                        onCopy: () => _copy(context, tenant.bankBic!, 'BIC'),
                      ),
                    ],
                    const SizedBox(height: 6),
                    _SepaRow(
                      label: 'Betrag',
                      value: _currency.format(stmt.balance),
                      onCopy: () => _copy(
                          context,
                          stmt.balance.toStringAsFixed(2).replaceAll('.', ','),
                          'Betrag'),
                    ),
                    const SizedBox(height: 6),
                    _SepaRow(
                      label: 'Verwendungszweck',
                      value: _purpose,
                      onCopy: () => _copy(context, _purpose, 'Verwendungszweck'),
                    ),
                  ],
                ),
              ),
              if (hasQrData) ...[
                const SizedBox(width: 12),
                Column(
                  children: [
                    QrImageView(
                      data: _epcQr,
                      version: QrVersions.auto,
                      size: 90,
                      eyeStyle: QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      dataModuleStyle: QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text('GiroCode',
                        style: TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SepaRow extends StatelessWidget {
  const _SepaRow(
      {required this.label, required this.value, required this.onCopy});
  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ),
        GestureDetector(
          onTap: onCopy,
          child: const Icon(Icons.copy_outlined, size: 13, color: Colors.grey),
        ),
      ],
    );
  }
}

// ─── Receipt gallery ──────────────────────────────────────────────────────────

class _ReceiptGallery extends StatelessWidget {
  const _ReceiptGallery({required this.label, required this.urls});
  final String label;
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Text('Belege: $label',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => launchUrl(Uri.parse(urls[i]),
                  mode: LaunchMode.externalApplication),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  urls[i],
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) =>
                      progress == null
                          ? child
                          : const Center(
                              child: CircularProgressIndicator()),
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      size: 40,
                      color: Colors.grey),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
