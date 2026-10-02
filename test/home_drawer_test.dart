import 'package:material_ui/material_ui.dart';
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
    await tester.pumpAndSettle();

    expect(find.byType(NextWeekPreviewPage), findsOneWidget);
  });
}
