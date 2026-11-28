import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/home/meal_card.dart';
import 'package:meal_client/l10n/app_localizations.dart';

// 실제 잉크 애니메이션이 제거되는지를 관찰한다.
class _TrackingSplashFactory extends InteractiveInkFeatureFactory {
  _TrackingSplashFactory(this.delegate);

  final InteractiveInkFeatureFactory delegate;
  int activeCount = 0;

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
    activeCount++;
    return delegate.create(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      textDirection: textDirection,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: () {
        activeCount--;
        onRemoved?.call();
      },
    );
  }
}

void main() {
  testWidgets('롱프레스 공유와 햅틱 순서를 유지하고 종료 이벤트 없이 잉크를 제거한다', (tester) async {
    final events = <String>[];
    final factory = _TrackingSplashFactory(InkRipple.splashFactory);
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
        theme: ThemeData(splashFactory: factory),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MealCard(
            title: '기숙사 식당',
            meal: Meal.regular(menu: const [MealMenuItem(ko: '쌀밥')]),
            onLongPress: (_) => events.add('share'),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MealCard)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(events, ['share', 'haptic']);
    expect(factory.activeCount, 1);
    await tester.pumpAndSettle();
    expect(factory.activeCount, 0);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('잉크 애니메이션 도중 카드를 제거해도 남은 효과와 ticker를 정리한다', (tester) async {
    for (final delegate in [InkRipple.splashFactory, InkSplash.splashFactory]) {
      final factory = _TrackingSplashFactory(delegate);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: factory),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MealCard(
              title: '기숙사 식당',
              meal: Meal.regular(menu: const [MealMenuItem(ko: '쌀밥')]),
              onLongPress: (_) {},
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MealCard)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(factory.activeCount, 1);
      await tester.pumpWidget(const SizedBox());
      expect(factory.activeCount, 0);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('영어 locale에서는 영어 메뉴명을 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
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
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
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

  testWidgets('서버의 섹션 제목과 제목 없는 섹션의 기본 제목을 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
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

    expect(find.text('천원의 아침밥'), findsOneWidget);
    final l10n = lookupAppLocalizations(const Locale('ko'));
    expect(find.text(l10n.menuSectionConvenience), findsOneWidget);
    expect(find.text('쌀밥'), findsOneWidget);
    expect(find.text('삼각김밥'), findsOneWidget);
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    required String menu,
    double width = 200,
    int? inlineKcal = 700,
    double? scale,
    double textScale = 1,
    Locale locale = const Locale('ko'),
    MediaQueryData? mediaQuery,
    bool isOperating = false,
  }) async {
    Widget card = SizedBox(
      width: width,
      child: MealCard(
        title: '기숙사 식당',
        operatingTimeLabel: '08:00 - 09:20',
        isOperating: isOperating,
        meal: Meal(
          sections: [
            MealSection(
              type: MealSectionType.regular,
              menu: [MealMenuItem(ko: menu, en: menu)],
              kcal: inlineKcal,
            ),
            const MealSection(
              type: MealSectionType.convenience,
              menu: [MealMenuItem(ko: '삼각김밥')],
              kcal: 300,
            ),
          ],
        ),
      ),
    );
    if (scale != null) {
      card = MealCardMetadataScaleScope(scale: scale, child: card);
    }
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data:
              mediaQuery ??
              MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: card),
          ),
        ),
      ),
    );
  }

  TextPainter measure(WidgetTester tester, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    return TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
      locale: paragraph.locale,
      textHeightBehavior: paragraph.textHeightBehavior,
      strutStyle: paragraph.strutStyle,
    )..layout(minWidth: paragraph.size.width, maxWidth: paragraph.size.width);
  }

  testWidgets('여러 줄 메뉴의 마지막 baseline에 칼로리를 오른쪽 정렬한다', (tester) async {
    const menu = '긴 메뉴 이름입니다\n밥';
    await pumpCard(tester, menu: menu, width: 240);
    final menuRect = tester.getRect(find.text(menu));
    final kcalRect = tester.getRect(find.text('700 kcal'));
    final menuPainter = measure(tester, menu);
    final kcalPainter = measure(tester, '700 kcal');
    try {
      expect(menuPainter.computeLineMetrics(), hasLength(2));
      expect(kcalRect.right, closeTo(menuRect.right, 0.01));
      expect(
        kcalRect.top + kcalPainter.computeLineMetrics().single.baseline,
        closeTo(
          menuRect.top + menuPainter.computeLineMetrics().last.baseline,
          0.01,
        ),
      );
      expect(kcalRect.bottom, lessThan(tester.getRect(find.text('삼각김밥')).top));
      expect(find.text('300 kcal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      menuPainter.dispose();
      kcalPainter.dispose();
    }
  });

  testWidgets('칼로리 유무와 관계없이 메뉴의 전체 폭과 줄바꿈을 유지한다', (tester) async {
    const menu = '아주 아주 아주 긴 메뉴 이름이 여기 들어갑니다 정말로 깁니다';
    await pumpCard(tester, menu: menu, inlineKcal: null);
    final originalSize = tester.getSize(find.text(menu));
    final originalPainter = measure(tester, menu);
    final originalWidths = originalPainter
        .computeLineMetrics()
        .map((line) => line.width)
        .toList();
    originalPainter.dispose();
    await pumpCard(tester, menu: menu);
    expect(tester.getSize(find.text(menu)), originalSize);
    final painter = measure(tester, menu);
    try {
      expect(
        painter.computeLineMetrics().map((line) => line.width).toList(),
        originalWidths,
      );
      expect(tester.takeException(), isNull);
    } finally {
      painter.dispose();
    }
  });

  testWidgets('마지막 줄에 공간이 부족하면 칼로리를 별도 줄 오른쪽에 표시한다', (tester) async {
    const menu = 'abcdefghij';
    await pumpCard(tester, menu: menu, width: 200);
    final menuRect = tester.getRect(find.text(menu));
    final kcalRect = tester.getRect(find.text('700 kcal'));
    expect(kcalRect.top, closeTo(menuRect.bottom, 0.01));
    expect(kcalRect.right, closeTo(menuRect.right, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('공통 배율과 시스템 글자 크기를 반영하고 의미를 한 번만 노출한다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final locale in [const Locale('ko'), const Locale('en')]) {
        for (final scale in [null, 0.5]) {
          await pumpCard(
            tester,
            menu: '밥',
            scale: scale,
            textScale: 2,
            locale: locale,
          );
          final inline = tester.widget<Text>(find.text('700 kcal'));
          final footer = tester.widget<Text>(find.text('300 kcal'));
          expect(inline.style!.fontSize, footer.style!.fontSize);
          expect(find.bySemanticsLabel('밥, 700 kcal'), findsOneWidget);
          expect(find.bySemanticsLabel('700 kcal'), findsNothing);
          expect(tester.takeException(), isNull);
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('배율 변경에 따라 마지막 줄 배치를 다시 계산한다', (tester) async {
    const menu = 'abcdef';
    await pumpCard(tester, menu: menu, width: 200, scale: 1);
    final menuRect = tester.getRect(find.text(menu));
    expect(
      tester.getRect(find.text('700 kcal')).top,
      closeTo(menuRect.bottom, 0.01),
    );
    await pumpCard(tester, menu: menu, width: 200, scale: 0.5);
    expect(
      tester.getRect(find.text('700 kcal')).top,
      lessThan(menuRect.bottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('접근성 굵기와 간격 설정에서도 마지막 줄 배치와 메뉴 높이가 일치한다', (tester) async {
    const menu = '긴 메뉴 이름입니다\n밥';
    for (final data in [
      const MediaQueryData(boldText: true),
      const MediaQueryData(lineHeightScaleFactorOverride: 2),
      const MediaQueryData(letterSpacingOverride: 3, wordSpacingOverride: 5),
      const MediaQueryData(
        boldText: true,
        lineHeightScaleFactorOverride: 2,
        letterSpacingOverride: 3,
        wordSpacingOverride: 5,
      ),
    ]) {
      await pumpCard(tester, menu: menu, width: 300, mediaQuery: data);
      final menuRect = tester.getRect(find.text(menu));
      final kcalRect = tester.getRect(find.text('700 kcal'));
      final menuPainter = measure(tester, menu);
      final kcalPainter = measure(tester, '700 kcal');
      try {
        expect(kcalRect.right, closeTo(menuRect.right, 0.01));
        expect(
          kcalRect.top + kcalPainter.computeLineMetrics().single.baseline,
          closeTo(
            menuRect.top + menuPainter.computeLineMetrics().last.baseline,
            0.01,
          ),
        );
        expect(
          menuRect.bottom,
          lessThan(tester.getRect(find.text('삼각김밥')).top),
        );
        final inlineHeight = menuRect.height;
        final inlineWidths = menuPainter
            .computeLineMetrics()
            .map((line) => line.width)
            .toList();
        await pumpCard(
          tester,
          menu: menu,
          width: 300,
          mediaQuery: data,
          inlineKcal: null,
        );
        expect(tester.getSize(find.text(menu)).height, inlineHeight);
        final plainPainter = measure(tester, menu);
        try {
          expect(
            plainPainter
                .computeLineMetrics()
                .map((line) => line.width)
                .toList(),
            inlineWidths,
          );
        } finally {
          plainPainter.dispose();
        }
        expect(tester.takeException(), isNull);
      } finally {
        menuPainter.dispose();
        kcalPainter.dispose();
      }
    }
  });

  testWidgets('운영시간 의미에 현지화된 운영 상태를 포함한다', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final locale in [const Locale('ko'), const Locale('en')]) {
        final l10n = lookupAppLocalizations(locale);
        for (final isOperating in [false, true]) {
          await pumpCard(
            tester,
            menu: '밥',
            locale: locale,
            isOperating: isOperating,
          );
          final status = isOperating
              ? l10n.cafeteriaOperating
              : l10n.cafeteriaNotOperating;
          expect(
            find.bySemanticsLabel('08:00 - 09:20, $status'),
            findsOneWidget,
          );
          expect(find.bySemanticsLabel('08:00 - 09:20'), findsNothing);
        }
      }
    } finally {
      semantics.dispose();
    }
  });
}
