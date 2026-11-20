import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/product_image.dart';

/// Stock status derived from on-hand quantity vs the minimum stock threshold.
enum StockStatus { inStock, lowStock, outOfStock }

StockStatus stockStatusOf(Map<String, dynamic> p) {
  final quantity = numberValue(p['quantity']);
  final minStock = numberValue(p['minStock']);
  if (quantity <= 0) return StockStatus.outOfStock;
  if (quantity <= minStock) return StockStatus.lowStock;
  return StockStatus.inStock;
}

Color stockStatusColor(StockStatus status) {
  switch (status) {
    case StockStatus.inStock:
      return C.ok;
    case StockStatus.lowStock:
      return C.warn;
    case StockStatus.outOfStock:
      return C.danger;
  }
}

String stockStatusLabel(StockStatus status) {
  switch (status) {
    case StockStatus.inStock:
      return 'In Stock';
    case StockStatus.lowStock:
      return 'Low Stock';
    case StockStatus.outOfStock:
      return 'Out of Stock';
  }
}

/// Image-first product catalogue card for the Products screen.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onQuickAdd,
    this.onEdit,
    this.onReceiveStock,
    this.onAdjustStock,
    this.onViewMovements,
    this.onArchive,
    this.userRole,
  });

  final Map<String, dynamic> product;
  final VoidCallback onTap;
  final VoidCallback? onQuickAdd;
  final VoidCallback? onEdit;
  final VoidCallback? onReceiveStock;
  final VoidCallback? onAdjustStock;
  final VoidCallback? onViewMovements;
  final VoidCallback? onArchive;
  final String? userRole;

  bool get _canArchive =>
      userRole == null || userRole == 'OWNER' || userRole == 'MANAGER';

  String _price() => kes(numberValue(product['sellingPrice']));

  String _unitLine() {
    final quantity = numberValue(product['quantity']);
    final unit = (product['unit'] ?? 'piece').toString();
    final label = unit == 'piece' ? 'pcs' : unit;
    return '${quantity.toInt()} $label';
  }

  List<Widget> _badges() {
    final badges = <Widget>[];
    final promo = numberValue(product['promotionalPrice']);
    final selling = numberValue(product['sellingPrice']);
    if (promo > 0 && promo < selling) {
      badges.add(const _Chip(label: 'Sale', color: C.coral));
    }
    final tags = (product['productTags'] as List? ?? []);
    for (final tag in tags) {
      final tagData = tag is Map ? tag['tag'] : null;
      final name = (tagData is Map ? tagData['name'] : null)?.toString() ?? '';
      if (name.toLowerCase() == 'fast-moving' || name.toLowerCase() == 'fast moving') {
        badges.add(const _Chip(label: 'Fast Moving', color: C.emerald));
      } else if (name.toLowerCase() == 'new') {
        badges.add(const _Chip(label: 'New', color: C.coral));
      }
    }
    return badges;
  }

  @override
  Widget build(BuildContext context) {
    final status = stockStatusOf(product);
    final color = stockStatusColor(status);
    final imageUrl = ProductImage.resolve(product['imageUrl']);
    final name = product['name']?.toString() ?? 'Product';
    final category = (product['category'] as Map?)?['name']?.toString() ?? 'Uncategorized';

    return Card(
      key: ValueKey(product['id']?.toString()),
      elevation: 1,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            AspectRatio(
              aspectRatio: 4 / 5,
              child: ProductImage(
                imageUrl: imageUrl,
                borderRadius: BorderRadius.zero,
                fit: BoxFit.cover,
              ),
            ),
            if (_badges().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: _badges(),
                ),
              ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: C.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _price(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _unitLine(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: C.muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: color.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            stockStatusLabel(status),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Actions
            if (onQuickAdd != null || _canArchive || onEdit != null || onReceiveStock != null || onAdjustStock != null || onViewMovements != null)
              _ActionBar(
                onQuickAdd: onQuickAdd,
                onEdit: onEdit,
                onReceiveStock: onReceiveStock,
                onAdjustStock: onAdjustStock,
                onViewMovements: onViewMovements,
                onArchive: _canArchive ? onArchive : null,
                product: product,
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration:                 BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      );
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.product,
    this.onQuickAdd,
    this.onEdit,
    this.onReceiveStock,
    this.onAdjustStock,
    this.onViewMovements,
    this.onArchive,
  });

  final Map<String, dynamic> product;
  final VoidCallback? onQuickAdd;
  final VoidCallback? onEdit;
  final VoidCallback? onReceiveStock;
  final VoidCallback? onAdjustStock;
  final VoidCallback? onViewMovements;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          if (onQuickAdd != null)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onQuickAdd,
                icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                label: const Text('Add', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  side: BorderSide(color: C.border),
                  foregroundColor: C.emerald,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          if (onQuickAdd != null) const SizedBox(width: 8),
          Expanded(
            child: PopupMenuButton<String>(
              tooltip: 'More actions',
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    onEdit?.call();
                  case 'receive':
                    onReceiveStock?.call();
                  case 'adjust':
                    onAdjustStock?.call();
                  case 'movements':
                    onViewMovements?.call();
                  case 'archive':
                    onArchive?.call();
                }
              },
              itemBuilder: (_) => [
                if (onEdit != null)
                  const PopupMenuItem(value: 'edit', child: Text('Edit product')),
                if (onReceiveStock != null)
                  const PopupMenuItem(value: 'receive', child: Text('Receive stock')),
                if (onAdjustStock != null)
                  const PopupMenuItem(value: 'adjust', child: Text('Adjust stock')),
                if (onViewMovements != null)
                  const PopupMenuItem(value: 'movements', child: Text('View stock movements')),
                if (onArchive != null)
                  const PopupMenuItem(value: 'archive', child: Text('Archive product')),
              ],
              child: Container(
                alignment: Alignment.center,
                child: const Icon(Icons.more_vert, size: 20, color: C.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
