import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meal_client/domain/meal.dart';
import 'package:meal_client/features/info/announcement_state.dart';
import 'package:meal_client/features/info/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const infoJson = {
    'announcement': {
      'title': {'ko': '제목', 'en': 'Title'},
      'content': {'ko': '공지사항입니다', 'en': 'This is announcement'},
      'showAnnouncementEveryTime': false,
    },
    'operatingHours': {
      'weekday': {
        'dormitory': {
          'breakfast': {'start': '08:00', 'end': '09:20'},
          'lunch': {'start': '11:30', 'end': '13:30'},
          'dinner': {'start': '17:30', 'end': '19:20'},
        },
        'student': {
          'lunch': {'start': '11:00', 'end': '13:30'},
          'dinner': {'start': '17:00', 'end': '19:00'},
        },
        'faculty': {
          'lunch': {'start': '11:00', 'end': '13:00'},
          'dinner': {'start': '17:30', 'end': '19:30'},
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
  };

  group('AppInfo.fromJson', () {
    test('공지사항의 다국어 제목과 본문을 파싱한다', () {
      final info = AppInfo.fromJson(infoJson);

      expect(info.announcement?.title?.textFor('ko'), '제목');
      expect(info.announcement?.title?.textFor('en'), 'Title');
      expect(info.announcement?.content.textFor('ko'), '공지사항입니다');
      expect(info.announcement?.content.textFor('en'), 'This is announcement');
      expect(info.announcement?.showAnnouncementEveryTime, isFalse);
    });

    test('announcement가 null이면 공지 없음으로 파싱한다', () {
      final info = AppInfo.fromJson({...infoJson, 'announcement': null});

      expect(info.announcement, isNull);
    });

    test('평일/주말 운영시간과 생략된 식당을 구분한다', () {
      final info = AppInfo.fromJson(infoJson);

      expect(
        info.operatingHours.weekday
            .timeFor(Cafeteria.dormitory, MealOfDay.breakfast)
            ?.label,
        '08:00 - 09:20',
      );
      expect(
        info.operatingHours.weekday.timeFor(
          Cafeteria.student,
          MealOfDay.breakfast,
        ),
        isNull,
      );
      expect(
        info.operatingHours.weekend
            .timeFor(Cafeteria.dormitory, MealOfDay.dinner)
            ?.label,
        '17:30 - 19:00',
      );
      expect(
        info.operatingHours.weekend.timeFor(Cafeteria.student, MealOfDay.lunch),
        isNull,
      );
    });
  });

  group('checkForNewAnnouncement', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('이전 공지와 본문이 같으면 다시 표시하지 않는다', () async {
      final info = AppInfo.fromJson(infoJson);

      final first = await checkForNewAnnouncement(loadInfo: () async => info);
      final second = await checkForNewAnnouncement(loadInfo: () async => info);

      expect(first?.content.textFor('ko'), '공지사항입니다');
      expect(second, isNull);
    });

    test('showAnnouncementEveryTime이 true이면 같은 본문도 다시 표시한다', () async {
      final info = AppInfo.fromJson({
        ...infoJson,
        'announcement': {
          ...infoJson['announcement']! as Map<String, Object?>,
          'showAnnouncementEveryTime': true,
        },
      });

      final first = await checkForNewAnnouncement(loadInfo: () async => info);
      final second = await checkForNewAnnouncement(loadInfo: () async => info);

      expect(first, isNotNull);
      expect(second, isNotNull);
    });

    test('저장된 공지 JSON을 다시 읽는다', () async {
      final info = AppInfo.fromJson(infoJson);
      await checkForNewAnnouncement(loadInfo: () async => info);

      final saved = await getStoredAnnouncement();

      expect(saved?.title?.textFor('ko'), '제목');
      expect(saved?.content.textFor('en'), 'This is announcement');
    });
  });

  test('API JSON 문자열을 모델로 변환할 수 있다', () {
    final raw = jsonEncode(infoJson);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;

    expect(AppInfo.fromJson(decoded).announcement?.content.ko, '공지사항입니다');
  });
}
