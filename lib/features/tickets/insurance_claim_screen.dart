import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/insurance_claim.dart';
import '../../models/ticket.dart';
import '../../repositories/activity_repository.dart';
import '../../repositories/ticket_repository.dart';
import '../../ticket_provider.dart';
import '../../widgets/app_state_widgets.dart';

class InsuranceClaimScreen extends ConsumerWidget {
  const InsuranceClaimScreen({super.key, required this.ticketId});
  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketAsync = ref.watch(ticketDetailProvider(ticketId));

    return Scaffold(
      appBar: AppBar(title: const Text('Versicherungsfall')),
      body: ticketAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(message: e.toString()),
        data: (ticket) {
          final claim =
              ticket.insuranceClaim ??
              const InsuranceClaim(
                status: ClaimStatus.reported,
                insurerName: '',
              );
          return _ClaimBody(ticket: ticket, claim: claim);
        },
      ),
    );
  }
}

// ─── Body ─────────────────────────────────────────────────────────────────────

class _ClaimBody extends ConsumerStatefulWidget {
  const _ClaimBody({required this.ticket, required this.claim});
  final Ticket ticket;
  final InsuranceClaim claim;

  @override
  ConsumerState<_ClaimBody> createState() => _ClaimBodyState();
}

class _ClaimBodyState extends ConsumerState<_ClaimBody> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  late final TextEditingController _insurerCtrl;
  late final TextEditingController _policyCtrl;
  late final TextEditingController _claimNumberCtrl;
  late final TextEditingController _deductibleCtrl;
  late final TextEditingController _estimatedCtrl;
  late final TextEditingController _approvedCtrl;
  late final TextEditingController _expertCtrl;
  late final TextEditingController _expertUrlCtrl;
  late final TextEditingController _notesCtrl;

  late ClaimStatus _status;
  DateTime? _reportedAt;
  DateTime? _settledAt;

  static final _dateFmt = DateFormat('dd.MM.yyyy');
  static final _eurFmt = NumberFormat('#,##0.00', 'de_DE');

  @override
  void initState() {
    super.initState();
    final c = widget.claim;
    _status = c.status;
    _reportedAt = c.reportedAt;
    _settledAt = c.settledAt;
    _insurerCtrl = TextEditingController(text: c.insurerName);
    _policyCtrl = TextEditingController(text: c.policyNumber ?? '');
    _claimNumberCtrl = TextEditingController(text: c.claimNumber ?? '');
    _deductibleCtrl = TextEditingController(
      text: c.deductibleAmount != null
          ? _eurFmt.format(c.deductibleAmount)
          : '',
    );
    _estimatedCtrl = TextEditingController(
      text: c.estimatedDamage != null ? _eurFmt.format(c.estimatedDamage) : '',
    );
    _approvedCtrl = TextEditingController(
      text: c.approvedAmount != null ? _eurFmt.format(c.approvedAmount) : '',
    );
    _expertCtrl = TextEditingController(text: c.expertName ?? '');
    _expertUrlCtrl = TextEditingController(text: c.expertReportUrl ?? '');
    _notesCtrl = TextEditingController(text: c.notes ?? '');
  }

  @override
  void dispose() {
    _insurerCtrl.dispose();
    _policyCtrl.dispose();
    _claimNumberCtrl.dispose();
    _deductibleCtrl.dispose();
    _estimatedCtrl.dispose();
    _approvedCtrl.dispose();
    _expertCtrl.dispose();
    _expertUrlCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double? _parseAmount(String text) {
    if (text.trim().isEmpty) return null;
    final clean = text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(clean);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final updated = widget.claim.copyWith(
        status: _status,
        insurerName: _insurerCtrl.text.trim(),
        policyNumber: _policyCtrl.text.trim().isEmpty
            ? null
            : _policyCtrl.text.trim(),
        claimNumber: _claimNumberCtrl.text.trim().isEmpty
            ? null
            : _claimNumberCtrl.text.trim(),
        deductibleAmount: _parseAmount(_deductibleCtrl.text),
        estimatedDamage: _parseAmount(_estimatedCtrl.text),
        approvedAmount: _parseAmount(_approvedCtrl.text),
        reportedAt: _reportedAt,
        settledAt: _settledAt,
        expertName: _expertCtrl.text.trim().isEmpty
            ? null
            : _expertCtrl.text.trim(),
        expertReportUrl: _expertUrlCtrl.text.trim().isEmpty
            ? null
            : _expertUrlCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      await ref
          .read(ticketRepositoryProvider)
          .updateInsuranceClaim(
            widget.ticket.id,
            updated,
            activityRepo: ref.read(activityRepositoryProvider),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Versicherungsfall gespeichert')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _advanceStatus(ClaimStatus next) async {
    setState(() => _status = next);
    if (next == ClaimStatus.settled) {
      _settledAt ??= DateTime.now();
    }
  }

  Future<void> _pickDate({required bool isReported}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isReported ? _reportedAt : _settledAt) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isReported) {
        _reportedAt = picked;
      } else {
        _settledAt = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status-Stepper ───────────────────────────────────────────
          _StatusStepper(
            current: _status,
            onAdvance: _status.isTerminal ? null : _advanceStatus,
          ),

          const SizedBox(height: 24),

          // ── Versicherungsdaten ───────────────────────────────────────
          _sectionTitle('Versicherung'),
          const SizedBox(height: 12),

          TextFormField(
            controller: _insurerCtrl,
            decoration: const InputDecoration(
              labelText: 'Versicherungsgesellschaft *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.business_outlined),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _policyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Policennummer',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.tag_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _claimNumberCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Schadennummer',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          _DateField(
            label: 'Schadensmeldung',
            date: _reportedAt,
            onTap: () => _pickDate(isReported: true),
          ),

          const SizedBox(height: 24),

          // ── Beträge ──────────────────────────────────────────────────
          _sectionTitle('Beträge'),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _AmountField(
                  controller: _deductibleCtrl,
                  label: 'Selbstbeteiligung (€)',
                  icon: Icons.remove_circle_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AmountField(
                  controller: _estimatedCtrl,
                  label: 'Geschätzter Schaden (€)',
                  icon: Icons.calculate_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          _AmountField(
            controller: _approvedCtrl,
            label: 'Genehmigter Betrag (€)',
            icon: Icons.euro_outlined,
            enabled:
                _status == ClaimStatus.approved ||
                _status == ClaimStatus.settled,
          ),

          const SizedBox(height: 24),

          // ── Gutachter ─────────────────────────────────────────────────
          _sectionTitle('Gutachter'),
          const SizedBox(height: 12),

          TextFormField(
            controller: _expertCtrl,
            decoration: const InputDecoration(
              labelText: 'Name des Gutachters',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_search_outlined),
            ),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _expertUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'Link zum Gutachten (URL)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link_outlined),
            ),
            keyboardType: TextInputType.url,
          ),

          if (_status == ClaimStatus.settled ||
              _status == ClaimStatus.approved) ...[
            const SizedBox(height: 12),
            _DateField(
              label: 'Reguliert am',
              date: _settledAt,
              onTap: () => _pickDate(isReported: false),
            ),
          ],

          const SizedBox(height: 24),

          // ── Notizen ───────────────────────────────────────────────────
          _sectionTitle('Interne Notizen'),
          const SizedBox(height: 12),

          TextFormField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Kommunikation, Vereinbarungen, Besonderheiten …',
            ),
            maxLines: 4,
          ),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: _saving
                ? const Center(child: CircularProgressIndicator())
                : FilledButton.icon(
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Speichern'),
                    onPressed: _save,
                  ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 14,
      letterSpacing: 0.4,
    ),
  );
}

// ─── Status-Stepper ───────────────────────────────────────────────────────────

class _StatusStepper extends StatelessWidget {
  const _StatusStepper({required this.current, this.onAdvance});
  final ClaimStatus current;
  final void Function(ClaimStatus)? onAdvance;

  static const _flow = [
    ClaimStatus.reported,
    ClaimStatus.underReview,
    ClaimStatus.approved,
    ClaimStatus.settled,
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRejected = current == ClaimStatus.rejected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(current.icon, color: current.color, size: 20),
                const SizedBox(width: 8),
                Text(
                  current.label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: current.color,
                  ),
                ),
                if (isRejected) ...[
                  const SizedBox(width: 8),
                  const Chip(
                    label: Text(
                      'Abgelehnt',
                      style: TextStyle(fontSize: 11, color: Colors.white),
                    ),
                    backgroundColor: Colors.red,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),

            if (!isRejected) ...[
              const SizedBox(height: 12),
              // Progress bar
              Row(
                children: _flow.map((s) {
                  final idx = _flow.indexOf(s);
                  final curIdx = _flow.indexOf(
                    _flow.contains(current) ? current : ClaimStatus.reported,
                  );
                  final done = idx <= curIdx;
                  return Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 4,
                            color: done
                                ? colorScheme.primary
                                : Colors.grey.shade300,
                          ),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: done
                                ? colorScheme.primary
                                : Colors.grey.shade300,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 4),
              Row(
                children: _flow
                    .map(
                      (s) => Expanded(
                        child: Text(
                          s.label,
                          style: TextStyle(
                            fontSize: 9,
                            color: s == current
                                ? colorScheme.primary
                                : Colors.grey,
                            fontWeight: s == current
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],

            if (onAdvance != null && current.nextStatuses.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: current.nextStatuses.map((next) {
                  return OutlinedButton.icon(
                    icon: Icon(next.icon, size: 16, color: next.color),
                    label: Text(
                      next == ClaimStatus.rejected
                          ? 'Als abgelehnt markieren'
                          : 'Weiter: ${next.label}',
                      style: TextStyle(color: next.color, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: next.color),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => onAdvance!(next),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
  });
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  static final _fmt = DateFormat('dd.MM.yyyy');

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: Text(
          date != null ? _fmt.format(date!) : 'Datum wählen',
          style: TextStyle(color: date != null ? null : Colors.grey),
        ),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.label,
    required this.icon,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
  }
}
