import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'strings_en.dart';
import 'strings_fr.dart';

/// English / French translations shared by all Babymama apps.
/// Usage: `context.tr('add_to_cart')` or `context.tr('items_count', {'n': 3})`.
class BmLocalizations {
  BmLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('fr')];
  static const LocalizationsDelegate<BmLocalizations> delegate = _BmLocalizationsDelegate();

  static const Map<String, Map<String, String>> _strings = {'en': stringsEn, 'fr': stringsFr};

  static BmLocalizations of(BuildContext context) =>
      Localizations.of<BmLocalizations>(context, BmLocalizations) ?? BmLocalizations(const Locale('en'));

  String get lang => locale.languageCode;

  String t(String key, [Map<String, Object?> args = const {}]) {
    var text = _strings[lang]?[key] ?? stringsEn[key] ?? key;
    args.forEach((name, value) => text = text.replaceAll('{$name}', '$value'));
    return text;
  }
}

class _BmLocalizationsDelegate extends LocalizationsDelegate<BmLocalizations> {
  const _BmLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'fr'].contains(locale.languageCode);

  @override
  Future<BmLocalizations> load(Locale locale) => SynchronousFuture(BmLocalizations(locale));

  @override
  bool shouldReload(_BmLocalizationsDelegate old) => false;
}

extension BmTranslate on BuildContext {
  String tr(String key, [Map<String, Object?> args = const {}]) => BmLocalizations.of(this).t(key, args);
  String get lang => BmLocalizations.of(this).lang;
}
