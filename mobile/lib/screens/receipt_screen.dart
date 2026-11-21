import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../features/sales/data/receipt_service.dart';

class ReceiptPreviewScreen extends StatefulWidget {
  const ReceiptPreviewScreen({super.key, required this.saleId});
  final String saleId;
  @override
  State<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends State<ReceiptPreviewScreen> {
  final service = ReceiptService();
  late Future<ReceiptBundle> receipt = service.load(widget.saleId);
  bool busy = false;

  Future<void> _action(Future<void> Function(ReceiptBundle) action) async {
    final value = await receipt;
    setState(() => busy = true);
    try {
      await action(value);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _download(ReceiptBundle value) async {
    final saved = await service.downloadPdf(value);
    if (mounted && saved != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Receipt PDF saved.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Receipt preview')),
    body: FutureBuilder<ReceiptBundle>(
      future: receipt,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(apiError(snapshot.error!)),
                TextButton(
                  onPressed: () =>
                      setState(() => receipt = service.load(widget.saleId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final value = snapshot.data!;
        final sale = value.sale;
        final rows = value.items;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'STOCKPESA',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      value.businessName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (value.phone?.isNotEmpty == true) Text(value.phone!),
                    if (value.location?.isNotEmpty == true)
                      Text(value.location!),
                    const Divider(height: 24),
                    Text(
                      'Receipt ${sale['saleNumber'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text('${sale['saleDate'] ?? ''}'),
                    if (value.cashierName != null)
                      Text('Cashier: ${value.cashierName}'),
                    if (sale['customer']?['name'] != null)
                      Text('Customer: ${sale['customer']['name']}'),
                    const Divider(height: 24),
                    for (final row in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          row['name']?.toString() ??
                              row['product']?['name']?.toString() ??
                              'Product',
                        ),
                        subtitle: Text(
                          '${row['quantity']} × ${kes(numberValue(row['unitPrice'] ?? row['sellingPrice']))}${numberValue(row['lineDiscount'] ?? row['discount']) > 0 ? ' · discount ${kes(numberValue(row['lineDiscount'] ?? row['discount']))}' : ''}',
                        ),
                        trailing: Text(kes(numberValue(row['lineTotal']))),
                      ),
                    const Divider(height: 24),
                    _line(
                      'Subtotal',
                      numberValue(
                        sale['subtotal'] ?? value.snapshot['subtotal'],
                      ),
                    ),
                    _line(
                      'Discount',
                      numberValue(
                        sale['discount'] ?? value.snapshot['discount'],
                      ),
                    ),
                    _line(
                      'Tax',
                      numberValue(sale['tax'] ?? value.snapshot['tax']),
                    ),
                    _line('Total', numberValue(sale['total']), bold: true),
                    _line('Paid', numberValue(sale['amountPaid'])),
                    _line('Balance due', numberValue(sale['balanceDue'])),
                    Text(
                      'Payment method: ${value.snapshot['method'] ?? (sale['payments'] as List? ?? []).firstOrNull?['method'] ?? 'CREDIT'}',
                    ),
                    for (final payment in sale['payments'] as List? ?? [])
                      if ((payment as Map)['reference'] != null)
                        Text('Payment reference: ${payment['reference']}'),
                    if (value.footer?.isNotEmpty == true) ...[
                      const SizedBox(height: 14),
                      Center(
                        child: Text(value.footer!, textAlign: TextAlign.center),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Center(
                      child: Text('Thank you for shopping with us.'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : () => _action(service.sharePdf),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _action(_download),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _action(service.shareSummary),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Share summary'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _action(service.printPdf),
                  icon: Icon(Icons.print_outlined),
                  label: Text('Print receipt'),
                ),
              ],
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        );
      },
    ),
  );

  Widget _line(String label, num amount, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontWeight: bold ? FontWeight.w800 : null),
          ),
        ),
        Text(
          kes(amount),
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : null,
            fontSize: bold ? 18 : 14,
          ),
        ),
      ],
    ),
  );
}
