import 'package:flutter/material.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.privacy});
  final bool privacy;

  @override
  Widget build(BuildContext context) {
    final sections = privacy ? _privacy : _terms;
    return Scaffold(
      appBar: AppBar(
        title: Text(privacy ? 'Privacy policy' : 'Terms & conditions'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const Text(
            'Template for review before commercial launch',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Version 1.0 · Last updated 17 November 2026',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          const Text(
            'This draft needs review by a qualified Kenyan lawyer. It is not legal advice and does not certify compliance.',
            style: TextStyle(color: Colors.deepOrange),
          ),
          for (final section in sections) ...[
            const SizedBox(height: 18),
            Text(
              section.$1,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(section.$2),
          ],
        ],
      ),
    );
  }
}

const _privacy = <(String, String)>[
  (
    'Who operates StockPesa',
    'StockPesa is an inventory and sales service for businesses. Before publication, the operator must add its registered name, address, support email and data-protection contact here.',
  ),
  (
    'Information we handle',
    'Depending on how you use the service, we process business name and type, owner and staff names, phone numbers and email addresses, optional business location, product and stock records, sales and payment records, customer contact details entered by the merchant, device and app diagnostic information, and push-notification tokens.',
  ),
  (
    'Why we use it',
    'We use information to provide inventory, checkout, customer-account and reporting features; authenticate users and enforce business roles; protect accounts and investigate misuse; deliver requested notifications; maintain and improve the service; and respond to support requests.',
  ),
  (
    'Lawful basis and choice',
    'The service operator should document an appropriate lawful basis for each processing purpose and provide any consent choices required by law. Marketing notifications are off unless the user separately opts in. Essential service and security messages may still be sent.',
  ),
  (
    'Sharing',
    'We do not sell personal information. We may share the minimum necessary information with hosting, database, delivery, analytics or support providers that help operate StockPesa, and where disclosure is required by law or needed to protect users and the service. Provider and cross-border transfer details must be published by the operator.',
  ),
  (
    'Retention and deletion',
    'Business records are retained while the account is active and as needed for service, security, dispute and legal purposes. The operator must publish the applicable backup-retention period. To request access, correction or deletion, contact the support channel published by the operator; some records may need to be retained where law requires.',
  ),
  (
    'Your choices and rights',
    'Subject to applicable law, users may request access, correction or deletion, object to or restrict certain processing, withdraw consent where consent is the basis, and complain to the Office of the Data Protection Commissioner. Requests can be sent to the operator’s published data-protection contact.',
  ),
  (
    'Security',
    'StockPesa uses account access controls and is intended to protect network traffic with HTTPS in production. No system can promise absolute security. The operator should maintain incident response procedures and notify affected people and authorities when required.',
  ),
  (
    'Children',
    'StockPesa is intended for business users and is not designed for children.',
  ),
  (
    'Changes and contact',
    'We may update this notice as the service changes. The current version and date appear above. Add the operator’s support email, physical address where applicable, and data-protection contact before release.',
  ),
];

const _terms = <(String, String)>[
  (
    'Service',
    'StockPesa provides tools to record products, stock movements, sales, customer balances and business reports. It supports record keeping; it is not accounting, tax, banking or legal advice.',
  ),
  (
    'Eligibility and accounts',
    'An account may be created by an adult authorized to represent a business. Keep login details confidential, use a strong password, and promptly report suspected account access. Business owners are responsible for assigning appropriate staff roles.',
  ),
  (
    'Acceptable use and data',
    'Use the service lawfully and do not interfere with its operation or access another business’s data. The merchant retains rights in data it enters and is responsible for having permission to enter customer information and for checking the accuracy of its records.',
  ),
  (
    'Payments and M-Pesa',
    'Fees, if any, must be shown before they apply and described in an operator-approved billing schedule. Recording an M-Pesa reference in StockPesa does not itself move money, confirm settlement, or make StockPesa an agent of Safaricom. Use the payment provider’s official confirmation for settlement.',
  ),
  (
    'Availability and changes',
    'We work to keep StockPesa available but cannot promise uninterrupted service. Features may change to improve security or operation. We will communicate material changes through an appropriate channel.',
  ),
  (
    'Responsibility and liability',
    'To the extent allowed by law, the service is provided without a guarantee that every record is error-free or suitable for every business purpose. Users should keep appropriate business records and backups. Nothing in these terms removes rights or liability that cannot legally be limited.',
  ),
  (
    'Suspension and termination',
    'The operator may suspend access to address a security threat, unlawful use or material breach. A business may stop using the service and request account/data handling through the published support contact. The operator should explain deletion and retention timelines.',
  ),
  (
    'Governing law and changes',
    'These terms are intended to be governed by the laws of Kenya, subject to mandatory consumer and data-protection rights. The operator must provide its legal name and contact details. Updated terms will show a new version and effective date.',
  ),
  (
    'Contact',
    'Before release, provide the StockPesa operator’s registered name, address and support email here.',
  ),
];
