import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n.dart';
import '../locale_controller.dart';
import '../theme.dart';

class BmImage extends StatelessWidget {
  const BmImage(this.url, {super.key, this.fit = BoxFit.cover, this.width, this.height, this.radius = 0});

  final String? url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: BmColors.surface,
      alignment: Alignment.center,
      child: const Icon(Icons.checkroom_outlined, color: BmColors.muted),
    );
    final image = url == null || url!.isEmpty
        ? placeholder
        : Image.network(
            url!,
            fit: fit,
            width: width,
            height: height,
            errorBuilder: (_, __, ___) => placeholder,
            loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
          );
    return radius == 0 ? image : ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.message, this.icon = Icons.inbox_outlined, this.action});

  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: BmColors.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: BmColors.muted, fontSize: 15)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.cloud_off_outlined,
      message: message,
      action: onRetry == null ? null : OutlinedButton(onPressed: onRetry, child: Text(context.tr('retry'))),
    );
  }
}

/// Colored pill for order / payment / delivery / product / ticket statuses.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.prefix = 'status_'});

  final String status;
  final String prefix;

  static Color colorFor(String status) {
    switch (status) {
      case 'DELIVERED':
      case 'PAID':
      case 'SUCCESS':
      case 'ACTIVE':
      case 'RESOLVED':
        return BmColors.success;
      case 'CANCELLED':
      case 'FAILED':
      case 'REJECTED':
      case 'REFUNDED':
      case 'SOLD_OUT':
        return BmColors.danger;
      case 'PENDING_PAYMENT':
      case 'PENDING':
      case 'PENDING_REVIEW':
      case 'UNASSIGNED':
      case 'UNPAID':
      case 'OPEN':
        return BmColors.warning;
      default:
        return BmColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(20)),
      child: Text(
        context.tr('$prefix$status'),
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.size = 18, this.onChanged});

  final num rating;
  final double size;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = rating >= i + 1;
        final half = !filled && rating > i;
        final icon = Icon(
          filled ? Icons.star_rounded : (half ? Icons.star_half_rounded : Icons.star_outline_rounded),
          color: const Color(0xFFF5A623),
          size: size,
        );
        if (onChanged == null) return icon;
        return InkResponse(onTap: () => onChanged!(i + 1), radius: size, child: Padding(padding: const EdgeInsets.all(2), child: icon));
      }),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

/// EN / FR switch for app bars.
class LanguageMenu extends StatelessWidget {
  const LanguageMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LocaleController>();
    return PopupMenuButton<String>(
      tooltip: context.tr('language'),
      initialValue: controller.lang,
      onSelected: controller.setLang,
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'en', child: Text('English')),
        PopupMenuItem(value: 'fr', child: Text('Français')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.language, size: 20),
          const SizedBox(width: 4),
          Text(controller.lang.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Number of grid columns for product grids, from phone to desktop web.
int gridColumns(double width) {
  if (width >= 1200) return 5;
  if (width >= 900) return 4;
  if (width >= 600) return 3;
  return 2;
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? BmColors.danger : null));
}

Future<bool> confirmDialog(BuildContext context, String message, {String? confirmLabel}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel ?? ctx.tr('confirm'))),
      ],
    ),
  );
  return result ?? false;
}
