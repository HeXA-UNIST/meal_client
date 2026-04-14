import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';

import 'pages/home.dart';

const mainColor = Color(0xFF00CD80);

ThemeData _buildTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  return ThemeData(
    fontFamily: 'Pretendard',
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: mainColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ).copyWith(
      onPrimaryContainer: Colors.white,
      surface: isLight ? Colors.white : Colors.black,
      surfaceContainer: isLight
          ? const Color(0xFFFAFAFA)
          : const Color(0xFF0F0F0F),
    ),
  );
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.title,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      themeMode: ThemeMode.system,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const HomePage(),
    );
  }
}
