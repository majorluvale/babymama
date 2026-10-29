import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'state/cart.dart';
import 'state/categories.dart';
import 'state/favorites.dart';
import 'screens/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  final locale = LocaleController(api);
  await locale.load();
  final session = Session(api);
  await session.restore();
  final cart = CartController();
  await cart.load();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<LocaleController>.value(value: locale),
        ChangeNotifierProvider<Session>.value(value: session),
        ChangeNotifierProvider<CartController>.value(value: cart),
        ChangeNotifierProvider<FavoritesController>(create: (_) => FavoritesController(api, session)),
        ChangeNotifierProvider<CategoriesController>(create: (_) => CategoriesController(api)),
      ],
      child: const BabymamaApp(),
    ),
  );
}

class BabymamaApp extends StatelessWidget {
  const BabymamaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Babymama',
      debugShowCheckedModeBanner: false,
      theme: bmTheme(),
      locale: context.watch<LocaleController>().locale,
      supportedLocales: BmLocalizations.supportedLocales,
      localizationsDelegates: const [
        BmLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RootShell(),
    );
  }
}
