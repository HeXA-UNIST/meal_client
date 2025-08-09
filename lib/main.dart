import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:provider/provider.dart';

import 'i18n.dart';
import 'string.dart' as string;
import 'meal.dart';
import 'model.dart';

import 'pages/home.dart';

const mainColor = Color(0xFF00CD80);

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => BapUModel(
        language: Language.kor,
        brightness:
            SchedulerBinding.instance.platformDispatcher.platformBrightness,
      ),
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
        if (bapu.brightness != MediaQuery.of(context).platformBrightness) {
          bapu.toggleBrightness();
        }

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
                ),
          ),
          home: child,
        );
      },
      child: const HomePage(),
    );
  }
}
