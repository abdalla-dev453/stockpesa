import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets/app_states.dart';
import '../features/products/data/products_repository.dart';
import '../features/stock/data/stock_repository.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, this.initialAction, this.initialBarcode});
  final String? initialAction;
  final String? initialBarcode;
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});
  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  bool scanned = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan barcode')),
    body: MobileScanner(
      onDetect: (capture) {
        if (scanned) return;
        final code = capture.barcodes.firstOrNull?.rawValue;
        if (code == null || code.isEmpty) return;
        scanned = true;
        Navigator.pop(context, code);
      },
    ),
  );
}

class _ProductsScreenState extends State<ProductsScreen> {
  final search = TextEditingController();
  Timer? _searchDebounce;
  List rows = [], categories = [];
  bool loading = true;
  String? loadError;
  String status = 'ALL';
  String? categoryId;
  String sortBy = 'name';
  int page = 1, totalPages = 1;
  @override
  void initState() {
    super.initState();
    load();
    if (widget.initialAction != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (widget.initialAction == 'add') {
          await addProduct(initialBarcode: widget.initialBarcode);
        }
        if (widget.initialAction == 'import') await importCsv();
      });
    }
  }

  @override
  void dispose() {
    search.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final responses = await Future.wait([
        dio.get(
          '/products',
          queryParameters: {
            'page': page,
            if (search.text.trim().isNotEmpty) 'search': search.text.trim(),
            'limit': 20,
            if (status.isNotEmpty) 'stockStatus': status,
            if (categoryId != null && categoryId!.isNotEmpty)
              'categoryId': categoryId,
            'sortBy': sortBy == 'quantity'
                ? 'stockQuantity'
                : sortBy == 'price'
                ? 'sellingPrice'
                : 'name',
          },
        ),
        dio.get('/categories'),
      ]);
      rows = (responses[0].data['data'] as List?) ?? [];
      loadError = null;
      totalPages = numberValue(
        responses[0].data['meta']?['totalPages'],
      ).toInt().clamp(1, 999999);
      categories = responses[1].data as List;
    } catch (e) {
      loadError = apiError(e);
    }
    if (mounted) setState(() => loading = false);
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> addProduct({String? initialBarcode}) async {
    final name = TextEditingController(),
        buying = TextEditingController(),
        selling = TextEditingController(),
        brand = TextEditingController(),
        minimum = TextEditingController(text: '0'),
        sku = TextEditingController(),
        barcode = TextEditingController(text: initialBarcode ?? '');
    String unit = 'piece';
    String? categoryId;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add product',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Product name'),
                ),
                TextField(
                  controller: sku,
                  decoration: const InputDecoration(
                    labelText: 'SKU (optional)',
                  ),
                ),
                TextField(
                  controller: barcode,
                  decoration: const InputDecoration(
                    labelText: 'Barcode (optional)',
                  ),
                ),
                TextField(
                  controller: brand,
                  decoration: const InputDecoration(
                    labelText: 'Brand (optional)',
                  ),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No category'),
                    ),
                    ...categories.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c['id'].toString(),
                        child: Text(c['name'].toString()),
                      ),
                    ),
                  ],
                  onChanged: (v) => setSheet(() => categoryId = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items:
                      const [
                            'piece',
                            'kg',
                            'gram',
                            'litre',
                            'millilitre',
                            'packet',
                            'carton',
                            'bale',
                            'dozen',
                            'bottle',
                            'pack',
                            'other',
                          ]
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                  onChanged: (v) => setSheet(() => unit = v ?? 'piece'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: buying,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Buying price',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: selling,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Selling price',
                        ),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: minimum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Low stock threshold',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    final b = double.tryParse(buying.text),
                        s = double.tryParse(selling.text),
                        m = double.tryParse(minimum.text);
                    if (name.text.trim().isEmpty ||
                        b == null ||
                        s == null ||
                        m == null ||
                        m < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enter a name and valid prices'),
                        ),
                      );
                      return;
                    }
                    try {
                      await dio.post(
                        '/products',
                        data: {
                          'name': name.text.trim(),
                          'sku': sku.text.trim().isEmpty
                              ? null
                              : sku.text.trim(),
                          'barcode': barcode.text.trim().isEmpty
                              ? null
                              : barcode.text.trim(),
                          'brand': brand.text.trim().isEmpty
                              ? null
                              : brand.text.trim(),
                          'categoryId': categoryId,
                          'unit': unit,
                          'buyingPrice': b,
                          'sellingPrice': s,
                          'minStock': m,
                        },
                      );
                      if (context.mounted) {
                        Navigator.pop(context, true);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(apiError(e))));
                      }
                    }
                  },
                  child: const Text('Save product'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    name.dispose();
    buying.dispose();
    selling.dispose();
    brand.dispose();
    minimum.dispose();
    sku.dispose();
    barcode.dispose();
    if (ok == true) {
      await load();
      if (mounted) _message('Product added');
    }
  }

  Future<void> importCsv() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (picked.isEmpty) return;
      final file = picked.single;
      final bytes = await file.readAsBytes();
      FormData upload() => FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: file.name),
      });
      final response = await dio.post(
        '/products/import/preview',
        data: upload(),
      );
      if (!mounted) return;
      final result = Map<String, dynamic>.from(response.data as Map),
          invalid = (response.data['invalid'] as List?) ?? [];
      final proceed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Review CSV import'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${result['validCount']} valid · ${result['invalidCount']} invalid out of ${result['totalRows']} rows',
                  ),
                  if (invalid.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('Invalid rows will be skipped:'),
                    ...invalid
                        .take(8)
                        .map(
                          (r) => Text(
                            'Row ${r['line']}: ${(r['errors'] as List).join(', ')}',
                            style: const TextStyle(color: C.danger),
                          ),
                        ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            if ((result['validCount'] as int) > 0)
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(
                  invalid.isEmpty ? 'Import products' : 'Import valid rows',
                ),
              ),
          ],
        ),
      );
      if (proceed != true) return;
      final imported = await dio.post(
        '/products/import/confirm',
        queryParameters: invalid.isEmpty ? null : {'skipInvalid': 'true'},
        data: upload(),
      );
      _message(
        '${imported.data['created']} products imported · ${imported.data['skipped']} skipped',
      );
      await load();
    } catch (e) {
      if (mounted) _message(apiError(e));
    }
  }

  Future<void> editProduct(Map<String, dynamic> product) async {
    final name = TextEditingController(text: product['name']?.toString() ?? ''),
        sku = TextEditingController(text: product['sku']?.toString() ?? ''),
        barcode = TextEditingController(
          text: product['barcode']?.toString() ?? '',
        ),
        buying = TextEditingController(
          text: numberValue(product['buyingPrice']).toString(),
        ),
        selling = TextEditingController(
          text: numberValue(product['sellingPrice']).toString(),
        ),
        minimum = TextEditingController(
          text: numberValue(product['minStock']).toString(),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit product'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: sku,
                decoration: const InputDecoration(labelText: 'SKU'),
              ),
              TextField(
                controller: barcode,
                decoration: const InputDecoration(labelText: 'Barcode'),
              ),
              TextField(
                controller: buying,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Buying price'),
              ),
              TextField(
                controller: selling,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Selling price'),
              ),
              TextField(
                controller: minimum,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Low stock threshold',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final b = double.tryParse(buying.text),
                  s = double.tryParse(selling.text),
                  m = double.tryParse(minimum.text);
              if (name.text.trim().isEmpty ||
                  b == null ||
                  s == null ||
                  m == null) {
                ScaffoldMessenger.of(c).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a name and valid prices/threshold'),
                  ),
                );
                return;
              }
              try {
                await dio.patch(
                  '/products/${product['id']}',
                  data: {
                    'name': name.text.trim(),
                    'sku': sku.text.trim().isEmpty ? null : sku.text.trim(),
                    'barcode': barcode.text.trim().isEmpty
                        ? null
                        : barcode.text.trim(),
                    'buyingPrice': b,
                    'sellingPrice': s,
                    'minStock': m,
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
            child: const Text('Save changes'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await load();
      if (mounted) _message('Product updated');
    }
  }

  Future<void> archiveProduct(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove product?'),
        content: Text(
          '${product['name']} will be archived if it has sales or stock history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await dio.delete('/products/${product['id']}');
      await load();
      if (mounted) _message('Product removed');
    } catch (e) {
      if (mounted) _message(apiError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                onChanged: (_) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () {
                      page = 1;
                      load();
                    },
                  );
                },
                onSubmitted: (_) {
                  _searchDebounce?.cancel();
                  page = 1;
                  load();
                },
                decoration: InputDecoration(
                  hintText: 'Search name, SKU or barcode',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: () {
                      _searchDebounce?.cancel();
                      page = 1;
                      load();
                    },
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Scan barcode',
              onPressed: () async {
                final code = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
                );
                if (code != null && mounted) {
                  search.text = code;
                  try {
                    final r = await dio.get(
                      '/products/lookup',
                      queryParameters: {'barcode': code},
                    );
                    final p = r.data as Map;
                    _message('${p['name']} · ${p['quantity']} in stock');
                    await load();
                  } catch (e) {
                    if (e is DioException && e.response?.statusCode == 404) {
                      _message(
                        'No product found. Add this barcode to a new product.',
                      );
                      await addProduct(initialBarcode: code);
                    } else {
                      _message(apiError(e));
                    }
                  }
                }
              },
              icon: const Icon(Icons.qr_code_scanner),
            ),
            IconButton(
              tooltip: 'Import CSV',
              onPressed: importCsv,
              icon: const Icon(Icons.file_upload_outlined),
            ),
            IconButton(
              tooltip: 'Add product',
              onPressed: addProduct,
              icon: const Icon(Icons.add_circle, color: C.emerald),
            ),
          ],
        ),
      ),
      SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final s in ['ALL', 'IN_STOCK', 'LOW_STOCK', 'OUT_OF_STOCK'])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(s.replaceAll('_', ' ')),
                  selected: status == s,
                  onSelected: (_) {
                    status = s;
                    page = 1;
                    load();
                  },
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: categoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All categories'),
                  ),
                  for (final item in categories)
                    DropdownMenuItem<String?>(
                      value: item['id']?.toString(),
                      child: Text(
                        item['name']?.toString() ?? 'Category',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  categoryId = value;
                  page = 1;
                  load();
                },
              ),
            ),
            const SizedBox(width: 12),
            PopupMenuButton<String>(
              tooltip: 'Sort products',
              initialValue: sortBy,
              onSelected: (value) {
                setState(() => sortBy = value);
                load();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'name', child: Text('Name')),
                PopupMenuItem(value: 'price', child: Text('Selling price')),
                PopupMenuItem(
                  value: 'quantity',
                  child: Text('Quantity on hand'),
                ),
              ],
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.sort),
                    SizedBox(width: 6),
                    Text('Sort'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: loading
            ? const LoadingState(label: 'Loading products…')
            : loadError != null
            ? ErrorState(message: loadError!, onRetry: load)
            : RefreshIndicator(
                onRefresh: load,
                child: rows.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 48),
                          Center(
                            child: Image.asset(
                              'assets/branding/empty-products.png',
                              width: 240,
                              height: 180,
                              semanticLabel: 'Illustration of a stock box',
                            ),
                          ),
                          const Center(child: Text('No products found')),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: rows.length + (totalPages > 1 ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          if (i == rows.length) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: 'Previous page',
                                  onPressed: page <= 1
                                      ? null
                                      : () {
                                          page--;
                                          load();
                                        },
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Text('Page $page of $totalPages'),
                                IconButton(
                                  tooltip: 'Next page',
                                  onPressed: page >= totalPages
                                      ? null
                                      : () {
                                          page++;
                                          load();
                                        },
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            );
                          }
                          final p = Map<String, dynamic>.from(rows[i] as Map),
                              quantity = numberValue(p['quantity']);
                          final state = (p['stockStatus'] ?? 'IN_STOCK')
                              .toString();
                          final color = state == 'OUT_OF_STOCK'
                              ? C.danger
                              : state == 'LOW_STOCK'
                              ? C.warn
                              : C.ok;
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: color.withValues(alpha: .12),
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  color: color,
                                ),
                              ),
                              title: Text(
                                p['name'] ?? 'Product',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onTap: () => context.go('/products/${p['id']}'),
                              subtitle: Text(
                                '${p['sku'] ?? 'No SKU'}  •  ${kes(numberValue(p['sellingPrice']))}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${quantity.toString()} ${p['unit'] ?? ''}',
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        state.replaceAll('_', ' '),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: C.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'edit') editProduct(p);
                                      if (v == 'remove') {
                                        archiveProduct(p);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit'),
                                      ),
                                      PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Remove'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
      ),
    ],
  );
}

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;
  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  late Future<List<dynamic>> data = _load();
  Future<List<dynamic>> _load() => Future.wait([
    ref.read(productsRepositoryProvider).get(widget.productId),
    ref.read(stockRepositoryProvider).movements(),
    dio.get('/products/${widget.productId}/variants').then((r) => r.data),
    dio.get('/products/${widget.productId}/images').then((r) => r.data),
    dio.get('/products/${widget.productId}/bundle').then((r) => r.data),
    dio.get('/products/${widget.productId}/price-history').then((r) => r.data),
  ]);

  Future<void> _addVariant() async {
    final name = TextEditingController();
    final sku = TextEditingController();
    final barcode = TextEditingController();
    final cost = TextEditingController();
    final price = TextEditingController();
    var unit = 'piece';
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add size or type'),
        content: StatefulBuilder(
          builder: (context, setDialog) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Variant name (for example 500ml)',
                  ),
                ),
                TextField(
                  controller: sku,
                  decoration: const InputDecoration(
                    labelText: 'SKU (optional)',
                  ),
                ),
                TextField(
                  controller: barcode,
                  decoration: const InputDecoration(
                    labelText: 'Barcode (optional)',
                  ),
                ),
                TextField(
                  controller: cost,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Buying price'),
                ),
                TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Selling price'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items:
                      const [
                            'piece',
                            'kg',
                            'gram',
                            'litre',
                            'millilitre',
                            'packet',
                            'carton',
                            'bale',
                            'dozen',
                            'bottle',
                            'pack',
                            'other',
                          ]
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                  onChanged: (v) => setDialog(() => unit = v ?? 'piece'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final buying = double.tryParse(cost.text),
                  selling = double.tryParse(price.text);
              if (name.text.trim().isEmpty ||
                  buying == null ||
                  selling == null ||
                  buying < 0 ||
                  selling < 0)
                return;
              Navigator.pop(context, {
                'name': name.text.trim(),
                'attributes': {'option': name.text.trim()},
                'sku': sku.text.trim().isEmpty ? null : sku.text.trim(),
                'barcode': barcode.text.trim().isEmpty
                    ? null
                    : barcode.text.trim(),
                'unit': unit,
                'buyingPrice': buying,
                'sellingPrice': selling,
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (body == null || !mounted) return;
    try {
      await dio.post('/products/${widget.productId}/variants', data: body);
      setState(() => data = _load());
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
    }
  }

  Future<void> _receiveVariantStock(Map<String, dynamic> variant) async {
    final quantity = TextEditingController();
    final cost = TextEditingController(
      text: variant['buyingPrice']?.toString() ?? '0',
    );
    final values = await showDialog<List<double>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Receive ${variant['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity received'),
            ),
            TextField(
              controller: cost,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Buying price per unit',
              ),
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
              final q = double.tryParse(quantity.text),
                  c = double.tryParse(cost.text);
              if (q == null || c == null || q <= 0 || c < 0) return;
              Navigator.pop(context, [q, c]);
            },
            child: const Text('Receive stock'),
          ),
        ],
      ),
    );
    if (values == null || !mounted) return;
    try {
      await dio.post(
        '/product-variants/${variant['id']}/stock',
        data: {'quantity': values[0], 'unitCost': values[1]},
        options: Options(
          headers: {
            'Idempotency-Key':
                'variant-intake-${variant['id']}-${DateTime.now().microsecondsSinceEpoch}',
          },
        ),
      );
      setState(() => data = _load());
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
    }
  }

  Future<void> _addImage() async {
    final url = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add product image'),
        content: TextField(
          controller: url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Image URL'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (url.text.trim().startsWith('https://'))
                Navigator.pop(context, url.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    try {
      await dio.post(
        '/products/${widget.productId}/images',
        data: {'url': value},
      );
      setState(() => data = _load());
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
    }
  }

  Future<void> _editTags() async {
    final current = Map<String, dynamic>.from(
      (await dio.get('/products/${widget.productId}')).data as Map,
    );
    if (!mounted) return;
    final tags = TextEditingController(
      text:
          ((current['productTags'] as List? ?? [])
                  .map((row) => row['tag']?['name'])
                  .whereType<String>())
              .join(', '),
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Product tags'),
        content: TextField(
          controller: tags,
          decoration: const InputDecoration(
            labelText: 'Separate tags with commas',
            hintText: 'Fast-moving, Promotion',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, tags.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    try {
      await dio.put(
        '/products/${widget.productId}/tags',
        data: {
          'tags': value
              .split(',')
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .toList(),
        },
      );
      setState(() => data = _load());
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
    }
  }

  Future<void> _setPromotion(Map<String, dynamic> product) async {
    final price = TextEditingController(
      text: product['promotionalPrice']?.toString() ?? '',
    );
    final value = await showDialog<double?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Promotion price'),
        content: TextField(
          controller: price,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Price (leave blank to remove)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (price.text.trim().isEmpty) {
                Navigator.pop(context, -1);
                return;
              }
              final parsed = double.tryParse(price.text);
              if (parsed != null && parsed >= 0) Navigator.pop(context, parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    try {
      await dio.patch(
        '/products/${widget.productId}',
        data: {'promotionalPrice': value < 0 ? null : value},
      );
      setState(() => data = _load());
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
    }
  }

  Future<void> _addConversion(String productUnit) async {
    var from = productUnit, to = productUnit == 'piece' ? 'dozen' : 'piece';
    final multiplier = TextEditingController(text: '1');
    const units = [
      'piece',
      'kg',
      'gram',
      'litre',
      'millilitre',
      'packet',
      'carton',
      'bale',
      'dozen',
      'bottle',
      'pack',
      'other',
    ];
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unit conversion'),
        content: StatefulBuilder(
          builder: (context, setDialog) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: from,
                decoration: const InputDecoration(labelText: 'From'),
                items: units
                    .map(
                      (unit) =>
                          DropdownMenuItem(value: unit, child: Text(unit)),
                    )
                    .toList(),
                onChanged: (value) => setDialog(() => from = value ?? from),
              ),
              DropdownButtonFormField<String>(
                initialValue: to,
                decoration: const InputDecoration(labelText: 'To'),
                items: units
                    .map(
                      (unit) =>
                          DropdownMenuItem(value: unit, child: Text(unit)),
                    )
                    .toList(),
                onChanged: (value) => setDialog(() => to = value ?? to),
              ),
              TextField(
                controller: multiplier,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '1 From unit equals how many To units?',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(multiplier.text);
              if (parsed != null && parsed > 0 && from != to)
                Navigator.pop(context, {
                  'productId': widget.productId,
                  'fromUnit': from,
                  'toUnit': to,
                  'multiplier': parsed,
                });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      await dio.post('/unit-conversions', data: result);
      setState(() => data = _load());
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
    }
  }

  Future<void> _editBundle() async {
    try {
      final dataResponse = await dio.get(
        '/products',
        queryParameters: {'page': 1, 'limit': 100},
      );
      final products = (dataResponse.data['data'] as List)
          .where((row) => row['id'] != widget.productId)
          .toList();
      if (!mounted) return;
      final selected = <String, TextEditingController>{};
      final items = await showModalBottomSheet<List<Map<String, dynamic>>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => StatefulBuilder(
          builder: (context, setSheet) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.viewInsetsOf(context).bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Choose bundle contents',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: products.map((value) {
                        final row = Map<String, dynamic>.from(value as Map);
                        final id = row['id'].toString();
                        return Row(
                          children: [
                            Expanded(
                              child: CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(row['name'].toString()),
                                value: selected.containsKey(id),
                                onChanged: (checked) => setSheet(() {
                                  if (checked == true) {
                                    selected[id] = TextEditingController(
                                      text: '1',
                                    );
                                  } else {
                                    selected.remove(id)?.dispose();
                                  }
                                }),
                              ),
                            ),
                            if (selected.containsKey(id))
                              SizedBox(
                                width: 68,
                                child: TextField(
                                  controller: selected[id],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Qty',
                                  ),
                                ),
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          final values = selected.entries
                              .map(
                                (entry) => {
                                  'productId': entry.key,
                                  'quantity':
                                      double.tryParse(entry.value.text) ?? 0,
                                },
                              )
                              .toList();
                          if (values.isNotEmpty &&
                              values.every(
                                (row) => (row['quantity'] as double) > 0,
                              ))
                            Navigator.pop(context, values);
                        },
                        child: const Text('Save bundle'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final controller in selected.values) {
        controller.dispose();
      }
      if (items == null || !mounted) return;
      await dio.put(
        '/products/${widget.productId}/bundle',
        data: {'items': items},
      );
      setState(() => data = _load());
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: data,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(apiError(snapshot.error!)),
                TextButton(
                  onPressed: () => setState(() => data = _load()),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final product = Map<String, dynamic>.from(snapshot.data![0] as Map);
      final allMovements = snapshot.data![1] as List;
      final variants = snapshot.data![2] as List;
      final images = snapshot.data![3] as List;
      final bundle = Map<String, dynamic>.from(snapshot.data![4] as Map);
      final priceHistory = snapshot.data![5] as List;
      final movements = allMovements
          .where(
            (row) =>
                row['productId'] == widget.productId ||
                row['product']?['id'] == widget.productId,
          )
          .toList();
      final quantity = numberValue(product['quantity']);
      final threshold = numberValue(product['minStock']);
      final stockStatus = quantity <= 0
          ? 'OUT_OF_STOCK'
          : quantity <= threshold
          ? 'LOW_STOCK'
          : 'IN_STOCK';
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        child: Icon(Icons.inventory_2_outlined),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          product['name']?.toString() ?? 'Product',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit product',
                        onPressed: () =>
                            context.go('/products/${widget.productId}/edit'),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'On hand: ${product['quantity'] ?? 0} ${product['unit'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Selling price: ${kes(numberValue(product['sellingPrice']))}',
                  ),
                  Text(
                    'Buying price: ${kes(numberValue(product['buyingPrice']))}',
                  ),
                  Text('Brand: ${product['brand'] ?? '—'}'),
                  Text('Category: ${product['category']?['name'] ?? '—'}'),
                  Text('SKU: ${product['sku'] ?? '—'}'),
                  Text('Barcode: ${product['barcode'] ?? '—'}'),
                  Text('Low stock threshold: ${product['minStock'] ?? 0}'),
                  Text('Stock status: ${stockStatus.replaceAll('_', ' ')}'),
                ],
              ),
            ),
          ),
          if (variants.isNotEmpty ||
              product['promotionalPrice'] != null ||
              product['status'] != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Product options',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (variants.isNotEmpty)
                      ...variants.map((value) {
                        final variant = Map<String, dynamic>.from(value as Map);
                        final vQuantity = numberValue(variant['quantity']);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(variant['name']?.toString() ?? 'Variant'),
                          subtitle: Text(
                            '${variant['sku'] ?? variant['barcode'] ?? 'No code'} · $vQuantity ${variant['unit']} on hand',
                          ),
                          trailing: Text(
                            kes(numberValue(variant['sellingPrice'])),
                          ),
                          onTap: () => _receiveVariantStock(variant),
                        );
                      }),
                    if (variants.isNotEmpty)
                      const Text('Tap a variant to receive stock.'),
                    if (product['promotionalPrice'] != null)
                      Text(
                        'Promotion: ${kes(numberValue(product['promotionalPrice']))}${product['promotionEndsAt'] == null ? '' : ' · ends ${product['promotionEndsAt']}'}',
                      ),
                    Text(
                      'Status: ${(product['status'] ?? 'ACTIVE').toString().replaceAll('_', ' ').toLowerCase()}',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _addVariant,
                          icon: const Icon(Icons.add),
                          label: const Text('Add size or type'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _addImage,
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Add image URL'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _editTags,
                          icon: const Icon(Icons.sell_outlined),
                          label: const Text('Edit tags'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _setPromotion(product),
                          icon: const Icon(Icons.local_offer_outlined),
                          label: const Text('Set promotion'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _addConversion(
                            product['unit']?.toString() ?? 'piece',
                          ),
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Add unit conversion'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _editBundle,
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('Set bundle contents'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (images.isNotEmpty)
            Card(
              child: Column(
                children: images.map((value) {
                  final image = Map<String, dynamic>.from(value as Map);
                  return ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: Text(
                      image['altText']?.toString().isNotEmpty == true
                          ? image['altText']
                          : 'Product image',
                    ),
                    subtitle: Text(
                      image['url'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
              ),
            ),
          if ((bundle['items'] as List? ?? []).isNotEmpty)
            Card(
              child: Column(
                children: [
                  const ListTile(
                    title: Text(
                      'Bundle contents',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  ...((bundle['items'] as List).map((value) {
                    final item = Map<String, dynamic>.from(value as Map);
                    return ListTile(
                      title: Text(
                        item['component']?['name']?.toString() ?? 'Product',
                      ),
                      trailing: Text('× ${item['quantity']}'),
                    );
                  })),
                ],
              ),
            ),
          if (priceHistory.isNotEmpty)
            Card(
              child: ExpansionTile(
                title: const Text('Price changes'),
                children: priceHistory.take(10).map((value) {
                  final row = Map<String, dynamic>.from(value as Map);
                  return ListTile(
                    title: Text(
                      '${kes(numberValue(row['oldSellingPrice']))} → ${kes(numberValue(row['sellingPrice']))} selling',
                    ),
                    subtitle: Text(
                      '${row['createdAt'] ?? ''} · buying ${kes(numberValue(row['oldBuyingPrice']))} → ${kes(numberValue(row['buyingPrice']))}',
                    ),
                  );
                }).toList(),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              'Recent stock movements',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          if (movements.isEmpty)
            const Card(child: ListTile(title: Text('No stock movements yet'))),
          for (final row in movements.take(25))
            Card(
              child: ListTile(
                leading: const Icon(Icons.swap_vert_circle_outlined),
                title: Text(
                  '${row['kind'] ?? row['type'] ?? 'Stock movement'}  ·  ${row['quantity'] ?? row['quantityChange'] ?? ''}',
                ),
                subtitle: Text(
                  '${row['reason'] ?? ''} ${row['createdAt'] ?? ''}',
                ),
              ),
            ),
        ],
      );
    },
  );
}

class ProductEditorScreen extends ConsumerStatefulWidget {
  const ProductEditorScreen({super.key, required this.productId});
  final String productId;
  @override
  ConsumerState<ProductEditorScreen> createState() =>
      _ProductEditorScreenState();
}

class _ProductEditorScreenState extends ConsumerState<ProductEditorScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      sku = TextEditingController(),
      barcode = TextEditingController(),
      brand = TextEditingController(),
      unit = TextEditingController(),
      buying = TextEditingController(),
      selling = TextEditingController(),
      minimum = TextEditingController();
  List<dynamic> categories = [];
  String? categoryId;
  bool active = true;
  bool loading = true, saving = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ref.read(productsRepositoryProvider).get(widget.productId),
        ref.read(productsRepositoryProvider).categories(),
      ]);
      final product = results[0] as Map<String, dynamic>;
      categories = results[1] as List<dynamic>;
      name.text = product['name']?.toString() ?? '';
      sku.text = product['sku']?.toString() ?? '';
      barcode.text = product['barcode']?.toString() ?? '';
      brand.text = product['brand']?.toString() ?? '';
      unit.text = product['unit']?.toString() ?? 'piece';
      categoryId = product['categoryId']?.toString();
      active = product['active'] != false;
      buying.text = product['buyingPrice']?.toString() ?? '0';
      selling.text = product['sellingPrice']?.toString() ?? '0';
      minimum.text = product['minStock']?.toString() ?? '0';
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    name.dispose();
    sku.dispose();
    barcode.dispose();
    brand.dispose();
    unit.dispose();
    buying.dispose();
    selling.dispose();
    minimum.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await ref.read(productsRepositoryProvider).update(widget.productId, {
        'name': name.text.trim(),
        'sku': sku.text.trim().isEmpty ? null : sku.text.trim(),
        'barcode': barcode.text.trim().isEmpty ? null : barcode.text.trim(),
        'brand': brand.text.trim().isEmpty ? null : brand.text.trim(),
        'unit': unit.text.trim(),
        'categoryId': categoryId,
        'active': active,
        'buyingPrice': double.parse(buying.text),
        'sellingPrice': double.parse(selling.text),
        'minStock': double.parse(minimum.text),
      });
      if (mounted) context.go('/products/${widget.productId}');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Edit product',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Product name'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a product name' : null,
          ),
          TextFormField(
            controller: sku,
            decoration: const InputDecoration(labelText: 'SKU (optional)'),
          ),
          TextFormField(
            controller: barcode,
            decoration: const InputDecoration(labelText: 'Barcode (optional)'),
          ),
          TextFormField(
            controller: brand,
            decoration: const InputDecoration(labelText: 'Brand (optional)'),
          ),
          TextFormField(
            controller: unit,
            decoration: const InputDecoration(labelText: 'Unit'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a unit' : null,
          ),
          DropdownButtonFormField<String?>(
            initialValue: categoryId,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('No category'),
              ),
              for (final category in categories)
                DropdownMenuItem<String?>(
                  value: category['id']?.toString(),
                  child: Text(category['name']?.toString() ?? 'Category'),
                ),
            ],
            onChanged: (value) => setState(() => categoryId = value),
          ),
          TextFormField(
            controller: buying,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Buying price'),
            validator: _nonNegative,
          ),
          TextFormField(
            controller: selling,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Selling price'),
            validator: _nonNegative,
          ),
          TextFormField(
            controller: minimum,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Low stock threshold'),
            validator: _nonNegative,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: active,
            title: const Text('Product is active'),
            onChanged: (value) => setState(() => active = value),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: saving ? null : _save,
            child: saving
                ? const CircularProgressIndicator()
                : const Text('Save changes'),
          ),
        ],
      ),
    );
  }

  String? _nonNegative(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null || parsed < 0
        ? 'Enter a valid non-negative amount'
        : null;
  }
}
