import 'package:flutter/material.dart';

import 'i18n.dart';

/// Colour keys accepted by the API (backend/src/lib/sizes.ts) with their swatch.
const productColors = <String, Color>{
  'black': Color(0xFF1F1F1F),
  'white': Color(0xFFFFFFFF),
  'grey': Color(0xFF9CA3AF),
  'beige': Color(0xFFE8DCC8),
  'brown': Color(0xFF8B5E3C),
  'navy': Color(0xFF1E2A4A),
  'blue': Color(0xFF3B6FB6),
  'green': Color(0xFF4F7F52),
  'red': Color(0xFFC0392B),
  'pink': Color(0xFFE8A0B4),
  'purple': Color(0xFF7D5BA6),
  'yellow': Color(0xFFE9C46A),
  'orange': Color(0xFFE07A3F),
  'multicolor': Color(0xFFCCCCCC),
};

const productConditions = ['NEW_WITH_TAGS', 'NEW_WITHOUT_TAGS', 'VERY_GOOD', 'GOOD', 'SATISFACTORY'];

extension ColorLabel on BuildContext {
  /// Translated colour name; unknown values (imported from WooCommerce) are shown as they are.
  String colorName(String key) => productColors.containsKey(key) ? tr('color_$key') : key;
}

/// Round colour swatch; "multicolor" is drawn as a rainbow.
class ColorSwatchDot extends StatelessWidget {
  const ColorSwatchDot(this.colorKey, {super.key, this.size = 16, this.selected = false});

  final String colorKey;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = productColors[colorKey] ?? Colors.grey;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorKey == 'multicolor' ? null : color,
        gradient: colorKey == 'multicolor'
            ? const SweepGradient(colors: [Colors.red, Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple, Colors.red])
            : null,
        border: Border.all(color: selected ? Colors.black87 : Colors.black26, width: selected ? 2 : 1),
      ),
    );
  }
}
