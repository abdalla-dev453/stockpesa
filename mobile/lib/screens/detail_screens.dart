import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../app/theme_provider.dart';
import '../features/sales/data/receipt_service.dart';

String _newRequestKey() => List.generate(
  32,
  (_) => Random.secure().nextInt(16).toRadixString(16),
).join();

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});
  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  List rows = [];
  bool loading = true;
  bool canReturn = false;
  final Map<String, String> _returnKeys = {};
  final Map<String, String> _returnPayloads = {};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await Future.wait([
        dio.get('/sales'),
        dio.get('/auth/me'),
      ]);
      rows = result[0].data as List;
      canReturn = ['OWNER', 'MANAGER'].contains(result[1].data['role']);
    } catch (e) {
      _message(apiError(e));
    }
    if (mounted) setState(() => loading = false);
  }

  void _message(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> printReceipt(Map sale, {bool share = false}) async {
    try {
      final result = await dio.get('/sales/${sale['id']}');
      final data = Map<String, dynamic>.from(result.data);
      final receiptRows = data['receipts'] as List? ?? [];
      final receipt = receiptRows.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(receiptRows.first['snapshot'] as Map);
      final items = receipt['items'] as List? ?? data['items'] as List;
      final shop = Map<String, dynamic>.from(
        (await dio.get('/business/profile')).data,
      );
      final businessName =
          receipt['businessName'] ?? shop['name'] ?? 'StockPesa';
      final businessPhone = receipt['businessPhone'] ?? shop['phone'];
      final footer = receipt['receiptFooter'] ?? shop['receiptFooter'];
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                businessName.toString(),
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (businessPhone != null) pw.Text(businessPhone.toString()),
              pw.Divider(),
              pw.Text('Receipt ${data['saleNumber']}'),
              pw.Text(data['saleDate'].toString()),
              if (data['customer']?['name'] != null)
                pw.Text('Customer: ${data['customer']['name']}'),
              pw.Divider(),
              for (final item in items)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${item['quantity']} × ${item['name'] ?? item['product']?['name'] ?? 'Product'}',
                        ),
                      ),
                      pw.Text(kes(numberValue(item['lineTotal']))),
                    ],
                  ),
                ),
              if ((data['returns'] as List? ?? []).isNotEmpty) ...[
                pw.Divider(),
                pw.Text(
                  'Returns',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                for (final record in data['returns'] as List)
                  for (final item in record['items'] as List)
                    pw.Text(
                      '${item['quantity']} × ${items.where((line) => line['saleItemId'] == item['saleItemId']).map((line) => line['name']).firstOrNull ?? item['saleItem']?['product']?['name'] ?? 'Product'} · −${kes(numberValue(item['lineTotal']))}',
                    ),
              ],
              pw.Divider(),
              pw.Text(
                'Subtotal: ${kes(numberValue(receipt['subtotal'] ?? data['subtotal']))}',
              ),
              if (numberValue(receipt['discount'] ?? data['discount']) > 0)
                pw.Text(
                  'Discount: −${kes(numberValue(receipt['discount'] ?? data['discount']))}',
                ),
              if (numberValue(receipt['tax'] ?? data['tax']) > 0)
                pw.Text(
                  'Tax: ${kes(numberValue(receipt['tax'] ?? data['tax']))}',
                ),
              pw.Text('Total: ${kes(numberValue(data['total']))}'),
              pw.Text('Paid: ${kes(numberValue(data['amountPaid']))}'),
              pw.Text('Balance: ${kes(numberValue(data['balanceDue']))}'),
              for (final payment in data['payments'] as List? ?? [])
                pw.Text(
                  'Payment: ${payment['method']} ${kes(numberValue(payment['amount']))} · ${payment['status']}${payment['reference'] == null ? '' : ' · ${payment['reference']}'}',
                ),
              if (footer != null) ...[
                pw.SizedBox(height: 16),
                pw.Text(footer.toString()),
              ],
            ],
          ),
        ),
      );
      final bytes = await doc.save();
      if (share) {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                name: '${data['saleNumber']}.pdf',
                mimeType: 'application/pdf',
              ),
            ],
            subject: 'StockPesa receipt ${data['saleNumber']}',
          ),
        );
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      }
    } catch (e) {
      _message(apiError(e));
    }
  }

  Future<void> returnItems(Map sale) async {
    try {
      final data = Map<String, dynamic>.from(
        (await dio.get('/sales/${sale['id']}')).data as Map,
      );
      if (!mounted) return;
      if (['void', 'refunded'].contains(data['status'])) {
        _message('This sale cannot be returned.');
        return;
      }
      final items = data['items'] as List;
      final fields = <String, TextEditingController>{};
      for (final item in items) {
        fields[item['id'].toString()] = TextEditingController(text: '0');
      }
      final reason = TextEditingController(text: 'Customer return');
      var restock = true;
      final selection = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, setD) => AlertDialog(
            title: Text('Return ${data['saleNumber']}'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in items) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(item['product']?['name'] ?? 'Product'),
                          ),
                          SizedBox(
                            width: 75,
                            child: TextField(
                              controller: fields[item['id'].toString()],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                hintText: '0',
                                helperText:
                                    'max ${(numberValue(item['quantity']) - numberValue(item['returnedQty'])).toString()}',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    TextField(
                      controller: reason,
                      decoration: const InputDecoration(labelText: 'Reason'),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: restock,
                      title: const Text('Return accepted items to stock'),
                      onChanged: (value) =>
                          setD(() => restock = value ?? false),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final values = <Map<String, dynamic>>[];
                  for (final item in items) {
                    final q =
                        double.tryParse(fields[item['id'].toString()]!.text) ??
                        0;
                    if (q > 0) {
                      values.add({'saleItemId': item['id'], 'quantity': q});
                    }
                  }
                  Navigator.pop(c, {'items': values, 'restock': restock});
                },
                child: const Text('Review return'),
              ),
            ],
          ),
        ),
      );
      final selected =
          (selection?['items'] as List?)?.cast<Map<String, dynamic>>() ??
          <Map<String, dynamic>>[];
      if (selected.isEmpty) return;
      var returnedTotal = 0.0;
      for (final selectedItem in selected) {
        final item = items.firstWhere(
          (i) => i['id'] == selectedItem['saleItemId'],
        );
        final gross =
            numberValue(item['lineTotal']) /
            numberValue(item['quantity']) *
            (selectedItem['quantity'] as num).toDouble();
        final subtotal = numberValue(data['subtotal']);
        final allocatedSaleDiscount = subtotal > 0
            ? numberValue(data['discount']) * gross / subtotal
            : 0.0;
        returnedTotal += ((gross - allocatedSaleDiscount) * 100).round() / 100;
      }
      final selectedById = {for (final row in selected) row['saleItemId']: row};
      final allRemainingItemsReturned = items.every((item) {
        final selectedQty =
            (selectedById[item['id']]?['quantity'] as num?)?.toDouble() ?? 0;
        return numberValue(item['returnedQty']) + selectedQty >=
            numberValue(item['quantity']);
      });
      if (allRemainingItemsReturned) {
        returnedTotal = numberValue(data['total']).toDouble();
      }
      final refund =
          (numberValue(data['amountPaid']) -
                  (numberValue(data['total']) - returnedTotal))
              .clamp(0, returnedTotal);
      final returnBody = {
        'items': selected,
        'reason': reason.text.trim(),
        'restock': selection?['restock'] == true,
        'refundAmount': double.parse(refund.toStringAsFixed(2)),
      };
      final returnFingerprint = jsonEncode(returnBody);
      final saleId = data['id'].toString();
      if (_returnKeys[saleId] == null ||
          _returnPayloads[saleId] != returnFingerprint) {
        _returnKeys[saleId] = _newRequestKey();
        _returnPayloads[saleId] = returnFingerprint;
      }
      final response = await dio.post(
        '/sales/${data['id']}/returns',
        data: returnBody,
        options: Options(headers: {'Idempotency-Key': _returnKeys[saleId]}),
      );
      _returnKeys.remove(saleId);
      _returnPayloads.remove(saleId);
      final result = Map<String, dynamic>.from(response.data as Map);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            icon: const Icon(Icons.assignment_return_outlined),
            title: const Text('Return recorded'),
            content: Text(
              'Return ${result['id']}\n'
              'Returned value: ${kes(numberValue(result['returnedTotal']))}\n'
              'Refund recorded: ${kes(numberValue(result['refunded']))}\n'
              'Sale balance: ${kes(numberValue(result['balanceDue']))}\n\n'
              '${selection?['restock'] == true ? 'Accepted items were returned to stock.' : 'Stock was not changed.'} '
              'The refund uses the original payment method where available.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
      await load();
    } catch (e) {
      if (mounted) _message(apiError(e));
    }
  }

  Future<void> saleActions(Map sale) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('View receipt'),
              onTap: () => Navigator.pop(c, 'receipt'),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share receipt PDF'),
              onTap: () => Navigator.pop(c, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Share receipt summary'),
              onTap: () => Navigator.pop(c, 'summary'),
            ),
            if (canReturn)
              ListTile(
                leading: const Icon(Icons.assignment_return_outlined),
                title: const Text('Return items'),
                onTap: () => Navigator.pop(c, 'return'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'receipt') context.go('/sales/${sale['id']}/receipt');
    if (action == 'share') await printReceipt(sale, share: true);
    if (action == 'summary') {
      try {
        final receipt = await ReceiptService().load(sale['id'].toString());
        await ReceiptService().shareSummary(receipt);
      } catch (error) {
        _message(apiError(error));
      }
    }
    if (action == 'return') await returnItems(sale);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sales history')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: rows.isEmpty
                ? const Center(child: Text('No sales yet'))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final s = rows[i] as Map;
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.receipt_long),
                        ),
                        title: Text(
                          s['saleNumber'] ?? 'Sale',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${formatBusinessDate(s['saleDate'])} · ${s['status'] ?? ''}',
                        ),
                        trailing: Text(kes(numberValue(s['total']))),
                        onTap: () => saleActions(s),
                      );
                    },
                  ),
          ),
  );
}

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List rows = [];
  List recentSales = [];
  final search = TextEditingController();
  bool loading = true;
  bool debtOnly = false;
  String? loadError;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final responses = await Future.wait([
        dio.get('/customers', queryParameters: {'search': search.text.trim()}),
        dio.get('/sales'),
      ]);
      final customers = responses[0].data as List;
      rows = debtOnly
          ? customers.where((row) => numberValue(row['balance']) > 0).toList()
          : customers;
      recentSales = responses[1].data as List;
      loadError = null;
    } catch (e) {
      loadError = apiError(e);
    }
    if (mounted) setState(() => loading = false);
  }

  void _message(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> _editCustomer({Map? customer}) async {
    final name = TextEditingController(
      text: customer?['name']?.toString() ?? '',
    );
    final phone = TextEditingController(
      text: customer?['phone']?.toString() ?? '',
    );
    final notes = TextEditingController(
      text: customer?['notes']?.toString() ?? '',
    );
    final creditLimit = TextEditingController(
      text: customer?['creditLimit']?.toString() ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(customer == null ? 'Add customer' : 'Edit customer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              TextField(
                controller: creditLimit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Credit limit (optional)',
                ),
              ),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Email and location are not supported by the current customer API.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final limit = creditLimit.text.trim().isEmpty
                    ? null
                    : double.tryParse(creditLimit.text.trim());
                if (name.text.trim().isEmpty ||
                    (creditLimit.text.trim().isNotEmpty &&
                        (limit == null || limit < 0))) {
                  _message('Enter a name and a valid credit limit.');
                  return;
                }
                final body = <String, dynamic>{
                  'name': name.text.trim(),
                  'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
                  'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
                  'creditLimit': limit,
                };
                if (customer == null) {
                  await dio.post('/customers', data: body);
                } else {
                  await dio.patch('/customers/${customer['id']}', data: body);
                }
                if (c.mounted) Navigator.pop(c, true);
              } catch (e) {
                if (c.mounted) {
                  ScaffoldMessenger.of(
                    c,
                  ).showSnackBar(SnackBar(content: Text(apiError(e))));
                }
              }
            },
            child: Text(customer == null ? 'Save' : 'Save changes'),
          ),
        ],
      ),
    );
    name.dispose();
    phone.dispose();
    notes.dispose();
    creditLimit.dispose();
    if (ok == true) load();
  }

  Future<void> add() => _editCustomer();

  Future<void> pay(Map customer) async {
    List sales;
    try {
      final details =
          (await dio.get('/customers/${customer['id']}')).data as Map;
      sales =
          (details['sales'] as List?)
              ?.where((s) => numberValue(s['balanceDue']) > 0)
              .toList() ??
          [];
    } catch (e) {
      if (mounted) _message(apiError(e));
      return;
    }
    if (sales.isEmpty) {
      _message('No unpaid sales to allocate this payment to.');
      return;
    }
    if (!mounted) return;
    final amount = TextEditingController();
    final reference = TextEditingController();
    String? paymentKey;
    String? paymentPayload;
    String method = 'CASH';
    String saleId = sales.first['id'].toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Record payment · ${customer['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Balance ${kes(numberValue(customer['balance']))}'),
              DropdownButtonFormField<String>(
                initialValue: saleId,
                decoration: const InputDecoration(labelText: 'Sale'),
                items: sales
                    .map(
                      (s) => DropdownMenuItem<String>(
                        value: s['id'].toString(),
                        child: Text(
                          '${s['saleNumber']} · ${kes(numberValue(s['balanceDue']))} due',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setD(() => saleId = v ?? saleId),
              ),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount received'),
              ),
              TextField(
                controller: reference,
                decoration: const InputDecoration(
                  labelText: 'Reference (optional)',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: method,
                items: const ['CASH', 'MPESA', 'BANK', 'CARD']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setD(() => method = v ?? 'CASH'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final n = double.tryParse(amount.text);
                if (n == null ||
                    n <= 0 ||
                    n >
                        numberValue(
                          (sales.firstWhere(
                            (row) => row['id'].toString() == saleId,
                          ))['balanceDue'],
                        ) ||
                    n > numberValue(customer['balance'])) {
                  _message(
                    'Enter an amount within the sale and customer balances.',
                  );
                  return;
                }
                final paymentBody = {
                  'amount': n,
                  'method': method,
                  'saleId': saleId,
                  if (reference.text.trim().isNotEmpty)
                    'reference': reference.text.trim(),
                };
                final fingerprint = jsonEncode(paymentBody);
                if (paymentKey == null || paymentPayload != fingerprint) {
                  paymentKey = _newRequestKey();
                  paymentPayload = fingerprint;
                }
                try {
                  await dio.post(
                    '/customers/${customer['id']}/payments',
                    data: paymentBody,
                    options: Options(headers: {'Idempotency-Key': paymentKey}),
                  );
                  if (c.mounted) Navigator.pop(c, true);
                } catch (e) {
                  if (c.mounted) {
                    ScaffoldMessenger.of(
                      c,
                    ).showSnackBar(SnackBar(content: Text(apiError(e))));
                  }
                }
              },
              child: const Text('Confirm and record'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    reference.dispose();
    if (ok == true) load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customers')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add,
      icon: const Icon(Icons.person_add_alt),
      label: const Text('Add customer'),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => load(),
            decoration: InputDecoration(
              labelText: 'Search by name or phone',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: load,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('All customers'),
                  selected: !debtOnly,
                  onSelected: (_) {
                    setState(() => debtOnly = false);
                    load();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('With debt'),
                  selected: debtOnly,
                  onSelected: (_) {
                    setState(() => debtOnly = true);
                    load();
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : loadError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(loadError!, textAlign: TextAlign.center),
                      TextButton(
                        onPressed: load,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: load,
                  child: rows.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 100),
                            Center(
                              child: Text(
                                debtOnly
                                    ? 'No customer debts.'
                                    : 'No customers yet. Add your first customer.',
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 90),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final c = rows[i] as Map;
                            final balance = numberValue(c['balance']);
                            final lastSale = recentSales
                                .where((sale) => sale['customerId'] == c['id'])
                                .firstOrNull;
                            return ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person_outline),
                              ),
                              title: Text(
                                c['name'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '${c['phone'] ?? 'No phone'}${lastSale == null ? '' : ' · Last purchase ${formatBusinessDate(lastSale['saleDate'])}'}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    kes(balance),
                                    style: TextStyle(
                                      color: balance > 0 ? C.warn : C.ok,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'payment') {
                                        pay(c);
                                      }
                                      if (value == 'edit') {
                                        _editCustomer(customer: c);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'payment',
                                        child: Text('Record payment'),
                                      ),
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit customer'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () => context.go('/customers/${c['id']}'),
                            );
                          },
                        ),
                ),
        ),
      ],
    ),
  );
}

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final String customerId;
  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late Future<Map<String, dynamic>> details = _load();
  Future<Map<String, dynamic>> _load() async {
    final results = await Future.wait([
      dio.get('/customers/${widget.customerId}'),
      dio.get('/sales'),
    ]);
    final customer = Map<String, dynamic>.from(results[0].data as Map);
    customer['_purchaseHistory'] = (results[1].data as List)
        .where((sale) => sale['customerId'] == widget.customerId)
        .toList();
    return customer;
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _recordPayment(Map sale, num customerBalance) async {
    final amount = TextEditingController();
    final reference = TextEditingController();
    var method = 'CASH';
    final value = await showDialog<(double, String)?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text('Payment · ${sale['saleNumber'] ?? 'Sale'}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Outstanding: ${kes(numberValue(sale['balanceDue']))}'),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Amount received'),
              ),
              TextField(
                controller: reference,
                decoration: const InputDecoration(
                  labelText: 'Reference (optional)',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Method'),
                items: const ['CASH', 'MPESA', 'BANK', 'CARD']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setDialog(() => method = v ?? 'CASH'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(amount.text);
                if (parsed == null ||
                    parsed <= 0 ||
                    parsed > numberValue(sale['balanceDue']) ||
                    parsed > customerBalance) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Enter an amount up to the customer and sale balances',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(context, (parsed, method));
              },
              child: const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    final paymentReference = reference.text.trim();
    reference.dispose();
    if (value == null) return;
    try {
      await dio.post(
        '/customers/${widget.customerId}/payments',
        data: {
          'amount': value.$1,
          'method': value.$2,
          'saleId': sale['id'],
          if (paymentReference.isNotEmpty) 'reference': paymentReference,
        },
        options: Options(headers: {'Idempotency-Key': _newRequestKey()}),
      );
      if (mounted) {
        _message('Payment recorded');
        setState(() => details = _load());
      }
    } catch (error) {
      if (mounted) _message(apiError(error));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: details,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(apiError(snapshot.error!)),
              TextButton(
                onPressed: () => setState(() => details = _load()),
                child: const Text('Try again'),
              ),
            ],
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final customer = snapshot.data!;
      final sales = customer['sales'] as List? ?? [];
      final purchases = customer['_purchaseHistory'] as List? ?? [];
      final payments = customer['payments'] as List? ?? [];
      return RefreshIndicator(
        onRefresh: () async {
          setState(() => details = _load());
          await details;
        },
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(
                  customer['name']?.toString() ?? 'Customer',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  customer['phone']?.toString() ?? 'No phone number',
                ),
                trailing: Text(
                  kes(numberValue(customer['balance'])),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () =>
                    context.go('/sell?customerId=${widget.customerId}'),
                icon: const Icon(Icons.point_of_sale),
                label: const Text('New sale for this customer'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                'Unpaid sales',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            if (sales.isEmpty)
              const Card(child: ListTile(title: Text('No outstanding sales'))),
            for (final row in sales)
              Card(
                child: ListTile(
                  title: Text(row['saleNumber']?.toString() ?? 'Sale'),
                  subtitle: Text('Due ${kes(numberValue(row['balanceDue']))}'),
                  trailing: IconButton(
                    tooltip: 'Record payment',
                    onPressed: () => _recordPayment(
                      row as Map,
                      numberValue(customer['balance']),
                    ),
                    icon: const Icon(Icons.payments_outlined),
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                'Recent purchases',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            if (purchases.isEmpty)
              const Card(child: ListTile(title: Text('No recent purchases'))),
            for (final purchase in purchases)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(purchase['saleNumber']?.toString() ?? 'Sale'),
                  subtitle: Text(
                    '${purchase['saleDate'] ?? ''} · ${purchase['status'] ?? ''}',
                  ),
                  trailing: Text(kes(numberValue(purchase['total']))),
                  onTap: () => context.go('/sales/${purchase['id']}/receipt'),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                'Recent payments',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            if (payments.isEmpty)
              const Card(child: ListTile(title: Text('No payments recorded'))),
            for (final payment in payments)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(kes(numberValue(payment['amount']))),
                  subtitle: Text(
                    '${payment['method'] ?? ''} · ${payment['createdAt'] ?? ''}',
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List rows = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows = (await dio.get('/categories')).data as List;
    } catch (e) {
      if (mounted) _message(apiError(e));
    }
    if (mounted) setState(() => loading = false);
  }

  void _message(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> add() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add category'),
        content: TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              try {
                await dio.post('/categories', data: {'name': name.text.trim()});
                if (c.mounted) Navigator.pop(c, true);
              } catch (e) {
                if (c.mounted) {
                  ScaffoldMessenger.of(
                    c,
                  ).showSnackBar(SnackBar(content: Text(apiError(e))));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) load();
  }

  Future<void> edit(Map category) async {
    final name = TextEditingController(text: category['name']?.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rename category'),
        content: TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              try {
                await dio.patch(
                  '/categories/${category['id']}',
                  data: {'name': name.text.trim()},
                );
                if (c.mounted) Navigator.pop(c, true);
              } catch (e) {
                if (c.mounted) {
                  ScaffoldMessenger.of(
                    c,
                  ).showSnackBar(SnackBar(content: Text(apiError(e))));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    if (ok == true) load();
  }

  Future<void> remove(Map category) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(category['name'].toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await dio.delete('/categories/${category['id']}');
      await load();
    } catch (e) {
      if (mounted) _message(apiError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Categories')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add,
      icon: const Icon(Icons.add),
      label: const Text('Add category'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = rows[i] as Map;
                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.category_outlined),
                  ),
                  title: Text(c['name'] ?? ''),
                  subtitle: Text('${c['_count']?['products'] ?? 0} products'),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Category actions',
                    onSelected: (value) =>
                        value == 'edit' ? edit(c) : remove(c),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Rename'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
  );
}

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  List rows = [];
  bool loading = true;
  bool isOwner = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final results = await Future.wait([
        dio.get('/users'),
        dio.get('/auth/me'),
      ]);
      rows = results[0].data as List;
      isOwner = results[1].data['role'] == 'OWNER';
    } catch (e) {
      _message(apiError(e));
    }
    if (mounted) setState(() => loading = false);
  }

  void _message(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> add() async {
    if (!isOwner) {
      _message('Only the business owner can manage staff accounts.');
      return;
    }
    final name = TextEditingController(),
        email = TextEditingController(),
        phone = TextEditingController(),
        password = TextEditingController();
    String role = 'CASHIER';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Add staff'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                TextField(
                  controller: password,
                  decoration: const InputDecoration(
                    labelText: 'Temporary password',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  items: const ['MANAGER', 'CASHIER', 'STOREKEEPER']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setD(() => role = v ?? 'CASHIER'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await dio.post(
                    '/users',
                    data: {
                      'fullName': name.text.trim(),
                      'email': email.text.trim(),
                      'phone': phone.text.trim(),
                      'password': password.text,
                      'role': role,
                    },
                  );
                  if (c.mounted) Navigator.pop(c, true);
                } catch (e) {
                  if (c.mounted) {
                    ScaffoldMessenger.of(
                      c,
                    ).showSnackBar(SnackBar(content: Text(apiError(e))));
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) load();
  }

  Future<void> edit(Map user) async {
    final name = TextEditingController(text: user['fullName']?.toString());
    final phone = TextEditingController(text: user['phone']?.toString());
    String role = user['role']?.toString() ?? 'CASHIER';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text('Edit ${user['fullName']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              DropdownButtonFormField<String>(
                initialValue: role,
                items: const ['OWNER', 'MANAGER', 'CASHIER', 'STOREKEEPER']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setD(() => role = v ?? role),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await dio.patch(
                    '/users/${user['id']}',
                    data: {
                      'fullName': name.text.trim(),
                      'phone': phone.text.trim(),
                      'role': role,
                    },
                  );
                  if (c.mounted) Navigator.pop(c, true);
                } catch (e) {
                  if (c.mounted) {
                    ScaffoldMessenger.of(
                      c,
                    ).showSnackBar(SnackBar(content: Text(apiError(e))));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    phone.dispose();
    if (ok == true) await load();
  }

  Future<void> deactivateUser(Map user) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Deactivate staff account?'),
        content: Text('${user['fullName']} will lose access to this business.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await dio.delete('/users/${user['id']}');
      await load();
    } catch (e) {
      if (mounted) _message(apiError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Staff')),
    floatingActionButton: isOwner
        ? FloatingActionButton.extended(
            onPressed: add,
            icon: const Icon(Icons.person_add),
            label: const Text('Add staff'),
          )
        : null,
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final u = rows[i] as Map;
                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.badge_outlined),
                  ),
                  title: Text(u['fullName'] ?? ''),
                  subtitle: Text('${u['email']} · ${u['phone']}'),
                  trailing: isOwner
                      ? PopupMenuButton<String>(
                          onSelected: (v) =>
                              v == 'edit' ? edit(u) : deactivateUser(u),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit role/details'),
                            ),
                            PopupMenuItem(
                              value: 'deactivate',
                              child: Text('Deactivate'),
                            ),
                          ],
                        )
                      : Text(
                          u['role'] ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                );
              },
            ),
          ),
  );
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map dash = {}, stock = {};
  Map sales = {}, debt = {};
  List products = [], lowStock = [], movements = [];
  String? error;
  bool canViewFinancials = false;
  bool loading = true;
  DateTime periodStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final user = (await dio.get('/auth/me')).data as Map;
      canViewFinancials = ['OWNER', 'MANAGER'].contains(user['role']);
      dash = (await dio.get('/reports/dashboard')).data as Map;
      if (canViewFinancials) {
        final now = DateTime.now();
        periodStart = DateTime(now.year, now.month, 1);
        final reports = await Future.wait([
          dio.get('/reports/stock-summary'),
          dio.get('/reports/products'),
          dio.get(
            '/reports/sales',
            queryParameters: {
              'from': periodStart.toIso8601String(),
              'to': now.toIso8601String(),
            },
          ),
          dio.get('/reports/customer-debt'),
          dio.get('/reports/low-stock'),
          dio.get('/reports/stock-movements', queryParameters: {'limit': 20}),
        ]);
        stock = reports[0].data as Map;
        products = reports[1].data as List;
        sales = reports[2].data as Map;
        debt = reports[3].data as Map;
        lowStock = ((reports[4].data as Map)['data'] as List? ?? []);
        movements = reports[5].data as List;
      }
      error = null;
    } catch (e) {
      error = apiError(e);
    }
    if (mounted) setState(() => loading = false);
  }

  String _csvCell(Object? value, {bool text = false}) {
    var source = value?.toString() ?? '';
    if (text && RegExp(r'^\s*[=+@\-]').hasMatch(source)) source = "'$source";
    return '"${source.replaceAll('"', '""')}"';
  }

  Future<void> _export() async {
    final rows = <List<Object?>>[
      ['Section', 'Name', 'Value'],
      ['Sales', 'Net sales this month', sales['total'] ?? 0],
      ['Sales', 'Transactions', sales['count'] ?? 0],
      ['Payments', 'Received', sales['paid'] ?? 0],
      ['Credit', 'Outstanding sales', sales['outstanding'] ?? 0],
      ['Profit', 'Estimated gross profit', sales['profit'] ?? 0],
      ['Credit', 'Customer debt', debt['total'] ?? 0],
      ['Inventory', 'Stock at cost', stock['stockValue'] ?? 0],
      ['Inventory', 'Retail value', stock['retailValue'] ?? 0],
      ['Inventory', 'Potential stock margin', stock['potentialProfit'] ?? 0],
      for (final entry in (sales['paymentMethods'] as Map? ?? {}).entries)
        ['Payment method', entry.key, entry.value],
      for (final row in (debt['customers'] as List? ?? []).take(100))
        ['Customer debt', row['name'] ?? 'Customer', row['balance'] ?? 0],
      for (final row in products.take(100))
        [
          'Top product',
          row['product']?['name'] ?? 'Product',
          row['revenue'] ?? 0,
        ],
      for (final row in lowStock.take(100))
        ['Low stock', row['name'] ?? 'Product', row['quantity'] ?? 0],
    ];
    final csv = rows
        .map(
          (row) => row
              .asMap()
              .entries
              .map((entry) => _csvCell(entry.value, text: entry.key < 2))
              .join(','),
        )
        .join('\r\n');
    try {
      final saved = await FilePicker.saveFile(
        fileName:
            'stockpesa-report-${DateTime.now().toIso8601String().substring(0, 10)}.csv',
        bytes: Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]),
        mimeType: 'text/csv',
        dialogTitle: 'Export StockPesa report',
      );
      if (saved == null || !mounted) return;
      await dio.post(
        '/reports/export',
        data: {
          'reportType': 'business_summary',
          'format': 'csv',
          'schema': 'mobile_summary_v1',
          'from': periodStart.toIso8601String(),
          'to': DateTime.now().toIso8601String(),
        },
      );
      if (mounted) {
        _message('Report exported. Customer names and balances are included.');
      }
    } catch (e) {
      if (mounted) _message(apiError(e));
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Reports'),
      actions: [
        if (canViewFinancials)
          IconButton(
            tooltip: 'Export report as CSV',
            onPressed: loading ? null : _export,
            icon: const Icon(Icons.file_download_outlined),
          ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (error != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.error_outline, color: C.danger),
                      title: Text(error!),
                      trailing: IconButton(
                        onPressed: load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ),
                _metric('Sales today', kes(numberValue(dash['salesToday']))),
                _metric(
                  'Sales this month',
                  kes(numberValue(dash['salesMonth'])),
                ),
                if (canViewFinancials) ...[
                  _metric(
                    'Sales this month (net)',
                    kes(numberValue(sales['total'])),
                  ),
                  _metric('Sales count this month', '${sales['count'] ?? 0}'),
                  _metric('Payments received', kes(numberValue(sales['paid']))),
                  _metric(
                    'Outstanding sales',
                    kes(numberValue(sales['outstanding'])),
                  ),
                  _metric(
                    'Estimated gross profit',
                    kes(numberValue(sales['profit'])),
                  ),
                  _metric('Customer debt', kes(numberValue(debt['total']))),
                  _metric(
                    'Stock at cost',
                    kes(numberValue(stock['stockValue'])),
                  ),
                  _metric(
                    'Stock retail value',
                    kes(numberValue(stock['retailValue'])),
                  ),
                  _metric(
                    'Potential stock margin',
                    kes(numberValue(stock['potentialProfit'])),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Payments by method',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  for (final entry
                      in (sales['paymentMethods'] as Map? ?? {}).entries)
                    _metric(
                      entry.key.toString(),
                      kes(numberValue(entry.value)),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'Customers with balances',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  for (final row in (debt['customers'] as List? ?? []).take(10))
                    ListTile(
                      dense: true,
                      title: Text(row['name']?.toString() ?? 'Customer'),
                      subtitle: Text(row['phone']?.toString() ?? ''),
                      trailing: Text(kes(numberValue(row['balance']))),
                    ),
                  Text(
                    'Low stock',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (lowStock.isEmpty)
                    const ListTile(title: Text('No low stock items')),
                  for (final row in lowStock.take(20))
                    ListTile(
                      dense: true,
                      title: Text(row['name']?.toString() ?? 'Product'),
                      subtitle: Text(
                        'On hand ${row['quantity']} ${row['unit'] ?? ''} · reorder ${row['suggestedReorder']}',
                      ),
                    ),
                  Text(
                    'Recent stock movements',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  for (final row in movements.take(10))
                    ListTile(
                      dense: true,
                      title: Text(
                        row['product']?['name']?.toString() ?? 'Product',
                      ),
                      subtitle: Text('${row['type']} · ${row['createdAt']}'),
                      trailing: Text('${row['quantity']}'),
                    ),
                ] else
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.lock_outline),
                      title: Text(
                        'Detailed financial and inventory reports are available to owners and managers.',
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Top products',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                ...products.take(20).map((r) {
                  final p = r as Map;
                  return ListTile(
                    title: Text(p['product']?['name'] ?? 'Product'),
                    subtitle: Text('${p['quantitySold']} ${p['product']?['unit'] ?? 'units'} sold'),
                    trailing: Text(kes(numberValue(p['revenue']))),
                  );
                }),
              ],
            ),
          ),
  );
  Widget _metric(String title, String value) => Card(
    child: ListTile(
      leading: const Icon(Icons.analytics_outlined, color: C.emerald),
      title: Text(title),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class BusinessSettingsScreen extends ConsumerStatefulWidget {
  const BusinessSettingsScreen({super.key});
  @override
  ConsumerState<BusinessSettingsScreen> createState() =>
      _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState
    extends ConsumerState<BusinessSettingsScreen> {
  final fields = {
    for (final k in [
      'name',
      'type',
      'phone',
      'location',
      'currency',
      'receiptFooter',
    ])
      k: TextEditingController(),
  };
  bool loading = true, saving = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = (await dio.get('/business/profile')).data as Map;
      for (final k in fields.keys) {
        fields[k]!.text = d[k]?.toString() ?? '';
      }
    } catch (e) {
      _message(apiError(e));
    }
    if (mounted) setState(() => loading = false);
  }

  void _message(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> save() async {
    setState(() => saving = true);
    try {
      await dio.patch(
        '/business/profile',
        data: {for (final k in fields.keys) k: fields[k]!.text.trim()},
      );
      _message('Business profile saved');
    } catch (e) {
      _message(apiError(e));
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Business settings')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.settings_brightness_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined),
                  ),
                ],
                selected: {ref.watch(themeModeProvider)},
                onSelectionChanged: (selection) => ref
                    .read(themeModeProvider.notifier)
                    .setMode(selection.first),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy policy'),
                  subtitle: const Text('Template · version 1.0'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/privacy'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms & conditions'),
                  subtitle: const Text('Template · version 1.0'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/terms'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Notification preferences'),
                  subtitle: const Text(
                    'Choose which business alerts you receive',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/notification-settings'),
                ),
              ),
              const SizedBox(height: 20),
              for (final e in fields.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: e.value,
                    decoration: InputDecoration(
                      labelText: e.key == 'receiptFooter'
                          ? 'Receipt footer'
                          : e.key[0].toUpperCase() + e.key.substring(1),
                    ),
                  ),
                ),
              FilledButton(
                onPressed: saving ? null : save,
                child: saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save settings'),
              ),
            ],
          ),
  );
}

class StockCountsScreen extends StatefulWidget {
  const StockCountsScreen({super.key});
  @override
  State<StockCountsScreen> createState() => _StockCountsScreenState();
}

class _StockCountsScreenState extends State<StockCountsScreen> {
  List rows = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows = (await dio.get('/stock-counts')).data as List;
    } catch (e) {
      _message(apiError(e));
    }
    if (mounted) setState(() => loading = false);
  }

  void _message(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> start() async {
    try {
      final r = await dio.post('/stock-counts', data: {});
      final id = r.data['id'].toString();
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CountDetailScreen(id: id)),
        );
      }
      await load();
    } catch (e) {
      _message(apiError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stock counts')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: start,
      icon: const Icon(Icons.add),
      label: const Text('Start count'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: load,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = rows[i] as Map;
                return ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text('Count ${c['id'].toString().substring(0, 8)}'),
                  subtitle: Text(
                    '${c['_count']?['items'] ?? 0} items · ${c['createdAt']}',
                  ),
                  trailing: Text((c['status'] ?? '').toString().toUpperCase()),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CountDetailScreen(id: c['id'].toString()),
                      ),
                    );
                    load();
                  },
                );
              },
            ),
          ),
  );
}

class CountDetailScreen extends StatefulWidget {
  const CountDetailScreen({super.key, required this.id});
  final String id;
  @override
  State<CountDetailScreen> createState() => _CountDetailScreenState();
}

class _CountDetailScreenState extends State<CountDetailScreen> {
  Map data = {};
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      data = (await dio.get('/stock-counts/${widget.id}')).data as Map;
    } catch (e) {
      _message(apiError(e));
    }
    if (mounted) setState(() => loading = false);
  }

  void _message(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> setCount(Map item) async {
    final c = TextEditingController(
      text: item['countedQty']?.toString() ?? item['systemQty'].toString(),
    );
    final n = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item['product']?['name'] ?? 'Count item'),
        content: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Counted quantity'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(c.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (n != null) {
      try {
        await dio.post(
          '/stock-counts/${widget.id}/items',
          data: {'productId': item['productId'], 'countedQuantity': n},
        );
        await load();
      } catch (e) {
        _message(apiError(e));
      }
    }
  }

  Future<void> complete() async {
    try {
      await dio.post('/stock-counts/${widget.id}/complete');
      await load();
      _message('Stock count completed');
    } catch (e) {
      _message(apiError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Count inventory'),
      actions: [
        if (data['status'] == 'open')
          TextButton(onPressed: complete, child: const Text('Complete')),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView.separated(
            itemCount: (data['items'] as List? ?? []).length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final item = (data['items'] as List)[i] as Map;
              return ListTile(
                title: Text(item['product']?['name'] ?? ''),
                subtitle: Text('System: ${item['systemQty']}'),
                trailing: Text(item['countedQty']?.toString() ?? 'Enter count'),
                onTap: data['status'] == 'open' ? () => setCount(item) : null,
              );
            },
          ),
  );
}
