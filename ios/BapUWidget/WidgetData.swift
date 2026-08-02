import Foundation

private let kstTimeZone = TimeZone(identifier: "Asia/Seoul")!

enum MealOfDay: String {
  case breakfast = "BREAKFAST"
  case lunch = "LUNCH"
  case dinner = "DINNER"

  var displayName: String {
    switch self {
    case .breakfast: "조식"
    case .lunch: "중식"
    case .dinner: "석식"
    }
  }

  var infoKey: String { rawValue.lowercased() }
}

struct WidgetContent {
  let mealOfDay: MealOfDay
  let menus: [String]
  let status: String
  let errorMessage: String?
}

struct WidgetDataLoader {
  private let appGroupInfoKey = "BAPU_APP_GROUP_IDENTIFIER"

  func load(cafeteria: CafeteriaOption, now: Date = Date()) -> WidgetContent {
    do {
      let container = try sharedContainerURL()
      let infoData = try Data(contentsOf: container.appendingPathComponent("info.json"))
      let hours = try JSONDecoder().decode(InfoResponse.self, from: infoData).operatingHours
      let context = try KSTMealContext.resolve(hours: hours, now: now)
      let status = OperatingStatusResolver.status(
        hours: hours,
        cafeteria: cafeteria,
        meal: context.meal,
        now: now
      )

      let mealURL = container.appendingPathComponent("meal.json")
      guard FileManager.default.fileExists(atPath: mealURL.path) else {
        return WidgetContent(
          mealOfDay: context.meal,
          menus: [],
          status: status,
          errorMessage: "식단 캐시가 없습니다"
        )
      }
      guard try isFreshMealCache(url: mealURL, now: now) else {
        return WidgetContent(
          mealOfDay: context.meal,
          menus: [],
          status: status,
          errorMessage: "식단 캐시가 오래되었습니다"
        )
      }

      let response = try JSONDecoder().decode(
        MealResponse.self,
        from: Data(contentsOf: mealURL)
      )
      let languageCode = Locale.current.language.languageCode?.identifier ?? "ko"
      let menus = MealParser.menu(
        response: response,
        cafeteria: cafeteria,
        dayKey: context.dayKey,
        meal: context.meal,
        languageCode: languageCode
      )
      return WidgetContent(
        mealOfDay: context.meal,
        menus: menus,
        status: status,
        errorMessage: nil
      )
    } catch {
      return WidgetContent(
        mealOfDay: .breakfast,
        menus: [],
        status: "-",
        errorMessage: "위젯 데이터를 불러올 수 없습니다"
      )
    }
  }

  func timelineDates(cafeteria: CafeteriaOption, now: Date = Date()) -> [Date] {
    do {
      let container = try sharedContainerURL()
      let infoData = try Data(contentsOf: container.appendingPathComponent("info.json"))
      let hours = try JSONDecoder().decode(InfoResponse.self, from: infoData).operatingHours
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = kstTimeZone
      let startOfDay = calendar.startOfDay(for: now)
      guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
        return [now]
      }

      var dates: Set<Date> = [now, nextMidnight]
      let period = hours.period(for: now)

      // 끼니 전환은 Android와 같이 모든 식당 중 가장 늦은 종료 시각 + 1분이다.
      for mealKey in ["breakfast", "lunch"] {
        if let end = period.values.compactMap({ $0[mealKey]?.endMinutes }).max(),
           let transition = date(minutesAfterMidnight: end + 1, day: startOfDay, calendar: calendar) {
          dates.insert(transition)
        }
      }

      let cafeteriaKey = switch cafeteria {
      case .dormKorean, .dormHalal: "dormitory"
      case .student: "student"
      case .faculty: "faculty"
      }
      for range in period[cafeteriaKey]?.values ?? [:].values {
        guard let start = range.startMinutes, let end = range.endMinutes else { continue }
        for minute in [start, end - 45, end, end + 30] where minute >= 0 {
          if let boundary = date(minutesAfterMidnight: minute, day: startOfDay, calendar: calendar) {
            dates.insert(boundary)
          }
        }

        // 숫자형 "종료 N분 전"이 멈춰 있지 않도록 마감임박 구간은 분 단위 Entry로 만든다.
        if end > 0 {
          for minute in max(start, end - 44)..<end {
            if let countdown = date(minutesAfterMidnight: minute, day: startOfDay, calendar: calendar) {
              dates.insert(countdown)
            }
          }
        }
      }

      return dates
        .filter { $0 >= now && $0 <= nextMidnight }
        .sorted()
    } catch {
      return [now, now.addingTimeInterval(30 * 60)]
    }
  }

  private func sharedContainerURL() throws -> URL {
    guard
      let identifier = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
      !identifier.isEmpty,
      let url = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: identifier
      )
    else {
      throw WidgetDataError.appGroupUnavailable
    }
    return url
  }

  private func isFreshMealCache(url: URL, now: Date) throws -> Bool {
    let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
    guard let modifiedAt = values.contentModificationDate else { return false }
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = kstTimeZone
    let cacheWeek = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: modifiedAt)
    let currentWeek = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
    return cacheWeek.yearForWeekOfYear == currentWeek.yearForWeekOfYear
      && cacheWeek.weekOfYear == currentWeek.weekOfYear
  }

  private func date(
    minutesAfterMidnight: Int,
    day: Date,
    calendar: Calendar
  ) -> Date? {
    calendar.date(byAdding: .minute, value: minutesAfterMidnight, to: day)
  }
}

private enum WidgetDataError: Error {
  case appGroupUnavailable
  case missingMealTransitions
}

private struct MealResponse: Decodable {
  let data: [CafeteriaPayload]
}

private struct CafeteriaPayload: Decodable {
  let cafeteria: String
  let meals: [MealPayload]
}

private struct MealPayload: Decodable {
  let dayOfWeek: String
  let timeType: String
  let menusByType: [MenuGroupPayload]
}

private struct MenuGroupPayload: Decodable {
  let menuType: String
  let sections: [MenuSectionPayload]
}

private struct MenuSectionPayload: Decodable {
  let sectionType: String
  let menus: [MenuItemPayload]
}

private struct MenuItemPayload: Decodable {
  let ko: String
  let en: String?

  func localized(languageCode: String) -> String {
    if languageCode == "en", let en, !en.isEmpty { return en }
    return ko
  }
}

private enum MealParser {
  static func menu(
    response: MealResponse,
    cafeteria: CafeteriaOption,
    dayKey: String,
    meal: MealOfDay,
    languageCode: String
  ) -> [String] {
    let cafeteriaKey: String
    let menuType: String
    switch cafeteria {
    case .dormKorean:
      cafeteriaKey = "DORMITORY"
      menuType = "KOREAN"
    case .dormHalal:
      cafeteriaKey = "DORMITORY"
      menuType = "HALAL"
    case .student:
      cafeteriaKey = "STUDENT"
      menuType = "KOREAN"
    case .faculty:
      cafeteriaKey = "FACULTY"
      menuType = "KOREAN"
    }

    return response.data
      .first(where: { $0.cafeteria == cafeteriaKey })?
      .meals
      .first(where: { $0.dayOfWeek == dayKey && $0.timeType == meal.rawValue })?
      .menusByType
      .first(where: { $0.menuType == menuType })?
      .sections
      .filter { $0.sectionType == "REGULAR" }
      .flatMap { $0.menus.map { $0.localized(languageCode: languageCode) } } ?? []
  }
}

private struct InfoResponse: Decodable {
  let operatingHours: OperatingHoursPayload
}

private struct OperatingHoursPayload: Decodable {
  let weekday: [String: [String: OperatingTimeRange]]
  let weekend: [String: [String: OperatingTimeRange]]

  func period(for now: Date) -> [String: [String: OperatingTimeRange]] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = kstTimeZone
    let weekdayValue = calendar.component(.weekday, from: now)
    return weekdayValue == 1 || weekdayValue == 7 ? weekend : weekday
  }
}

private struct OperatingTimeRange: Decodable, Hashable {
  let start: String
  let end: String

  var startMinutes: Int? { Self.minutes(start) }
  var endMinutes: Int? { Self.minutes(end) }

  private static func minutes(_ value: String) -> Int? {
    let components = value.split(separator: ":")
    guard
      components.count == 2,
      let hour = Int(components[0]),
      let minute = Int(components[1]),
      (0...23).contains(hour),
      (0...59).contains(minute)
    else { return nil }
    return hour * 60 + minute
  }
}

private struct KSTMealContext {
  let meal: MealOfDay
  let dayKey: String

  static func resolve(hours: OperatingHoursPayload, now: Date) throws -> KSTMealContext {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = kstTimeZone
    let period = hours.period(for: now)
    guard
      let breakfastEnd = latestEnd(period: period, mealKey: "breakfast"),
      let lunchEnd = latestEnd(period: period, mealKey: "lunch"),
      breakfastEnd < lunchEnd
    else {
      throw WidgetDataError.missingMealTransitions
    }

    let nowMinutes = calendar.component(.hour, from: now) * 60
      + calendar.component(.minute, from: now)
    let meal: MealOfDay = if nowMinutes <= breakfastEnd {
      .breakfast
    } else if nowMinutes <= lunchEnd {
      .lunch
    } else {
      .dinner
    }
    let dayKeys = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    return KSTMealContext(
      meal: meal,
      dayKey: dayKeys[calendar.component(.weekday, from: now) - 1]
    )
  }

  private static func latestEnd(
    period: [String: [String: OperatingTimeRange]],
    mealKey: String
  ) -> Int? {
    period.values.compactMap { $0[mealKey]?.endMinutes }.max()
  }
}

private enum OperatingStatusResolver {
  static func status(
    hours: OperatingHoursPayload,
    cafeteria: CafeteriaOption,
    meal: MealOfDay,
    now: Date
  ) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = kstTimeZone
    let cafeteriaKey = switch cafeteria {
    case .dormKorean, .dormHalal: "dormitory"
    case .student: "student"
    case .faculty: "faculty"
    }
    guard
      let range = hours.period(for: now)[cafeteriaKey]?[meal.infoKey],
      let start = range.startMinutes,
      let end = range.endMinutes
    else { return "미운영" }

    let current = calendar.component(.hour, from: now) * 60
      + calendar.component(.minute, from: now)
    if current < start {
      return String(format: "%02d:%02d부터 운영", start / 60, start % 60)
    }
    if current < end {
      let remaining = end - current
      return remaining >= 45 ? "운영 중" : "종료 \(remaining)분 전"
    }
    if current <= end + 30 || meal == .dinner { return "운영 종료" }
    return String(format: "%02d:%02d부터 운영", start / 60, start % 60)
  }
}
