import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/features/home/home_drawer.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:meal_client/l10n/app_localizations.dart';

void main() {
  testWidgets('HomePageDrawer는 API의 주말 운영시간만 표시한다', (tester) async {
    final info = AppInfo.fromJson({
      'announcement': null,
      'operatingHours': {
        'weekday': {
          'dormitory': {
            'breakfast': {'start': '08:00', 'end': '09:20'},
            'lunch': {'start': '11:30', 'end': '13:30'},
            'dinner': {'start': '17:30', 'end': '19:20'},
          },
          'student': {
            'lunch': {'start': '11:00', 'end': '13:30'},
          },
        },
        'weekend': {
          'dormitory': {
            'breakfast': {'start': '08:00', 'end': '09:20'},
            'lunch': {'start': '11:30', 'end': '13:30'},
            'dinner': {'start': '17:30', 'end': '19:00'},
          },
        },
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: HomePageDrawer(
            infoFuture: Future.value(info),
            currentKstDate: DateTime(2026, 6, 20),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dormitory'), findsOneWidget);
    expect(find.text('Student'), findsNothing);
    expect(find.text('17:30 - 19:00'), findsOneWidget);
    expect(find.text('17:30 - 19:20'), findsNothing);
  });
}
