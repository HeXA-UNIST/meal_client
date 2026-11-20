import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
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
                DayOfWeekTabBar(
                  tabController: tabController,
                  today: DayOfWeek.thu,
                ),
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

      final barRect = tester.getRect(find.byType(DayOfWeekTabBar));
      await tester.tapAt(Offset(barRect.left + 9, barRect.center.dy));
      await tester.pumpAndSettle();
      expect(tabController.index, 0, reason: '둥근 바의 왼쪽 끝도 월요일을 선택한다');

      await tester.tapAt(Offset(barRect.right - 9, barRect.center.dy));
      await tester.pumpAndSettle();
      expect(tabController.index, 6, reason: '둥근 바의 오른쪽 끝도 일요일을 선택한다');

      await tester.tapAt(Offset(barRect.left + 9, barRect.top + 1));
      await tester.pumpAndSettle();
      expect(tabController.index, 6, reason: '둥근 바깥 모서리는 터치 영역에서 제외한다');
    } finally {
      tabController.dispose();
      semanticsHandle.dispose();
    }
  });
}
