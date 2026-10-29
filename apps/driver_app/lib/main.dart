import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'location_reporter.dart';
import 'rider_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  final locale = LocaleController(api);
  await locale.load();
  final session = Session(api, storageKey: 'bm_rider_token');
  await session.restore();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<LocaleController>.value(value: locale),
        ChangeNotifierProvider<Session>.value(value: session),
        ChangeNotifierProvider<LocationReporter>(create: (_) => LocationReporter(api)),
      ],
      child: const RiderApp(),
    ),
  );
}

class RiderApp extends StatelessWidget {
  const RiderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return MaterialApp(
      title: 'Babymama Rider',
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
      home: session.isLoggedIn && session.user!.isDriver
          ? const RiderHome()
          : const StaffLoginScreen(title: 'Babymama Rider', allowedRoles: ['DRIVER'], icon: Icons.delivery_dining),
    );
  }
}
