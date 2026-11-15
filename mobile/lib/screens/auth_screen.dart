import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../core/validation.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.onAuthenticated,
    this.startInRegistration = false,
    this.onForgotPassword,
  });
  final VoidCallback onAuthenticated;
  final bool startInRegistration;
  final VoidCallback? onForgotPassword;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final business = TextEditingController(),
      name = TextEditingController(),
      phone = TextEditingController(),
      identifier = TextEditingController(),
      password = TextEditingController(),
      businessType = TextEditingController(text: 'retail shop');
  bool registering = false, busy = false, hidePassword = true;
  bool acceptedTerms = false;
  final location = TextEditingController();
  final confirmation = TextEditingController();
  @override
  void initState() {
    super.initState();
    registering = widget.startInRegistration;
  }

  @override
  void dispose() {
    business.dispose();
    name.dispose();
    phone.dispose();
    identifier.dispose();
    password.dispose();
    businessType.dispose();
    location.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      if (registering) {
        final response = await dio.post(
          '/auth/register',
          data: {
            'businessName': business.text.trim(),
            'businessType': businessType.text.trim(),
            'fullName': name.text.trim(),
            'phone': phone.text.trim(),
            'email': identifier.text.trim(),
            'password': password.text,
            'location': location.text.trim(),
          },
        );
        await saveTokens(Map<String, dynamic>.from(response.data as Map));
      } else {
        await login(identifier.text.trim(), password.text);
      }
      widget.onAuthenticated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.emerald,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.inventory_2,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    registering ? 'Set up your shop' : 'Welcome back',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    registering
                        ? 'Create your StockPesa business account.'
                        : 'Sign in to keep your business moving.',
                    style: const TextStyle(color: C.muted),
                  ),
                  const SizedBox(height: 28),
                  if (registering) ...[
                    _field(
                      business,
                      'Business name',
                      Icons.store,
                      validator: (v) =>
                          validateRequired(v, label: 'Business name'),
                    ),
                    const SizedBox(height: 12),
                    _field(
                      businessType,
                      'Business type',
                      Icons.category_outlined,
                      validator: (v) =>
                          validateRequired(v, label: 'Business type'),
                    ),
                    const SizedBox(height: 12),
                    _field(
                      name,
                      'Your full name',
                      Icons.person_outline,
                      validator: (v) => validateRequired(v, label: 'Name'),
                    ),
                    const SizedBox(height: 12),
                    _field(
                      phone,
                      'Phone number',
                      Icons.phone_outlined,
                      keyboard: TextInputType.phone,
                      validator: validateKenyanPhone,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      location,
                      'Town or location',
                      Icons.location_on_outlined,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _field(
                    identifier,
                    registering ? 'Email address' : 'Email or phone',
                    Icons.alternate_email,
                    keyboard: registering
                        ? TextInputType.emailAddress
                        : TextInputType.text,
                    validator: registering
                        ? validateEmail
                        : (v) => validateRequired(v, label: 'Email or phone'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: password,
                    obscureText: hidePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => hidePassword = !hidePassword),
                        icon: Icon(
                          hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 8)
                        ? 'Use at least 8 characters'
                        : null,
                  ),
                  const SizedBox(height: 22),
                  if (registering) ...[
                    TextFormField(
                      controller: confirmation,
                      obscureText: hidePassword,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (value) => value != password.text
                          ? 'Passwords do not match'
                          : null,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: acceptedTerms,
                      onChanged: busy
                          ? null
                          : (value) =>
                                setState(() => acceptedTerms = value ?? false),
                      title: const Text(
                        'I agree to the terms and privacy policy',
                        style: TextStyle(fontSize: 13),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    const SizedBox(height: 8),
                  ] else if (widget.onForgotPassword != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: widget.onForgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  FilledButton(
                    onPressed: busy || (registering && !acceptedTerms)
                        ? null
                        : submit,
                    child: busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(registering ? 'Create account' : 'Sign in'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => registering = !registering),
                    child: Text(
                      registering
                          ? 'Already have an account? Sign in'
                          : 'New to StockPesa? Create an account',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    String? Function(String?)? validator,
    TextInputType? keyboard,
  }) => TextFormField(
    controller: c,
    keyboardType: keyboard,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    validator: validator,
  );
}
