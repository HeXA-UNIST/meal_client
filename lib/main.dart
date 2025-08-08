import 'package:flutter/material.dart';

import 'i18n.dart';
import 'string.dart' as string;
import 'pages/bapu_main.dart';

const mainColor = Color(0xFF00CD80);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Brightness.light;
    final language = Language.kor;
    return MaterialApp(
      title: string.title.getLocalizedString(language),
      theme: ThemeData(
        fontFamily: 'Pretendard',
        brightness: brightness,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: mainColor,
              brightness: brightness,
              dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
            ).copyWith(
              onPrimaryContainer: Colors.white,
              surface: brightness == Brightness.light
                  ? Colors.white
                  : Colors.black,
            ),
      ),
      home: const MainPage(),
    );
  }
}

