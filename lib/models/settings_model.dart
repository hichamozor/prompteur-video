import 'package:flutter/material.dart';

class PrompterSettings {
  // Texte
  final double fontSize;
  final double scrollSpeed;
  final Color textColor;
  final Color backgroundColor;
  final double backgroundOpacity;
  final String fontFamily;
  final bool mirrorMode;
  final int countdownSeconds;
  final TextAlign textAlign;
  final double lineSpacing;
  final double marginHorizontal;

  // Affichage
  final bool keepScreenOn;
  final bool showCamera;
  final bool useFrontCamera;
  final bool showReadingLine;        // ligne fine au tiers haut
  final double focusMaskOpacity;     // 0=off, 0.6=fort masque haut/bas
  final bool showSafeZone;           // overlay TikTok/Reels

  // Vidéo
  final String videoResolution; // 'high' | 'veryHigh' | 'ultraHigh'
  final int targetFps;          // 30 | 60

  // Lecture
  final int wpm; // mots/minute pour estimation du temps

  const PrompterSettings({
    this.fontSize = 42.0,
    this.scrollSpeed = 80.0,
    this.textColor = Colors.white,
    this.backgroundColor = Colors.black,
    this.backgroundOpacity = 0.55,
    this.fontFamily = 'Default',
    this.mirrorMode = false,
    this.countdownSeconds = 3,
    this.textAlign = TextAlign.center,
    this.lineSpacing = 1.6,
    this.marginHorizontal = 20.0,
    this.keepScreenOn = true,
    this.showCamera = true,
    this.useFrontCamera = true,
    this.showReadingLine = true,
    this.focusMaskOpacity = 0.55,
    this.showSafeZone = false,
    this.videoResolution = 'veryHigh',
    this.targetFps = 30,
    this.wpm = 150,
  });

  PrompterSettings copyWith({
    double? fontSize,
    double? scrollSpeed,
    Color? textColor,
    Color? backgroundColor,
    double? backgroundOpacity,
    String? fontFamily,
    bool? mirrorMode,
    int? countdownSeconds,
    TextAlign? textAlign,
    double? lineSpacing,
    double? marginHorizontal,
    bool? keepScreenOn,
    bool? showCamera,
    bool? useFrontCamera,
    bool? showReadingLine,
    double? focusMaskOpacity,
    bool? showSafeZone,
    String? videoResolution,
    int? targetFps,
    int? wpm,
  }) {
    return PrompterSettings(
      fontSize: fontSize ?? this.fontSize,
      scrollSpeed: scrollSpeed ?? this.scrollSpeed,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      fontFamily: fontFamily ?? this.fontFamily,
      mirrorMode: mirrorMode ?? this.mirrorMode,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      textAlign: textAlign ?? this.textAlign,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      marginHorizontal: marginHorizontal ?? this.marginHorizontal,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      showCamera: showCamera ?? this.showCamera,
      useFrontCamera: useFrontCamera ?? this.useFrontCamera,
      showReadingLine: showReadingLine ?? this.showReadingLine,
      focusMaskOpacity: focusMaskOpacity ?? this.focusMaskOpacity,
      showSafeZone: showSafeZone ?? this.showSafeZone,
      videoResolution: videoResolution ?? this.videoResolution,
      targetFps: targetFps ?? this.targetFps,
      wpm: wpm ?? this.wpm,
    );
  }

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'scrollSpeed': scrollSpeed,
        'textColor': textColor.value,
        'backgroundColor': backgroundColor.value,
        'backgroundOpacity': backgroundOpacity,
        'fontFamily': fontFamily,
        'mirrorMode': mirrorMode,
        'countdownSeconds': countdownSeconds,
        'textAlign': textAlign.index,
        'lineSpacing': lineSpacing,
        'marginHorizontal': marginHorizontal,
        'keepScreenOn': keepScreenOn,
        'showCamera': showCamera,
        'useFrontCamera': useFrontCamera,
        'showReadingLine': showReadingLine,
        'focusMaskOpacity': focusMaskOpacity,
        'showSafeZone': showSafeZone,
        'videoResolution': videoResolution,
        'targetFps': targetFps,
        'wpm': wpm,
      };

  factory PrompterSettings.fromJson(Map<String, dynamic> j) {
    const d = PrompterSettings();
    return PrompterSettings(
      fontSize: (j['fontSize'] as num?)?.toDouble() ?? d.fontSize,
      scrollSpeed: (j['scrollSpeed'] as num?)?.toDouble() ?? d.scrollSpeed,
      textColor: j['textColor'] is int ? Color(j['textColor'] as int) : d.textColor,
      backgroundColor: j['backgroundColor'] is int
          ? Color(j['backgroundColor'] as int)
          : d.backgroundColor,
      backgroundOpacity:
          (j['backgroundOpacity'] as num?)?.toDouble() ?? d.backgroundOpacity,
      fontFamily: j['fontFamily'] as String? ?? d.fontFamily,
      mirrorMode: j['mirrorMode'] as bool? ?? d.mirrorMode,
      countdownSeconds: j['countdownSeconds'] as int? ?? d.countdownSeconds,
      textAlign: TextAlign.values[
          (j['textAlign'] as int?) ?? d.textAlign.index],
      lineSpacing: (j['lineSpacing'] as num?)?.toDouble() ?? d.lineSpacing,
      marginHorizontal:
          (j['marginHorizontal'] as num?)?.toDouble() ?? d.marginHorizontal,
      keepScreenOn: j['keepScreenOn'] as bool? ?? d.keepScreenOn,
      showCamera: j['showCamera'] as bool? ?? d.showCamera,
      useFrontCamera: j['useFrontCamera'] as bool? ?? d.useFrontCamera,
      showReadingLine: j['showReadingLine'] as bool? ?? d.showReadingLine,
      focusMaskOpacity:
          (j['focusMaskOpacity'] as num?)?.toDouble() ?? d.focusMaskOpacity,
      showSafeZone: j['showSafeZone'] as bool? ?? d.showSafeZone,
      videoResolution: j['videoResolution'] as String? ?? d.videoResolution,
      targetFps: j['targetFps'] as int? ?? d.targetFps,
      wpm: j['wpm'] as int? ?? d.wpm,
    );
  }

  // ── Presets : ne touchent que ce qui change vraiment selon la plateforme

  static const PrompterSettings tiktok = PrompterSettings(
    fontSize: 42,
    scrollSpeed: 90,
    countdownSeconds: 3,
    videoResolution: 'veryHigh',
    targetFps: 30,
    showSafeZone: true,
    showCamera: true,
  );

  static const PrompterSettings youtubeShort = PrompterSettings(
    fontSize: 44,
    scrollSpeed: 82,
    countdownSeconds: 3,
    videoResolution: 'ultraHigh',
    targetFps: 30,
    showSafeZone: false,
    showCamera: true,
  );

  static const PrompterSettings reels = PrompterSettings(
    fontSize: 42,
    scrollSpeed: 90,
    countdownSeconds: 3,
    videoResolution: 'veryHigh',
    targetFps: 30,
    showSafeZone: true,
    showCamera: true,
  );

  static const PrompterSettings podcast = PrompterSettings(
    fontSize: 36,
    scrollSpeed: 70,
    countdownSeconds: 5,
    videoResolution: 'ultraHigh',
    targetFps: 30,
    showSafeZone: false,
    showCamera: false,
  );
}
