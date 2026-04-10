import 'package:autobutler/models/plugin_manifest.dart';
import 'package:autobutler/router.dart';
import 'package:autobutler/services/app_settings.dart';
import 'package:autobutler/services/plugin_service.dart';
import 'package:autobutler/services/plugin_state.dart';
import 'package:autobutler/theme/autobutler_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

Future<void> main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  runApp(const AutobutlerApp());
}

class AutobutlerApp extends StatefulWidget {
  const AutobutlerApp({super.key});

  @override
  State<AutobutlerApp> createState() => _AutobutlerAppState();
}

class _AutobutlerAppState extends State<AutobutlerApp> {
  List<PluginManifest> _plugins = const [];
  late GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = buildRouter(plugins: _plugins);
    _loadPlugins();
  }

  Future<void> _loadPlugins() async {
    if (AppSettings.instance.activeHost == null) return;
    try {
      final plugins = await PluginService.listPlugins();
      if (!mounted) return;
      PluginState.instance.setPlugins(plugins);
      setState(() {
        _plugins = plugins;
        _router = buildRouter(plugins: _plugins);
      });
    } catch (_) {
      // Plugins are non-critical; fail silently on load errors.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.instance.themeMode,
      builder: (context, mode, _) {
        return MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'Autobutler',
          theme: AutobutlerTheme.light(),
          darkTheme: AutobutlerTheme.dark(),
          themeMode: mode,
          routerConfig: _router,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
        );
      },
    );
  }
}
