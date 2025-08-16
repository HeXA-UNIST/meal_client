import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'i18n.dart';
import 'string.dart' as string;
import 'model.dart';

import 'pages/home.dart';

const mainColor = Color(0xFF00CD80);

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) {
        final platformDispatcher = PlatformDispatcher.instance;
        final Language language;
        if ( /* platformDispatcher.locale.languageCode == "ko" */ true) {
          language = Language.kor;
        } else {
          language = Language.eng;
        }

        final model = BapUModel(
          language: language,
          brightness: platformDispatcher.platformBrightness,
        );

        platformDispatcher.onLocaleChanged = () {
          final Language language;
          if ( /* platformDispatcher.locale.languageCode == "ko" */ true) {
            language = Language.kor;
          } else {
            language = Language.eng;
          }
          model.changeLanguage(language);
        };

        platformDispatcher.onPlatformBrightnessChanged = () {
          if (model.brightness != platformDispatcher.platformBrightness) {
            model.toggleBrightness();
          }
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
          title: string.title.getLocalizedString(bapu.language),
          theme: ThemeData(
            fontFamily: 'Pretendard',
            brightness: bapu.brightness,
            colorScheme:
                ColorScheme.fromSeed(
                  seedColor: mainColor,
                  brightness: bapu.brightness,
                  dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
                ).copyWith(
                  onPrimaryContainer: Colors.white,
                  surface: bapu.brightness == Brightness.light
                      ? Colors.white
                      : Colors.black,
                  surfaceContainer: bapu.brightness == Brightness.light
                      ? Color.fromARGB(0xff, 0xfA, 0xfA, 0xfA)
                      : Color.fromARGB(0xff, 0xf, 0xf, 0xf),
                ),
          ),
          scrollBehavior: MaterialScrollBehavior().copyWith(overscroll: false),
          home: child,
        );
      },
      child: const HomePage(),
    );
  }
}
