import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/home/meal_card.dart';

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
        home: Scaffold(
          body: MealCard(
            title: '기숙사 식당',
            meal: const Meal(['쌀밥'], 935),
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
        home: Scaffold(
          body: MealCard(
            title: '기숙사 식당',
            meal: const Meal(['쌀밥'], 935),
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
}
