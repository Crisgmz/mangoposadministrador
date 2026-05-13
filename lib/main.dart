import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/router/app_router.dart';
import 'app/theme/app_theme.dart';
import 'core/network/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // URLs limpias en web (sin `#`).
  usePathUrlStrategy();

  // Locale es-DO para fechas relativas y formatos.
  await initializeDateFormatting('es', null);

  await dotenv.load(fileName: '.env');
  await initSupabase();

  runApp(const ProviderScope(child: MangoPosAdminApp()));
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
    );
  }
}
