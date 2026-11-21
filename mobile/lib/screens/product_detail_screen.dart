import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets/product_image.dart';
import '../features/products/data/products_repository.dart';
import '../features/products/widgets/product_card.dart'
    show stockStatusOf, stockStatusColor, stockStatusLabel;

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;
  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  late Future<List<dynamic>> data = _load();
  int _heroIndex = 0;
  Future<List<dynamic>> _load() => Future.wait([
        ref.read(productsRepositoryProvider).get(widget.productId),
        dio.get('/products/${widget.productId}/images').then((r) => (r.data as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()),
        dio.get('/products/${widget.productId}/movements').then((r) => (r.data as List? ?? [])),
        dio.get('/products/${widget.productId}/variants').then((r) => (r.data as List? ?? [])),
      ]);

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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (url.text.trim().startsWith('https://')) {
                Navigator.pop(context, url.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    try {
      await dio.post('/products/${widget.productId}/images', data: {'url': value});
      setState(() => data = _load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    }
  }

  Future<void> _uploadImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isEmpty) return;
    final file = result.single;
    try {
      final bytes = await file.readAsBytes();
      await dio.post('/products/${widget.productId}/images/upload', data: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: file.name),
      }));
      if (mounted) setState(() => data = _load());
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
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
                      const SizedBox(height: 12),
                      TextButton(onPressed: () => setState(() => data = _load()), child: const Text('Try again')),
                    ],
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final product = Map<String, dynamic>.from(snapshot.data![0] as Map);
            final images = (snapshot.data![1] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            final movements = (snapshot.data![2] as List)
                .where((row) =>
                    row['productId'] == widget.productId ||
                    row['product']?['id'] == widget.productId)
                .toList()
              ..sort((a, b) {
                final da = DateTime.tryParse((a['createdAt'] ?? '').toString()) ?? DateTime(1970);
                final db = DateTime.tryParse((b['createdAt'] ?? '').toString()) ?? DateTime(1970);
                return db.compareTo(da);
              });
            final variants = (snapshot.data![3] as List? ?? []);
            final quantity = numberValue(product['quantity']);
            final buying = numberValue(product['buyingPrice']);
            final selling = numberValue(product['sellingPrice']);
            final wholesale = numberValue(product['wholesalePrice']);
            final minStock = numberValue(product['minStock']);
            final status = stockStatusOf(product);
            final statusColor = stockStatusColor(status);
            final stockValue = quantity * buying;
            final retailValue = quantity * selling;
            final name = product['name']?.toString() ?? 'Product';
            final imageUrl = ProductImage.resolve(product['imageUrl']);
            final heroImage = images.isNotEmpty
                ? ProductImage.resolve(images[_heroIndex.clamp(0, images.length - 1)]['url'])
                : imageUrl;

            return Scaffold(
              appBar: AppBar(
                title: Text(name, overflow: TextOverflow.ellipsis, maxLines: 1),
                actions: [
                  IconButton(
                    tooltip: 'Edit product',
                    onPressed: () => context.go('/products/${widget.productId}/edit'),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              body: ListView(
                children: [
                  // Hero image
                  Stack(
                    children: [
                      SizedBox(
                        height: 260,
                        width: double.infinity,
                        child: heroImage == null
                            ? Container(
                                color: C.border,
                                alignment: Alignment.center,
                                child: const Icon(Icons.inventory_2_outlined, size: 56, color: C.muted),
                              )
                            : ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(20),
                                  bottomRight: Radius.circular(20),
                                ),
                                child: ProductImage(
                                  imageUrl: heroImage,
                                  fit: BoxFit.cover,
                                ),
                              ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                stockStatusLabel(status),
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (images.length > 1)
                    SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: images.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, index) {
                          final image = images[index];
                          final url = ProductImage.resolve(image['url']);
                          return GestureDetector(
                            onTap: () => setState(() => _heroIndex = index),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: ProductImage(
                                    imageUrl: url,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                if (index == 0)
                                  Positioned(
                                    right: 2,
                                    top: 2,
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: C.emerald,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.check, color: Colors.white, size: 16),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: Theme.of(context).textTheme.headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: C.border,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          product['category']?['name']?.toString() ?? 'Uncategorized',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: mutedOn(context)),
                                        ),
                                      ),
                                      if ((product['brand'] ?? '').toString().isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: C.emerald.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: C.emerald.withValues(alpha: 0.3)),
                                          ),
                                          child: Text(
                                            'Brand · ${product['brand']}',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.emerald),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => context.go('/products/${widget.productId}/edit'),
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Edit'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(36),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'SKU: ${product['sku'] ?? '—'}   ·   Barcode: ${product['barcode'] ?? '—'}   ·   Unit: ${product['unit'] ?? 'piece'}',
                          style: TextStyle(fontSize: 12, color: mutedOn(context)),
                        ),
                        if ((product['description'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('Description', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: mutedOn(context))),
                          const SizedBox(height: 6),
                          Text(
                            product['description'].toString(),
                            style: TextStyle(fontSize: 14, height: 1.4, color: inkOn(context)),
                          ),
                        ],
                        const SizedBox(height: 16),
                        // Pricing
                        Row(
                          children: [
                            Expanded(
                              child: _ValueCard(
                                title: 'Selling price',
                                value: kes(selling),
                                big: true,
                                color: C.ink,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ValueCard(
                                title: 'Buying price',
                                value: kes(buying),
                                color: C.muted,
                              ),
                            ),
                            if (wholesale > 0)
                              Expanded(
                                child: _ValueCard(
                                  title: 'Wholesale',
                                  value: kes(wholesale),
                                  color: C.muted,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Stock
                        Card(
                          elevation: 1,
                          shadowColor: Colors.black12,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Stock', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: mutedOn(context))),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${quantity.toIntAsFixed(0)} ${(product['unit'] ?? 'piece') == 'piece' ? 'pcs' : product['unit']}',
                                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Minimum level: ${minStock.toIntAsFixed(0)}',
                                            style: TextStyle(fontSize: 12, color: mutedOn(context)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
                                      ),
                                      child: Text(
                                        stockStatusLabel(status),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(child: _ValueCard(title: 'Stock value', value: kes(stockValue), color: C.muted)),
                                    const SizedBox(width: 10),
                                    Expanded(child: _ValueCard(title: 'Retail value', value: kes(retailValue), color: C.muted)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Actions
                        Text('Actions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: mutedOn(context))),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: quantity > 0
                                    ? () => context.go('/sell?productId=${widget.productId}')
                                    : null,
                                icon: const Icon(Icons.add_shopping_cart, size: 18),
                                label: const Text('Sell'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Receive stock opened')),
                                  );
                                },
                                icon: const Icon(Icons.inventory_outlined, size: 18),
                                label: const Text('Receive Stock'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Adjust stock opened')),
                                  );
                                },
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: const Text('Adjust Stock'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => context.go('/products/${widget.productId}/edit'),
                                icon: const Icon(Icons.edit_note_outlined, size: 18),
                                label: const Text('Edit Product'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Images management
                        if (images.isNotEmpty)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Images', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: mutedOn(context))),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _addImage,
                                    icon: const Icon(Icons.image_outlined, size: 18),
                                    label: const Text('Add image URL'),
                                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(36), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: _uploadImage,
                                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                                    label: const Text('Upload photo'),
                                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(36), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        // Movements
                        Text('Recent stock movements', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: mutedOn(context))),
                        const SizedBox(height: 8),
                        if (movements.isEmpty)
                          const Card(child: ListTile(title: Text('No stock movements yet')))
                        else
                          ...movements.take(15).map((row) {
                            final r = Map<String, dynamic>.from(row as Map);
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                leading: const Icon(Icons.swap_vert_circle_outlined, color: C.muted),
                                title: Text(
                                  '${r['kind'] ?? r['type'] ?? 'Stock movement'}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                subtitle: Text(
                                  '${r['reason'] ?? ''} ${r['quantityChange'] ?? r['quantity'] ?? ''} · ${r['createdAt'] ?? ''}',
                                  style: const TextStyle(fontSize: 11, color: C.muted),
                                ),
                              ),
                            );
                          }),
                        if (variants.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('Variants', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: mutedOn(context))),
                          const SizedBox(height: 8),
                          ...variants.map((v) {
                            final variant = Map<String, dynamic>.from(v as Map);
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              child: ListTile(
                                title: Text(variant['name']?.toString() ?? 'Variant'),
                                subtitle: Text('${variant['sku'] ?? variant['barcode'] ?? '—'} · ${kes(numberValue(variant['sellingPrice']))}'),
                                trailing: Text('${numberValue(variant['quantity'])} ${variant['unit']}'),
                              ),
                            );
                          }),
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: quantity > 0
                    ? () => context.go('/sell?productId=${widget.productId}')
                    : null,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Sell'),
              ),
            );
          },
        );
  }
}

class _ValueCard extends StatelessWidget {
  const _ValueCard({required this.title, required this.value, this.color, this.big = false});
  final String title;
  final String value;
  final Color? color;
  final bool big;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: C.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: mutedOn(context))),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: big ? 17 : 14,
                fontWeight: FontWeight.w800,
                color: color ?? C.ink,
              ),
            ),
          ],
        ),
      );
}

extension _NumExt on num {
  String toIntAsFixed([int fractionDigits = 0]) {
    final d = toDouble();
    if (d == d.roundToDouble()) return d.round().toStringAsFixed(fractionDigits);
    return d.toStringAsFixed(fractionDigits);
  }
}
