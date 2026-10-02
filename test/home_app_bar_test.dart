import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/home/home_app_bar.dart';
import 'package:meal_client/l10n/app_localizations.dart';

void main() {
  testWidgets('요일 탭의 터치 영역을 확보하고 탭 선택을 반영한다', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final semanticsHandle = tester.ensureSemantics();
    final tabController = TabController(length: 7, vsync: tester);
    try {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                DayOfWeekTabBar(tabController: tabController),
                MealOfDaySwitchButton(
                  onPressed: () {},
                  label: '아침',
                  icon: Icons.sunny,
                ),
              ],
            ),
          ),
        ),
      );

      for (final label in ['월', '화', '수', '목', '금', '토', '일']) {
        final semantics = tester.getSemantics(
          find.bySemanticsLabel(RegExp('^$label')),
        );
        expect(
          semantics.rect.height,
          greaterThanOrEqualTo(44),
          reason: '$label 탭의 터치 영역 높이',
        );
        expect(
          semantics.rect.width,
          greaterThanOrEqualTo(48),
          reason: '$label 탭의 터치 영역 너비',
        );
      }

      await tester.tap(find.bySemanticsLabel(RegExp('^수')));
      await tester.pumpAndSettle();

      expect(tabController.index, 2);
    } finally {
      tabController.dispose();
      semanticsHandle.dispose();
    }
  });
}
