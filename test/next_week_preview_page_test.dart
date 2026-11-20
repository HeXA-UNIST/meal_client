import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:meal_client/features/home/next_week_preview_page.dart';
import 'package:meal_client/features/home/home_app_bar.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/l10n/app_localizations.dart';

AppInfo _emptyAppInfo() => AppInfo.fromJson({
  'announcement': null,
  'operatingHours': {
    'weekday': <String, dynamic>{},
    'weekend': <String, dynamic>{},
  },
});

void main() {
  testWidgets('미리보기 경계는 일요일에서 멈추고 월요일에서 이번 주로 돌아온다', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => NextWeekPreviewPage(
                    nextWeekStart: '2026-06-22',
                    initialMealOfDay: MealOfDay.dinner,
                    appInfo: Future.value(_emptyAppInfo()),
                    loadDatedWeek: (_) async =>
                        parseRawMeal(_emptyWeekRawJson('2026-06-22')),
                    onNextWeekMealRefreshed: () {},
                  ),
                ),
              ),
              child: const Text('이번 주'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('이번 주'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MealOfDaySwitchButton>(find.byType(MealOfDaySwitchButton))
          .label,
      '저녁',
    );
    Future<void> overscroll({required bool forward}) async {
      final center = tester.getCenter(find.byType(TabBarView));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: center,
          scrollDelta: Offset(forward ? 160 : -160, 0),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('일'));
    await tester.pumpAndSettle();
    await overscroll(forward: true);
    expect(find.byType(NextWeekPreviewPage), findsOneWidget);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 6);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('월'));
    await tester.pumpAndSettle();
    await overscroll(forward: false);
    expect(find.byType(NextWeekPreviewPage), findsNothing);
    expect(find.text('이번 주'), findsOneWidget);
  });
  testWidgets('다음 주 미준비 시 화면 전환 없이 안내 Toast를 띄운다', (tester) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('PonnamKarthik/fluttertoast');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return true;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openNextWeekPreview(
                context: context,
                nextWeekStartFuture: Future.value(null),
                appInfo: Future.value(_emptyAppInfo()),
              ),
              child: const Text('미리보기 열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('미리보기 열기'));
    await tester.pumpAndSettle();
    const message = '다음 주 식단이 아직 준비되지 않았어요.';
    expect(find.byType(NextWeekPreviewPage), findsNothing);
    expect(find.text('미리보기 열기'), findsOneWidget);
    if (kIsWeb) {
      expect(find.text(message), findsOneWidget);
      await tester.tap(find.text('미리보기 열기'));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(calls, isEmpty);
    } else {
      expect(calls.map((call) => call.method), ['cancel', 'showToast']);
      expect(calls.last.arguments['msg'], message);
    }
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
  });

  testWidgets('다음 주 식단을 불러오지 못하면 에러 메시지를 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: NextWeekPreviewPage(
          nextWeekStart: '2026-06-22',
          appInfo: Future.value(_emptyAppInfo()),
          loadDatedWeek: (_) async => throw Exception('network error'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.cannotLoadMeal), findsOneWidget);
    expect(find.byType(AnimatedDateTitle), findsOneWidget);
    expect(find.byType(DayOfWeekTabBar), findsOneWidget);
    expect(find.byType(MealOfDaySwitchButton), findsOneWidget);
  });

  testWidgets('nextWeekStart가 있으면 다음 주 데이터를 불러와 배너와 함께 보여준다', (tester) async {
    var datedLoads = 0;
    var notificationReconciliations = 0;
    final rawJson = jsonEncode({
      'week': {
        'startDate': '2026-06-22',
        'isCurrentWeek': false,
        'nextWeekStart': null,
      },
      'lastUpdated': '2026-06-22T09:00:00+09:00',
      'data': [
        {
          'cafeteria': 'DORMITORY',
          'meals': [
            {
              'date': '2026-06-22',
              'dayOfWeek': 'MON',
              'timeType': 'BREAKFAST',
              'menusByType': [
                {
                  'menuType': 'KOREAN',
                  'sections': [
                    {
                      'sectionType': 'REGULAR',
                      'sectionTitle': null,
                      'calorie': 500,
                      'sectionAllergens': null,
                      'menus': [
                        {'ko': '쌀밥', 'en': 'Rice', 'allergens': []},
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        // 이 테스트의 fixture는 실제 API 응답처럼 ko/en을 모두 채워서
        // 넣는다. MealCard는 Localizations.localeOf(context)로 언어를
        // 고르므로(meal_card.dart:30,61), 로케일을 명시하지 않으면 플러터
        // 테스트 기본 로케일(영어)에서 'Rice'가 표시되어 '쌀밥' 검증이
        // 실패한다. 다음 주 미리보기도 앱의 실제 언어 설정(한국어 기준
        // 문구)을 그대로 반영해야 하므로 한국어 로케일을 명시한다.
        locale: const Locale('ko'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: NextWeekPreviewPage(
          nextWeekStart: '2026-06-22',
          appInfo: Future.value(_emptyAppInfo()),
          loadDatedWeek: (_) async {
            datedLoads++;
            return parseRawMeal(rawJson);
          },
          onNextWeekMealRefreshed: () => notificationReconciliations++,
        ),
      ),
    );

    await tester.pumpAndSettle();

    final l10n = lookupAppLocalizations(const Locale('ko'));
    expect(find.text(l10n.previewingNextWeek), findsOneWidget);
    expect(find.text('쌀밥'), findsOneWidget);
    expect(datedLoads, 1);
    expect(notificationReconciliations, 1);
  });
}

String _emptyWeekRawJson(String weekStart) => jsonEncode({
  'week': {
    'startDate': weekStart,
    'isCurrentWeek': false,
    'nextWeekStart': null,
  },
  'data': <Object?>[],
});
