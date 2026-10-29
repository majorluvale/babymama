import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';

/// Line icons for categories, drawn on a 24×24 grid. The key is stored on each category (`icon`).
const categoryIconPaths = <String, String>{
  'women': '<circle cx="12" cy="5" r="2.5"/><path d="M10 9h4l3 9h-3v3h-4v-3H7z"/>',
  'men': '<circle cx="12" cy="5" r="2.5"/><path d="M9 9h6v7h-1.5v5h-3v-5H9z"/>',
  'kids': '<circle cx="12" cy="7" r="2.2"/><path d="M9.5 11h5l1 5h-2v4h-3v-4h-2z"/><path d="M6 13l3.5-2M18 13l-3.5-2"/>',
  'dress': '<path d="M9.5 3h5l-1 4.5 4.5 13.5H6l4.5-13.5z"/><path d="M10 7.5h4"/>',
  'tshirt': '<path d="M8.5 3.5 3 6.5l2 4 2-1V21h10V9.5l2 1 2-4-5.5-3c0 1.7-1.6 3-3.5 3s-3.5-1.3-3.5-3z"/>',
  'shirt': '<path d="M8.5 3.5 3 6.5l2 4 2-1V21h10V9.5l2 1 2-4-5.5-3L12 7z"/><path d="M12 7v14M12 11h.01M12 15h.01"/>',
  'sweater': '<path d="M8.5 3.5 4 6v13h3V9.5V21h10V9.5V19h3V6l-4.5-2.5c0 1.7-1.6 3-3.5 3s-3.5-1.3-3.5-3z"/><path d="M7 18.5h10"/>',
  'trousers': '<path d="M7 3h10l1.5 18h-4.5l-2-11-2 11H5.5z"/><path d="M7.2 6h9.6"/>',
  'shorts': '<path d="M6 5h12l1.5 11h-5.5l-2-5-2 5H4.5z"/><path d="M6.2 8h11.6"/>',
  'skirt': '<path d="M8 4h8l3.5 15h-15z"/><path d="M8 7h8"/>',
  'coat': '<path d="M9 3 4.5 6v15H9V10l3 4 3-4v11h4.5V6L15 3l-3 5z"/><path d="M12 14v7"/>',
  'tie': '<path d="M10 3h4l-1 3 2 10-3 5-3-5 2-10z"/>',
  'sport': '<path d="M4 9v6M7 7v10M17 7v10M20 9v6M7 12h10"/>',
  'pattern': '<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M4 12 12 4l8 8-8 8z"/><circle cx="12" cy="12" r="1.5"/>',
  'maternity': '<circle cx="11" cy="4.5" r="2"/><path d="M9.5 8h3c3 2 4 6 1.5 8.5L15 21H9l1-5-1.5-3z"/>',
  'shoe': '<path d="M3 17.5V12l4-.5 3-4.5 3 2-1 3 7 2c1.8.5 2.5 1.6 2.5 3.5H3z"/><path d="M3 17.5h18.5"/>',
  'sneaker': '<path d="M3 17.5V11h3l2 2 3-3 2.5 2.5L20 14c1.2.4 1.5 1.5 1.5 3.5H3z"/><path d="M3 17.5h18.5M9.5 12.5l1 1M11.5 11.5l1 1"/>',
  'heel': '<path d="M3.5 11c3 0 6 2 9 5h6c1.7 0 2.5 1 2.5 2H9l-3-3.5-1 3.5H3.5z"/><path d="M18.5 16 21 9"/>',
  'bag': '<path d="M5 8h14l-1 13H6z"/><path d="M9 8V6.5a3 3 0 0 1 6 0V8"/>',
  'jewel': '<path d="M6 4h12l3 5-9 11L3 9z"/><path d="M3 9h18M9.5 4 8 9l4 11 4-11-1.5-5"/>',
  'cap': '<path d="M4 15a8 8 0 0 1 16 0z"/><path d="M12 15h9"/><path d="M12 7v1"/>',
  'hat': '<path d="M6 16a6 6 0 0 1 12 0z"/><path d="M4 16h16v2H4z"/><circle cx="12" cy="8.5" r="1.3"/>',
  'bodysuit': '<path d="M8.5 3h7l3.5 4-2.5 2-1-1v6l-2 5h-3l-2-5V8l-1 1L5 7z"/><path d="M10.5 3a1.5 1.5 0 0 0 3 0"/>',
  'moon': '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>',
  'school': '<path d="M2.5 9 12 4.5 21.5 9 12 13.5z"/><path d="M6.5 11v5c3 2.5 8 2.5 11 0v-5M21.5 9v6"/>',
  'tag': '<path d="M3 12V4h8l10 10-8 8z"/><circle cx="7.5" cy="8.5" r="1.3"/>',
};

/// A category icon in the given colour; unknown or missing keys show a price tag.
class CategoryIcon extends StatelessWidget {
  const CategoryIcon(this.iconKey, {super.key, this.size = 22, this.color = BmColors.ink});

  final String? iconKey;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final body = categoryIconPaths[iconKey] ?? categoryIconPaths['tag']!;
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" '
      'stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">$body</svg>',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
