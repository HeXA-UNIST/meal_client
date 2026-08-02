import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/main.dart';
import 'package:meal_client/features/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildApp() {
  return FutureBuilder<SharedPreferences>(
    future: SharedPreferences.getInstance(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const SizedBox();
      return ChangeNotifierProvider(
        create: (_) => AppSettings(snapshot.data!),
        child: const BapUApp(home: SizedBox()),
      );
    },
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('BapUApp은 ThemeMode.system으로 렌더링된다', (WidgetTester tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pump();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
  });

  testWidgets('BapUApp의 라이트/다크 테마에 Pretendard 폰트가 설정된다', (WidgetTester tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pump();
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
