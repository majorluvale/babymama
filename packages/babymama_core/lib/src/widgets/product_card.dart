import 'package:flutter/material.dart';

import '../catalog_options.dart';
import '../format.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import 'common.dart';

/// Height of the text block under the photo; grids add it to the 3:4 photo to align every card.
const kProductCardInfoHeight = 92.0;

/// Product tile: photo (the second photo shows on mouse hover), category, title, size / condition and price.
class ProductCard extends StatefulWidget {
  const ProductCard({super.key, required this.product, this.onTap, this.onFavorite, this.favorite, this.width});

  final Product product;
  final VoidCallback? onTap;
  final VoidCallback? onFavorite;

  /// Overrides `product.isFavorite` (the apps keep favorites in a shared controller).
  final bool? favorite;
  final double? width;

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final lang = context.lang;
    final isFavorite = widget.favorite ?? p.isFavorite;
    final secondImage = p.images.length > 1 ? p.images[1] : null;
    final details = [
      p.size,
      if (p.color != null) context.colorName(p.color!),
      context.tr('condition_${p.condition}'),
    ].whereType<String>().join(' · ');
    final discount = p.compareAtPrice != null && p.compareAtPrice! > p.price;

    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      BmImage(p.image),
                      if (secondImage != null)
                        AnimatedOpacity(
                          opacity: _hover ? 1 : 0,
                          duration: const Duration(milliseconds: 250),
                          child: BmImage(secondImage),
                        ),
                      if (!p.isAvailable)
                        Container(
                          color: Colors.white.withAlpha(170),
                          alignment: Alignment.center,
                          child: Text(context.tr('sold_out').toUpperCase(),
                              style: const TextStyle(color: BmColors.ink, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                        ),
                      if (p.isAvailable && p.isNew)
                        Positioned(left: 8, top: 8, child: _Badge(text: context.tr('badge_new'), color: BmColors.ink)),
                      if (discount)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: _Badge(
                            text: '-${(((p.compareAtPrice! - p.price) / p.compareAtPrice!) * 100).round()}%',
                            color: BmColors.danger,
                          ),
                        ),
                      if (widget.onFavorite != null)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Material(
                            color: Colors.white,
                            shape: const CircleBorder(),
                            elevation: 1,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: widget.onFavorite,
                              child: Padding(
                                padding: const EdgeInsets.all(7),
                                child: Icon(
                                  isFavorite ? Icons.favorite : Icons.favorite_border,
                                  size: 18,
                                  color: isFavorite ? BmColors.accent : BmColors.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: kProductCardInfoHeight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (p.category?.path(lang) ?? '').toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: BmColors.muted, fontSize: 10.5, letterSpacing: 0.8, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          decoration: _hover ? TextDecoration.underline : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: BmColors.muted, fontSize: 12)),
                      const Spacer(),
                      Row(
                        children: [
                          Text(formatKes(p.price),
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: discount ? BmColors.danger : BmColors.ink)),
                          if (discount) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                formatKes(p.compareAtPrice!),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: BmColors.muted, fontSize: 12, decoration: TextDecoration.lineThrough),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
      child: Text(text.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
    );
  }
}
