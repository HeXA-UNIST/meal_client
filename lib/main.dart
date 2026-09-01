import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meal_client/core/native_startup.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/features/home/home_page.dart';
import 'package:meal_client/features/settings/app_settings.dart';

const mainColor = Color(0xFF00CD80);

const _defaultPageTransitionsTheme = PageTransitionsTheme();

// Flutter 기본 플랫폼 전환은 유지하고 Android만 Cupertino 슬라이드로 교체한다.
final _pageTransitionsTheme = PageTransitionsTheme(
  builders: {
    ..._defaultPageTransitionsTheme.builders,
    TargetPlatform.android: const CupertinoPageTransitionsBuilder(),
  },
);

ThemeData _buildTheme(Brightness brightness) {
  final isLight = brightness == Brightness.light;
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: mainColor,
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      ).copyWith(
        onPrimaryContainer: Colors.white,
        onSurface: isLight ? null : const Color(0xFFE6E6E6),
        outline: isLight ? null : const Color(0xFF9E9E9E),
        outlineVariant: isLight ? null : const Color(0xFF454545),
        surface: isLight ? Colors.white : Colors.black,
        surfaceContainer: isLight
            ? const Color(0xFFFAFAFA)
            : const Color(0xFF121212),
      );
  final theme = ThemeData(
    fontFamily: 'Pretendard',
    brightness: brightness,
    pageTransitionsTheme: _pageTransitionsTheme,
    colorScheme: colorScheme,
  );
  return theme.copyWith(
    appBarTheme: theme.appBarTheme.copyWith(
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

// ColorScheme.fromSeed는 매 호출마다 시드 색에서 팔레트를 다시 계산해 비용이 크다.
// 테마는 밝기 외의 입력이 없으므로 한 번만 만들어 재사용한다.
final _lightTheme = _buildTheme(Brightness.light);
final _darkTheme = _buildTheme(Brightness.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeNativeServices();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ChangeNotifierProvider<AppSettings>(
      create: (_) {
        final settings = AppSettings(prefs);
        // 앱 시작 시 native pending 요청을 현재 설정에 맞춘다.
        settings.rescheduleMealNotifications();
        return settings;
      },
      child: const BapUApp(),
    ),
  );
}

class BapUApp extends StatelessWidget {
  const BapUApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 알림 설정 화면은 탭 한 번에 여러 번 notifyListeners를 호출하므로,
    // watch로 전체 MaterialApp을 다시 만들지 않고 themeMode 변경만 구독한다.
    final themeMode = context.select<AppSettings, ThemeMode>(
      (settings) => settings.themeMode,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.title,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        final theme = Theme.of(context);
        return AppBarTheme(
          data: theme.appBarTheme.copyWith(
            titleTextStyle: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: child!,
        );
      },
      themeMode: themeMode,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      home: const HomePage(),
    );
  }
}
