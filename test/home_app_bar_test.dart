import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/home/home_app_bar.dart';
import 'package:meal_client/l10n/app_localizations.dart';

void main() {
  testWidgets('요일바는 44px이고 선택 필박스와 끼니 버튼은 36px이다', (tester) async {
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
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

      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      final tabBarSize = tester.getSize(find.byType(TabBar));
      final tabBarBackground = find.descendant(
        of: find.byType(DayOfWeekTabBar),
        matching: find.byType(DecoratedBox),
      );
      final tabBarBackgroundSize = tester.getSize(tabBarBackground);
      final mealButton = find.byType(TextButton);
      final mealButtonMaterial = find.descendant(
        of: mealButton,
        matching: find.byType(Material),
      );

      expect(
        tester
            .widget<DayOfWeekTabBar>(find.byType(DayOfWeekTabBar))
            .preferredSize,
        const Size.fromHeight(44),
      );
      expect(tabBarSize.height, 44);
      expect(tabBarBackgroundSize.height, 44);
      expect(tabBarBackgroundSize.width - tabBarSize.width, 8);
      expect(tabBar.indicatorSize, TabBarIndicatorSize.tab);
      expect(tabBar.indicatorPadding, const EdgeInsets.symmetric(vertical: 4));
      expect(tabBarSize.height - tabBar.indicatorPadding.vertical, 36);

      expect(tester.getSize(mealButton).height, 44);
      expect(tester.getSize(mealButtonMaterial).height, 36);

      for (final label in ['월', '화', '수', '목', '금', '토', '일']) {
        final semantics = tester.getSemantics(
          find.bySemanticsLabel(RegExp('^$label')),
        );
        expect(semantics.rect.height, 44, reason: '$label 탭의 터치 영역 높이');
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
