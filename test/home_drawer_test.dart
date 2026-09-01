import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/home/home_drawer.dart';
import 'package:meal_client/features/home/next_week_preview_page.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/l10n/app_localizations.dart';

void main() {
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
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

    expect(find.text('Operation Hours'), findsOneWidget);
    expect(find.text('17:30 - 19:00'), findsNothing);
    expect(find.text('17:30 - 19:20'), findsNothing);

    await tester.tap(find.text('Operation Hours'));
    await tester.pumpAndSettle();

    expect(find.text('Weekday'), findsOneWidget);
    expect(find.text('Weekend'), findsOneWidget);
    expect(find.text('Dormitory'), findsNWidgets(2));
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
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

    expect(find.text("Next Week's Menu Preview"), findsOneWidget);

    await tester.tap(find.text("Next Week's Menu Preview"));
    await tester.pumpAndSettle();

    expect(find.byType(NextWeekPreviewPage), findsOneWidget);
  });
}
