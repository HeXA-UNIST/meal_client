import AppIntents
import SwiftUI
import WidgetKit

enum CafeteriaOption: String, AppEnum {
  case dormKorean
  case dormHalal
  case student
  case faculty

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "식당")
  static let caseDisplayRepresentations: [CafeteriaOption: DisplayRepresentation] = [
    .dormKorean: "기숙사 한식",
    .dormHalal: "기숙사 할랄",
    .student: "학생식당",
    .faculty: "교직원식당",
  ]

  var displayName: String {
    switch self {
    case .dormKorean, .dormHalal: "기숙사 식당"
    case .student: "학생식당"
    case .faculty: "교직원식당"
    }
  }

  var foodType: String? {
    switch self {
    case .dormKorean: "한식"
    case .dormHalal: "할랄"
    case .student, .faculty: nil
    }
  }
}

struct CafeteriaConfigurationIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "식당 선택"
  static let description = IntentDescription("위젯에 표시할 식당을 선택합니다.")

  @Parameter(title: "식당", default: .dormKorean)
  var cafeteria: CafeteriaOption
}

struct BapUWidgetEntry: TimelineEntry {
  let date: Date
  let cafeteria: CafeteriaOption
  let content: WidgetContent
}

struct BapUWidgetProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> BapUWidgetEntry {
    BapUWidgetEntry(
      date: Date(),
      cafeteria: .dormKorean,
      content: WidgetContent(
        mealOfDay: .lunch,
        menus: ["어니언하이라이스", "계란후라이", "우동국"],
        status: "운영 중",
        errorMessage: nil
      )
    )
  }

  func snapshot(
    for configuration: CafeteriaConfigurationIntent,
    in context: Context
  ) async -> BapUWidgetEntry {
    makeEntry(configuration: configuration)
  }

  func timeline(
    for configuration: CafeteriaConfigurationIntent,
    in context: Context
  ) async -> Timeline<BapUWidgetEntry> {
    let loader = WidgetDataLoader()
    let dates = loader.timelineDates(cafeteria: configuration.cafeteria)
    let entries = dates.map { date in
      BapUWidgetEntry(
        date: date,
        cafeteria: configuration.cafeteria,
        content: loader.load(cafeteria: configuration.cafeteria, now: date)
      )
    }
    return Timeline(entries: entries, policy: .atEnd)
  }

  private func makeEntry(
    configuration: CafeteriaConfigurationIntent
  ) -> BapUWidgetEntry {
    BapUWidgetEntry(
      date: Date(),
      cafeteria: configuration.cafeteria,
      content: WidgetDataLoader().load(cafeteria: configuration.cafeteria)
    )
  }
}

struct BapUWidgetView: View {
  let entry: BapUWidgetEntry
  @Environment(\.colorScheme) private var colorScheme

  private let brandColor = Color(red: 0, green: 0.804, blue: 0.502)

  private var cardColor: Color {
    colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : .white
  }

  private var menuColors: [Color] {
    colorScheme == .dark
      ? [Color(red: 0.17, green: 0.17, blue: 0.18), Color(red: 0.15, green: 0.15, blue: 0.16)]
      : [Color(red: 0.965, green: 0.965, blue: 0.973), Color(red: 0.945, green: 0.945, blue: 0.957)]
  }

  private var menuColor: Color {
    colorScheme == .dark ? Color(red: 0.898, green: 0.898, blue: 0.918) : Color(red: 0.18, green: 0.18, blue: 0.18)
  }

  private var statusColor: Color {
    if entry.content.status == "운영 중" { return brandColor }
    if entry.content.status.hasPrefix("종료 ") {
      return colorScheme == .dark ? .white : .black
    }
    return colorScheme == .dark
      ? Color(red: 0.56, green: 0.56, blue: 0.58)
      : Color(red: 0.44, green: 0.44, blue: 0.44)
  }

  private var visibleMenus: [String] {
    let filtered = entry.content.menus.filter { !$0.isEmpty }
    guard filtered.count > 8 else { return filtered }
    return Array(filtered.prefix(7)) + ["…"]
  }

  private var menuColumns: ([String], [String]) {
    let midpoint = (visibleMenus.count + 1) / 2
    return (Array(visibleMenus.prefix(midpoint)), Array(visibleMenus.dropFirst(midpoint)))
  }

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 5) {
        Text(entry.cafeteria.displayName)
          .foregroundStyle(brandColor)
          .font(.custom("Pretendard-Bold", fixedSize: 15))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        if let foodType = entry.cafeteria.foodType {
          Text(foodType)
            .foregroundStyle(.primary)
            .font(.custom("Pretendard-Bold", fixedSize: 15))
            .lineLimit(1)
        }
        Spacer()
        Text(entry.content.mealOfDay.displayName)
          .foregroundStyle(.primary)
          .font(.custom("Pretendard-Bold", fixedSize: 14))
      }
      .padding(.horizontal, 4)

      Group {
        if let errorMessage = entry.content.errorMessage {
          Text(errorMessage)
            .font(.custom("Pretendard-Medium", fixedSize: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entry.content.menus.isEmpty {
          Text("-")
            .font(.custom("Pretendard-Medium", fixedSize: 14))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          HStack(alignment: .top, spacing: 0) {
            menuColumn(menuColumns.0)
            Rectangle()
              .fill(Color.primary.opacity(0.08))
              .frame(width: 1)
              .padding(.vertical, 1)
              .padding(.horizontal, 10)
            menuColumn(menuColumns.1)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(.horizontal, 13)
      .padding(.vertical, 9)
      .background(
        LinearGradient(
          colors: menuColors,
          startPoint: .top,
          endPoint: .bottom
        ),
        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
      )

      Text(entry.content.status)
        .frame(maxWidth: .infinity)
        .foregroundStyle(statusColor)
        .font(.custom("Pretendard-Bold", fixedSize: 13))
        .lineLimit(1)
    }
    .padding(.horizontal, 16)
    .padding(.top, 13)
    .padding(.bottom, 10)
    .containerBackground(cardColor, for: .widget)
  }

  private func menuColumn(_ menus: [String]) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(Array(menus.enumerated()), id: \.offset) { _, menu in
        Text(menu)
          .foregroundStyle(menuColor)
          .font(.custom("Pretendard-Medium", fixedSize: 13))
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

@main
struct BapUWidget: Widget {
  let kind = "BapUWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: kind,
      intent: CafeteriaConfigurationIntent.self,
      provider: BapUWidgetProvider()
    ) { entry in
      BapUWidgetView(entry: entry)
    }
    .configurationDisplayName("밥먹어U 식단")
    .description("선택한 식당의 오늘 식단을 표시합니다.")
    .supportedFamilies([.systemMedium])
    .contentMarginsDisabled()
  }
}
