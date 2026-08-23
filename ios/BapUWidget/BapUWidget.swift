import SwiftUI
import WidgetKit

#if !BAPU_WIDGET_TESTS
import Intents
#endif

private enum WidgetContract {
  static let kind = "BapUWidget"
  static let mealCacheFile = "meal.json"
  static let nextMealCacheFile = "meal-next.json"
  static let infoCacheFile = "info.json"
  static let closingSoonMinutes = 45

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

enum WidgetMenuSelection: Equatable, CaseIterable {
  case dormKorean
  case dormHalal
  case student
  case faculty

  init(intentRawValue: Int?) {
    switch intentRawValue {
    case 2: self = .dormHalal
    case 3: self = .student
    case 4: self = .faculty
    default: self = .dormKorean
    }
  }

  var apiCafeteria: String {
    switch self {
    case .dormKorean, .dormHalal: return "DORMITORY"
    case .student: return "STUDENT"
    case .faculty: return "FACULTY"
    }
  }

  var apiMenuType: String {
    self == .dormHalal ? "HALAL" : "KOREAN"
  }

  var localizedCafeteriaName: String {
    let korean = Locale.current.languageCode != "en"
    switch self {
    case .dormKorean, .dormHalal: return korean ? "기숙사 식당" : "Dormitory"
    case .student: return korean ? "학생 식당" : "Student"
    case .faculty: return korean ? "교직원 식당" : "Faculty"
    }
  }

  var localizedFoodTypeName: String? {
    let korean = Locale.current.languageCode != "en"
    switch self {
    case .dormKorean: return korean ? "한식" : "Korean"
    case .dormHalal: return korean ? "할랄" : "Halal"
    case .student, .faculty: return nil
    }
  }
}

private struct LocalizedMenu: Decodable {
  let ko: String
  let en: String?

  func localizedName(for languageCode: String) -> String? {
    let koreanName = ko.trimmingCharacters(in: .whitespacesAndNewlines)
    let englishName = en?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let localized = languageCode.hasPrefix("en") && !englishName.isEmpty
      ? englishName
      : koreanName
    return localized.isEmpty ? nil : localized
  }
}

private struct MealResponse: Decodable {
  let week: WeekResponse
  let data: [CafeteriaResponse]
}

private struct WeekResponse: Decodable {
  let startDate: String
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

  func hours(for selection: WidgetMenuSelection) -> CafeteriaHoursResponse? {
    switch selection {
    case .dormKorean, .dormHalal: return dormitory
    case .student: return student
    case .faculty: return faculty
    }
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
    case .open: return WidgetTextColor.brand
    case .closingSoon: return .primary
    case .closed, .noService, .beforeOpen, .unavailable:
      return WidgetTextColor.secondary
    }
  }
}

private enum WidgetTextColor {
  // Android 위젯과 같은 OKLCH 계열이다. 작은 텍스트가 각 시스템 배경에서
  // APCA |Lc| 약 75 이상을 유지하도록 라이트/다크 밝기를 분리한다.
  static let brand = adaptive(light: 0x147549, dark: 0x40E99B)
  static let secondary = adaptive(light: 0x526057, dark: 0xCECECE)

  private static func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
      UIColor(
        red: CGFloat((traits.userInterfaceStyle == .dark ? dark : light) >> 16 & 0xFF) / 255,
        green: CGFloat((traits.userInterfaceStyle == .dark ? dark : light) >> 8 & 0xFF) / 255,
        blue: CGFloat((traits.userInterfaceStyle == .dark ? dark : light) & 0xFF) / 255,
        alpha: 1
      )
    })
  }
}

struct WidgetSnapshot {
  let selection: WidgetMenuSelection
  let meal: WidgetMealOfDay
  let menu: [String]
  let status: OperatingStatus
}

// 한 timeline을 만드는 동안의 입력을 고정한다. WidgetKit entry마다 같은 주간
// JSON을 다시 읽지 않으면서도 다음 reload에서는 최신 파일을 다시 읽는다.
private struct WidgetTimelineInput {
  let info: InfoResponse?
  let currentMeal: MealResponse?
  let nextMeal: MealResponse?
}

func displayMenuItems(_ items: [String], limit: Int = 5) -> [String] {
  guard limit > 0 else { return [] }
  var displayed = Array(items.prefix(limit))
  guard items.count > limit, !displayed.isEmpty else { return displayed }
  displayed[displayed.count - 1] += "…"
  return displayed
}

fileprivate struct BapUWidgetEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot

  static let placeholder = BapUWidgetEntry(
    date: Date(),
    snapshot: WidgetSnapshot(
      selection: .dormKorean,
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

  func snapshot(
    at date: Date,
    selection: WidgetMenuSelection = .dormKorean
  ) -> WidgetSnapshot {
    snapshot(at: date, selection: selection, input: loadTimelineInput())
  }

  private func snapshot(
    at date: Date,
    selection: WidgetMenuSelection,
    input: WidgetTimelineInput
  ) -> WidgetSnapshot {
    guard let hours = input.info else {
      return WidgetSnapshot(
        selection: selection,
        meal: .lunch,
        menu: [],
        status: .unavailable
      )
    }

    let period = periodResponse(from: hours, at: date)
    guard let meal = currentMeal(in: period, at: date) else {
      return WidgetSnapshot(
        selection: selection,
        meal: .lunch,
        menu: [],
        status: .unavailable
      )
    }

    let menu = readMenu(at: date, meal: meal, selection: selection, input: input)
    let range = period.hours(for: selection)?.range(for: meal)
    return WidgetSnapshot(
      selection: selection,
      meal: meal,
      menu: menu,
      status: operatingStatus(range: range, at: date)
    )
  }

  func timelineDates(after date: Date) -> [Date] {
    timelineDates(after: date, input: loadTimelineInput())
  }

  private func timelineDates(after date: Date, input: WidgetTimelineInput) -> [Date] {
    guard let info = input.info else {
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

  fileprivate func timelineEntries(
    from date: Date,
    selection: WidgetMenuSelection
  ) -> [BapUWidgetEntry] {
    let input = loadTimelineInput()
    let dates = [date] + timelineDates(after: date, input: input)
    return dates.map {
      BapUWidgetEntry(
        date: $0,
        snapshot: snapshot(at: $0, selection: selection, input: input)
      )
    }
  }

  private func readMenu(
    at date: Date,
    meal: WidgetMealOfDay,
    selection: WidgetMenuSelection,
    input: WidgetTimelineInput
  ) -> [String] {
    guard let response = mealResponse(for: date, input: input) else {
      return []
    }

    let weekday = dayOfWeek(at: date)
    let groups = response.data
      .first { $0.cafeteria == selection.apiCafeteria }?
      .meals
      .first { $0.dayOfWeek == weekday && $0.timeType == meal.rawValue }?
      .menusByType ?? []

    // Android와 같이 같은 menuType을 순서대로 보되, REGULAR 메뉴가 실제로
    // 존재하는 첫 그룹만 사용한다. 여러 그룹을 합쳐 중복 메뉴를 만들지 않는다.
    for group in groups where group.menuType == selection.apiMenuType {
      let menu = group.sections
        .filter { $0.sectionType == "REGULAR" }
        .flatMap(\.menus)
        .compactMap { $0.localizedName(for: languageCode) }
      if !menu.isEmpty { return menu }
    }
    return []
  }

  private func mealResponse(for date: Date, input: WidgetTimelineInput) -> MealResponse? {
    let targetWeekStart = kstWeekIdentifier(for: date)
    for response in [input.currentMeal, input.nextMeal].compactMap({ $0 }) {
      if response.week.startDate == targetWeekStart { return response }
    }
    return nil
  }

  private func loadTimelineInput() -> WidgetTimelineInput {
    WidgetTimelineInput(
      info: decode(WidgetContract.infoCacheFile),
      currentMeal: decode(WidgetContract.mealCacheFile),
      nextMeal: decode(WidgetContract.nextMealCacheFile)
    )
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
      return end - now <= WidgetContract.closingSoonMinutes ? .closingSoon : .open
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
private extension WidgetMenuSelection {
  init(configuration: BapUWidgetConfigurationIntent) {
    // SiriKit의 생성 enum은 Objective-C 정수 enum으로 브리지된다. 생성된 case
    // 이름에 비즈니스 로직을 결합하지 않고 intentdefinition의 안정적인 raw value만 읽는다.
    let rawValue = (configuration.value(forKey: "cafeteria") as? NSNumber)?.intValue
    self.init(intentRawValue: rawValue)
  }
}

private struct BapUWidgetProvider: IntentTimelineProvider {
  typealias Intent = BapUWidgetConfigurationIntent
  private let cache = WidgetCacheReader()

  func placeholder(in context: Context) -> BapUWidgetEntry {
    .placeholder
  }

  func getSnapshot(
    for configuration: BapUWidgetConfigurationIntent,
    in context: Context,
    completion: @escaping (BapUWidgetEntry) -> Void
  ) {
    completion(
      context.isPreview
        ? .placeholder
        : entry(
          at: Date(),
          selection: WidgetMenuSelection(configuration: configuration)
        )
    )
  }

  func getTimeline(
    for configuration: BapUWidgetConfigurationIntent,
    in context: Context,
    completion: @escaping (Timeline<BapUWidgetEntry>) -> Void
  ) {
    let now = Date()
    let selection = WidgetMenuSelection(configuration: configuration)
    let entries = cache.timelineEntries(from: now, selection: selection)
    // 캐시가 바뀌면 Flutter bridge가 reload를 요청한다. 여기서는 이미 제공한
    // 마지막 경계까지 소비한 뒤에만 다음 timeline을 요청해 갱신 예산을 아낀다.
    completion(Timeline(entries: entries, policy: .atEnd))
  }

  private func entry(at date: Date, selection: WidgetMenuSelection) -> BapUWidgetEntry {
    BapUWidgetEntry(
      date: date,
      snapshot: cache.snapshot(at: date, selection: selection)
    )
  }
}

private struct BapUWidgetView: View {
  let entry: BapUWidgetEntry

  var body: some View {
    VStack(spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(entry.snapshot.selection.localizedCafeteriaName)
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(WidgetTextColor.brand)
          .lineLimit(1)
        if let foodType = entry.snapshot.selection.localizedFoodTypeName {
          Text(foodType)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(WidgetTextColor.secondary)
        }
        Spacer(minLength: 4)
        Text(entry.snapshot.meal.localizedName)
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(WidgetTextColor.secondary)
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
          .foregroundStyle(WidgetTextColor.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
        Spacer(minLength: 0)
      } else {
        ForEach(Array(displayMenuItems(entry.snapshot.menu).enumerated()), id: \.offset) { _, item in
          Text(item)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
        }
      }
    }
    .padding(9)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(
      Color(uiColor: .secondarySystemBackground),
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
    IntentConfiguration(
      kind: kind,
      intent: BapUWidgetConfigurationIntent.self,
      provider: BapUWidgetProvider()
    ) { entry in
      BapUWidgetView(entry: entry)
    }
    .configurationDisplayName(LocalizedStringKey("widgetConfigurationDisplayName"))
    .description(LocalizedStringKey("widgetConfigurationDescription"))
    .supportedFamilies([.systemSmall])
  }
}
#endif
