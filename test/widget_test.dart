// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meal_client/i18n.dart';
import 'package:meal_client/model.dart';

void main() {
  test('BapUModel은 같은 밝기값이면 알림하지 않는다', () {
    final model = BapUModel(
      language: Language.kor,
      themeBrightness: Brightness.light,
    );

    var notifyCount = 0;
    model.addListener(() {
      notifyCount += 1;
    });

    model.setThemeBrightness(Brightness.light);

    expect(model.themeBrightness, Brightness.light);
    expect(notifyCount, 0);
  });

  test('BapUModel은 밝기값이 바뀌면 갱신하고 알림한다', () {
    final model = BapUModel(
      language: Language.kor,
      themeBrightness: Brightness.light,
    );

    var notifyCount = 0;
    model.addListener(() {
      notifyCount += 1;
    });

    model.setThemeBrightness(Brightness.dark);

    expect(model.themeBrightness, Brightness.dark);
    expect(notifyCount, 1);
  });

  testWidgets('themeBrightness 변경이 MaterialApp 테마에 반영된다', (
    WidgetTester tester,
  ) async {
    final model = BapUModel(
      language: Language.kor,
      themeBrightness: Brightness.light,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<BapUModel>.value(
        value: model,
        child: Consumer<BapUModel>(
          builder: (context, bapu, child) {
            return MaterialApp(
              theme: ThemeData(brightness: bapu.themeBrightness),
              home: const SizedBox.shrink(),
            );
          },
        ),
      ),
    );

    var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.brightness, Brightness.light);

    model.setThemeBrightness(Brightness.dark);
    await tester.pump();

    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.brightness, Brightness.dark);
  });
}
