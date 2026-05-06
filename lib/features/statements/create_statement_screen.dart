import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../models/annual_statement.dart';
import '../../models/app_user.dart';
import '../../models/statement_position.dart';
import '../../repositories/annual_statement_repository.dart';
import '../../user_provider.dart';
import 'statement_pdf_generator.dart';

// ─── Lokaler Entwurf einer Kostenposition (inkl. noch nicht hochgeladener Bilder)

class _PositionDraft {
  _PositionDraft({
    required this.category,
    required this.label,
    required this.totalCost,
    required this.distributionKey,
    required this.tenantPercent,
    List<Uint8List>? images,
  }) : images = images ?? [];

  BetriebskostenCategory category;
  String label;
  double totalCost;
  DistributionKey distributionKey;
  double tenantPercent;
  List<Uint8List> images; // vor Upload im Speicher

  double get tenantAmount => totalCost * tenantPercent / 100;
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class CreateStatementScreen extends ConsumerStatefulWidget {
  const CreateStatementScreen({super.key});

  @override
  ConsumerState<CreateStatementScreen> createState() =>
      _CreateStatementScreenState();
}

class _CreateStatementScreenState
    extends ConsumerState<CreateStatementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _advanceCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _currency = NumberFormat.currency(locale: 'de_DE', symbol: '€');

  int _year = DateTime.now().year - 1;
  AppUser? _selectedTenant;
  List<AppUser> _tenants = [];
  bool _loadingTenants = true;
  bool _saving = false;
  String _savingStep = '';

  final List<_PositionDraft> _positions = [];

  @override
  void initState() {
    super.initState();
    _loadTenants();
  }

  @override
  void dispose() {
    _advanceCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTenants() async {
    final orgTenantId =
        ref.read(currentUserProvider).valueOrNull?.tenantId ?? '';
    if (orgTenantId.isEmpty) return;
    final list = await ref
        .read(annualStatementRepositoryProvider)
        .watchTenants(orgTenantId)
        .first;
    if (mounted) {
      setState(() {
        _tenants = list;
        _loadingTenants = false;
      });
    }
  }

  double get _totalTenantCosts =>
      _positions.fold(0.0, (acc, p) => acc + p.tenantAmount);

  double get _advancePayments =>
      double.tryParse(_advanceCtrl.text.replaceAll(',', '.')) ?? 0.0;

  double get _balance => _totalTenantCosts - _advancePayments;

  // ── Positions ─────────────────────────────────────────────────────────────

  void _addPosition() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PositionSheet(
        onSave: (draft) => setState(() => _positions.add(draft)),
      ),
    );
  }

  void _editPosition(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PositionSheet(
        existing: _positions[index],
        onSave: (draft) => setState(() => _positions[index] = draft),
      ),
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTenant == null) {
      _snack('Bitte einen Mieter auswählen.');
      return;
    }
    if (_positions.isEmpty) {
      _snack('Mindestens eine Kostenposition erforderlich.');
      return;
    }
    _formKey.currentState!.save();

    setState(() {
      _saving = true;
      _savingStep = 'Bilder werden hochgeladen …';
    });

    try {
      final user = ref.read(currentUserProvider).valueOrNull!;
      final repo = ref.read(annualStatementRepositoryProvider);
      final orgId = user.tenantId;

      // 1. Belegbilder hochladen und URLs einholen
      final uploadedPositions = <StatementPosition>[];
      final imageBytesMap = <String, List<Uint8List>>{};

      for (final draft in _positions) {
        final urls = <String>[];
        for (int i = 0; i < draft.images.length; i++) {
          final fileName =
              '${draft.label}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          final url =
              await repo.uploadReceiptImage(orgId, fileName, draft.images[i]);
          urls.add(url);
        }
        uploadedPositions.add(StatementPosition(
          category: draft.category,
          label: draft.label,
          totalCost: draft.totalCost,
          distributionKey: draft.distributionKey,
          tenantPercent: draft.tenantPercent,
          receiptImageUrls: urls,
        ));
        if (draft.images.isNotEmpty) {
          imageBytesMap[draft.label] = draft.images;
        }
      }

      // 2. PDF generieren
      if (mounted) setState(() => _savingStep = 'PDF wird generiert …');
      final stmt = AnnualStatement(
        id: '',
        tenantId: orgId,
        unitId: _selectedTenant!.unitId ?? '',
        unitName: '',
        recipientId: _selectedTenant!.uid,
        recipientName: _selectedTenant!.name.isNotEmpty
            ? _selectedTenant!.name
            : _selectedTenant!.email,
        year: _year,
        periodStart: DateTime(_year, 1, 1),
        periodEnd: DateTime(_year, 12, 31),
        pdfUrl: '',
        status: StatementStatus.sent,
        createdBy: user.uid,
        positions: uploadedPositions,
        advancePayments: _advancePayments,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );

      final pdfBytes = await StatementPdfGenerator.generate(
        stmt,
        imageBytes: imageBytesMap,
      );

      // 3. PDF hochladen
      if (mounted) setState(() => _savingStep = 'PDF wird hochgeladen …');
      final pdfFileName =
          '${_selectedTenant!.uid}_${_year}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final pdfUrl = await repo.uploadPdf(orgId, pdfFileName, pdfBytes);

      // 4. Firestore-Dokument anlegen
      if (mounted) setState(() => _savingStep = 'Abrechnung wird gespeichert …');
      final finalStmt = AnnualStatement(
        id: '',
        tenantId: stmt.tenantId,
        unitId: stmt.unitId,
        unitName: stmt.unitName,
        recipientId: stmt.recipientId,
        recipientName: stmt.recipientName,
        year: stmt.year,
        periodStart: stmt.periodStart,
        periodEnd: stmt.periodEnd,
        pdfUrl: pdfUrl,
        status: StatementStatus.sent,
        createdBy: stmt.createdBy,
        positions: uploadedPositions,
        advancePayments: _advancePayments,
        note: stmt.note,
      );
      await repo.create(finalStmt);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        _snack('Fehler: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : null,
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_saving) return _SavingOverlay(step: _savingStep);

    return Scaffold(
      appBar: AppBar(title: const Text('Abrechnung erstellen')),
      body: _loadingTenants
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Empfänger + Jahr ──────────────────────────────
                  _Section(
                    title: 'Empfänger & Zeitraum',
                    children: [
                      _tenants.isEmpty
                          ? const Text(
                              'Keine Mieter gefunden.',
                              style: TextStyle(color: Colors.grey),
                            )
                          : DropdownButtonFormField<AppUser>(
                              value: _selectedTenant,
                              decoration: const InputDecoration(
                                labelText: 'Mieter',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              items: _tenants
                                  .map((t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(
                                          t.name.isNotEmpty
                                              ? t.name
                                              : t.email,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _selectedTenant = v),
                              validator: (v) => v == null
                                  ? 'Bitte Mieter auswählen'
                                  : null,
                            ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: _year,
                        decoration: const InputDecoration(
                          labelText: 'Abrechnungsjahr',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today_outlined),
                        ),
                        items: List.generate(
                                5, (i) => DateTime.now().year - 1 - i)
                            .map((y) => DropdownMenuItem(
                                  value: y,
                                  child: Text('$y  (01.01.$y – 31.12.$y)'),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _year = v ?? _year),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Vorauszahlungen ───────────────────────────────
                  _Section(
                    title: 'Vorauszahlungen',
                    children: [
                      TextFormField(
                        controller: _advanceCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Geleistete Vorauszahlungen (€)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Bitte Vorauszahlungen eingeben (0 falls keine)';
                          }
                          if (double.tryParse(v.replaceAll(',', '.')) ==
                              null) {
                            return 'Ungültiger Betrag';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Kostenpositionen ──────────────────────────────
                  _Section(
                    title: 'Kostenpositionen',
                    trailing: TextButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Hinzufügen'),
                      onPressed: _addPosition,
                    ),
                    children: [
                      if (_positions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: Text(
                              'Noch keine Positionen.\nTippe auf „Hinzufügen".',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ..._positions.asMap().entries.map((e) =>
                            _PositionCard(
                              draft: e.value,
                              currency: _currency,
                              onEdit: () => _editPosition(e.key),
                              onDelete: () =>
                                  setState(() => _positions.removeAt(e.key)),
                            )),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Live-Kalkulation ──────────────────────────────
                  if (_positions.isNotEmpty)
                    _BalanceCard(
                      totalCosts: _totalTenantCosts,
                      advance: _advancePayments,
                      balance: _balance,
                      currency: _currency,
                    ),

                  const SizedBox(height: 20),

                  // ── Hinweis ───────────────────────────────────────
                  _Section(
                    title: 'Hinweis (optional)',
                    children: [
                      TextFormField(
                        controller: _noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'z.B. Zahlungsmodalitäten',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.notes_outlined),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── § 556 Hinweis ─────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.gavel_outlined,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Das PDF wird inklusive aller Belegbilder generiert. '
                            'Datum und Uhrzeit der Kenntnisnahme durch den Mieter '
                            'werden als rechtssicherer Zustellnachweis (§ 556 BGB) gespeichert.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('PDF generieren & Senden'),
                      onPressed: _positions.isEmpty ? null : _submit,
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

// ─── Saving overlay ───────────────────────────────────────────────────────────

class _SavingOverlay extends StatelessWidget {
  const _SavingOverlay({required this.step});
  final String step;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(step,
                  style: const TextStyle(fontSize: 15),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

// ─── Balance card ─────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.totalCosts,
    required this.advance,
    required this.balance,
    required this.currency,
  });
  final double totalCosts;
  final double advance;
  final double balance;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    final isNach = balance > 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isNach
            ? Colors.orange.withValues(alpha: 0.1)
            : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isNach
                ? Colors.orange.shade300
                : Colors.green.shade300),
      ),
      child: Column(
        children: [
          _Row('Summe Betriebskosten (Mieteranteil)',
              currency.format(totalCosts)),
          const Divider(height: 16),
          _Row('Vorauszahlungen', '– ${currency.format(advance)}'),
          const SizedBox(height: 8),
          _Row(
            isNach ? 'Nachzahlung' : 'Rückerstattung',
            currency.format(balance.abs()),
            bold: true,
            color: isNach ? Colors.red.shade700 : Colors.green.shade700,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value,
      {this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight:
                      bold ? FontWeight.bold : FontWeight.normal,
                  fontSize: bold ? 14 : 13)),
          Text(value,
              style: TextStyle(
                  fontWeight:
                      bold ? FontWeight.bold : FontWeight.normal,
                  fontSize: bold ? 14 : 13,
                  color: color)),
        ],
      );
}

// ─── Position card ────────────────────────────────────────────────────────────

class _PositionCard extends StatelessWidget {
  const _PositionCard({
    required this.draft,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
  });
  final _PositionDraft draft;
  final NumberFormat currency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined, size: 20),
        title: Text(draft.label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${currency.format(draft.totalCost)} gesamt · '
          '${draft.tenantPercent.toStringAsFixed(1)} % = '
          '${currency.format(draft.tenantAmount)}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (draft.images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Chip(
                  label: Text('${draft.images.length} Bild(er)',
                      style: const TextStyle(fontSize: 10)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: onEdit),
            IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.red),
                onPressed: onDelete),
          ],
        ),
        isThreeLine: false,
      ),
    );
  }
}

// ─── Section helper ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section(
      {required this.title,
      required this.children,
      this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.3)),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      );
}

// ─── Position Sheet ───────────────────────────────────────────────────────────

class _PositionSheet extends StatefulWidget {
  const _PositionSheet({required this.onSave, this.existing});
  final void Function(_PositionDraft) onSave;
  final _PositionDraft? existing;

  @override
  State<_PositionSheet> createState() => _PositionSheetState();
}

class _PositionSheetState extends State<_PositionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _percentCtrl = TextEditingController();

  BetriebskostenCategory _category = BetriebskostenCategory.sonstiges;
  DistributionKey _distKey = DistributionKey.equal;
  List<Uint8List> _images = [];

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _category = ex.category;
      _labelCtrl.text = ex.label;
      _totalCtrl.text = ex.totalCost.toStringAsFixed(2);
      _distKey = ex.distributionKey;
      _percentCtrl.text = ex.tenantPercent.toStringAsFixed(2);
      _images = List.from(ex.images);
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _totalCtrl.dispose();
    _percentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked =
        await picker.pickMultiImage(imageQuality: 80, maxWidth: 1600);
    if (picked.isEmpty) return;
    final bytes =
        await Future.wait(picked.map((f) => f.readAsBytes()));
    setState(() => _images.addAll(bytes));
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSave(_PositionDraft(
      category: _category,
      label: _labelCtrl.text.trim(),
      totalCost:
          double.parse(_totalCtrl.text.trim().replaceAll(',', '.')),
      distributionKey: _distKey,
      tenantPercent:
          double.parse(_percentCtrl.text.trim().replaceAll(',', '.')),
      images: _images,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing == null
                    ? 'Position hinzufügen'
                    : 'Position bearbeiten',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // ── Kategorie ─────────────────────────────────────────
              DropdownButtonFormField<BetriebskostenCategory>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'Kategorie (§ 2 BetrKV)',
                  border: OutlineInputBorder(),
                ),
                items: BetriebskostenCategory.values
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.label,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (c) {
                  if (c == null) return;
                  setState(() {
                    _category = c;
                    if (_labelCtrl.text.isEmpty ||
                        BetriebskostenCategory.values
                            .any((e) => e.label == _labelCtrl.text)) {
                      _labelCtrl.text = c.label;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),

              // ── Bezeichnung ───────────────────────────────────────
              TextFormField(
                controller: _labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Bezeichnung (anpassbar)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Pflichtfeld'
                    : null,
              ),
              const SizedBox(height: 12),

              // ── Gesamtkosten + Anteil ─────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _totalCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Gesamtkosten (€)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Pflichtfeld';
                        }
                        if (double.tryParse(
                                v.replaceAll(',', '.')) ==
                            null) {
                          return 'Ungültig';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _percentCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ihr Anteil (%)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Pflichtfeld';
                        }
                        final d = double.tryParse(
                            v.replaceAll(',', '.'));
                        if (d == null || d < 0 || d > 100) {
                          return '0–100';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Umlageschlüssel ───────────────────────────────────
              DropdownButtonFormField<DistributionKey>(
                value: _distKey,
                decoration: const InputDecoration(
                  labelText: 'Umlageschlüssel',
                  border: OutlineInputBorder(),
                ),
                items: DistributionKey.values
                    .map((k) => DropdownMenuItem(
                          value: k,
                          child: Text(k.label),
                        ))
                    .toList(),
                onChanged: (k) {
                  if (k != null) setState(() => _distKey = k);
                },
              ),
              const SizedBox(height: 16),

              // ── Belegbilder ───────────────────────────────────────
              Row(
                children: [
                  const Text('Belegbilder',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 16),
                    label: const Text('Bilder hinzufügen'),
                    onPressed: _pickImages,
                  ),
                ],
              ),
              if (_images.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: 8),
                    itemBuilder: (_, i) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            _images[i],
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => setState(
                                () => _images.removeAt(i)),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.close,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '§ 259 BGB: Mieter haben Anspruch auf Kopien der Belege.',
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(widget.existing == null
                      ? 'Position hinzufügen'
                      : 'Speichern'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
