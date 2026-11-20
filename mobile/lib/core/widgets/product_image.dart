import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../theme.dart';

class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  static String? resolve(Object? value) {
    final url = value?.toString();
    if (url == null || url.isEmpty) return null;
    return url.startsWith('http') ? url : '$apiBase$url';
  }

  String? get url => resolve(imageUrl);

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final radius = borderRadius;
    // Responsive cache sizing: render at display size × DPR, with sensible
    // defaults when width/height are not specified.
    final cacheW = (width ?? 400) * dpr;
    final cacheH = (height ?? 500) * dpr;
    final child = url == null
        ? const _Placeholder()
        : CachedNetworkImage(
            imageUrl: url!,
            fit: fit,
            width: width,
            height: height,
            cacheKey: url,
            memCacheWidth: cacheW.round(),
            memCacheHeight: cacheH.round(),
            placeholder: (_, __) => const _Placeholder(),
            errorWidget: (_, __, ___) => const _Error(),
          );
    return radius == null ? child : ClipRRect(borderRadius: radius, child: child);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) => Container(
        color: C.border,
        alignment: Alignment.center,
        child: Icon(Icons.inventory_2_outlined, size: 34, color: C.muted.withValues(alpha: 0.55)),
      );
}

class _Error extends StatelessWidget {
  const _Error();
  @override
  Widget build(BuildContext context) => Container(
        color: C.border,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, color: C.muted, size: 34),
      );
}
