import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../login_screen.dart' show translateFirebaseError;
import '../../repositories/invitation_repository.dart';
import '../../repositories/tenant_repository.dart';
import '../../repositories/user_repository.dart';
import '../../router.dart';
import 'qr_scanner_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.prefillCode});

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
  bool _obscurePassword = true;
  String? _errorMessage;
  // null = not validated, empty = invalid/too short, non-empty = valid preview
  String? _invitePreview;
  bool _codeValid = false;

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
    if (code.length < 8) {
      setState(() {
        _invitePreview = null;
        _codeValid = false;
      });
      return;
    }
    try {
      final inv = await ref
          .read(invitationRepositoryProvider)
          .validate(code.toUpperCase());

      // Try to load company name for a friendlier preview
      String orgName = inv.tenantId;
      try {
        final tenant = await ref
            .read(tenantRepositoryProvider)
            .watchTenant(inv.tenantId)
            .first;
        if (tenant?.name != null && tenant!.name.isNotEmpty) {
          orgName = tenant.name;
        }
      } catch (_) {}

      setState(() {
        _invitePreview = '${inv.roleLabel} bei $orgName';
        _codeValid = true;
      });
    } catch (_) {
      setState(() {
        _invitePreview = null;
        _codeValid = false;
      });
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
      final invitation = await invRepo.validate(code);

      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      await userRepo.getOrCreate(credential.user!, invitation: invitation);
      await invRepo.markUsed(code);
    } on InvitationException catch (e) {
      setState(() => _errorMessage = e.message);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = translateFirebaseError(e));
    } catch (_) {
      setState(() => _errorMessage = 'Registrierung fehlgeschlagen. Bitte versuche es erneut.');
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
    final cs = Theme.of(context).colorScheme;

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
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Einladungscode',
                      hintText: 'z.B. ABCD1234',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.key_outlined),
                      // Show green check when valid, nothing otherwise
                      suffixIcon: _codeValid
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                      helperText: _codeValid ? _invitePreview : null,
                      helperStyle: const TextStyle(color: Colors.green),
                      errorText: _codeController.text.length >= 8 && !_codeValid
                          ? 'Ungültiger oder bereits verwendeter Code'
                          : null,
                    ),
                    onChanged: _previewCode,
                    validator: (v) {
                      if (v == null || v.trim().length < 8) {
                        return 'Bitte Einladungscode eingeben (mind. 8 Zeichen)';
                      }
                      if (!_codeValid) return 'Ungültiger oder bereits verwendeter Code';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'QR-Code scannen',
                  child: IconButton.outlined(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scanQr,
                  ),
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
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'E-Mail',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final e = v?.trim() ?? '';
                if (e.isEmpty) return 'Bitte E-Mail eingeben';
                if (!e.contains('@') || !e.contains('.')) {
                  return 'Keine gültige E-Mail-Adresse';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _register(),
              decoration: InputDecoration(
                labelText: 'Passwort',
                prefixIcon: const Icon(Icons.lock_outlined),
                border: const OutlineInputBorder(),
                helperText: 'Mindestens 6 Zeichen',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  tooltip: _obscurePassword ? 'Passwort anzeigen' : 'Passwort verbergen',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) =>
                  (v == null || v.length < 6) ? 'Mindestens 6 Zeichen erforderlich' : null,
            ),

            const SizedBox(height: 24),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: cs.onErrorContainer, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                            color: cs.onErrorContainer, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : FilledButton(
                    onPressed: _register,
                    style: FilledButton.styleFrom(
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
