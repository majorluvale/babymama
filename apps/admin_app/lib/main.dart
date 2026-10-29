import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  final locale = LocaleController(api);
  await locale.load();
  final session = Session(api, storageKey: 'bm_admin_token');
  await session.restore();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<LocaleController>.value(value: locale),
        ChangeNotifierProvider<Session>.value(value: session),
      ],
      child: const AdminApp(),
    ),
  );
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final role = session.user?.role;
    return MaterialApp(
      title: 'Babymama Admin',
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
      home: role == 'ADMIN' || role == 'SUPPORT'
          ? const AdminShell()
          : const StaffLoginScreen(
              title: 'Babymama Admin',
              allowedRoles: ['ADMIN', 'SUPPORT'],
              icon: Icons.admin_panel_settings_outlined,
            ),
    );
  }
}
