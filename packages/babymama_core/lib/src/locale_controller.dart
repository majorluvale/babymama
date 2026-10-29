import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Current app language (English / French), saved on the device and sent to the API.
class LocaleController extends ChangeNotifier {
  LocaleController(this.api);

  static const _key = 'bm_locale';
  final ApiClient api;
  Locale _locale = const Locale('en');

  Locale get locale => _locale;
  String get lang => _locale.languageCode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    final system = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    _apply(saved ?? system);
  }

  Future<void> setLang(String code) async {
    _apply(code);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, lang);
  }

  void _apply(String code) {
    _locale = Locale(code == 'fr' ? 'fr' : 'en');
    api.locale = _locale.languageCode;
  }
}
