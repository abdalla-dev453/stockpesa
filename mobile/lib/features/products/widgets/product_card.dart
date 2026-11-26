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
    this.onSell,
    this.onEdit,
    this.onReceiveStock,
    this.onAdjustStock,
    this.onViewMovements,
    this.onArchive,
    this.userRole,
  });

  final Map<String, dynamic> product;
  final VoidCallback onTap;
  final VoidCallback? onSell;
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

  Widget _statusBadge(
    StockStatus status,
    Color color, {
    bool compact = false,
  }) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 5 : 8,
      vertical: compact ? 3 : 4,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(
      stockStatusLabel(status),
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: compact ? 8 : 9,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    ),
  );

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
      if (name.toLowerCase() == 'fast-moving' ||
          name.toLowerCase() == 'fast moving') {
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
    final category =
        (product['category'] as Map?)?['name']?.toString() ?? 'Uncategorized';
    final badges = _badges();

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
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 1.25,
                  child: ProductImage(
                    imageUrl: imageUrl,
                    borderRadius: BorderRadius.zero,
                    fit: BoxFit.cover,
                  ),
                ),
                if (badges.isNotEmpty)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Wrap(spacing: 6, runSpacing: 6, children: badges),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: mutedOn(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 150;
                        final quantity = Text(
                          _unitLine(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: mutedOn(context),
                            fontWeight: FontWeight.w700,
                          ),
                        );
                        final price = Text(
                          _price(),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        );
                        final badge = _statusBadge(
                          status,
                          color,
                          compact: compact,
                        );
                        if (compact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              price,
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Expanded(child: quantity),
                                  const SizedBox(width: 4),
                                  badge,
                                ],
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  price,
                                  const SizedBox(height: 2),
                                  quantity,
                                ],
                              ),
                            ),
                            badge,
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            // Actions
            if (onSell != null ||
                _canArchive ||
                onEdit != null ||
                onReceiveStock != null ||
                onAdjustStock != null ||
                onViewMovements != null)
              _ActionBar(
                onSell: onSell,
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
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
    ),
  );
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.product,
    this.onSell,
    this.onEdit,
    this.onReceiveStock,
    this.onAdjustStock,
    this.onViewMovements,
    this.onArchive,
  });

  final Map<String, dynamic> product;
  final VoidCallback? onSell;
  final VoidCallback? onEdit;
  final VoidCallback? onReceiveStock;
  final VoidCallback? onAdjustStock;
  final VoidCallback? onViewMovements;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        children: [
          if (onSell != null)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onSell,
                icon: Icon(
                  Icons.point_of_sale_outlined,
                  size: compact ? 16 : 18,
                ),
                label: const Text(
                  'Sell',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 12),
                  side: BorderSide(color: C.border),
                  foregroundColor: C.emerald,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (onSell != null) const SizedBox(width: 8),
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
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit product'),
                  ),
                if (onReceiveStock != null)
                  const PopupMenuItem(
                    value: 'receive',
                    child: Text('Receive stock'),
                  ),
                if (onAdjustStock != null)
                  const PopupMenuItem(
                    value: 'adjust',
                    child: Text('Adjust stock'),
                  ),
                if (onViewMovements != null)
                  const PopupMenuItem(
                    value: 'movements',
                    child: Text('View stock movements'),
                  ),
                if (onArchive != null)
                  const PopupMenuItem(
                    value: 'archive',
                    child: Text('Archive product'),
                  ),
              ],
              child: Container(
                alignment: Alignment.center,
                child: Icon(Icons.more_vert, size: 20, color: mutedOn(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
