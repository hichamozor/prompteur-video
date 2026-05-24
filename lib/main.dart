import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final settingsProvider = SettingsProvider();
  await settingsProvider.load();

  runApp(PrompterApp(settingsProvider: settingsProvider));
}

class PrompterApp extends StatelessWidget {
  final SettingsProvider settingsProvider;
  const PrompterApp({super.key, required this.settingsProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return DynamicColorBuilder(
            builder: (lightDynamic, darkDynamic) {
              ColorScheme scheme;
              if (settings.settings.dynamicColors && darkDynamic != null) {
                scheme = darkDynamic.harmonized();
              } else {
                scheme = ColorScheme.fromSeed(
                  seedColor: const Color(0xFFD4AF37),
                  brightness: Brightness.dark,
                );
              }
              return MaterialApp(
                title: 'Prompteur Vidéo',
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                  colorScheme: scheme,
                  useMaterial3: true,
                  pageTransitionsTheme: const PageTransitionsTheme(
                    builders: {
                      TargetPlatform.android: ZoomPageTransitionsBuilder(),
                      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                    },
                  ),
                ),
                home: const HomeScreen(),
              );
            },
          );
        },
      ),
    );
  }
}
