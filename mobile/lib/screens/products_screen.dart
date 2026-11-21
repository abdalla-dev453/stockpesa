import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets/app_states.dart';
import '../features/products/widgets/category_chip.dart';
import '../features/products/widgets/filter_sort_bottom_sheet.dart';
import '../features/products/widgets/product_card.dart';
import '../features/products/widgets/product_skeleton_card.dart';
import '../core/storage/cart_store.dart';

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

  Future<void> _enterManually() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter barcode'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Barcode',
            prefixIcon: Icon(Icons.qr_code_2_outlined),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Use barcode'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code != null && code.isNotEmpty && mounted) {
      Navigator.pop(context, code);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan barcode')),
    body: Stack(
      children: [
        MobileScanner(
          errorBuilder: (_, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.no_photography_outlined, size: 44),
                  const SizedBox(height: 12),
                  Text(
                    'Camera access is unavailable. Enter the barcode instead.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
          onDetect: (capture) {
            if (scanned) return;
            final code = capture.barcodes.firstOrNull?.rawValue;
            if (code == null || code.isEmpty) return;
            scanned = true;
            Navigator.pop(context, code);
          },
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: Center(
            child: FilledButton.tonalIcon(
              onPressed: _enterManually,
              icon: const Icon(Icons.keyboard_outlined),
              label: const Text('Enter barcode manually'),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProductsScreenState extends State<ProductsScreen> {
  final search = TextEditingController();
  Timer? _searchDebounce;
  final _scrollController = ScrollController();
  final _store = CartStore();

  List<Map<String, dynamic>> products = [];
  List<dynamic> categories = [];
  bool loading = true;
  bool loadingMore = false;
  bool _usingCache = false;
  String? loadError;
  String status = 'ALL';
  String? categoryId;
  String? brand;
  num? priceMin;
  num? priceMax;
  String sortBy = 'name';
  String sortOrder = 'ASC';
  int page = 1;
  int totalPages = 1;
  String? userRole;

  bool get hasMore => page < totalPages;
  bool get _defaultCatalogView =>
      search.text.trim().isEmpty &&
      categoryId == null &&
      status == 'ALL' &&
      brand == null &&
      priceMin == null &&
      priceMax == null &&
      sortBy == 'name' &&
      sortOrder == 'ASC';

  Future<void> _cacheCatalog() async {
    try {
      await _store.saveCatalog(
        products,
        categories
            .map((category) => Map<String, dynamic>.from(category as Map))
            .toList(),
      );
    } catch (_) {
      if (mounted) _message('Could not save products for offline browsing.');
    }
  }

  List<Map<String, dynamic>> _filterCachedProducts(
    List<Map<String, dynamic>> cached,
  ) {
    final term = search.text.trim().toLowerCase();
    final selectedBrand = brand?.toLowerCase();
    final filtered = cached.where((product) {
      final category = product['category'];
      final productCategoryId = category is Map
          ? category['id']?.toString()
          : product['categoryId']?.toString();
      if (categoryId != null && productCategoryId != categoryId) return false;
      if (term.isNotEmpty &&
          ![product['name'], product['sku'], product['barcode']].any(
            (value) => value?.toString().toLowerCase().contains(term) == true,
          )) {
        return false;
      }
      if (selectedBrand != null &&
          !(product['brand']?.toString().toLowerCase().contains(
                selectedBrand,
              ) ??
              false)) {
        return false;
      }
      final price = numberValue(product['sellingPrice']);
      if (priceMin != null && price < priceMin!) return false;
      if (priceMax != null && price > priceMax!) return false;
      final quantity = numberValue(product['quantity']);
      final minimum = numberValue(product['minStock']);
      if (status == 'IN_STOCK' && quantity <= minimum) return false;
      if (status == 'LOW_STOCK' && (quantity <= 0 || quantity > minimum)) {
        return false;
      }
      if (status == 'OUT_OF_STOCK' && quantity > 0) return false;
      return true;
    }).toList();
    filtered.sort((a, b) {
      final comparison = switch (sortBy) {
        'quantity' || 'stockQuantity' => numberValue(
          a['quantity'],
        ).compareTo(numberValue(b['quantity'])),
        'price' || 'sellingPrice' => numberValue(
          a['sellingPrice'],
        ).compareTo(numberValue(b['sellingPrice'])),
        _ => (a['name']?.toString() ?? '').toLowerCase().compareTo(
          (b['name']?.toString() ?? '').toLowerCase(),
        ),
      };
      return sortOrder == 'DESC' ? -comparison : comparison;
    });
    return filtered;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    load();
    _loadRole();
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

  Future<void> _loadRole() async {
    try {
      final me = await dio.get('/auth/me');
      if (mounted) setState(() => userRole = me.data['role']?.toString());
    } catch (_) {}
  }

  @override
  void dispose() {
    search.dispose();
    _searchDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 150) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore || !hasMore || _usingCache) return;
    setState(() => loadingMore = true);
    try {
      final response = await dio.get(
        '/products',
        queryParameters: {
          'page': page + 1,
          'limit': 20,
          if (search.text.trim().isNotEmpty) 'search': search.text.trim(),
          if (status.isNotEmpty) 'stockStatus': status,
          if (categoryId != null && categoryId!.isNotEmpty)
            'categoryId': categoryId,
          if (brand != null && brand!.isNotEmpty) 'brand': brand,
          if (priceMin != null) 'priceMin': priceMin,
          if (priceMax != null) 'priceMax': priceMax,
          'sortBy': sortBy == 'quantity'
              ? 'stockQuantity'
              : sortBy == 'price'
              ? 'sellingPrice'
              : sortBy,
          'sortOrder': sortOrder,
        },
      );
      final more = (response.data['data'] as List? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      if (mounted) {
        setState(() {
          products.addAll(more);
          page++;
          loadingMore = false;
        });
        if (_defaultCatalogView) await _cacheCatalog();
      }
    } catch (e) {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      loadError = null;
      page = 1;
      products = [];
    });
    try {
      final responses = await Future.wait([
        dio.get(
          '/products',
          queryParameters: {
            'page': 1,
            'limit': 20,
            if (search.text.trim().isNotEmpty) 'search': search.text.trim(),
            if (status.isNotEmpty) 'stockStatus': status,
            if (categoryId != null && categoryId!.isNotEmpty)
              'categoryId': categoryId,
            if (brand != null && brand!.isNotEmpty) 'brand': brand,
            if (priceMin != null) 'priceMin': priceMin,
            if (priceMax != null) 'priceMax': priceMax,
            'sortBy': sortBy == 'quantity'
                ? 'stockQuantity'
                : sortBy == 'price'
                ? 'sellingPrice'
                : sortBy,
            'sortOrder': sortOrder,
          },
        ),
        dio.get('/categories'),
      ]);
      products = (responses[0].data['data'] as List? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      totalPages = numberValue(
        responses[0].data['meta']?['totalPages'],
      ).toInt().clamp(1, 999999);
      categories = responses[1].data as List;
      loadError = null;
      _usingCache = false;
      if (_defaultCatalogView) await _cacheCatalog();
    } catch (e) {
      try {
        final cached = await _store.loadCatalog();
        if (cached == null) {
          final saleProducts = await _store.loadProducts();
          if (saleProducts.isEmpty) {
            loadError = apiError(e);
          } else {
            products = _filterCachedProducts(saleProducts);
            totalPages = 1;
            loadError = null;
            _usingCache = true;
          }
        } else {
          final cachedProducts = (cached['products'] as List? ?? [])
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList();
          categories = (cached['categories'] as List? ?? [])
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList();
          products = _filterCachedProducts(cachedProducts);
          totalPages = 1;
          loadError = null;
          _usingCache = true;
        }
      } catch (_) {
        loadError =
            'Products are unavailable offline. Reconnect and try again.';
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _onRefreshed() async {
    await load();
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _openFilters() async {
    final result = await FilterSortBottomSheet.show(
      context,
      categoryId: categoryId,
      stockStatus: status,
      brand: brand,
      priceMin: priceMin,
      priceMax: priceMax,
      sortBy: sortBy == 'stockQuantity' ? 'name' : sortBy,
      sortOrder: sortOrder,
      categories: categories,
    );
    if (result == null || !mounted) return;
    setState(() {
      categoryId = result.categoryId;
      status = result.stockStatus;
      brand = result.brand;
      priceMin = result.priceMin;
      priceMax = result.priceMax;
      sortBy = result.sortBy;
      sortOrder = result.sortOrder;
    });
    await load();
  }

  Future<void> addProduct({String? initialBarcode}) async {
    final name = TextEditingController(),
        buying = TextEditingController(),
        selling = TextEditingController(),
        brandCtrl = TextEditingController(),
        minimum = TextEditingController(text: '0'),
        sku = TextEditingController(),
        barcode = TextEditingController(text: initialBarcode ?? '');
    String unit = 'piece';
    String? categoryIdLocal;
    PlatformFile? productPhoto;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
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
                const SizedBox(height: 10),
                TextField(
                  controller: sku,
                  decoration: const InputDecoration(
                    labelText: 'SKU (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: barcode,
                  decoration: const InputDecoration(
                    labelText: 'Barcode (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: brandCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Brand (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: categoryIdLocal,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No category'),
                    ),
                    ...categories.map((c) {
                      final row = Map<String, dynamic>.from(c as Map);
                      return DropdownMenuItem<String?>(
                        value: row['id'].toString(),
                        child: Text(row['name'].toString()),
                      );
                    }),
                  ],
                  onChanged: (v) => setSheet(() => categoryIdLocal = v),
                ),
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
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
                const SizedBox(height: 10),
                TextField(
                  controller: minimum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Low stock threshold',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.pickFiles(
                      type: FileType.image,
                    );
                    if (result.isNotEmpty)
                      setSheet(() => productPhoto = result.single);
                  },
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(
                    productPhoto == null
                        ? 'Choose product photo'
                        : 'Photo: ${productPhoto!.name}',
                  ),
                ),
                if (productPhoto != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: C.ok.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: C.ok.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: C.ok, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Photo selected: ${productPhoto!.name}',
                            style: const TextStyle(fontSize: 12, color: C.ok),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                      final created = await dio.post(
                        '/products',
                        data: {
                          'name': name.text.trim(),
                          'sku': sku.text.trim().isEmpty
                              ? null
                              : sku.text.trim(),
                          'barcode': barcode.text.trim().isEmpty
                              ? null
                              : barcode.text.trim(),
                          'brand': brandCtrl.text.trim().isEmpty
                              ? null
                              : brandCtrl.text.trim(),
                          'categoryId': categoryIdLocal,
                          'unit': unit,
                          'buyingPrice': b,
                          'sellingPrice': s,
                          'minStock': m,
                          'imageUrl': null,
                        },
                      );
                      if (context.mounted) {
                        Navigator.pop(context, true);
                      }
                      if (productPhoto != null) {
                        try {
                          final bytes = await productPhoto!.readAsBytes();
                          await dio.post(
                            '/products/${created.data['id']}/images/upload',
                            data: FormData.fromMap({
                              'file': MultipartFile.fromBytes(
                                bytes,
                                filename: productPhoto!.name,
                              ),
                            }),
                          );
                        } catch (e) {
                          if (mounted) {
                            _message(
                              'Product created, but its photo could not be uploaded: ${apiError(e)}',
                            );
                          }
                        }
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
    brandCtrl.dispose();
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
              const SizedBox(height: 10),
              TextField(
                controller: sku,
                decoration: const InputDecoration(labelText: 'SKU'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: barcode,
                decoration: const InputDecoration(labelText: 'Barcode'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: buying,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Buying price'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: selling,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Selling price'),
              ),
              const SizedBox(height: 10),
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
    if (userRole != 'OWNER' && userRole != 'MANAGER') {
      _message('Archive is restricted to owners and managers.');
      return;
    }
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

  void _startSale(Map<String, dynamic> product) {
    final id = product['id']?.toString();
    if (id == null || id.isEmpty) {
      _message('This product cannot be sold right now.');
      return;
    }
    context.go('/sell?productId=${Uri.encodeComponent(id)}');
  }

  Widget _buildHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Products',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: inkOn(context),
                ),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: TextField(
          controller: search,
          onChanged: (_) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 300), () {
              page = 1;
              load();
            });
          },
          onSubmitted: (_) {
            _searchDebounce?.cancel();
            page = 1;
            load();
          },
          decoration: InputDecoration(
            hintText: 'Search name, SKU or barcode',
            hintStyle: const TextStyle(color: C.muted, fontSize: 14),
            prefixIcon: const Icon(Icons.search, color: C.muted),
            suffixIcon: search.text.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      _searchDebounce?.cancel();
                      search.clear();
                      page = 1;
                      load();
                    },
                    icon: const Icon(Icons.clear, color: C.muted),
                  )
                : IconButton(
                    onPressed: () {
                      _searchDebounce?.cancel();
                      page = 1;
                      load();
                    },
                    icon: const Icon(Icons.arrow_forward, color: C.emerald),
                  ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: C.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: C.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: C.emerald),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
    ],
  );

  Widget _buildCategoryChips() {
    final allCount = products.length;
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: CategoryChip(
              id: 'all',
              name: 'All',
              selected: categoryId == null && status == 'ALL',
              count: allCount,
              onSelected: () {
                setState(() {
                  categoryId = null;
                  status = 'ALL';
                });
                page = 1;
                load();
              },
            ),
          ),
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: CategoryChip(
                id: c['id']?.toString() ?? '',
                name: c['name']?.toString() ?? 'Category',
                selected: categoryId == c['id'],
                count: numberValue((c as Map)['_count']?['products']).toInt(),
                onSelected: () {
                  setState(() {
                    categoryId = c['id']?.toString();
                    status = 'ALL';
                  });
                  page = 1;
                  load();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width < 360
        ? 1
        : width >= 1100
        ? 4
        : width >= 700
        ? 3
        : 2;
    final cardAspectRatio = width < 360
        ? 0.68
        : width < 700
        ? 0.51
        : width < 1100
        ? 0.57
        : 0.66;
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: cardAspectRatio,
        crossAxisSpacing: 16,
        mainAxisSpacing: 18,
      ),
      itemCount: products.length + (loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == products.length) {
          return const Center(
            child: SizedBox(height: 60, child: CircularProgressIndicator()),
          );
        }
        final p = products[i];
        return ProductCard(
          key: ValueKey(p['id']?.toString()),
          product: p,
          userRole: userRole,
          onTap: () => context.go('/products/${p['id']}'),
          onSell: () => _startSale(p),
          onEdit: () => editProduct(p),
          onReceiveStock: () {
            _message('Open receive stock for ${p['name']}');
          },
          onAdjustStock: () {
            _message('Open adjust stock for ${p['name']}');
          },
          onViewMovements: () {
            _message('View movements for ${p['name']}');
          },
          onArchive: () => archiveProduct(p),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            tooltip: 'Scan barcode',
            onPressed: () async {
              final code = await Navigator.push<String>(
                context,
                MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
              );
              if (code == null || !mounted) return;
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
                final cached = products
                    .where((product) => product['barcode']?.toString() == code)
                    .firstOrNull;
                if (cached != null) {
                  _message('Showing the saved product record.');
                  _startSale(cached);
                } else if (e is DioException && e.response?.statusCode == 404) {
                  _message(
                    'No product found. Add this barcode to a new product.',
                  );
                  await addProduct(initialBarcode: code);
                } else {
                  _message(apiError(e));
                }
              }
            },
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: 'Filter & sort',
            onPressed: _openFilters,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Import CSV',
            onPressed: importCsv,
            icon: const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          _buildCategoryChips(),
          if (_usingCache)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0CC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_off_outlined, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline · showing saved products. Stock may have changed; sales need a connection.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: loading
                ? ListView(
                    children: [
                      ProductSkeletonCard(),
                      ProductSkeletonCard(),
                      ProductSkeletonCard(),
                      ProductSkeletonCard(),
                    ],
                  )
                : loadError != null
                ? ErrorState(message: loadError!, onRetry: load)
                : RefreshIndicator(
                    onRefresh: _onRefreshed,
                    child: products.isEmpty
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
                              const SizedBox(height: 16),
                              const Text(
                                'No products found.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Add your first product or change filters.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: C.muted),
                              ),
                              const SizedBox(height: 18),
                              FilledButton.icon(
                                onPressed: () => addProduct(),
                                icon: const Icon(Icons.add),
                                label: const Text('Add your first product'),
                              ),
                            ],
                          )
                        : _buildGrid(),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => addProduct(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
