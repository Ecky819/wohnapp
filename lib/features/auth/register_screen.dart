import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/invitation_repository.dart';
import '../../repositories/user_repository.dart';
import '../../router.dart';
import 'qr_scanner_screen.dart';
import 'package:go_router/go_router.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.prefillCode});

  /// Pre-filled from deep link: wohnapp://invite?code=XXXX
  final String? prefillCode;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _invitePreview; // shows role+tenant after code validation

  @override
  void initState() {
    super.initState();
    if (widget.prefillCode != null) {
      _codeController.text = widget.prefillCode!;
      _previewCode(widget.prefillCode!);
    }
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result == null) return;
    // Support full registration URLs encoded in QR (e.g. https://…/register?code=XXXX)
    final code = _extractCode(result);
    _codeController.text = code.toUpperCase();
    await _previewCode(code);
  }

  static String _extractCode(String raw) {
    try {
      final uri = Uri.parse(raw);
      final codeParam = uri.queryParameters['code'];
      if (codeParam != null && codeParam.isNotEmpty) return codeParam;
    } catch (_) {}
    return raw;
  }

  Future<void> _previewCode(String code) async {
    if (code.length < 8) return;
    try {
      final inv = await ref
          .read(invitationRepositoryProvider)
          .validate(code.toUpperCase());
      setState(() => _invitePreview =
          'Einladung gültig: ${inv.roleLabel} · Tenant ${inv.tenantId}');
    } catch (_) {
      setState(() => _invitePreview = null);
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final code = _codeController.text.trim().toUpperCase();
    final invRepo = ref.read(invitationRepositoryProvider);
    final userRepo = ref.read(userRepositoryProvider);

    try {
      // 1. Validate invitation
      final invitation = await invRepo.validate(code);

      // 2. Create Firebase Auth user
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      // 3. Create Firestore user document with correct tenantId + role
      await userRepo.getOrCreate(
        credential.user!,
        invitation: invitation,
      );

      // 4. Mark invitation as used
      await invRepo.markUsed(code);

      // GoRouter redirect picks up the new auth state automatically
    } on InvitationException catch (e) {
      setState(() => _errorMessage = e.message);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? e.code);
    } catch (e) {
      setState(() => _errorMessage = 'Unbekannter Fehler: $e');
    }

    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrieren')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // ── Einladungscode ──────────────────────────────────────────────
            const Text('Einladungscode',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      hintText: 'z.B. ABCD1234',
                      suffixIcon: const Icon(Icons.key_outlined),
                      helperText: _invitePreview,
                      helperStyle: const TextStyle(color: Colors.green),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: _previewCode,
                    validator: (v) => (v == null || v.trim().length < 8)
                        ? 'Einladungscode eingeben'
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'QR-Code scannen',
                  onPressed: _scanQr,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Account ─────────────────────────────────────────────────────
            const Text('Account erstellen',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'E-Mail'),
              validator: (v) {
                final e = v?.trim() ?? '';
                if (e.isEmpty) return 'E-Mail eingeben';
                if (!e.contains('@') || !e.contains('.')) {
                  return 'Keine gültige E-Mail';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Passwort'),
              validator: (v) =>
                  (v == null || v.length < 6) ? 'Mindestens 6 Zeichen' : null,
            ),

            const SizedBox(height: 16),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              ),

            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _register,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Konto erstellen'),
                  ),

            const SizedBox(height: 12),

            TextButton(
              onPressed: () => context.go(AppRoutes.login),
              child: const Text('Bereits registriert? Zum Login'),
            ),
          ],
        ),
      ),
    );
  }
}
