import 'dart:ui';

import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import 'model.dart';

import 'pages/home.dart';

const mainColor = Color(0xFF00CD80);

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) {
        final platformDispatcher = PlatformDispatcher.instance;

        // 라이트/다크 모드 구현이 일반적인 themeMode/darkTheme 방식과 다름
        // 시스템 밝기값을 BapUModel의 themeBrightness로 보관한 뒤,
        // 그 값이 바뀔 때마다 MaterialApp.theme 전체를 재생성
        // (MaterialApp의 theme는 themeBrightness에 따라 ThemeData와 ColorScheme을 다시 계산하도록 구현)
        final model = BapUModel(
          themeBrightness: platformDispatcher.platformBrightness,
        );

        platformDispatcher.onPlatformBrightnessChanged = () {
          model.setThemeBrightness(platformDispatcher.platformBrightness);
        };

        return model;
      },
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BapUModel>(
      builder: (context, bapu, child) {
        return MaterialApp(
          onGenerateTitle:
              (context) => AppLocalizations.of(context)!.title,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // themeBrightness를 기준으로 ThemeData와 ColorScheme을 다시 계산해
          // 앱 전체의 라이트/다크 모드가 적용됨
          theme: ThemeData(
            fontFamily: 'Pretendard',
            brightness: bapu.themeBrightness,
            colorScheme:
                ColorScheme.fromSeed(
                  seedColor: mainColor,
                  brightness: bapu.themeBrightness,
                  dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
                ).copyWith(
                  onPrimaryContainer: Colors.white,
                  surface: bapu.themeBrightness == Brightness.light
                      ? Colors.white
                      : Colors.black,
                  surfaceContainer: bapu.themeBrightness == Brightness.light
                      ? Color.fromARGB(0xff, 0xfA, 0xfA, 0xfA)
                      : Color.fromARGB(0xff, 0xf, 0xf, 0xf),
                ),
          ),
          home: child,
        );
      },
      child: const HomePage(),
    );
  }
}
