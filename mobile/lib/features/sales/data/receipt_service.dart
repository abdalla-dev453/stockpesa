import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../core/api.dart';
import '../../../core/theme.dart';

class ReceiptBundle {
  const ReceiptBundle({
    required this.sale,
    required this.snapshot,
    required this.business,
    this.cashierName,
  });
  final Map<String, dynamic> sale;
  final Map<String, dynamic> snapshot;
  final Map<String, dynamic> business;
  final String? cashierName;

  String get businessName =>
      (snapshot['businessName'] ?? business['name'] ?? 'StockPesa').toString();
  String? get phone =>
      (snapshot['businessPhone'] ?? business['phone'])?.toString();
  String? get location =>
      (snapshot['businessLocation'] ?? business['location'])?.toString();
  String? get footer =>
      (snapshot['receiptFooter'] ?? business['receiptFooter'])?.toString();
  List<dynamic> get items =>
      (snapshot['items'] as List?) ?? (sale['items'] as List? ?? []);
}

class ReceiptService {
  ReceiptService([Dio? client]) : _client = client ?? dio;
  final Dio _client;

  Future<ReceiptBundle> load(String saleId) async {
    final results = await Future.wait([
      _client.get('/sales/$saleId'),
      _client.get('/business/profile'),
      _client.get('/auth/me'),
    ]);
    final sale = Map<String, dynamic>.from(results[0].data as Map);
    final business = Map<String, dynamic>.from(results[1].data as Map);
    final user = Map<String, dynamic>.from(results[2].data as Map);
    final receipts = sale['receipts'] as List? ?? [];
    final snapshot = receipts.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from((receipts.first as Map)['snapshot'] as Map);
    final cashierName =
        sale['cashierName']?.toString() ??
        (sale['userId'] == user['id'] ? user['fullName']?.toString() : null);
    return ReceiptBundle(
      sale: sale,
      snapshot: snapshot,
      business: business,
      cashierName: cashierName,
    );
  }

  Future<Uint8List> pdf(ReceiptBundle receipt) async {
    final sale = receipt.sale;
    final snap = receipt.snapshot;
    final items = receipt.items;
    final payments = sale['payments'] as List? ?? [];
    final date = DateTime.tryParse(
      (snap['saleDate'] ?? sale['saleDate'] ?? '').toString(),
    );
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Center(
            child: pw.Text(
              'STOCKPESA',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            receipt.businessName,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          if (receipt.phone != null && receipt.phone!.isNotEmpty)
            pw.Text(receipt.phone!),
          if (receipt.location != null && receipt.location!.isNotEmpty)
            pw.Text(receipt.location!),
          pw.Divider(),
          pw.Text(
            'Receipt ${sale['saleNumber'] ?? snap['saleNumber'] ?? ''}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (date != null)
            pw.Text(DateFormat('dd MMM yyyy, HH:mm').format(date.toLocal())),
          if (receipt.cashierName != null)
            pw.Text('Cashier: ${receipt.cashierName}'),
          if (sale['customer']?['name'] != null)
            pw.Text('Customer: ${sale['customer']['name']}'),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const ['Item', 'Qty', 'Unit price', 'Discount', 'Amount'],
            data: [
              for (final row in items)
                [
                  row['name'] ?? row['product']?['name'] ?? 'Product',
                  '${row['quantity'] ?? ''}${row['unit'] == null ? '' : ' ${row['unit']}'}',
                  kes(numberValue(row['unitPrice'] ?? row['sellingPrice'])),
                  kes(numberValue(row['lineDiscount'] ?? row['discount'])),
                  kes(numberValue(row['lineTotal'])),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.Divider(),
          _pdfRow(
            'Subtotal',
            numberValue(sale['subtotal'] ?? snap['subtotal']),
          ),
          _pdfRow(
            'Discount',
            numberValue(sale['discount'] ?? snap['discount']),
          ),
          _pdfRow('Tax', numberValue(sale['tax'] ?? snap['tax'])),
          _pdfRow(
            'Total',
            numberValue(sale['total'] ?? snap['total']),
            bold: true,
          ),
          _pdfRow(
            'Amount paid',
            numberValue(sale['amountPaid'] ?? snap['amountPaid']),
          ),
          _pdfRow(
            'Balance due',
            numberValue(sale['balanceDue'] ?? snap['balanceDue']),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Payment method: ${snap['method'] ?? payments.firstOrNull?['method'] ?? 'CREDIT'}',
          ),
          for (final payment in payments)
            if ((payment as Map)['reference'] != null)
              pw.Text('Reference: ${payment['reference']}'),
          if (receipt.footer != null && receipt.footer!.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Center(
              child: pw.Text(receipt.footer!, textAlign: pw.TextAlign.center),
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Center(child: pw.Text('Thank you for shopping with us.')),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfRow(String label, num value, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Text(
          kes(value),
          style: pw.TextStyle(
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    ),
  );

  Future<void> sharePdf(ReceiptBundle receipt) async {
    final bytes = await pdf(receipt);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: '${receipt.sale['saleNumber'] ?? 'receipt'}.pdf',
            mimeType: 'application/pdf',
          ),
        ],
        subject: 'Receipt ${receipt.sale['saleNumber'] ?? ''}',
        text: 'Receipt from ${receipt.businessName}',
      ),
    );
  }

  Future<Uri?> downloadPdf(ReceiptBundle receipt) async => FilePicker.saveFile(
    fileName: '${receipt.sale['saleNumber'] ?? 'stockpesa-receipt'}.pdf',
    bytes: await pdf(receipt),
    mimeType: 'application/pdf',
    dialogTitle: 'Save receipt PDF',
  );

  Future<void> shareSummary(ReceiptBundle receipt) async {
    final sale = receipt.sale;
    final message = [
      receipt.businessName,
      'Receipt ${sale['saleNumber'] ?? ''}',
      'Total: ${kes(numberValue(sale['total']))}',
      'Paid: ${kes(numberValue(sale['amountPaid']))}',
      if (numberValue(sale['balanceDue']) > 0)
        'Balance due: ${kes(numberValue(sale['balanceDue']))}',
    ].join('\n');
    await SharePlus.instance.share(
      ShareParams(
        text: message,
        subject: 'StockPesa receipt ${sale['saleNumber'] ?? ''}',
      ),
    );
  }
}
