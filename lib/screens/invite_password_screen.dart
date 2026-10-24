import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InvitePasswordScreen extends StatefulWidget {
  const InvitePasswordScreen({required this.onPasswordChanged, super.key});

  final VoidCallback onPasswordChanged;

  @override
  State<InvitePasswordScreen> createState() => _InvitePasswordScreenState();
}

class _InvitePasswordScreenState extends State<InvitePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isSaving = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    final password = _passwordController.text;
    if (password.length < 8) {
      _showMessage('Use a password with at least 8 characters.');
      return;
    }
    if (password != _confirmationController.text) {
      _showMessage('The passwords do not match.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (mounted) widget.onPasswordChanged();
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('Could not update password: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      border: const OutlineInputBorder(),
      suffixIcon: IconButton(
        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.lock_reset,
                      size: 54,
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Set your password',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose a password for your invited account to continue.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: inputDecoration.copyWith(
                        labelText: 'New password',
                        helperText: 'At least 8 characters',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmationController,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      onSubmitted: (_) => _savePassword(),
                      decoration: inputDecoration.copyWith(
                        labelText: 'Confirm new password',
                      ),
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _isSaving ? null : _savePassword,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save password and continue'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
