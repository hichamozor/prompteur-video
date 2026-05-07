import 'package:flutter/material.dart';
import '../models/settings_model.dart';
import '../services/logger.dart';
import '../services/storage_service.dart';

class SettingsProvider extends ChangeNotifier {
  PrompterSettings _settings = const PrompterSettings();
  bool _loaded = false;

  PrompterSettings get settings => _settings;
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final json = await StorageService.loadSettings();
      if (json.isNotEmpty) {
        _settings = PrompterSettings.fromJson(json);
      }
    } catch (e, st) {
      Log.e('SettingsProvider', 'load failed, using defaults', e, st);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    await StorageService.saveSettings(_settings.toJson());
  }

  void updateSettings(PrompterSettings s) {
    _settings = s;
    notifyListeners();
    _persist();
  }

  void updateFontSize(double v) =>
      updateSettings(_settings.copyWith(fontSize: v));
  void updateScrollSpeed(double v) =>
      updateSettings(_settings.copyWith(scrollSpeed: v));
  void toggleMirror() =>
      updateSettings(_settings.copyWith(mirrorMode: !_settings.mirrorMode));
  void toggleCamera() =>
      updateSettings(_settings.copyWith(showCamera: !_settings.showCamera));
  void switchCamera() => updateSettings(
      _settings.copyWith(useFrontCamera: !_settings.useFrontCamera));
  void toggleSafeZone() => updateSettings(
      _settings.copyWith(showSafeZone: !_settings.showSafeZone));
  void toggleReadingLine() => updateSettings(
      _settings.copyWith(showReadingLine: !_settings.showReadingLine));

  /// Applique un preset (TikTok, Short, Reels, Podcast).
  /// Garde les choix esthétiques (couleur, police) et écrase les choix
  /// "techniques" (vitesse, taille, résolution, fps, safe-zone, countdown).
  void applyPreset(PrompterSettings preset) {
    _settings = _settings.copyWith(
      fontSize: preset.fontSize,
      scrollSpeed: preset.scrollSpeed,
      countdownSeconds: preset.countdownSeconds,
      videoResolution: preset.videoResolution,
      targetFps: preset.targetFps,
      showSafeZone: preset.showSafeZone,
      showCamera: preset.showCamera,
    );
    notifyListeners();
    _persist();
  }
}
