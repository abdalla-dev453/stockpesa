import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class ProductSkeletonCard extends StatelessWidget {
  const ProductSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 1,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: C.border,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: _Line(widthFactor: 0.85, height: 18),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: _Line(widthFactor: 0.6, height: 12),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: _Line(widthFactor: 0.5, height: 14),
            ),
          ],
        ),
      );
}

class _Line extends StatelessWidget {
  const _Line({required this.widthFactor, required this.height});
  final double widthFactor;
  final double height;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, constraints) => Container(
          height: height,
          width: constraints.maxWidth * widthFactor,
          decoration: BoxDecoration(color: C.border.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
        ),
      );
}
