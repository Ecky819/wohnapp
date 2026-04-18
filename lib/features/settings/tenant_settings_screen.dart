import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tenant.dart';
import '../../repositories/tenant_repository.dart';
import '../../user_provider.dart';

class TenantSettingsScreen extends ConsumerStatefulWidget {
  const TenantSettingsScreen({super.key});

  @override
  ConsumerState<TenantSettingsScreen> createState() =>
      _TenantSettingsScreenState();
}

class _TenantSettingsScreenState extends ConsumerState<TenantSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;

  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _colorCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _initFrom(Tenant tenant) {
    if (_initialized) return;
    _nameCtrl = TextEditingController(text: tenant.name);
    _colorCtrl = TextEditingController(
        text: tenant.primaryColorHex?.replaceAll('#', '') ?? '');
    _emailCtrl = TextEditingController(text: tenant.contactEmail ?? '');
    _phoneCtrl = TextEditingController(text: tenant.contactPhone ?? '');
    _addressCtrl = TextEditingController(text: tenant.address ?? '');
    _initialized = true;
  }

  void _initEmpty(String tenantId) {
    if (_initialized) return;
    _nameCtrl = TextEditingController(text: tenantId);
    _colorCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _initialized = true;
  }

  Future<void> _save(String tenantId) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final colorRaw = _colorCtrl.text.trim();
    final colorHex =
        colorRaw.isNotEmpty ? '#${colorRaw.replaceAll('#', '')}' : null;

    final tenant = Tenant(
      id: tenantId,
      name: _nameCtrl.text.trim(),
      primaryColorHex: colorHex,
      contactEmail:
          _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      contactPhone:
          _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      address:
          _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
    );

    try {
      await ref.read(tenantRepositoryProvider).upsertTenant(tenant);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Einstellungen gespeichert')),
        );
      }
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
    final user = ref.watch(currentUserProvider).valueOrNull;
    final tenantId = user?.tenantId ?? '';
    final tenantAsync = ref.watch(tenantProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mandanten-Einstellungen')),
      body: tenantAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (tenant) {
          if (tenant != null) {
            _initFrom(tenant);
          } else {
            _initEmpty(tenantId);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Branding preview ─────────────────────────────
                  _BrandingPreview(
                    name: _nameCtrl.text,
                    colorHex: _colorCtrl.text,
                  ),

                  const SizedBox(height: 24),
                  _sectionTitle('Branding'),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Unternehmensname',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Pflichtfeld' : null,
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _colorCtrl,
                    decoration: InputDecoration(
                      labelText: 'Primärfarbe (Hex, z.B. 6366F1)',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.palette_outlined),
                      suffixIcon: _colorCtrl.text.length == 6
                          ? Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Color(int.tryParse(
                                        'FF${_colorCtrl.text}',
                                        radix: 16) ??
                                    0xFF6366F1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            )
                          : null,
                    ),
                    maxLength: 6,
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      if (v.length != 6) return '6 Hex-Zeichen erforderlich';
                      if (int.tryParse('FF$v', radix: 16) == null) {
                        return 'Ungültiger Hex-Wert';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),
                  _sectionTitle('Kontaktdaten'),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'E-Mail',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Telefon',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Adresse',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    maxLines: 2,
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: _saving
                        ? const Center(child: CircularProgressIndicator())
                        : FilledButton.icon(
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Speichern'),
                            onPressed: () => _save(tenantId),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
            letterSpacing: 0.4),
      );
}

// ─── Live Branding-Vorschau ────────────────────────────────────────────────────

class _BrandingPreview extends StatelessWidget {
  const _BrandingPreview({required this.name, required this.colorHex});
  final String name;
  final String colorHex;

  @override
  Widget build(BuildContext context) {
    final color = colorHex.length == 6
        ? Color(int.tryParse('FF$colorHex', radix: 16) ?? 0xFF6366F1)
        : const Color(0xFF6366F1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name.isNotEmpty ? name : 'Unternehmensname',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(Icons.preview_outlined, color: Colors.white70, size: 16),
          const SizedBox(width: 4),
          const Text('Vorschau',
              style: TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}
