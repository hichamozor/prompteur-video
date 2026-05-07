import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/scripts_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Pré-charge settings + scripts pour éviter l'écran blanc / flash de defaults
  final settingsProvider = SettingsProvider();
  final scriptsProvider = ScriptsProvider();
  await Future.wait([
    settingsProvider.load(),
    scriptsProvider.load(),
  ]);

  runApp(PrompterApp(
    settingsProvider: settingsProvider,
    scriptsProvider: scriptsProvider,
  ));
}

class PrompterApp extends StatelessWidget {
  final SettingsProvider settingsProvider;
  final ScriptsProvider scriptsProvider;
  const PrompterApp({
    super.key,
    required this.settingsProvider,
    required this.scriptsProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: scriptsProvider),
      ],
      child: MaterialApp(
        title: 'Prompteur Vidéo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C63FF),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
