import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/home/meal_card.dart';
import 'package:meal_client/l10n/app_localizations.dart';

void main() {
  Finder findOperatingTimeText() {
    return find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('08:00 - 09:20'),
    );
  }

  testWidgets('운영시간은 칼로리보다 굵은 글씨로 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MealCard(
            title: '기숙사 식당',
            meal: Meal.regular(menu: const [MealMenuItem(ko: '쌀밥')], kcal: 935),
            operatingTimeLabel: '08:00 - 09:20',
            isOperating: true,
          ),
        ),
      ),
    );

    final timeText = tester.widget<RichText>(findOperatingTimeText());
    final kcalText = tester.widget<Text>(find.text('935 kcal'));
    final timeStyle = (timeText.text as TextSpan).style;

    expect(timeStyle?.fontWeight, FontWeight.w700);
    expect(kcalText.style?.fontWeight, isNot(FontWeight.w700));
  });

  testWidgets('롱프레스에서는 공유 콜백을 먼저 실행하고 첫 ink 프레임 뒤 햅틱을 실행한다', (tester) async {
    final events = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          events.add('haptic');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MealCard(
            title: '기숙사 식당',
            meal: Meal.regular(menu: const [MealMenuItem(ko: '쌀밥')]),
            onLongPress: () => events.add('share'),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MealCard)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(events, ['share', 'haptic']);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('영어 locale에서는 영어 메뉴명을 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MealCard(
            title: 'Dormitory',
            meal: Meal.regular(
              menu: const [MealMenuItem(ko: '쌀밥', en: 'Rice')],
              kcal: 935,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('쌀밥'), findsNothing);
  });

  testWidgets('영어 locale에서 영어 메뉴명이 없으면 한국어 메뉴명을 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MealCard(
            title: 'Student',
            meal: Meal.regular(menu: const [MealMenuItem(ko: '된장찌개')]),
          ),
        ),
      ),
    );

    expect(find.text('된장찌개'), findsOneWidget);
  });

  testWidgets('섹션 제목을 메뉴 위에 작은 굵은 글씨로 좌측 정렬해 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MealCard(
            title: '기숙사 식당',
            meal: const Meal(
              sections: [
                MealSection(
                  type: MealSectionType.regular,
                  title: MealSectionTitle(ko: '천원의 아침밥'),
                  menu: [MealMenuItem(ko: '쌀밥')],
                ),
                MealSection(
                  type: MealSectionType.convenience,
                  menu: [MealMenuItem(ko: '삼각김밥')],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final titleText = tester.widget<Text>(find.text('천원의 아침밥'));
    expect(titleText.textAlign, isNull);
    expect(titleText.style?.fontWeight, FontWeight.w600);
    final l10n = lookupAppLocalizations(const Locale('ko'));
    expect(find.text(l10n.menuSectionConvenience), findsOneWidget);
    expect(find.text('쌀밥'), findsOneWidget);
    expect(find.text('삼각김밥'), findsOneWidget);
  });

  testWidgets(
    '섹션이 2개 이상이면 마지막 섹션 이전 칼로리는 구분선 위 마지막 메뉴 줄에, 마지막 섹션 칼로리는 운영시간 옆에 표시한다',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ko'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MealCard(
              title: '기숙사 식당',
              operatingTimeLabel: '08:00 - 09:20',
              meal: const Meal(
                sections: [
                  MealSection(
                    type: MealSectionType.regular,
                    menu: [MealMenuItem(ko: '쌀밥')],
                    kcal: 700,
                  ),
                  MealSection(
                    type: MealSectionType.convenience,
                    menu: [MealMenuItem(ko: '삼각김밥')],
                    kcal: 300,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // 첫 섹션(마지막 섹션이 아님)의 칼로리는 해당 섹션 마지막 메뉴 줄과 같은 Row에서
      // Expanded 옆에 인라인으로 렌더링된다.
      final inlineKcal = find.text('700 kcal');
      expect(inlineKcal, findsOneWidget);
      expect(
        find.ancestor(of: inlineKcal, matching: find.byType(Expanded)),
        findsNothing,
      );
      final inlineRow = find.ancestor(
        of: inlineKcal,
        matching: find.byType(Row),
      );
      expect(inlineRow, findsOneWidget);
      expect(
        find.descendant(of: inlineRow, matching: find.text('쌀밥')),
        findsOneWidget,
      );

      // 마지막 섹션의 칼로리는 기존처럼 카드 하단 운영시간 옆에 표시된다.
      expect(find.text('300 kcal'), findsOneWidget);
    },
  );

  testWidgets('인라인 칼로리가 있는 마지막 메뉴는 겹치지 않도록 Expanded로 줄바꿈 가능해진다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: MealCard(
              title: '기숙사 식당',
              meal: const Meal(
                sections: [
                  MealSection(
                    type: MealSectionType.regular,
                    menu: [
                      MealMenuItem(ko: '아주 아주 아주 긴 메뉴 이름이 여기 들어갑니다 정말로 깁니다'),
                    ],
                    kcal: 700,
                  ),
                  MealSection(
                    type: MealSectionType.convenience,
                    menu: [MealMenuItem(ko: '삼각김밥')],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final longMenuFinder = find.textContaining('아주 아주 아주 긴 메뉴');
    final menuText = tester.widget<Text>(longMenuFinder);
    expect(
      find.ancestor(of: longMenuFinder, matching: find.byType(Expanded)),
      findsOneWidget,
    );
    // Expanded가 칼로리 라벨 폭을 먼저 확보하므로 긴 메뉴 텍스트는 줄바꿈된다.
    final renderParagraph = tester.renderObject<RenderParagraph>(
      longMenuFinder,
    );
    expect(renderParagraph.text.toPlainText(), menuText.data);
    expect(renderParagraph.size.height, greaterThan(20));
  });
}
