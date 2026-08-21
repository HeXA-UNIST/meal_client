import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/features/home/home_page.dart';
import 'package:meal_client/features/meal/meal_background_refresh.dart';
import 'package:meal_client/features/settings/app_settings.dart';
import 'package:meal_client/features/notification/meal_notification_worker.dart';
import 'package:meal_client/features/notification/notification_service.dart';

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
  return ThemeData(
    fontFamily: 'Pretendard',
    brightness: brightness,
    pageTransitionsTheme: _pageTransitionsTheme,
    colorScheme:
        ColorScheme.fromSeed(
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
  await Workmanager().initialize(callbackDispatcher);
  await initializeMealBackgroundRefresh();
  final prefs = await SharedPreferences.getInstance();
  await initNotifications();

  runApp(
    ChangeNotifierProvider<AppSettings>(
      create: (_) {
        final settings = AppSettings(prefs);
        // 앱 시작 시 Android Workmanager와 iOS pending 요청을 현재 설정에 맞춘다.
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
