import 'dart:convert';

import 'package:meal_client/domain/meal.dart';

class AppInfo {
  final AppAnnouncement? announcement;
  final OperatingHours operatingHours;

  const AppInfo({required this.announcement, required this.operatingHours});

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    final announcementJson = json['announcement'];
    return AppInfo(
      announcement: announcementJson == null
          ? null
          : AppAnnouncement.fromJson(announcementJson as Map<String, dynamic>),
      operatingHours: OperatingHours.fromJson(
        json['operatingHours'] as Map<String, dynamic>,
      ),
    );
  }
}

class LocalizedText {
  final String ko;
  final String en;

  const LocalizedText({required this.ko, required this.en});

  factory LocalizedText.fromJson(Map<String, dynamic> json) {
    return LocalizedText(ko: json['ko'] as String, en: json['en'] as String);
  }

  factory LocalizedText.fromLegacyContent(String content) {
    return LocalizedText(ko: content, en: content);
  }

  Map<String, dynamic> toJson() => {'ko': ko, 'en': en};

  String textFor(String languageCode) => languageCode == 'en' ? en : ko;
}

class AppAnnouncement {
  final LocalizedText? title;
  final LocalizedText content;
  final bool showAnnouncementEveryTime;

  const AppAnnouncement({
    required this.title,
    required this.content,
    required this.showAnnouncementEveryTime,
  });

  factory AppAnnouncement.fromJson(Map<String, dynamic> json) {
    final titleJson = json['title'];
    return AppAnnouncement(
      title: titleJson == null
          ? null
          : LocalizedText.fromJson(titleJson as Map<String, dynamic>),
      content: LocalizedText.fromJson(json['content'] as Map<String, dynamic>),
      showAnnouncementEveryTime:
          json['showAnnouncementEveryTime'] as bool? ?? false,
    );
  }

  factory AppAnnouncement.fromStoredString(String value) {
    try {
      final decoded = jsonDecode(value) as Map<String, dynamic>;
      return AppAnnouncement.fromJson(decoded);
    } on Object {
      return AppAnnouncement(
        title: null,
        content: LocalizedText.fromLegacyContent(value),
        showAnnouncementEveryTime: false,
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'title': title?.toJson(),
    'content': content.toJson(),
    'showAnnouncementEveryTime': showAnnouncementEveryTime,
  };

  String get contentFingerprint => jsonEncode(content.toJson());
}

class OperatingHours {
  final OperatingHoursPeriod weekday;
  final OperatingHoursPeriod weekend;

  const OperatingHours({required this.weekday, required this.weekend});

  factory OperatingHours.fromJson(Map<String, dynamic> json) {
    return OperatingHours(
      weekday: OperatingHoursPeriod.fromJson(
        json['weekday'] as Map<String, dynamic>,
      ),
      weekend: OperatingHoursPeriod.fromJson(
        json['weekend'] as Map<String, dynamic>,
      ),
    );
  }

  OperatingHoursPeriod forDate(DateTime kstDate) {
    return kstDate.weekday == DateTime.saturday ||
            kstDate.weekday == DateTime.sunday
        ? weekend
        : weekday;
  }
}

class OperatingHoursPeriod {
  final Map<Cafeteria, Map<MealOfDay, OperatingTimeRange>> _hours;

  const OperatingHoursPeriod(this._hours);

  factory OperatingHoursPeriod.fromJson(Map<String, dynamic> json) {
    return OperatingHoursPeriod({
      for (final cafeteriaEntry in json.entries)
        _cafeteriaFromInfoKey(cafeteriaEntry.key): {
          for (final mealEntry
              in (cafeteriaEntry.value as Map<String, dynamic>).entries)
            _mealOfDayFromInfoKey(mealEntry.key): OperatingTimeRange.fromJson(
              mealEntry.value as Map<String, dynamic>,
            ),
        },
    });
  }

  Iterable<Cafeteria> get cafeterias => _hours.keys;

  OperatingTimeRange? timeFor(Cafeteria cafeteria, MealOfDay mealOfDay) {
    return _hours[cafeteria]?[mealOfDay];
  }

  List<OperatingTimeRange> timesFor(Cafeteria cafeteria) {
    final cafeteriaHours = _hours[cafeteria];
    if (cafeteriaHours == null) {
      return const [];
    }
    return [
      for (final mealOfDay in MealOfDay.values)
        if (cafeteriaHours[mealOfDay] != null) cafeteriaHours[mealOfDay]!,
    ];
  }
}

class OperatingTimeRange {
  final String start;
  final String end;

  const OperatingTimeRange({required this.start, required this.end});

  factory OperatingTimeRange.fromJson(Map<String, dynamic> json) {
    return OperatingTimeRange(
      start: json['start'] as String,
      end: json['end'] as String,
    );
  }

  String get label => '$start - $end';

  bool contains(DateTime time) {
    final currentMinutes = time.hour * 60 + time.minute;
    return _minutesOfDay(start) <= currentMinutes &&
        currentMinutes <= _minutesOfDay(end);
  }
}

int _minutesOfDay(String value) {
  final parts = value.split(':');
  if (parts.length != 2) {
    throw FormatException('알 수 없는 시간 형식: $value');
  }
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  return hour * 60 + minute;
}

Cafeteria _cafeteriaFromInfoKey(String key) {
  return switch (key) {
    'dormitory' => Cafeteria.dormitory,
    'student' => Cafeteria.student,
    'faculty' => Cafeteria.faculty,
    _ => throw FormatException('알 수 없는 cafeteria: $key'),
  };
}

MealOfDay _mealOfDayFromInfoKey(String key) {
  return switch (key) {
    'breakfast' => MealOfDay.breakfast,
    'lunch' => MealOfDay.lunch,
    'dinner' => MealOfDay.dinner,
    _ => throw FormatException('알 수 없는 mealOfDay: $key'),
  };
}
