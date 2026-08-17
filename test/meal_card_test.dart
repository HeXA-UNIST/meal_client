import 'package:flutter/material.dart';
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

  testWidgets('운영시간은 칼로리보다 굵은 글씨로 표시하고, 운영 중일 때는 회색이 아닌 색으로 표시한다', (
    tester,
  ) async {
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
    expect(
      timeStyle?.color,
      isNot(
        Theme.of(tester.element(find.byType(MealCard))).colorScheme.outline,
      ),
    );
  });

  testWidgets('운영 중이 아닌 운영시간은 회색으로 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MealCard(
            title: '기숙사 식당',
            meal: Meal.regular(menu: const [MealMenuItem(ko: '쌀밥')], kcal: 935),
            operatingTimeLabel: '08:00 - 09:20',
            isOperating: false,
          ),
        ),
      ),
    );

    final timeText = tester.widget<RichText>(findOperatingTimeText());
    final timeStyle = (timeText.text as TextSpan).style;

    expect(
      timeStyle?.color,
      Theme.of(tester.element(find.byType(MealCard))).colorScheme.outline,
    );
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

  testWidgets('섹션 제목을 메뉴 위에 작은 회색 굵은 글씨로 좌측 정렬해 표시한다', (tester) async {
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
    expect(
      titleText.style?.color,
      Theme.of(tester.element(find.byType(MealCard))).colorScheme.outline,
    );
    expect(find.text('간편식'), findsOneWidget);
    expect(find.text('쌀밥'), findsOneWidget);
    expect(find.text('삼각김밥'), findsOneWidget);
  });
}
