import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/invoice.dart';
import '../../repositories/invoice_repository.dart';
import '../../services/invoice_ai_service.dart';

class InvoiceDetailScreen extends ConsumerStatefulWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  ConsumerState<InvoiceDetailScreen> createState() =>
      _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  bool _processing = false;
  bool _analyzing = false;
  InvoiceAnalysis? _aiAnalysis;

  Future<void> _runAiAnalysis(Invoice invoice) async {
    setState(() => _analyzing = true);
    final analysis = await InvoiceAiService.instance.analyzeInvoice(
      ticketTitle: invoice.ticketTitle,
      ticketCategory: 'damage', // Ticket-Kategorie nicht im Invoice gespeichert → Fallback
      tradeCategory: 'general',
      contractorName: invoice.contractorName,
      amount: invoice.amount,
      positions: invoice.positions
          .map((p) => {'description': p.description, 'amount': p.amount})
          .toList(),
    );
    if (mounted) {
      setState(() {
        _aiAnalysis = analysis;
        _analyzing = false;
      });
      if (analysis == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('KI-Prüfung fehlgeschlagen – bitte erneut versuchen.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _approve(Invoice invoice) async {
    setState(() => _processing = true);
    try {
      await ref.read(invoiceRepositoryProvider).approveInvoice(invoice.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rechnung freigegeben')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _reject(Invoice invoice) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Rechnung ablehnen'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Ablehnungsgrund',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Ablehnen'),
            ),
          ],
        );
      },
    );
    if (reason == null || reason.isEmpty) return;

    setState(() => _processing = true);
    try {
      await ref
          .read(invoiceRepositoryProvider)
          .rejectInvoice(invoice.id, reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rechnung abgelehnt')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rechnung prüfen')),
      body: _InvoiceDetailBody(
        invoiceId: widget.invoiceId,
        onApprove: _approve,
        onReject: _reject,
        onAnalyze: _runAiAnalysis,
        processing: _processing,
        analyzing: _analyzing,
        aiAnalysis: _aiAnalysis,
      ),
    );
  }
}

class _InvoiceDetailBody extends ConsumerWidget {
  const _InvoiceDetailBody({
    required this.invoiceId,
    required this.onApprove,
    required this.onReject,
    required this.onAnalyze,
    required this.processing,
    required this.analyzing,
    this.aiAnalysis,
  });

  final String invoiceId;
  final Future<void> Function(Invoice) onApprove;
  final Future<void> Function(Invoice) onReject;
  final Future<void> Function(Invoice) onAnalyze;
  final bool processing;
  final bool analyzing;
  final InvoiceAnalysis? aiAnalysis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(_invoiceByIdProvider(invoiceId));

    return invoiceAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (invoice) {
        if (invoice == null) {
          return const Center(child: Text('Rechnung nicht gefunden.'));
        }
        return _InvoiceContent(
          invoice: invoice,
          onApprove: onApprove,
          onReject: onReject,
          onAnalyze: onAnalyze,
          processing: processing,
          analyzing: analyzing,
          aiAnalysis: aiAnalysis,
        );
      },
    );
  }
}

class _InvoiceContent extends StatelessWidget {
  const _InvoiceContent({
    required this.invoice,
    required this.onApprove,
    required this.onReject,
    required this.onAnalyze,
    required this.processing,
    required this.analyzing,
    this.aiAnalysis,
  });

  final Invoice invoice;
  final Future<void> Function(Invoice) onApprove;
  final Future<void> Function(Invoice) onReject;
  final Future<void> Function(Invoice) onAnalyze;
  final bool processing;
  final bool analyzing;
  final InvoiceAnalysis? aiAnalysis;

  Color _statusColor(InvoiceStatus s) {
    switch (s) {
      case InvoiceStatus.approved:
        return Colors.green;
      case InvoiceStatus.rejected:
        return Colors.red;
      case InvoiceStatus.exported:
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.yyyy – HH:mm');
    final currency = NumberFormat.currency(locale: 'de_DE', symbol: '€');
    final isPending = invoice.status == InvoiceStatus.pending;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status badge ───────────────────────────────────────────
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    _statusColor(invoice.status).withValues(alpha: 0.18),
                    Theme.of(context).colorScheme.surface,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  invoice.status.label,
                  style: TextStyle(
                    color: _statusColor(invoice.status),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Meta info ──────────────────────────────────────────────
          _Row(label: 'Ticket', value: invoice.ticketTitle),
          _Row(label: 'Handwerker', value: invoice.contractorName),
          _Row(
            label: 'Eingereicht',
            value: invoice.createdAt != null
                ? fmt.format(invoice.createdAt!)
                : '–',
          ),
          if (invoice.approvedAt != null)
            _Row(
              label: 'Freigegeben',
              value: fmt.format(invoice.approvedAt!),
            ),
          if (invoice.rejectionReason != null)
            _Row(
              label: 'Ablehnungsgrund',
              value: invoice.rejectionReason!,
            ),

          const Divider(height: 32),

          // ── Amount ────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Betrag',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 16)),
              Text(
                invoice.amount > 0
                    ? currency.format(invoice.amount)
                    : 'Kein Betrag angegeben',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ],
          ),

          // ── Positions ─────────────────────────────────────────────
          if (invoice.positions.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Positionen',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            ...invoice.positions.map(
              (p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(p.description,
                            style: const TextStyle(fontSize: 13))),
                    Text(currency.format(p.amount),
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],

          // ── PDF ───────────────────────────────────────────────────
          if (invoice.pdfUrl != null) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('PDF öffnen'),
              onPressed: () async {
                final uri = Uri.parse(invoice.pdfUrl!);
                if (await canLaunchUrl(uri)) launchUrl(uri);
              },
            ),
          ],

          // ── KI-Prüfung ────────────────────────────────────────────
          if (isPending) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            if (aiAnalysis != null)
              _AiAnalysisCard(analysis: aiAnalysis!)
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: analyzing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.psychology_outlined, size: 18),
                  label: Text(analyzing ? 'Wird geprüft …' : 'KI-Prüfung starten'),
                  onPressed: analyzing ? null : () => onAnalyze(invoice),
                ),
              ),
          ],

          // ── Action buttons (only when pending) ────────────────────
          if (isPending) ...[
            const SizedBox(height: 16),
            processing
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text('Ablehnen',
                              style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                          ),
                          onPressed: () => onReject(invoice),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('Freigeben'),
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.green),
                          onPressed: () => onApprove(invoice),
                        ),
                      ),
                    ],
                  ),
          ],
        ],
      ),
    );
  }
}

// ─── KI-Analyse Ergebniskarte ─────────────────────────────────────────────────

class _AiAnalysisCard extends StatelessWidget {
  const _AiAnalysisCard({required this.analysis});
  final InvoiceAnalysis analysis;

  Color get _verdictColor {
    switch (analysis.verdict) {
      case InvoiceVerdict.ok:
        return Colors.green;
      case InvoiceVerdict.suspicious:
        return Colors.orange;
      case InvoiceVerdict.overpriced:
        return Colors.red;
    }
  }

  IconData get _verdictIcon {
    switch (analysis.verdict) {
      case InvoiceVerdict.ok:
        return Icons.check_circle_outline;
      case InvoiceVerdict.suspicious:
        return Icons.warning_amber_outlined;
      case InvoiceVerdict.overpriced:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _verdictColor;
    final currency = NumberFormat.currency(locale: 'de_DE', symbol: '€');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            color.withValues(alpha: 0.08),
            Theme.of(context).colorScheme.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.psychology_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              const Text('KI-Rechnungsprüfung',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const Spacer(),
              Text(
                '${(analysis.confidence * 100).round()} % Konfidenz',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Verdict chip + reasoning
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_verdictIcon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      analysis.verdict.label,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: color,
                          fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(analysis.reasoning,
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),

          // Suggested price range
          if (analysis.suggestedMax > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.euro_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Plausible Spanne: ${currency.format(analysis.suggestedMin)} – ${currency.format(analysis.suggestedMax)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],

          // Flags
          if (analysis.flags.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...analysis.flags.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.arrow_right, size: 16, color: color),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(f,
                          style: TextStyle(fontSize: 12, color: color)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─── Provider: load single invoice by ID ──────────────────────────────────────

final _invoiceByIdProvider =
    StreamProvider.family<Invoice?, String>((ref, invoiceId) {
  return FirebaseInvoiceStream.watchById(invoiceId);
});

// Thin wrapper so we don't need a full repository method for a single doc
class FirebaseInvoiceStream {
  static Stream<Invoice?> watchById(String invoiceId) {
    return FirebaseFirestore.instance
        .collection('invoices')
        .doc(invoiceId)
        .snapshots()
        .map((snap) => snap.exists ? Invoice.fromFirestore(snap) : null);
  }
}
