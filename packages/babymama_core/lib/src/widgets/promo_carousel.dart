import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// Auto-playing carousel with arrows and page dots (no external package, works on web, Android and iOS).
/// Autoplay pauses while the mouse is over it.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({
    super.key,
    required this.slides,
    this.height = 200,
    this.interval = const Duration(seconds: 6),
  });

  final List<Widget> slides;
  final double height;
  final Duration interval;

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<PromoCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (!_hover) _go(_index + 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _go(int page) {
    final count = widget.slides.length;
    if (!mounted || count < 2 || !_controller.hasClients) return;
    _controller.animateToPage(page % count, duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.slides.length;
    if (count == 0) return const SizedBox.shrink();
    return MouseRegion(
      onEnter: (_) => _hover = true,
      onExit: (_) => _hover = false,
      child: SizedBox(
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: count,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => widget.slides[i],
              ),
              if (count > 1) ...[
                Positioned(left: 12, top: 0, bottom: 0, child: Center(child: CarouselArrow(left: true, onPressed: () => _go(_index - 1 + count)))),
                Positioned(right: 12, top: 0, bottom: 0, child: Center(child: CarouselArrow(left: false, onPressed: () => _go(_index + 1)))),
                Positioned(
                  bottom: 14,
                  right: 20,
                  child: Row(
                    children: List.generate(
                      count,
                      (i) => GestureDetector(
                        onTap: () => _go(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _index ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _index ? BmColors.ink : BmColors.ink.withAlpha(60),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Round white arrow button used by the carousel and the product gallery.
class CarouselArrow extends StatelessWidget {
  const CarouselArrow({super.key, required this.left, required this.onPressed, this.size = 40});

  final bool left;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withAlpha(235),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(left ? Icons.chevron_left : Icons.chevron_right, color: BmColors.ink, size: size * 0.6),
        ),
      ),
    );
  }
}

/// A single slide. Wide screens: text on a plain panel beside the photo. Phones: photo with a text card at the bottom.
/// Either way the text never sits directly on the photo, so it stays readable.
class CarouselSlide extends StatelessWidget {
  const CarouselSlide({
    super.key,
    required this.imageUrl,
    required this.title,
    this.subtitle,
    this.badge,
    this.cta,
    this.onTap,
  });

  final String? imageUrl;
  final String title;
  final String? subtitle;
  final String? badge;
  final String? cta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 700;
      final text = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badge != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(badge!.toUpperCase(),
                  style: const TextStyle(color: BmColors.accent, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            ),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: BmColors.ink, fontSize: wide ? 38 : 20, height: 1.1, fontWeight: FontWeight.w800),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            SizedBox(height: wide ? 12 : 4),
            Text(subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: BmColors.ink.withAlpha(200), fontSize: wide ? 17 : 13, height: 1.35)),
          ],
          if (cta != null) ...[
            SizedBox(height: wide ? 24 : 10),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: BmColors.ink,
                foregroundColor: Colors.white,
                minimumSize: Size(0, wide ? 48 : 38),
                padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: Text(cta!),
            ),
          ],
        ],
      );

      if (wide) {
        return GestureDetector(
          onTap: onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: Container(
                  color: BmColors.surface,
                  padding: const EdgeInsets.fromLTRB(72, 32, 40, 40),
                  alignment: Alignment.centerLeft,
                  child: text,
                ),
              ),
              Expanded(flex: 6, child: BmImage(imageUrl)),
            ],
          ),
        );
      }
      return GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            BmImage(imageUrl),
            Positioned(
              left: 12,
              right: 12,
              bottom: 32,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white.withAlpha(240), borderRadius: BorderRadius.circular(6)),
                child: text,
              ),
            ),
          ],
        ),
      );
    });
  }
}
