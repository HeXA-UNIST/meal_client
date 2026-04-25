import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_localizations.dart';
import 'pages/home.dart';
import 'settings/app_settings.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppSettings(prefs),
      child: const BapUApp(),
    ),
  );
}

class BapUApp extends StatelessWidget {
  const BapUApp({super.key});

  @override
  Widget build(BuildContext context) {
    // context.select 대신 context.watch 사용: 설정 변경은 사용자 탭으로만 발생하므로
    // 빈도가 낮고, home: const HomePage()가 홈 서브트리 리빌드를 막아 실질적 영향 없음.
    final themeMode = context.watch<AppSettings>().themeMode;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.title,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      themeMode: themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const HomePage(),
    );
  }
}
