import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What `main` paints when the saved settings are slow to load (#2066): a
/// centered [QuarkLoader] in place of the blank native launch screen.
///
/// An app of its own, in the shipped theme and the platform's brightness: it
/// runs before `AppSettings` has loaded, so it reads none of it. `QuarkApp`
/// replaces it once the settings are in.
class StartupLoader extends StatelessWidget {
  const StartupLoader({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Quark',
    theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
    darkTheme: QuarkTheme.dark(themeColor: QuarkThemeColor.classic),
    home: const Scaffold(body: Center(child: QuarkLoader())),
  );
}
