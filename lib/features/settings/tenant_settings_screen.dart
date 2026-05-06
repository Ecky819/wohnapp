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
  late final TextEditingController _holderCtrl;
  late final TextEditingController _ibanCtrl;
  late final TextEditingController _bicCtrl;
  late final TextEditingController _webhookUrlCtrl;
  late final TextEditingController _webhookSecretCtrl;
  late final TextEditingController _datevConsultantCtrl;
  late final TextEditingController _datevClientCtrl;

  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _colorCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _holderCtrl.dispose();
    _ibanCtrl.dispose();
    _bicCtrl.dispose();
    _webhookUrlCtrl.dispose();
    _webhookSecretCtrl.dispose();
    _datevConsultantCtrl.dispose();
    _datevClientCtrl.dispose();
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
    _holderCtrl = TextEditingController(text: tenant.bankAccountHolder ?? '');
    _ibanCtrl = TextEditingController(text: tenant.bankIban ?? '');
    _bicCtrl = TextEditingController(text: tenant.bankBic ?? '');
    _webhookUrlCtrl = TextEditingController(text: tenant.erpWebhookUrl ?? '');
    _webhookSecretCtrl = TextEditingController(text: tenant.erpWebhookSecret ?? '');
    _datevConsultantCtrl = TextEditingController(text: tenant.datevConsultantNumber ?? '');
    _datevClientCtrl = TextEditingController(text: tenant.datevClientNumber ?? '');
    _initialized = true;
  }

  void _initEmpty(String tenantId) {
    if (_initialized) return;
    _nameCtrl = TextEditingController(text: tenantId);
    _colorCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _holderCtrl = TextEditingController();
    _ibanCtrl = TextEditingController();
    _bicCtrl = TextEditingController();
    _webhookUrlCtrl = TextEditingController();
    _webhookSecretCtrl = TextEditingController();
    _datevConsultantCtrl = TextEditingController();
    _datevClientCtrl = TextEditingController();
    _initialized = true;
  }

  Future<void> _save(String tenantId) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final colorRaw = _colorCtrl.text.trim();
    final colorHex =
        colorRaw.isNotEmpty ? '#${colorRaw.replaceAll('#', '')}' : null;

    String? opt(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();

    final tenant = Tenant(
      id: tenantId,
      name: _nameCtrl.text.trim(),
      primaryColorHex: colorHex,
      contactEmail: opt(_emailCtrl),
      contactPhone: opt(_phoneCtrl),
      address: opt(_addressCtrl),
      bankAccountHolder: opt(_holderCtrl),
      bankIban: opt(_ibanCtrl),
      bankBic: opt(_bicCtrl),
      erpWebhookUrl: opt(_webhookUrlCtrl),
      erpWebhookSecret: opt(_webhookSecretCtrl),
      datevConsultantNumber: opt(_datevConsultantCtrl),
      datevClientNumber: opt(_datevClientCtrl),
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

                  const SizedBox(height: 28),
                  _sectionTitle('Bankverbindung (SEPA)'),
                  const SizedBox(height: 4),
                  const Text(
                    'Wird auf der Jahresabrechnung als Zahlungsempfänger angezeigt.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _holderCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kontoinhaber',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.account_balance_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _ibanCtrl,
                    decoration: const InputDecoration(
                      labelText: 'IBAN',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.credit_card_outlined),
                      hintText: 'DE00 0000 0000 0000 0000 00',
                    ),
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final clean = v.replaceAll(' ', '');
                      if (!RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$')
                          .hasMatch(clean)) {
                        return 'Ungültige IBAN';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _bicCtrl,
                    decoration: const InputDecoration(
                      labelText: 'BIC / SWIFT',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.swap_horiz_outlined),
                      hintText: 'z.B. DEUTDEDB',
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),

                  const SizedBox(height: 28),
                  _sectionTitle('Integrationen'),
                  const SizedBox(height: 4),
                  const Text(
                    'ERP-Webhook und DATEV-Verbindung für automatischen Datenaustausch.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _webhookUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ERP Webhook-URL',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.webhook_outlined),
                      hintText: 'https://erp.example.com/webhook',
                    ),
                    keyboardType: TextInputType.url,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      if (!v.trim().startsWith('https://')) {
                        return 'Muss mit https:// beginnen';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: _webhookSecretCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Webhook-Secret (optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.key_outlined),
                      hintText: 'Wird als X-Webhook-Secret Header gesendet',
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _datevConsultantCtrl,
                          decoration: const InputDecoration(
                            labelText: 'DATEV Beraternr.',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.tag_outlined),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _datevClientCtrl,
                          decoration: const InputDecoration(
                            labelText: 'DATEV Mandantennr.',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.tag_outlined),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
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
