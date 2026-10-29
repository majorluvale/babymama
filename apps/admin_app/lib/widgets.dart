import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

/// Picks an image from the computer / phone and uploads it. Returns its URL.
Future<String?> pickAndUpload(BuildContext context) async {
  final api = context.read<ApiClient>();
  final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2000);
  if (file == null) return null;
  try {
    return await api.uploadImage(await file.readAsBytes(), file.name);
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
    return null;
  }
}

/// Runs an API call, shows its error in a snackbar. Returns true on success.
Future<bool> runApi(BuildContext context, Future<void> Function() call, {String? success}) async {
  try {
    await call();
    if (success != null && context.mounted) showSnack(context, success);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
    return false;
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.color = BmColors.primary, this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Card(
        elevation: 0,
        color: BmColors.surface,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(backgroundColor: color.withAlpha(30), child: Icon(icon, color: color)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(label, style: const TextStyle(color: BmColors.muted, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Previous / next page buttons.
class Pager extends StatelessWidget {
  const Pager({super.key, required this.page, required this.pages, required this.total, required this.onPage});

  final int page;
  final int pages;
  final int total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text(context.tr('page_of', {'page': page, 'pages': pages, 'total': total})),
        IconButton(onPressed: page > 1 ? () => onPage(page - 1) : null, icon: const Icon(Icons.chevron_left)),
        IconButton(onPressed: page < pages ? () => onPage(page + 1) : null, icon: const Icon(Icons.chevron_right)),
      ]),
    );
  }
}

/// Small dialog with one text field. Returns null when cancelled.
Future<String?> promptText(BuildContext context, String title, {String? hint, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(ctx.tr('confirm'))),
      ],
    ),
  );
}

class PageHeader extends StatelessWidget implements PreferredSizeWidget {
  const PageHeader({super.key, required this.title, this.actions = const [], this.bottom});

  final String title;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      actions: [...actions, const SizedBox(width: 12)],
      bottom: bottom,
    );
  }
}
