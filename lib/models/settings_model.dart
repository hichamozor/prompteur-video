import 'package:flutter/material.dart';

class PrompterSettings {
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
  final bool keepScreenOn;
  final bool showCamera;
  final bool useFrontCamera;

  const PrompterSettings({
    this.fontSize = 38.0,
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
    );
  }
}
