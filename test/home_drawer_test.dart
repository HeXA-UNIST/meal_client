import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/core/constants.dart';
import 'package:meal_client/features/home/home_drawer.dart';
import 'package:meal_client/features/home/next_week_preview_page.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final hasAnnouncement in [true, false]) {
    testWidgets(
      hasAnnouncement
          ? '저장된 과거 공지가 있어도 메뉴는 최신 공지를 표시한다'
          : '서버에 공지가 없으면 저장된 과거 공지 대신 공지 없음으로 표시한다',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          StorageKeys.announcementKey: '과거 공지',
        });
        final info = AppInfo.fromJson({
          'announcement': hasAnnouncement
              ? {
                  'title': {'ko': '최신 제목', 'en': 'Latest title'},
                  'content': {'ko': '최신 공지', 'en': 'Latest announcement'},
                }
              : null,
          'operatingHours': {
            'weekday': <String, dynamic>{},
            'weekend': <String, dynamic>{},
          },
        });
        final scaffoldKey = GlobalKey<ScaffoldState>();

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ko'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              key: scaffoldKey,
              drawer: HomePageDrawer(infoFuture: Future.value(info)),
              body: const SizedBox.shrink(),
            ),
          ),
        );

        scaffoldKey.currentState!.openDrawer();
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(HomePageDrawer)),
        )!;
        await tester.tap(find.text(l10n.announcement));
        await tester.pumpAndSettle();

        expect(find.text('과거 공지'), findsNothing);
        expect(
          find.text(hasAnnouncement ? '최신 공지' : l10n.noAnnouncement),
          findsOneWidget,
        );
        if (hasAnnouncement) {
          expect(find.text('최신 제목'), findsOneWidget);
        }
      },
    );
  }

  testWidgets('HomePageDrawer는 운영시간을 메뉴 항목으로 표시하고 팝업에서 평일과 주말을 구분한다', (
    tester,
  ) async {
    final info = AppInfo.fromJson({
      'announcement': null,
      'operatingHours': {
        'weekday': {
          'dormitory': {
            'dinner': {'start': '17:30', 'end': '19:20'},
          },
        },
        'weekend': {
          'dormitory': {
            'dinner': {'start': '17:30', 'end': '19:00'},
          },
        },
      },
    });
    final scaffoldKey = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          key: scaffoldKey,
          drawer: HomePageDrawer(infoFuture: Future.value(info)),
          body: const SizedBox.shrink(),
        ),
      ),
    );

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomePageDrawer)),
    )!;
    expect(find.text('17:30 - 19:00'), findsNothing);
    expect(find.text('17:30 - 19:20'), findsNothing);

    await tester.tap(find.text(l10n.operationHours));
    await tester.pumpAndSettle();

    expect(find.text('17:30 - 19:20'), findsOneWidget);
    expect(find.text('17:30 - 19:00'), findsOneWidget);
  });

  testWidgets('다음 주 미리보기 항목을 탭하면 NextWeekPreviewPage로 이동한다', (tester) async {
    final info = AppInfo.fromJson({
      'announcement': null,
      'operatingHours': {
        'weekday': <String, dynamic>{},
        'weekend': <String, dynamic>{},
      },
    });
    final scaffoldKey = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          key: scaffoldKey,
          drawer: HomePageDrawer(
            infoFuture: Future.value(info),
            nextWeekStart: Future.value(null),
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(HomePageDrawer)),
    )!;
    await tester.tap(find.text(l10n.nextWeekPreview));
    // 이동만 검증하므로 데이터 조회 중인 로딩 애니메이션의 종료는 기다리지 않는다.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(NextWeekPreviewPage), findsOneWidget);
  });
}
