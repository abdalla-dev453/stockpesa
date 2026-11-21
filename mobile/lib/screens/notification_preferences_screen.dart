import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/notifications/push_notifications.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});
  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  final thresholdController = TextEditingController();
  bool loading = true, saving = false, pushEnabled = false;
  Map<String, dynamic> preferences = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final response = await dio.get('/notifications/preferences');
      preferences = Map<String, dynamic>.from(response.data as Map);
      thresholdController.text =
          preferences['debtThreshold']?.toString() ?? '10000';
      pushEnabled = await StockPesaPushNotifications.instance.hasPermission();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> change(String key, Object value) async {
    final previous = preferences[key] == true;
    setState(() {
      preferences[key] = value;
      saving = true;
    });
    try {
      final response = await dio.patch(
        '/notifications/preferences',
        data: {key: value},
      );
      if (mounted) {
        setState(
          () => preferences = Map<String, dynamic>.from(response.data as Map),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => preferences[key] = previous);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> enablePush() async {
    final enabled = await StockPesaPushNotifications.instance
        .requestPermissionAndRegister();
    if (!mounted) return;
    setState(() => pushEnabled = enabled);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Push notifications enabled on this device.'
              : 'Push notifications could not be enabled. Check permission and Firebase app configuration.',
        ),
      ),
    );
  }

  Future<void> saveThreshold() async {
    final value = num.tryParse(thresholdController.text.trim());
    if (value == null || value < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid non-negative KES amount.')),
      );
      return;
    }
    await change('debtThreshold', value);
  }

  @override
  void dispose() {
    thresholdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            children: [
              if (saving) const LinearProgressIndicator(minHeight: 2),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Choose which push messages you receive. Stock and account alerts also appear in the in-app alert center.',
                ),
              ),
              if (kIsWeb)
                const ListTile(
                  leading: Icon(Icons.notifications_active_outlined),
                  title: Text('In-app alerts'),
                  subtitle: Text(
                    'Alerts appear here and as pop-ups while StockPesa is open. Browser push is not configured in this build.',
                  ),
                )
              else
                ListTile(
                  leading: const Icon(Icons.phone_android_outlined),
                  title: const Text('This device'),
                  subtitle: Text(
                    pushEnabled
                        ? 'Push is enabled'
                        : 'Enable push delivery on this device',
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: pushEnabled ? null : enablePush,
                    child: Text(pushEnabled ? 'Enabled' : 'Enable'),
                  ),
                ),
              _option(
                'lowStock',
                'Low stock',
                'When a product reaches its minimum level.',
              ),
              _option(
                'outOfStock',
                'Out of stock',
                'When a product has no stock remaining.',
              ),
              _option(
                'dailySummary',
                'Daily summary',
                'A daily view of sales, stock and customer balances.',
              ),
              _option(
                'creditSale',
                'Credit sales',
                'When a customer purchase is recorded on credit.',
              ),
              _option(
                'customerPayment',
                'Customer payments',
                'When a customer payment is recorded.',
              ),
              _option(
                'debtThresholdEnabled',
                'Balance threshold alerts',
                'When a customer balance rises past your chosen amount.',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: thresholdController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Debt threshold (KES)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: saving ? null : saveThreshold,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
              _option(
                'securityAlerts',
                'Security alerts',
                'Important account and staff security events.',
              ),
              _option(
                'newSale',
                'New sale',
                'A notice when a sale is completed.',
              ),
              const Divider(),
              _option(
                'marketing',
                'Product updates',
                'Optional StockPesa news and offers. Off until you enable it.',
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Push delivery requires notifications to be enabled on this device.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            ],
          ),
  );

  Widget _option(String key, String title, String subtitle) => SwitchListTile(
    value: preferences[key] == true,
    onChanged: saving ? null : (value) => change(key, value),
    title: Text(title),
    subtitle: Text(subtitle),
  );
}
