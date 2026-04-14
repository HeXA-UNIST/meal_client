import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meal_client/main.dart';
import 'package:meal_client/model.dart';

void main() {
  test('BapUModel은 인수 없이 생성 가능하다', () {
    expect(() => BapUModel(), returnsNormally);
  });

  testWidgets('MyApp은 ThemeMode.system으로 렌더링된다', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
  });

  testWidgets('MyApp의 라이트/다크 테마에 Pretendard 폰트가 설정된다', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    // ThemeData는 fontFamily public getter가 없으므로 textTheme을 통해 간접 검증한다.
    expect(
      app.theme?.textTheme.bodyMedium?.fontFamily,
      'Pretendard',
    );
    expect(
      app.darkTheme?.textTheme.bodyMedium?.fontFamily,
      'Pretendard',
    );
  });
}
