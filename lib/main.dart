import 'package:flutter/material.dart';
import 'package:meal_client/meal.dart';
import 'package:meal_client/model.dart';
import 'package:provider/provider.dart';

import 'i18n.dart';
import 'string.dart' as string;
import 'pages/bapu_main.dart';

const mainColor = Color(0xFF00CD80);

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => BapUModel(
        language: Language.kor,
        brightness: Brightness.light,
        month: 6,
        day: 27,
        mealOfDay: MealOfDay.lunch,
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
      builder: (context, bapu, child) => MaterialApp(
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
      ),
      child: const MainPage(),
    );
  }
}
