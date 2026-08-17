import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/home/next_week_preview_page.dart';
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
  testWidgets('nextWeekStart 조회 중에는 로딩 인디케이터를 보여준다', (tester) async {
    final completer = Completer<String?>();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NextWeekPreviewPage(
          nextWeekStartFuture: completer.future,
          appInfo: Future.value(_emptyAppInfo()),
          refreshNextWeekStart: () async => null,
        ),
      ),
    );

    // completer가 끝나지 않아 CircularProgressIndicator가 무기한
    // 애니메이션 중이므로, pumpAndSettle이 아닌 pump 한 프레임만 진행한다.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 위젯 트리를 정리해 completer의 future가 dangling되지 않게 한다.
    completer.complete(null);
    await tester.pump();
    await tester.pump();
  });

  testWidgets('다음 주 식단을 불러오지 못하면 에러 메시지를 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NextWeekPreviewPage(
          nextWeekStartFuture: Future.value('2026-06-22'),
          appInfo: Future.value(_emptyAppInfo()),
          loadDatedWeek: (_) async => throw Exception('network error'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('Cannot load meal information.'), findsOneWidget);
  });

  testWidgets('nextWeekStart가 null이면 준비되지 않음 메시지를 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NextWeekPreviewPage(
          nextWeekStartFuture: Future.value(null),
          appInfo: Future.value(_emptyAppInfo()),
          refreshNextWeekStart: () async => null,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text("Next week's menu isn't ready yet."), findsOneWidget);
  });

  testWidgets('nextWeekStart가 있으면 다음 주 데이터를 불러와 배너와 함께 보여준다', (tester) async {
    var metadataRefreshes = 0;
    var datedLoads = 0;
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NextWeekPreviewPage(
          nextWeekStartFuture: Future.value('2026-06-22'),
          appInfo: Future.value(_emptyAppInfo()),
          refreshNextWeekStart: () async {
            metadataRefreshes++;
            return '2026-06-22';
          },
          loadDatedWeek: (_) async {
            datedLoads++;
            return parseRawMeal(rawJson);
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('다음 주 미리보기 중'), findsOneWidget);
    expect(find.text('쌀밥'), findsOneWidget);
    expect(metadataRefreshes, 0);
    expect(datedLoads, 1);
  });

  testWidgets('다음 주 날짜가 없으면 current metadata를 한 번만 갱신한다', (tester) async {
    var metadataRefreshes = 0;
    var datedFetches = 0;
    final rawJson = _emptyWeekRawJson('2026-06-22');

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NextWeekPreviewPage(
          nextWeekStartFuture: Future.value(null),
          appInfo: Future.value(_emptyAppInfo()),
          refreshNextWeekStart: () async {
            metadataRefreshes++;
            return '2026-06-22';
          },
          loadDatedWeek: (_) async {
            datedFetches++;
            return parseRawMeal(rawJson);
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(metadataRefreshes, 1);
    expect(datedFetches, 1);
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
