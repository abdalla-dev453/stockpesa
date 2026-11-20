import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.id,
    required this.name,
    required this.selected,
    required this.count,
    required this.onSelected,
  });

  final String id;
  final String name;
  final bool selected;
  final int count;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
        avatar: selected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
        label: Text(
          '$name ${count > 0 ? '($count)' : ''}',
          style: TextStyle(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? Colors.white : C.ink,
            fontSize: 13,
          ),
        ),
        selected: selected,
        onSelected: (_) => onSelected(),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(color: selected ? C.emerald : C.border, width: 1),
        backgroundColor: Colors.white,
        selectedColor: C.emerald,
        checkmarkColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      );
}
