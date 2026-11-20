import 'package:flutter/material.dart';

import '../../../core/theme.dart';

class FilterResult {
  const FilterResult({
    this.categoryId,
    this.stockStatus = 'ALL',
    this.brand,
    this.priceMin,
    this.priceMax,
    this.sortBy = 'name',
    this.sortOrder = 'ASC',
  });

  final String? categoryId;
  final String stockStatus;
  final String? brand;
  final num? priceMin;
  final num? priceMax;
  final String sortBy;
  final String sortOrder;
}

class FilterSortBottomSheet extends StatefulWidget {
  const FilterSortBottomSheet({
    super.key,
    this.categoryId,
    this.stockStatus = 'ALL',
    this.brand,
    this.priceMin,
    this.priceMax,
    this.sortBy = 'name',
    this.sortOrder = 'ASC',
    this.categories = const [],
  });

  final String? categoryId;
  final String stockStatus;
  final String? brand;
  final num? priceMin;
  final num? priceMax;
  final String sortBy;
  final String sortOrder;
  final List<dynamic> categories;

  static Future<FilterResult?> show(BuildContext context, {
    String? categoryId,
    String stockStatus = 'ALL',
    String? brand,
    num? priceMin,
    num? priceMax,
    String sortBy = 'name',
    String sortOrder = 'ASC',
    required List<dynamic> categories,
  }) {
    return showModalBottomSheet<FilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilterSortBottomSheet(
        categoryId: categoryId,
        stockStatus: stockStatus,
        brand: brand,
        priceMin: priceMin,
        priceMax: priceMax,
        sortBy: sortBy,
        sortOrder: sortOrder,
        categories: categories,
      ),
    );
  }

  @override
  State<FilterSortBottomSheet> createState() => _FilterSortBottomSheetState();
}

class _FilterSortBottomSheetState extends State<FilterSortBottomSheet> {
  late String? _categoryId;
  late String _stockStatus;
  late String? _brand;
  late num? _priceMin;
  late num? _priceMax;
  late String _sortBy;
  late String _sortOrder;
  final _brandCtrl = TextEditingController();
  final _priceMinCtrl = TextEditingController();
  final _priceMaxCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categoryId;
    _stockStatus = widget.stockStatus;
    _brand = widget.brand;
    _priceMin = widget.priceMin;
    _priceMax = widget.priceMax;
    _sortBy = widget.sortBy;
    _sortOrder = widget.sortOrder;
    _brandCtrl.text = _brand ?? '';
    _priceMinCtrl.text = _priceMin?.toString() ?? '';
    _priceMaxCtrl.text = _priceMax?.toString() ?? '';
  }

  @override
  void dispose() {
    _brandCtrl.dispose();
    _priceMinCtrl.dispose();
    _priceMaxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 6),
            Container(
              height: 4,
              width: 36,
              decoration: BoxDecoration(color: C.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Filter & sort',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _categoryId = null;
                        _stockStatus = 'ALL';
                        _brand = null;
                        _priceMin = null;
                        _priceMax = null;
                      });
                    },
                    child: const Text('Reset filters'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const Text('Stock status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.muted)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['ALL', 'IN_STOCK', 'LOW_STOCK', 'OUT_OF_STOCK'].map((s) {
                      final selected = _stockStatus == s;
                      return ChoiceChip(
                        label: Text(s.replaceAll('_', ' ')),
                        selected: selected,
                        onSelected: (_) => setState(() => _stockStatus = s),
                        selectedColor: C.emerald.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: selected ? C.emerald : C.ink,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                        side: BorderSide(color: selected ? C.emerald : C.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        backgroundColor: Colors.white,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.muted)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: _categoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
                      ...widget.categories.map((c) {
                        final row = Map<String, dynamic>.from(c as Map);
                        return DropdownMenuItem<String?>(
                          value: row['id']?.toString(),
                          child: Text(row['name']?.toString() ?? 'Category', overflow: TextOverflow.ellipsis),
                        );
                      }),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  const SizedBox(height: 16),
                  const Text('Brand (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.muted)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _brandCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Brand',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    onChanged: (v) => setState(() => _brand = v.trim().isEmpty ? null : v.trim()),
                  ),
                  const SizedBox(height: 16),
                  const Text('Price range (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.muted)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: TextFormField(
                            controller: _priceMinCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Min',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                            onChanged: (v) => setState(() => _priceMin = num.tryParse(v)),
                          ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: TextFormField(
                            controller: _priceMaxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Max',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            ),
                            onChanged: (v) => setState(() => _priceMax = num.tryParse(v)),
                          ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Sort by', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.muted)),
                  const SizedBox(height: 8),
                  RadioGroup<String>(
                    groupValue: '${_sortBy}|$_sortOrder',
                    onChanged: (v) {
                      if (v == null) return;
                      final parts = v.split('|');
                      setState(() {
                        _sortBy = parts[0];
                        _sortOrder = parts[1];
                      });
                    },
                    child: Column(
                      children: _sortOptions
                          .map(
                            (o) => RadioListTile<String>(
                              value: '${o.value}|${o.order}',
                              title: Text(o.label),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context, FilterResult(
                        categoryId: _categoryId,
                        stockStatus: _stockStatus,
                        brand: _brand,
                        priceMin: _priceMin,
                        priceMax: _priceMax,
                        sortBy: _sortBy,
                        sortOrder: _sortOrder,
                      ));
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SortOption {
  const _SortOption(this.label, this.value, this.order);
  final String label;
  final String value;
  final String order;
}

List<_SortOption> get _sortOptions => const [
  _SortOption('Name A–Z', 'name', 'ASC'),
  _SortOption('Name Z–A', 'name', 'DESC'),
  _SortOption('Price low to high', 'sellingPrice', 'ASC'),
  _SortOption('Price high to low', 'sellingPrice', 'DESC'),
  _SortOption('Stock low to high', 'stockQuantity', 'ASC'),
  _SortOption('Recently added', 'createdAt', 'DESC'),
  _SortOption('Best selling', 'createdAt', 'DESC'),
];
