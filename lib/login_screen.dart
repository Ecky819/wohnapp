import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';

String translateFirebaseError(FirebaseAuthException e) {
  switch (e.code) {
    case 'user-not-found':
    case 'invalid-credential':
    case 'wrong-password':
      return 'E-Mail oder Passwort ist falsch.';
    case 'invalid-email':
      return 'Die E-Mail-Adresse ist ungültig.';
    case 'user-disabled':
      return 'Dieses Konto wurde gesperrt. Bitte kontaktiere den Support.';
    case 'too-many-requests':
      return 'Zu viele Anmeldeversuche. Bitte warte kurz und versuche es erneut.';
    case 'network-request-failed':
      return 'Keine Internetverbindung. Bitte prüfe deine Verbindung.';
    case 'email-already-in-use':
      return 'Diese E-Mail-Adresse ist bereits registriert.';
    case 'weak-password':
      return 'Das Passwort ist zu schwach. Mindestens 6 Zeichen erforderlich.';
    case 'operation-not-allowed':
      return 'Diese Anmeldemethode ist nicht aktiviert.';
    default:
      return 'Anmeldung fehlgeschlagen. Bitte versuche es erneut.';
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = translateFirebaseError(e));
    } catch (_) {
      setState(() =>
          _errorMessage = 'Anmeldung fehlgeschlagen. Bitte versuche es erneut.');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _showForgotPassword() async {
    final emailCtrl =
        TextEditingController(text: _emailController.text.trim());
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ForgotPasswordSheet(
        emailCtrl: emailCtrl,
        formKey: formKey,
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
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
              onFieldSubmitted: (_) => _login(),
              decoration: InputDecoration(
                labelText: 'Passwort',
                prefixIcon: const Icon(Icons.lock_outlined),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  tooltip: _obscurePassword
                      ? 'Passwort anzeigen'
                      : 'Passwort verbergen',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) => (v == null || v.length < 6)
                  ? 'Mindestens 6 Zeichen erforderlich'
                  : null,
            ),

            // Passwort vergessen — rechtsbündig unter dem Passwortfeld
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _showForgotPassword,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                ),
                child: const Text('Passwort vergessen?'),
              ),
            ),

            const SizedBox(height: 8),

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
                    onPressed: _login,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Anmelden'),
                  ),

            const SizedBox(height: 12),

            TextButton(
              onPressed: () => context.push(AppRoutes.register),
              child: const Text('Noch kein Konto? Registrieren'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Passwort-vergessen Bottom Sheet ─────────────────────────────────────────

class _ForgotPasswordSheet extends StatefulWidget {
  const _ForgotPasswordSheet({
    required this.emailCtrl,
    required this.formKey,
  });
  final TextEditingController emailCtrl;
  final GlobalKey<FormState> formKey;

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  bool _sending = false;
  bool _sent = false;
  String? _error;

  Future<void> _send() async {
    if (!widget.formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: widget.emailCtrl.text.trim(),
      );
      setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = switch (e.code) {
          'user-not-found' =>
            'Kein Konto mit dieser E-Mail gefunden.',
          'invalid-email' => 'Ungültige E-Mail-Adresse.',
          'too-many-requests' =>
            'Zu viele Versuche. Bitte warte einen Moment.',
          _ => 'Fehler beim Senden. Bitte versuche es erneut.',
        };
      });
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: _sent ? _SuccessContent(email: widget.emailCtrl.text.trim()) : Form(
        key: widget.formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Passwort zurücksetzen',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Gib deine E-Mail-Adresse ein. Du erhältst einen Link zum Zurücksetzen deines Passworts.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: widget.emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofocus: widget.emailCtrl.text.isEmpty,
              onFieldSubmitted: (_) => _send(),
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
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: cs.onErrorContainer, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              color: cs.onErrorContainer, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: _sending
                  ? const Center(child: CircularProgressIndicator())
                  : FilledButton.icon(
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('Link senden'),
                      onPressed: _send,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessContent extends StatelessWidget {
  const _SuccessContent({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mark_email_read_outlined,
            size: 56, color: Colors.green),
        const SizedBox(height: 16),
        const Text(
          'E-Mail gesendet!',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Wir haben einen Reset-Link an $email gesendet.\nBitte prüfe auch deinen Spam-Ordner.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Zurück zum Login'),
          ),
        ),
      ],
    );
  }
}
