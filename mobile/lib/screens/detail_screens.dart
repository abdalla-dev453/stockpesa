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
import '../core/storage/cart_store.dart';
import '../core/storage/offline_store.dart';
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
  bool showingCache = false;
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
        dio.get('/customers'),
        dio.get('/sales'),
      ]);
      final customers = responses[0].data as List;
      recentSales = responses[1].data as List;
      try {
        await OfflineStore().saveSnapshot('customers', {
          'customers': customers,
          'sales': recentSales,
        });
      } catch (error) {
        if (mounted) _message('Could not save customers for offline use: ${apiError(error)}');
      }
      _setCustomerRows(customers);
      showingCache = false;
      loadError = null;
    } catch (e) {
      final cached = await OfflineStore().loadSnapshot('customers');
      if (cached == null) {
        loadError = apiError(e);
      } else {
        final data = Map<String, dynamic>.from(cached['data'] as Map);
        recentSales = data['sales'] as List? ?? [];
        _setCustomerRows(data['customers'] as List? ?? []);
        showingCache = true;
        loadError = null;
      }
    }
    if (mounted) setState(() => loading = false);
  }

  void _setCustomerRows(List customers) {
    final query = search.text.trim().toLowerCase();
    final matches = customers.where((row) {
      final customer = row as Map;
      return query.isEmpty ||
          (customer['name']?.toString().toLowerCase().contains(query) ??
              false) ||
          (customer['phone']?.toString().toLowerCase().contains(query) ??
              false);
    });
    rows = debtOnly
        ? matches.where((row) => numberValue(row['balance']) > 0).toList()
        : matches.toList();
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
        if (showingCache)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0CC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Showing saved customer records; balances may be out of date.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
    try {
      final results = await Future.wait([
        dio.get('/customers/${widget.customerId}'),
        dio.get('/sales'),
      ]);
      final customer = Map<String, dynamic>.from(results[0].data as Map);
      customer['_purchaseHistory'] = (results[1].data as List)
          .where((sale) => sale['customerId'] == widget.customerId)
          .toList();
      customer['_offline'] = false;
      try {
        await OfflineStore().saveSnapshot(
          'customer-${widget.customerId}',
          customer,
        );
      } catch (error) {
        if (mounted) {
          _message('Could not save this customer for offline use: ${apiError(error)}');
        }
      }
      return customer;
    } catch (error) {
      final cached = await OfflineStore().loadSnapshot(
        'customer-${widget.customerId}',
      );
      if (cached == null) rethrow;
      final customer = Map<String, dynamic>.from(cached['data'] as Map);
      customer['_offline'] = true;
      return customer;
    }
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
            if (customer['_offline'] == true)
              const Card(
                color: Color(0xFFFFF0CC),
                child: ListTile(
                  leading: Icon(Icons.cloud_off_outlined),
                  title: Text('Showing saved customer data; it may be out of date.'),
                ),
              ),
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
  bool showingCache = false;
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
      try {
        await OfflineStore().saveSnapshot('reports', {
          'dash': dash,
          'stock': stock,
          'sales': sales,
          'debt': debt,
          'products': products,
          'lowStock': lowStock,
          'movements': movements,
          'canViewFinancials': canViewFinancials,
          'periodStart': periodStart.toIso8601String(),
        });
      } catch (cacheError) {
        if (mounted) {
          _message('Could not save reports for offline use: ${apiError(cacheError)}');
        }
      }
      showingCache = false;
      error = null;
    } catch (e) {
      final cached = await OfflineStore().loadSnapshot('reports');
      if (cached == null) {
        error = apiError(e);
      } else {
        final data = Map<String, dynamic>.from(cached['data'] as Map);
        dash = Map.from(data['dash'] as Map? ?? {});
        stock = Map.from(data['stock'] as Map? ?? {});
        sales = Map.from(data['sales'] as Map? ?? {});
        debt = Map.from(data['debt'] as Map? ?? {});
        products = data['products'] as List? ?? [];
        lowStock = data['lowStock'] as List? ?? [];
        movements = data['movements'] as List? ?? [];
        canViewFinancials = data['canViewFinancials'] == true;
        if (data['periodStart'] != null) {
          periodStart = DateTime.parse(data['periodStart'].toString());
        }
        showingCache = true;
        error = null;
      }
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
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 700;
    final now = DateTime.now();
    final monthLabel =
        '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][now.month - 1]} ${now.year}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          if (canViewFinancials)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: loading ? null : _export,
                icon: const Icon(Icons.file_download_outlined, size: 19),
                label: const Text('Export CSV'),
              ),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 22,
                  16,
                  compact ? 14 : 22,
                  100,
                ),
                children: [
                  if (showingCache)
                    const Card(
                      color: Color(0xFFFFF0CC),
                      child: ListTile(
                        leading: Icon(Icons.cloud_off_outlined),
                        title: Text('Showing saved reports; figures may be out of date.'),
                      ),
                    ),
                  if (error != null)
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.error_outline,
                          color: C.danger,
                        ),
                        title: Text(error!),
                        trailing: IconButton(
                          onPressed: load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Business performance',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.4,
                              ),
                        ),
                      ),
                      if (!compact)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: C.emerald.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            monthLabel,
                            style: const TextStyle(
                              color: C.emerald,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1100
                          ? 4
                          : constraints.maxWidth >= 700
                          ? 3
                          : 2;
                      final metrics = <(String, String, IconData, Color)>[
                        (
                          'Sales today',
                          kes(numberValue(dash['salesToday'])),
                          Icons.today_outlined,
                          C.emerald,
                        ),
                        (
                          'Sales this month',
                          kes(numberValue(dash['salesMonth'])),
                          Icons.calendar_month_outlined,
                          C.forest,
                        ),
                        if (canViewFinancials) ...[
                          (
                            'Net sales',
                            kes(numberValue(sales['total'])),
                            Icons.payments_outlined,
                            C.emerald,
                          ),
                          (
                            'Transactions',
                            '${sales['count'] ?? 0}',
                            Icons.receipt_long_outlined,
                            const Color(0xFF4F46E5),
                          ),
                          (
                            'Payments received',
                            kes(numberValue(sales['paid'])),
                            Icons.account_balance_wallet_outlined,
                            C.ok,
                          ),
                          (
                            'Outstanding sales',
                            kes(numberValue(sales['outstanding'])),
                            Icons.pending_actions_outlined,
                            C.warn,
                          ),
                          (
                            'Gross profit',
                            kes(numberValue(sales['profit'])),
                            Icons.trending_up_rounded,
                            C.coral,
                          ),
                          (
                            'Customer debt',
                            kes(numberValue(debt['total'])),
                            Icons.people_alt_outlined,
                            C.danger,
                          ),
                          (
                            'Stock at cost',
                            kes(numberValue(stock['stockValue'])),
                            Icons.inventory_2_outlined,
                            C.forest,
                          ),
                          (
                            'Retail value',
                            kes(numberValue(stock['retailValue'])),
                            Icons.storefront_outlined,
                            C.emerald,
                          ),
                          (
                            'Potential margin',
                            kes(numberValue(stock['potentialProfit'])),
                            Icons.show_chart_rounded,
                            const Color(0xFF7C3AED),
                          ),
                        ],
                      ];
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: metrics.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          mainAxisExtent: 112,
                        ),
                        itemBuilder: (context, index) {
                          final metric = metrics[index];
                          return _metric(
                            metric.$1,
                            metric.$2,
                            icon: metric.$3,
                            color: metric.$4,
                          );
                        },
                      );
                    },
                  ),
                  if (canViewFinancials) ...[
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final paymentEntries =
                            (sales['paymentMethods'] as Map? ?? {}).entries
                                .toList();
                        final topProducts = products.take(8).toList();
                        final chart = _ReportChartCard(
                          title: 'Payments by method',
                          subtitle: 'Collected by payment channel',
                          entries: [
                            for (final entry in paymentEntries)
                              (
                                entry.key.toString(),
                                numberValue(entry.value).toDouble(),
                              ),
                          ],
                          valueBuilder: (value) => kes(value),
                        );
                        final productChart = _ReportChartCard(
                          title: 'Top products',
                          subtitle: 'Revenue by product',
                          entries: [
                            for (final row in topProducts)
                              (
                                (row['product'] as Map?)?['name']?.toString() ??
                                    'Product',
                                numberValue(row['revenue']).toDouble(),
                              ),
                          ],
                          valueBuilder: (value) => kes(value),
                        );
                        if (constraints.maxWidth >= 900) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: chart),
                              const SizedBox(width: 14),
                              Expanded(child: productChart),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            chart,
                            const SizedBox(height: 14),
                            productChart,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final customerCard = _ReportListCard(
                          title: 'Customers with balances',
                          icon: Icons.people_alt_outlined,
                          rows: [
                            for (final row
                                in (debt['customers'] as List? ?? []).take(10))
                              (
                                row['name']?.toString() ?? 'Customer',
                                row['phone']?.toString() ?? '',
                                kes(numberValue(row['balance'])),
                              ),
                          ],
                          emptyText: 'No customer balances',
                        );
                        final lowStockCard = _ReportListCard(
                          title: 'Low stock',
                          icon: Icons.inventory_2_outlined,
                          rows: [
                            for (final row in lowStock.take(20))
                              (
                                row['name']?.toString() ?? 'Product',
                                'On hand ${row['quantity']} ${row['unit'] ?? ''} · reorder ${row['suggestedReorder']}',
                                '${row['quantity']}',
                              ),
                          ],
                          emptyText: 'No low stock items',
                        );
                        if (constraints.maxWidth >= 900) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: customerCard),
                              const SizedBox(width: 14),
                              Expanded(child: lowStockCard),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            customerCard,
                            const SizedBox(height: 14),
                            lowStockCard,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    _ReportMovementCard(movements: movements),
                  ] else
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.lock_outline),
                        title: Text(
                          'Detailed financial and inventory reports are available to owners and managers.',
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  _TopProductsList(products: products),
                ],
              ),
            ),
    );
  }

  Widget _metric(
    String title,
    String value, {
    IconData icon = Icons.analytics_outlined,
    Color color = C.emerald,
  }) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: C.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D1B2A41),
          blurRadius: 14,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const Spacer(),
            Icon(Icons.north_east_rounded, size: 15, color: C.muted),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: -.3,
          ),
        ),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: mutedOn(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _ReportChartCard extends StatelessWidget {
  const _ReportChartCard({
    required this.title,
    required this.subtitle,
    required this.entries,
    required this.valueBuilder,
  });

  final String title;
  final String subtitle;
  final List<(String, double)> entries;
  final String Function(double value) valueBuilder;

  @override
  Widget build(BuildContext context) {
    final maxValue = entries.isEmpty
        ? 1.0
        : entries.map((entry) => entry.$2).reduce(max);
    return Container(
      constraints: const BoxConstraints(minHeight: 250),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              color: mutedOn(context),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No data available'),
            )
          else
            for (final entry in entries) ...[
              Row(
                children: [
                  SizedBox(
                    width: 82,
                    child: Text(
                      entry.$1,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: maxValue == 0 ? 0 : entry.$2 / maxValue,
                        minHeight: 14,
                        backgroundColor: C.emerald.withValues(alpha: .08),
                        color: C.emerald,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 82,
                    child: Text(
                      valueBuilder(entry.$2),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _ReportListCard extends StatelessWidget {
  const _ReportListCard({
    required this.title,
    required this.icon,
    required this.rows,
    required this.emptyText,
  });

  final String title;
  final IconData icon;
  final List<(String, String, String)> rows;
  final String emptyText;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 250),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: C.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: C.emerald),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(emptyText),
          )
        else
          for (final row in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: C.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.$1,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        if (row.$2.isNotEmpty)
                          Text(
                            row.$2,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: mutedOn(context),
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    row.$3,
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
      ],
    ),
  );
}

class _ReportMovementCard extends StatelessWidget {
  const _ReportMovementCard({required this.movements});
  final List movements;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: C.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.swap_horiz_rounded, color: C.emerald),
            const SizedBox(width: 8),
            Text(
              'Recent stock movements',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (movements.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('No recent stock movements'),
          )
        else
          for (final row in movements.take(10))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(
                radius: 17,
                backgroundColor: C.emerald.withValues(alpha: .08),
                foregroundColor: C.emerald,
                child: const Icon(Icons.inventory_2_outlined, size: 18),
              ),
              title: Text(
                row['product']?['name']?.toString() ?? 'Product',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${row['type']} · ${row['createdAt']}',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                '${row['quantity']}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
      ],
    ),
  );
}

class _TopProductsList extends StatelessWidget {
  const _TopProductsList({required this.products});
  final List products;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).cardTheme.color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: C.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top products',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (products.isEmpty)
          const Text('No product sales recorded')
        else
          for (final r in products.take(20))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(
                radius: 17,
                backgroundColor: C.emerald.withValues(alpha: .08),
                foregroundColor: C.emerald,
                child: const Icon(Icons.shopping_bag_outlined, size: 18),
              ),
              title: Text(
                (r as Map)['product']?['name']?.toString() ?? 'Product',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${(r)['quantitySold']} ${(r)['product']?['unit'] ?? 'units'} sold',
              ),
              trailing: Text(
                kes(numberValue((r)['revenue'])),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
      ],
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
  bool showingCache = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final serverRows = (await dio.get('/stock-counts')).data as List;
      try {
        await OfflineStore().saveSnapshot('stock-counts', serverRows);
      } catch (error) {
        if (mounted) _message('Could not save counts for offline use: ${apiError(error)}');
      }
      final queued = await OfflineStore().loadStockQueueForCurrentUser();
      rows = _withQueuedCounts(serverRows, queued);
      showingCache = false;
    } catch (e) {
      final cached = await OfflineStore().loadSnapshot('stock-counts');
      final queued = await OfflineStore().loadStockQueueForCurrentUser();
      if (cached == null && queued.isEmpty) {
        _message(apiError(e));
      } else {
        rows = _withQueuedCounts(cached?['data'] as List? ?? [], queued);
        showingCache = true;
      }
    }
    if (mounted) setState(() => loading = false);
  }

  List _withQueuedCounts(List saved, List<Map<String, dynamic>> queued) {
    final result = [...saved];
    final ids = result.map((row) => row['id'].toString()).toSet();
    for (final operation in queued.where((item) => item['kind'] == 'count')) {
      final countId = operation['payload']['countId'].toString();
      if (!ids.add(countId)) continue;
      result.add({
        'id': countId,
        'status': 'offline_draft',
        'createdAt': operation['createdAt'],
        'notes': operation['payload']['notes'],
        '_count': {
          'items': operation['payload']['totalItems'] ??
              (operation['payload']['items'] as List? ?? []).length,
        },
      });
    }
    return result;
  }

  void _message(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  Future<void> start() async {
    final requestId = OfflineStore().newOperationId();
    const countNotes = 'Stock count';
    try {
      final r = await dio.post(
        '/stock-counts',
        data: {'clientId': requestId, 'notes': countNotes},
      );
      final id = r.data['id'].toString();
      try {
        await OfflineStore().saveSnapshot('stock-count-$id', r.data);
      } catch (error) {
        if (mounted) {
          _message('Could not save this count for offline use: ${apiError(error)}');
        }
      }
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CountDetailScreen(id: id)),
        );
      }
      await load();
    } catch (e) {
      if (e is DioException && e.response == null) {
        try {
          final identity = await OfflineStore().loadIdentity();
          final catalog = await CartStore().loadCatalog();
          if (identity == null ||
              identity['id'] == null ||
              identity['businessId'] == null ||
              catalog == null) {
            _message('Reconnect to prepare this device before starting an offline count.');
            return;
          }
          if (!['OWNER', 'MANAGER'].contains(identity['role'])) {
            _message('Only owners and managers can start stock counts.');
            return;
          }
          final products = (catalog['products'] as List? ?? [])
              .where((product) => product['active'] != false)
              .map(
                (product) => Map<String, dynamic>.from(product as Map),
              )
              .toList();
          if (products.isEmpty) {
            _message('No saved products are available for an offline count.');
            return;
          }
          final createdAt = DateTime.now().toIso8601String();
          final localCount = <String, dynamic>{
            'id': requestId,
            'status': 'open',
            '_offlineDraft': true,
            'createdAt': createdAt,
            'notes': countNotes,
            'items': [
              for (final product in products)
                {
                  'productId': product['id'],
                  'systemQty': product['quantity'] ?? 0,
                  'countedQty': null,
                  'product': product,
                },
            ],
          };
          await OfflineStore().enqueueStockOperation({
            'id': requestId,
            'kind': 'count',
            'payload': {
              'countId': requestId,
              'create': true,
              'notes': countNotes,
              'totalItems': products.length,
              'items': <Map<String, dynamic>>[],
            },
            'userId': identity['id'],
            'businessId': identity['businessId'],
            'status': 'pending',
            'createdAt': createdAt,
          });
          await OfflineStore().saveSnapshot(
            'stock-count-$requestId',
            localCount,
          );
          if (mounted) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CountDetailScreen(id: requestId),
              ),
            );
            await load();
          }
        } catch (storageError) {
          _message('Could not save this offline count: ${apiError(storageError)}');
        }
        return;
      }
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
              itemCount: rows.length + (showingCache ? 1 : 0),
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                if (showingCache && i == 0) {
                  return const ListTile(
                    leading: Icon(Icons.cloud_off_outlined),
                    title: Text('Showing saved counts; status may be out of date.'),
                  );
                }
                final c = rows[i - (showingCache ? 1 : 0)] as Map;
                final id = c['id'].toString();
                return ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text('Count ${id.substring(0, min(8, id.length))}'),
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
  bool showingCache = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      data = (await dio.get('/stock-counts/${widget.id}')).data as Map;
      data['_offlineDraft'] = false;
      try {
        await OfflineStore().saveSnapshot('stock-count-${widget.id}', data);
      } catch (error) {
        if (mounted) _message('Could not save this count for offline use: ${apiError(error)}');
      }
      showingCache = false;
    } catch (e) {
      final cached = await OfflineStore().loadSnapshot(
        'stock-count-${widget.id}',
      );
      if (cached == null) {
        _message(apiError(e));
      } else {
        data = Map<String, dynamic>.from(cached['data'] as Map);
        data['_offlineDraft'] = true;
        showingCache = true;
      }
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
      if (n < 0 || n * 1000 != (n * 1000).roundToDouble()) {
        _message('Counted quantity must be nonnegative and use at most 3 decimals.');
        return;
      }
      try {
        await dio.post(
          '/stock-counts/${widget.id}/items',
          data: {'productId': item['productId'], 'countedQuantity': n},
        );
        await load();
      } catch (e) {
        if (e is DioException && e.response == null) {
          try {
            final items = (data['items'] as List? ?? [])
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList();
            final index = items.indexWhere(
              (row) => row['productId'].toString() == item['productId'].toString(),
            );
            if (index >= 0) items[index]['countedQty'] = n;
            data = {...data, 'items': items, '_offlineDraft': true};
            final store = OfflineStore();
            await store.saveSnapshot('stock-count-${widget.id}', data);
            final queue = await store.loadStockQueueForCurrentUser();
            final existing = queue.where(
              (operation) =>
                  operation['kind'] == 'count' &&
                  operation['payload']['countId'] == widget.id,
            );
            final queuedItems = [
              for (final row in items)
                if (row['countedQty'] != null)
                  {
                    'productId': row['productId'],
                    'countedQuantity': row['countedQty'],
                  },
            ];
            if (existing.isNotEmpty) {
              final operation = existing.first;
              await store.updateStockOperation(operation['id'].toString(), {
                'payload': {
                  ...Map<String, dynamic>.from(operation['payload'] as Map),
                  'items': queuedItems,
                },
              });
            } else {
              final identity = await store.loadIdentity();
              if (identity == null ||
                  identity['id'] == null ||
                  identity['businessId'] == null) {
                throw StateError('Reconnect to prepare this device for offline stock updates.');
              }
              final operationId = store.newOperationId();
              await store.enqueueStockOperation({
                'id': operationId,
                'kind': 'count',
                'payload': {
                  'countId': widget.id,
                  'create': false,
                  'items': queuedItems,
                },
                'userId': identity['id'],
                'businessId': identity['businessId'],
                'status': 'pending',
                'createdAt': DateTime.now().toIso8601String(),
              });
            }
            if (mounted) {
              setState(() {
                showingCache = true;
              });
            }
            return;
          } catch (storageError) {
            _message('Could not save this count offline: ${apiError(storageError)}');
            return;
          }
        }
        _message(apiError(e));
      }
    }
  }

  Future<void> complete() async {
    if (showingCache) {
      _message('Reconnect to verify the latest stock before completing this count.');
      return;
    }
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
            itemCount:
                (data['items'] as List? ?? []).length +
                (showingCache ? 1 : 0),
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (showingCache && i == 0) {
                return const ListTile(
                  leading: Icon(Icons.cloud_off_outlined),
                  title: Text('Offline draft · saved values will sync when connected.'),
                );
              }
              final item = (data['items'] as List)[
                i - (showingCache ? 1 : 0)
              ] as Map;
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
