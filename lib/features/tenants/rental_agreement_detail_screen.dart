import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/rental_agreement.dart';
import '../../repositories/rental_agreement_repository.dart';
import '../../widgets/app_state_widgets.dart';
import '../../utils/app_exception.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class RentalAgreementDetailScreen extends ConsumerStatefulWidget {
  const RentalAgreementDetailScreen({super.key, required this.agreementId});
  final String agreementId;

  @override
  ConsumerState<RentalAgreementDetailScreen> createState() =>
      _RentalAgreementDetailScreenState();
}

class _RentalAgreementDetailScreenState
    extends ConsumerState<RentalAgreementDetailScreen> {
  bool _isUploading = false;

  Future<void> _uploadContract(RentalAgreement agreement) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final bytes = result.files.single.bytes!;
    final name = result.files.single.name;

    setState(() => _isUploading = true);
    try {
      await ref
          .read(rentalAgreementRepositoryProvider)
          .uploadContract(widget.agreementId, bytes, name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mietvertrag hochgeladen')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _openContract(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showStatusSheet(RentalAgreement agreement) async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => _StatusSheet(
        agreement: agreement,
        onChanged: (newStatus) async {
          await ref
              .read(rentalAgreementRepositoryProvider)
              .updateStatus(agreement.id, newStatus);
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _confirmDelete(RentalAgreement agreement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mietverhältnis löschen?'),
        content: Text(
          'Das Mietverhältnis von ${agreement.tenantName} wird unwiderruflich gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(rentalAgreementRepositoryProvider)
          .delete(agreement.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agreementAsync =
        ref.watch(rentalAgreementByIdProvider(widget.agreementId));

    return agreementAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(body: ErrorState(message: userMessage(e))),
      data: (agreement) {
        if (agreement == null) {
          return const Scaffold(
            body: Center(child: Text('Mietverhältnis nicht gefunden.')),
          );
        }
        return _buildScaffold(context, agreement);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, RentalAgreement agreement) {
    final df = DateFormat('dd.MM.yyyy');
    final nf =
        NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

    return Scaffold(
      appBar: AppBar(
        title: Text(agreement.tenantName),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _confirmDelete(agreement);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title:
                      Text('Löschen', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        children: [
          Center(
            child: AppStatusBadge(
              label: agreement.statusLabel,
              color: agreement.statusColor,
            ),
          ),
          const SizedBox(height: 16),

          // ── Mieter ──────────────────────────────────────────────────
          _DetailCard(title: 'Mieter', children: [
            _InfoRow(
              icon: Icons.person_outlined,
              label: 'Name',
              value: agreement.tenantName,
            ),
            if (agreement.tenantEmail.isNotEmpty)
              _InfoRow(
                icon: Icons.email_outlined,
                label: 'E-Mail',
                value: agreement.tenantEmail,
              ),
          ]),
          const SizedBox(height: 12),

          // ── Wohnung ──────────────────────────────────────────────────
          _DetailCard(title: 'Wohnung', children: [
            _InfoRow(
              icon: Icons.location_city_outlined,
              label: 'Gebäude',
              value: agreement.buildingName,
            ),
            _InfoRow(
              icon: Icons.apartment_outlined,
              label: 'Wohnung',
              value: agreement.unitName,
            ),
          ]),
          const SizedBox(height: 12),

          // ── Mietdaten ────────────────────────────────────────────────
          _DetailCard(title: 'Mietdaten', children: [
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              label: 'Beginn',
              value: df.format(agreement.startDate),
            ),
            _InfoRow(
              icon: Icons.event_outlined,
              label: 'Ende',
              value: agreement.endDate != null
                  ? df.format(agreement.endDate!)
                  : 'Unbefristet',
            ),
            if (agreement.monthlyRent != null)
              _InfoRow(
                icon: Icons.euro_outlined,
                label: 'Kaltmiete',
                value: nf.format(agreement.monthlyRent!),
              ),
            if (agreement.deposit != null)
              _InfoRow(
                icon: Icons.savings_outlined,
                label: 'Kaution',
                value: nf.format(agreement.deposit!),
              ),
          ]),
          const SizedBox(height: 12),

          // ── Nebenkosten ──────────────────────────────────────────────
          if (agreement.hasUtilityCosts)
            _DetailCard(title: 'Nebenkosten', children: [
              if (agreement.monthlyHeatingAdvance != null)
                _InfoRow(
                  icon: Icons.local_fire_department_outlined,
                  label: 'Heizkosten',
                  value:
                      '${nf.format(agreement.monthlyHeatingAdvance!)}/Monat',
                ),
              if (agreement.nebenkostenPositionen.isNotEmpty) ...[
                if (agreement.monthlyHeatingAdvance != null)
                  const SizedBox(height: 4),
                const Text(
                  'Betriebskosten (§2 BetrKV)',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey),
                ),
                const SizedBox(height: 6),
                ...agreement.nebenkostenPositionen.map((p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.circle,
                              size: 6, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(p.bezeichnung,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Text(
                            '${nf.format(p.monatlicheVorauszahlung)}/Monat',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              p.umlageschluesselLabel,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
              if (agreement.nebenkostenPositionen.isNotEmpty) ...[
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Betriebskosten gesamt',
                        style: TextStyle(fontSize: 13)),
                    Text(
                      '${nf.format(agreement.monthlyUtilityTotal)}/Monat',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Warmmiete',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    '${nf.format(agreement.monthlyWarmRent)}/Monat',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ]),
          if (agreement.hasUtilityCosts) const SizedBox(height: 12),

          // ── Mietvertrag ──────────────────────────────────────────────
          _DetailCard(title: 'Mietvertrag', children: [
            if (agreement.hasContract) ...[
              _InfoRow(
                icon: Icons.picture_as_pdf,
                label: 'Datei',
                value: agreement.contractFileName ?? 'Mietvertrag.pdf',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new_outlined),
                      label: const Text('Öffnen'),
                      onPressed: () =>
                          _openContract(agreement.contractUrl!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: _isUploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: const Text('Ersetzen'),
                      onPressed: _isUploading
                          ? null
                          : () => _uploadContract(agreement),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Icon(Icons.attach_file_outlined,
                      color: Colors.grey.shade400, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Kein Mietvertrag hinterlegt',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _isUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_outlined),
                  label: const Text('Mietvertrag hochladen'),
                  onPressed: _isUploading
                      ? null
                      : () => _uploadContract(agreement),
                ),
              ),
            ],
          ]),

          if (agreement.notes != null && agreement.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DetailCard(title: 'Notizen', children: [
              Text(agreement.notes!, style: const TextStyle(fontSize: 14)),
            ]),
          ],

          const SizedBox(height: 24),

          // ── Status-Aktionen ──────────────────────────────────────────
          FilledButton.icon(
            icon: const Icon(Icons.tune_outlined),
            label: const Text('Status ändern'),
            onPressed: () => _showStatusSheet(agreement),
            style: FilledButton.styleFrom(
              backgroundColor:
                  Theme.of(context).colorScheme.secondaryContainer,
              foregroundColor:
                  Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status sheet ─────────────────────────────────────────────────────────────

class _StatusSheet extends StatelessWidget {
  const _StatusSheet({required this.agreement, required this.onChanged});
  final RentalAgreement agreement;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status ändern',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _statusOption(context, 'active', 'Aktiv', Colors.green),
            _statusOption(context, 'notice_given',
                'Kündigung eingegangen', Colors.orange),
            _statusOption(context, 'ended', 'Beendet', Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _statusOption(
      BuildContext context, String value, String label, Color color) {
    final isActive = agreement.status == value;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(label),
      trailing: isActive
          ? const Icon(Icons.check, color: Colors.green)
          : null,
      onTap: isActive ? null : () => onChanged(value),
    );
  }
}

// ─── Helper widgets ───────────────────────────────────────────────────────────

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
