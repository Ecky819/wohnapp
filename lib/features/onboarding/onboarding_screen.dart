import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/tenant.dart';
import '../../repositories/building_repository.dart';
import '../../repositories/tenant_repository.dart';
import '../../router.dart';
import '../../user_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;
  bool _saving = false;

  // Step 1 — Mandant
  final _orgNameCtrl = TextEditingController();
  final _orgEmailCtrl = TextEditingController();
  final _orgAddressCtrl = TextEditingController();
  final _orgColorCtrl = TextEditingController(text: '6366F1');
  final _step1Key = GlobalKey<FormState>();

  // Step 2 — Gebäude + Wohnung
  final _buildingNameCtrl = TextEditingController();
  final _buildingAddressCtrl = TextEditingController();
  final _unitNameCtrl = TextEditingController(text: 'Wohnung 1');
  final _step2Key = GlobalKey<FormState>();

  @override
  void dispose() {
    _pageCtrl.dispose();
    _orgNameCtrl.dispose();
    _orgEmailCtrl.dispose();
    _orgAddressCtrl.dispose();
    _orgColorCtrl.dispose();
    _buildingNameCtrl.dispose();
    _buildingAddressCtrl.dispose();
    _unitNameCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 0 && !(_step1Key.currentState?.validate() ?? false)) return;
    if (_page == 1 && !(_step2Key.currentState?.validate() ?? false)) return;
    if (_page < 2) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      if (user == null) return;
      final tenantId = user.tenantId;

      final colorRaw = _orgColorCtrl.text.trim();
      final colorHex =
          colorRaw.length == 6 ? '#$colorRaw' : null;

      // 1. Create tenant doc
      await ref.read(tenantRepositoryProvider).upsertTenant(
            Tenant(
              id: tenantId,
              name: _orgNameCtrl.text.trim(),
              primaryColorHex: colorHex,
              contactEmail: _orgEmailCtrl.text.trim().isEmpty
                  ? null
                  : _orgEmailCtrl.text.trim(),
              address: _orgAddressCtrl.text.trim().isEmpty
                  ? null
                  : _orgAddressCtrl.text.trim(),
            ),
          );

      // 2. Create first building + unit
      final buildingId = await ref
          .read(buildingRepositoryProvider)
          .createBuilding(
            name: _buildingNameCtrl.text.trim(),
            address: _buildingAddressCtrl.text.trim(),
            tenantId: tenantId,
          );

      await ref.read(buildingRepositoryProvider).createUnit(
            buildingId: buildingId,
            name: _unitNameCtrl.text.trim(),
            tenantId: tenantId,
          );

      if (mounted) context.go(AppRoutes.manager);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Progress bar ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: List.generate(3, (i) {
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 4,
                      margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                      decoration: BoxDecoration(
                        color: i <= _page
                            ? cs.primary
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Schritt ${_page + 1} von 3',
                  style: TextStyle(fontSize: 11, color: cs.outline),
                ),
              ),
            ),

            // ── Pages ──────────────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  _Step1(
                    formKey: _step1Key,
                    nameCtrl: _orgNameCtrl,
                    emailCtrl: _orgEmailCtrl,
                    addressCtrl: _orgAddressCtrl,
                    colorCtrl: _orgColorCtrl,
                  ),
                  _Step2(
                    formKey: _step2Key,
                    buildingNameCtrl: _buildingNameCtrl,
                    buildingAddressCtrl: _buildingAddressCtrl,
                    unitNameCtrl: _unitNameCtrl,
                  ),
                  _Step3(orgName: _orgNameCtrl.text),
                ],
              ),
            ),

            // ── Navigation buttons ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  if (_page > 0)
                    TextButton(
                      onPressed: () => _pageCtrl.previousPage(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                      ),
                      child: const Text('Zurück'),
                    ),
                  const Spacer(),
                  _saving
                      ? const CircularProgressIndicator()
                      : FilledButton.icon(
                          icon: Icon(
                            _page < 2 ? Icons.arrow_forward : Icons.check,
                          ),
                          label: Text(_page < 2 ? 'Weiter' : 'Los geht\'s!'),
                          onPressed: _page < 2 ? _next : _finish,
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step 1: Mandant einrichten ───────────────────────────────────────────────

class _Step1 extends StatefulWidget {
  const _Step1({
    required this.formKey,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.addressCtrl,
    required this.colorCtrl,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController addressCtrl;
  final TextEditingController colorCtrl;

  @override
  State<_Step1> createState() => _Step1State();
}

class _Step1State extends State<_Step1> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Form(
        key: widget.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.business_outlined, size: 40, color: Colors.indigo),
            const SizedBox(height: 12),
            const Text(
              'Willkommen bei Wohnapp!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Richten Sie zuerst Ihr Unternehmen ein.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: widget.nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Unternehmensname *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business_outlined),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: widget.emailCtrl,
              decoration: const InputDecoration(
                labelText: 'E-Mail (Kontakt)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: widget.addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Adresse',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: widget.colorCtrl,
              decoration: InputDecoration(
                labelText: 'Primärfarbe (Hex)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.palette_outlined),
                suffixIcon: widget.colorCtrl.text.length == 6
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: Color(int.tryParse(
                                  'FF${widget.colorCtrl.text}',
                                  radix: 16) ??
                              0xFF6366F1),
                        ),
                      )
                    : null,
              ),
              maxLength: 6,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step 2: Erstes Gebäude + Wohnung ─────────────────────────────────────────

class _Step2 extends StatelessWidget {
  const _Step2({
    required this.formKey,
    required this.buildingNameCtrl,
    required this.buildingAddressCtrl,
    required this.unitNameCtrl,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController buildingNameCtrl;
  final TextEditingController buildingAddressCtrl;
  final TextEditingController unitNameCtrl;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.apartment_outlined, size: 40, color: Colors.indigo),
            const SizedBox(height: 12),
            const Text(
              'Erstes Gebäude',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Legen Sie Ihr erstes Objekt an. Weitere können Sie jederzeit hinzufügen.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: buildingNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Gebäudename *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.home_work_outlined),
                hintText: 'z.B. Musterstraße 1',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: buildingAddressCtrl,
              decoration: const InputDecoration(
                labelText: 'Adresse *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              maxLines: 2,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              'Erste Wohnung',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: unitNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Wohnungsbezeichnung *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.door_front_door_outlined),
                hintText: 'z.B. Wohnung 1 oder EG links',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step 3: Fertig ───────────────────────────────────────────────────────────

class _Step3 extends StatelessWidget {
  const _Step3({required this.orgName});
  final String orgName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline,
                size: 64, color: Colors.green),
          ),
          const SizedBox(height: 24),
          Text(
            orgName.isNotEmpty ? 'Alles bereit, $orgName!' : 'Alles bereit!',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Ihr Mandant, das erste Gebäude und die erste Wohnung wurden angelegt.\n\n'
            'Sie können jetzt Mieter einladen, Tickets anlegen und Abrechnungen versenden.',
            style: TextStyle(color: Colors.grey, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const _CheckRow(text: 'Gebäude & Wohnung angelegt'),
          const _CheckRow(text: 'Mandanten-Profil erstellt'),
          const _CheckRow(text: 'Mieter einladen über Einladungen'),
          const _CheckRow(text: 'Bulk-Import für viele Wohnungen'),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
