import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';

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
      // GoRouter redirect handles navigation after login
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              decoration: const InputDecoration(hintText: 'E-Mail'),
              validator: (v) {
                final e = v?.trim() ?? '';
                if (e.isEmpty) return 'E-Mail eingeben';
                if (!e.contains('@') || !e.contains('.')) return 'Keine gültige E-Mail';
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
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(
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
