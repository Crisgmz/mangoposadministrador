import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/router/app_router.dart';
import 'app/theme/app_theme.dart';
import 'core/debug/load_timing_observer.dart';
import 'core/network/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // URLs limpias en web (sin `#`).
  usePathUrlStrategy();

  // Paralelizar inits que son independientes entre sí. Antes eran 4 awaits
  // seriales (~300-500ms de cold start); ahora bajan a max(individuales)
  // gracias a `Future.wait`. `initSupabase` queda fuera del wait porque
  // depende de `dotenv` (lee SUPABASE_URL/SUPABASE_ANON_KEY).
  await Future.wait([
    initializeDateFormatting('es', null),
    initializeDateFormatting('es_DO', null),
    dotenv.load(fileName: '.env'),
  ]);
  await initSupabase();

  runApp(
    ProviderScope(
      // En debug imprime en consola cuánto tarda cada carga de datos.
      observers: kDebugMode
          ? const [LoadTimingObserver()]
          : const <ProviderObserver>[],
      child: const MangoPosAdminApp(),
    ),
  );
}

class MangoPosAdminApp extends ConsumerWidget {
  const MangoPosAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'MangoPOS Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      // Localizaciones es-DO. Sin esto `showDatePicker(locale: Locale('es'))`
      // y otros widgets Material que necesitan strings traducidos lanzan
      // "No MaterialLocalizations found".
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'DO'),
        Locale('es'),
        Locale('en'),
      ],
      locale: const Locale('es', 'DO'),
    );
  }
}
