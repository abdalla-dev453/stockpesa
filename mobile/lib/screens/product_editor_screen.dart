import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../core/widgets/product_image.dart';
import '../features/products/data/products_repository.dart';

class ProductEditorScreen extends ConsumerStatefulWidget {
  const ProductEditorScreen({super.key, required this.productId});
  final String productId;
  @override
  ConsumerState<ProductEditorScreen> createState() => _ProductEditorScreenState();
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
      minimum = TextEditingController(),
      imageUrl = TextEditingController();
  List<dynamic> categories = [];
  String? categoryId;
  bool active = true;
  bool loading = true, saving = false;
  String? currentImageUrl;
  List<Map<String, dynamic>> images = [];
  @override
  void initState() {
    super.initState();
    _load();
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
    imageUrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ref.read(productsRepositoryProvider).get(widget.productId),
        ref.read(productsRepositoryProvider).categories(),
        dio.get('/products/${widget.productId}/images').then((r) => (r.data as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList()),
      ]);
      final product = results[0] as Map<String, dynamic>;
      categories = results[1] as List<dynamic>;
      images = results[2] as List<Map<String, dynamic>>;
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
      currentImageUrl = product['imageUrl']?.toString();
      imageUrl.text = currentImageUrl ?? '';
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    }
    if (mounted) setState(() => loading = false);
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
        'imageUrl': imageUrl.text.trim().isEmpty ? null : imageUrl.text.trim(),
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

  Future<void> _setMainImageUrl() async {
    final value = await showDialog<String?>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Main image URL'),
        content: TextField(
          controller: TextEditingController(text: currentImageUrl ?? ''),
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Secure image URL (https://)',
            hintText: 'https://example.com/product.jpg',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(c, ''),
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, imageUrl.text.trim().isEmpty ? null : imageUrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    if (value.isNotEmpty && !value.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use a secure HTTPS URL')),
      );
      return;
    }
    try {
      await dio.patch(
        '/products/${widget.productId}/main-image',
        data: {'imageUrl': value.isEmpty ? null : value},
      );
      setState(() => currentImageUrl = value.isEmpty ? null : value);
      imageUrl.text = value;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Main image updated')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    }
  }

  Future<void> _uploadPhoto() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result.isEmpty) return;
    final file = result.single;
    try {
      final bytes = await file.readAsBytes();
      await dio.post(
        '/products/${widget.productId}/images/upload',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: file.name),
        }),
      );
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo uploaded')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
    }
  }

  Future<void> _removeImage(Map<String, dynamic> image) async {
    try {
      await dio.delete(
        '/products/${widget.productId}/images/${image['id']}',
      );
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image removed')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(error))));
      }
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
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          // Main image preview + controls
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Main product image',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: mutedOn(context)),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: currentImageUrl == null
                        ? const Center(child: _Placeholder())
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: ProductImage(
                                  imageUrl: currentImageUrl,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.change_circle_outlined, color: Colors.white, size: 20),
                                    onPressed: _setMainImageUrl,
                                    tooltip: 'Change main image',
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _setMainImageUrl,
                        icon: const Icon(Icons.link_outlined, size: 18),
                        label: const Text('Set image URL'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(36),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _uploadPhoto,
                        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                        label: const Text('Upload photo'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(36),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                  if (images.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Additional images', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: mutedOn(context))),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 64,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: images.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, index) {
                          final image = images[index];
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: ProductImage(
                                  imageUrl: ProductImage.resolve(image['url']),
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: GestureDetector(
                                  onTap: () => _removeImage(image),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: C.danger,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Product name'),
            validator: (v) => v == null || v.trim().isEmpty ? 'Enter a product name' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: sku,
            decoration: const InputDecoration(labelText: 'SKU (optional)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: barcode,
            decoration: const InputDecoration(labelText: 'Barcode (optional)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: brand,
            decoration: const InputDecoration(labelText: 'Brand (optional)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: unit,
            decoration: const InputDecoration(labelText: 'Unit'),
            validator: (v) => v == null || v.trim().isEmpty ? 'Enter a unit' : null,
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: buying,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Buying price'),
                  validator: _nonNegative,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: selling,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Selling price'),
                  validator: _nonNegative,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: minimum,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Low stock threshold'),
            validator: _nonNegative,
          ),
          const SizedBox(height: 12),
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

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) => Container(
        color: C.border,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, color: mutedOn(context), size: 40),
            const SizedBox(height: 6),
            Text('No image', style: TextStyle(fontSize: 12, color: mutedOn(context))),
          ],
        ),
      );
}
