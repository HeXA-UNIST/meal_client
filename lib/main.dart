import 'dart:async' show unawaited;
import 'dart:ui' show PlatformDispatcher;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoPageTransitionsBuilder;
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, kReleaseMode;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'package:meal_client/core/native_startup.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:meal_client/features/home/home_page.dart';
import 'package:meal_client/features/settings/bapu_settings.dart';

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
  if (!kIsWeb) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  if (!kIsWeb &&
      (defaultTargetPlatform != TargetPlatform.android || kReleaseMode)) {
    // Android는 프레임워크가 포착한 오류를 non-fatal로 기록한다.
    // iOS의 기존 분류는 해당 플랫폼에서 검증할 때까지 유지한다.
    FlutterError.onError = (errorDetails) {
      unawaited(
        _observeCrashReport(
          FirebaseCrashlytics.instance.recordFlutterError(
            errorDetails,
            fatal: defaultTargetPlatform != TargetPlatform.android,
          ),
        ),
      );
    };

    // 처리되지 않은 최상위 비동기 오류는 fatal로 분류한다.
    // 실제 프로세스 종료 여부를 판별하는 것은 아니다.
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        _observeCrashReport(
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
        ),
      );
      return true;
    };
  }

  // Android/iOS의 백그라운드 식단 갱신 작업을 등록한다.
  // flutter_local_notifications를 설정하고 Android 알림 채널을 생성한다.
  await initializeNativeServices();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ChangeNotifierProvider<BapuSettings>(
      create: (_) {
        final settings = BapuSettings(prefs);
        // 앱 시작 시 native pending 요청을 현재 설정에 맞춘다.
        settings.rescheduleMealNotifications();
        return settings;
      },
      child: const BapUApp(),
    ),
  );
  // Web 측정 SDK의 네트워크 로딩을 기다리지 않고 앱을 표시한다.
  if (kIsWeb && kReleaseMode) unawaited(_initializeWebAnalytics());
}

Future<void> _initializeWebAnalytics() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final analytics = FirebaseAnalytics.instance;
    if (await analytics.isSupported()) {
      // Web은 Core 초기화만으로 측정이 시작되지 않는다.
      // 광고 관련 기본값은 SDK가 로드되기 전에 index.html에서 설정한다.
      await analytics.setAnalyticsCollectionEnabled(true);
    }
  } catch (error, stack) {
    // 측정 차단이나 초기화 실패가 식단 조회까지 막지 않도록 한다.
    debugPrint('Web Analytics initialization failed: $error');
    debugPrintStack(stackTrace: stack);
  }
}

Future<void> _observeCrashReport(Future<void> report) async {
  try {
    await report;
  } catch (error, stack) {
    // 보고 실패가 전역 오류 처리기로 재진입하여 보고를 반복하지 않도록 한다.
    debugPrint('Crashlytics reporting failed: $error');
    debugPrintStack(stackTrace: stack);
  }
}

class BapUApp extends StatelessWidget {
  const BapUApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 알림 설정 화면은 탭 한 번에 여러 번 notifyListeners를 호출하므로,
    // watch로 전체 MaterialApp을 다시 만들지 않고 themeMode 변경만 구독한다.
    final themeMode = context.select<BapuSettings, ThemeMode>(
      (settings) => settings.themeMode,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.title,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
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
