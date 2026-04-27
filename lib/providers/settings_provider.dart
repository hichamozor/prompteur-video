import 'package:flutter/material.dart';
import '../models/settings_model.dart';

class SettingsProvider extends ChangeNotifier {
  PrompterSettings _settings = const PrompterSettings();
  String _script = '';

  PrompterSettings get settings => _settings;
  String get script => _script;

  void updateSettings(PrompterSettings s) {
    _settings = s;
    notifyListeners();
  }

  void updateScript(String text) {
    _script = text;
    notifyListeners();
  }

  void updateFontSize(double v) {
    _settings = _settings.copyWith(fontSize: v);
    notifyListeners();
  }

  void updateScrollSpeed(double v) {
    _settings = _settings.copyWith(scrollSpeed: v);
    notifyListeners();
  }

  void toggleMirror() {
    _settings = _settings.copyWith(mirrorMode: !_settings.mirrorMode);
    notifyListeners();
  }

  void toggleCamera() {
    _settings = _settings.copyWith(showCamera: !_settings.showCamera);
    notifyListeners();
  }

  void switchCamera() {
    _settings = _settings.copyWith(useFrontCamera: !_settings.useFrontCamera);
    notifyListeners();
  }
}
