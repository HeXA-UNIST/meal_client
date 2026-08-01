import SwiftUI
import WidgetKit

private enum WidgetContract {
  static let kind = "BapUWidget"
  static let mealCacheFile = "meal.json"
  static let infoCacheFile = "info.json"
  static let closingSoonMinutes = 45
  static let justClosedMinutes = 30

  static let kst: TimeZone = TimeZone(identifier: "Asia/Seoul")!

  static var appGroupIdentifier: String? {
    Bundle.main.object(forInfoDictionaryKey: "BAPU_APP_GROUP_IDENTIFIER") as? String
  }
}

enum WidgetMealOfDay: String, CaseIterable {
  case breakfast = "BREAKFAST"
  case lunch = "LUNCH"
  case dinner = "DINNER"

  var localizedName: String {
    let korean = Locale.current.languageCode != "en"
    switch self {
    case .breakfast: return korean ? "조식" : "Breakfast"
    case .lunch: return korean ? "중식" : "Lunch"
    case .dinner: return korean ? "석식" : "Dinner"
    }
  }
}

enum WidgetCafeteria: String {
  case dormitory = "DORMITORY"

  var localizedName: String {
    Locale.current.languageCode == "en" ? "Dormitory" : "기숙사"
  }
}

private struct LocalizedMenu: Decodable {
  let ko: String
  let en: String?

  func localizedName(for languageCode: String) -> String {
    guard languageCode == "en",
          let en,
          !en.isEmpty
    else {
      return ko
    }
    return en
  }
}

private struct MealResponse: Decodable {
  let data: [CafeteriaResponse]
}

private struct CafeteriaResponse: Decodable {
  let cafeteria: String
  let meals: [MealResponseItem]
}

private struct MealResponseItem: Decodable {
  let dayOfWeek: String
  let timeType: String
  let menusByType: [MenuGroup]
}

private struct MenuGroup: Decodable {
  let menuType: String
  let sections: [MenuSection]
}

private struct MenuSection: Decodable {
  let sectionType: String
  let menus: [LocalizedMenu]
}

private struct InfoResponse: Decodable {
  let operatingHours: OperatingHoursResponse
}

private struct OperatingHoursResponse: Decodable {
  let weekday: OperatingPeriodResponse
  let weekend: OperatingPeriodResponse
}

private struct OperatingPeriodResponse: Decodable {
  let dormitory: CafeteriaHoursResponse?
  let student: CafeteriaHoursResponse?
  let faculty: CafeteriaHoursResponse?

  var allCafeterias: [CafeteriaHoursResponse] {
    [dormitory, student, faculty].compactMap { $0 }
  }
}

private struct CafeteriaHoursResponse: Decodable {
  let breakfast: TimeRangeResponse?
  let lunch: TimeRangeResponse?
  let dinner: TimeRangeResponse?

  func range(for meal: WidgetMealOfDay) -> TimeRangeResponse? {
    switch meal {
    case .breakfast: return breakfast
    case .lunch: return lunch
    case .dinner: return dinner
    }
  }
}

private struct TimeRangeResponse: Decodable, Hashable {
  let start: String
  let end: String

  var startMinutes: Int? { Self.minutes(from: start) }
  var endMinutes: Int? { Self.minutes(from: end) }

  private static func minutes(from value: String) -> Int? {
    let parts = value.split(separator: ":")
    guard parts.count == 2,
          let hour = Int(parts[0]),
          let minute = Int(parts[1]),
          (0...23).contains(hour),
          (0...59).contains(minute)
    else {
      return nil
    }
    return hour * 60 + minute
  }
}

enum OperatingStatus: Equatable {
  case beforeOpen(startMinutes: Int)
  case open
  case closingSoon
  case closed
  case noService
  case unavailable

  var localizedText: String {
    let korean = Locale.current.languageCode != "en"
    switch self {
    case .beforeOpen(let minutes):
      let time = String(format: "%02d:%02d", minutes / 60, minutes % 60)
      return korean ? "\(time) 운영 시작" : "Opens at \(time)"
    case .open: return korean ? "운영 중" : "Open"
    case .closingSoon: return korean ? "마감 임박" : "Closing soon"
    case .closed: return korean ? "운영 종료" : "Closed"
    case .noService: return korean ? "미운영" : "No service"
    case .unavailable: return korean ? "운영시간 정보 없음" : "Hours unavailable"
    }
  }

  var color: Color {
    switch self {
    case .open: return Color(red: 0, green: 0.62, blue: 0.39)
    case .closingSoon: return Color(red: 0.89, green: 0.52, blue: 0.05)
    case .closed, .noService: return .secondary
    case .beforeOpen, .unavailable: return Color(red: 0.24, green: 0.45, blue: 0.72)
    }
  }
}

struct WidgetSnapshot {
  let cafeteria: WidgetCafeteria
  let meal: WidgetMealOfDay
  let menu: [String]
  let status: OperatingStatus
}

private struct BapUWidgetEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot

  static let placeholder = BapUWidgetEntry(
    date: Date(),
    snapshot: WidgetSnapshot(
      cafeteria: .dormitory,
      meal: .lunch,
      menu: ["쌀밥", "된장찌개", "제육볶음", "오늘의 반찬"],
      status: .open
    )
  )
}

struct WidgetCacheReader {
  private let decoder = JSONDecoder()
  private let containerURL: URL?
  private let languageCode: String

  init(
    containerURL: URL? = WidgetCacheReader.defaultContainerURL(),
    languageCode: String = Locale.current.languageCode ?? "ko"
  ) {
    self.containerURL = containerURL
    self.languageCode = languageCode
  }

  private static func defaultContainerURL() -> URL? {
    guard let appGroupIdentifier = WidgetContract.appGroupIdentifier,
          !appGroupIdentifier.isEmpty
    else {
      return nil
    }
    return FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    )
  }

  func snapshot(at date: Date) -> WidgetSnapshot {
    guard let hours: InfoResponse = decode(WidgetContract.infoCacheFile) else {
      return WidgetSnapshot(
        cafeteria: .dormitory,
        meal: .lunch,
        menu: [],
        status: .unavailable
      )
    }

    let period = periodResponse(from: hours, at: date)
    guard let meal = currentMeal(in: period, at: date) else {
      return WidgetSnapshot(
        cafeteria: .dormitory,
        meal: .lunch,
        menu: [],
        status: .unavailable
      )
    }

    let menu = readMenu(at: date, meal: meal)
    let range = period.dormitory?.range(for: meal)
    return WidgetSnapshot(
      cafeteria: .dormitory,
      meal: meal,
      menu: menu,
      status: operatingStatus(range: range, at: date)
    )
  }

  func timelineDates(after date: Date) -> [Date] {
    guard let info: InfoResponse = decode(WidgetContract.infoCacheFile) else {
      return [date.addingTimeInterval(30 * 60)]
    }

    let period = periodResponse(from: info, at: date)
    var minutes = Set<Int>()
    for cafeteria in period.allCafeterias {
      for meal in WidgetMealOfDay.allCases {
        guard let range = cafeteria.range(for: meal),
              let start = range.startMinutes,
              let end = range.endMinutes
        else {
          continue
        }
        minutes.insert(start)
        minutes.insert(max(0, end - WidgetContract.closingSoonMinutes))
        minutes.insert(end)
        minutes.insert(min(24 * 60 - 1, end + WidgetContract.justClosedMinutes + 1))
      }
    }

    let breakfastEnds = period.allCafeterias.compactMap { $0.breakfast?.endMinutes }
    let lunchEnds = period.allCafeterias.compactMap { $0.lunch?.endMinutes }
    if let breakfastEnd = breakfastEnds.max() { minutes.insert(breakfastEnd + 1) }
    if let lunchEnd = lunchEnds.max() { minutes.insert(lunchEnd + 1) }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = WidgetContract.kst
    let startOfDay = calendar.startOfDay(for: date)
    let boundaries = minutes.compactMap {
      calendar.date(byAdding: .minute, value: $0, to: startOfDay)
    }
    let midnight = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

    return (boundaries + [midnight])
      .filter { $0 > date }
      .sorted()
  }

  private func readMenu(at date: Date, meal: WidgetMealOfDay) -> [String] {
    guard isFreshMealCache(at: date) else { return [] }
    guard let response: MealResponse = decode(WidgetContract.mealCacheFile) else {
      return []
    }

    let weekday = dayOfWeek(at: date)
    return response.data
      .first { $0.cafeteria == WidgetCafeteria.dormitory.rawValue }?
      .meals
      .first { $0.dayOfWeek == weekday && $0.timeType == meal.rawValue }?
      .menusByType
      .first { $0.menuType == "KOREAN" }?
      .sections
      .filter { $0.sectionType == "REGULAR" }
      .flatMap(\.menus)
      .map { $0.localizedName(for: languageCode) } ?? []
  }

  private func periodResponse(from info: InfoResponse, at date: Date) -> OperatingPeriodResponse {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = WidgetContract.kst
    switch calendar.component(.weekday, from: date) {
    case 1, 7: return info.operatingHours.weekend
    default: return info.operatingHours.weekday
    }
  }

  private func currentMeal(in period: OperatingPeriodResponse, at date: Date) -> WidgetMealOfDay? {
    let breakfastEnd = period.allCafeterias.compactMap { $0.breakfast?.endMinutes }.max()
    let lunchEnd = period.allCafeterias.compactMap { $0.lunch?.endMinutes }.max()
    guard let breakfastEnd, let lunchEnd, breakfastEnd < lunchEnd else {
      return nil
    }

    let now = minuteOfDay(at: date)
    if now <= breakfastEnd { return .breakfast }
    if now <= lunchEnd { return .lunch }
    return .dinner
  }

  private func operatingStatus(range: TimeRangeResponse?, at date: Date) -> OperatingStatus {
    guard let range else { return .noService }
    guard let start = range.startMinutes, let end = range.endMinutes else { return .unavailable }
    let now = minuteOfDay(at: date)

    if now < start { return .beforeOpen(startMinutes: start) }
    if now < end {
      return end - now < WidgetContract.closingSoonMinutes ? .closingSoon : .open
    }
    return .closed
  }

  private func minuteOfDay(at date: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = WidgetContract.kst
    return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
  }

  private func dayOfWeek(at date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = WidgetContract.kst
    return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][
      calendar.component(.weekday, from: date) - 1
    ]
  }

  private func decode<T: Decodable>(_ fileName: String) -> T? {
    guard let container = containerURL else { return nil }
    let url = container.appendingPathComponent(fileName)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? decoder.decode(T.self, from: data)
  }

  private func isFreshMealCache(at date: Date) -> Bool {
    guard let container = containerURL else { return false }

    let url = container.appendingPathComponent(WidgetContract.mealCacheFile)
    guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
          let modifiedAt = values.contentModificationDate
    else {
      return false
    }
    return kstWeekIdentifier(for: modifiedAt) == kstWeekIdentifier(for: date)
  }

  private func kstWeekIdentifier(for date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = WidgetContract.kst
    calendar.firstWeekday = 2
    let startOfDay = calendar.startOfDay(for: date)
    let weekday = calendar.component(.weekday, from: startOfDay)
    let daysSinceMonday = (weekday + 5) % 7
    let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: startOfDay)!
    let components = calendar.dateComponents([.year, .month, .day], from: monday)
    return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
  }
}

#if !BAPU_WIDGET_TESTS
private struct BapUWidgetProvider: TimelineProvider {
  private let cache = WidgetCacheReader()

  func placeholder(in context: Context) -> BapUWidgetEntry {
    .placeholder
  }

  func getSnapshot(in context: Context, completion: @escaping (BapUWidgetEntry) -> Void) {
    completion(context.isPreview ? .placeholder : entry(at: Date()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<BapUWidgetEntry>) -> Void) {
    let now = Date()
    let dates = [now] + cache.timelineDates(after: now)
    let entries = dates.map(entry(at:))
    let nextRefresh = dates.dropFirst().first ?? now.addingTimeInterval(30 * 60)
    completion(Timeline(entries: entries, policy: .after(nextRefresh)))
  }

  private func entry(at date: Date) -> BapUWidgetEntry {
    BapUWidgetEntry(date: date, snapshot: cache.snapshot(at: date))
  }
}

private struct BapUWidgetView: View {
  let entry: BapUWidgetEntry

  var body: some View {
    VStack(spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(entry.snapshot.cafeteria.localizedName)
          .font(.system(size: 12, weight: .bold))
          .lineLimit(1)
        Text(Locale.current.languageCode == "en" ? "Korean" : "한식")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
        Spacer(minLength: 4)
        Text(entry.snapshot.meal.localizedName)
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.secondary)
      }

      menuPanel
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

      Text(entry.snapshot.status.localizedText)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(entry.snapshot.status.color)
        .lineLimit(1)
    }
    .padding(12)
    .widgetURL(URL(string: "bapu://home"))
    .modifier(WidgetBackgroundModifier())
  }

  @ViewBuilder
  private var menuPanel: some View {
    VStack(alignment: .leading, spacing: 3) {
      if entry.snapshot.menu.isEmpty {
        Spacer(minLength: 0)
        Text(Locale.current.languageCode == "en" ? "No menu" : "메뉴 정보 없음")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
        Spacer(minLength: 0)
      } else {
        ForEach(Array(entry.snapshot.menu.prefix(5).enumerated()), id: \.offset) { _, item in
          Text(item)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
        }
      }
    }
    .padding(9)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      LinearGradient(
        colors: [
          Color(red: 0.91, green: 1.0, blue: 0.96),
          Color(red: 0.96, green: 0.98, blue: 1.0),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: 8)
    )
  }
}

private struct WidgetBackgroundModifier: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(for: .widget) {
        Color(uiColor: .systemBackground)
      }
    } else {
      content.background(Color(uiColor: .systemBackground))
    }
  }
}

@main
struct BapUWidget: Widget {
  let kind = WidgetContract.kind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: BapUWidgetProvider()) { entry in
      BapUWidgetView(entry: entry)
    }
    .configurationDisplayName("밥먹어U")
    .description("현재 학식 메뉴와 운영 상태를 확인합니다.")
    .supportedFamilies([.systemSmall])
  }
}
#endif
