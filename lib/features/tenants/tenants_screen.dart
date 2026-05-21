import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/rental_agreement.dart';
import '../../repositories/rental_agreement_repository.dart';
import '../../router.dart';
import '../../services/onboarding_service.dart';
import '../../widgets/app_state_widgets.dart';
import '../../widgets/onboarding_tooltip.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────

class TenantsScreen extends ConsumerWidget {
  const TenantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agreementsAsync = ref.watch(rentalAgreementsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mietverhältnisse')),
      floatingActionButton: OnboardingTooltip(
        hintKey: OnboardingKeys.tenantsCreateFab,
        message: 'Lege hier dein erstes Mietverhältnis an',
        child: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('Neu anlegen'),
          onPressed: () => context
              .push(AppRoutes.createRentalAgreement)
              .then((created) {
            if (created == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mietverhältnis angelegt')),
              );
            }
          }),
        ),
      ),
      body: agreementsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(message: e.toString()),
        data: (agreements) {
          if (agreements.isEmpty) {
            return const EmptyState(
              icon: Icons.description_outlined,
              title: 'Keine Mietverhältnisse',
              subtitle:
                  'Tippe auf „Neu anlegen" um einen Mietvertrag einzupflegen.',
            );
          }

          final active =
              agreements.where((a) => a.status == 'active').toList();
          final notice =
              agreements.where((a) => a.status == 'notice_given').toList();
          final ended =
              agreements.where((a) => a.status == 'ended').toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
            children: [
              if (active.isNotEmpty) ...[
                _SectionHeader(
                    label: 'Aktiv',
                    count: active.length,
                    color: Colors.green),
                ...active.map((a) => _AgreementTile(agreement: a)),
              ],
              if (notice.isNotEmpty) ...[
                _SectionHeader(
                    label: 'Kündigung',
                    count: notice.length,
                    color: Colors.orange),
                ...notice.map((a) => _AgreementTile(agreement: a)),
              ],
              if (ended.isNotEmpty) ...[
                _SectionHeader(
                    label: 'Beendet',
                    count: ended.length,
                    color: Colors.grey),
                ...ended.map((a) => _AgreementTile(agreement: a)),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Agreement tile ───────────────────────────────────────────────────────────

class _AgreementTile extends StatelessWidget {
  const _AgreementTile({required this.agreement});
  final RentalAgreement agreement;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy');
    final dateRange = agreement.endDate != null
        ? '${df.format(agreement.startDate)} – ${df.format(agreement.endDate!)}'
        : 'ab ${df.format(agreement.startDate)}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            agreement.tenantName.isNotEmpty
                ? agreement.tenantName[0].toUpperCase()
                : '?',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          agreement.tenantName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Row(
              children: [
                const Icon(Icons.location_city_outlined,
                    size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${agreement.buildingName} · ${agreement.unitName}',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(dateRange,
                style:
                    const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AppStatusBadge(
              label: agreement.statusLabel,
              color: agreement.statusColor,
            ),
            const SizedBox(height: 4),
            Icon(
              Icons.attach_file,
              size: 14,
              color:
                  agreement.hasContract ? Colors.green : Colors.grey.shade400,
            ),
          ],
        ),
        onTap: () => context
            .push(AppRoutes.rentalAgreementDetailPath(agreement.id)),
      ),
    );
  }
}
