import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_chrome.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen(
      {super.key, required this.apiService, required this.onLogin});

  final ApiService apiService;
  final ValueChanged<AppUser> onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      setState(() => _error = 'Enter name and phone number');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = await widget.apiService.login(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      widget.onLogin(user);
    } catch (e) {
      setState(() {
        _error = ApiService.readErrorMessage(
          e,
          fallback: 'Login failed. Check name and phone.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppChrome(
        scrollable: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 28),
              const StatChip(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Shared trips, clean splits'),
              const SizedBox(height: 28),
              Text(
                'Track group expenses without the clutter.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Sign in with your saved name and number. No passwords, no friction, just your trip ledger.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF9BB0BC),
                    ),
              ),
              const SizedBox(height: 24),
              AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Welcome back',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use the same details you inserted in the database.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Contact number',
                        prefixIcon: Icon(Icons.call_outlined),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0x33FF6E74),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0x66FF6E74)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: Color(0xFFFF8E94)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style:
                                    const TextStyle(color: Color(0xFFFFC8CB)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_rounded),
                      label: Text(_loading ? 'Signing in...' : 'Continue'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
