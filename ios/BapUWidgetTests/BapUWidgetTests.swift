import XCTest

final class BapUWidgetTests: XCTestCase {
  private var cacheDirectory: URL!

  override func setUpWithError() throws {
    cacheDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: cacheDirectory,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: cacheDirectory)
  }

  func testParsesCurrentDormitoryMealAndOperatingStatus() throws {
    let date = try kstDate(year: 2026, month: 8, day: 3, hour: 12, minute: 0)
    try writeInfoCache()
    try writeMealCache(modifiedAt: date)

    let snapshot = WidgetCacheReader(
      containerURL: cacheDirectory,
      languageCode: "ko"
    ).snapshot(at: date)

    XCTAssertEqual(snapshot.selection, .dormKorean)
    XCTAssertEqual(snapshot.meal, .lunch)
    XCTAssertEqual(snapshot.menu, ["쌀밥", "된장찌개"])
    XCTAssertEqual(snapshot.status, .open)
  }

  func testStaleMealCacheReturnsEmptyMenu() throws {
    let date = try kstDate(year: 2026, month: 8, day: 10, hour: 12, minute: 0)
    let previousWeek = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -7, to: date))
    try writeInfoCache()
    try writeMealCache(modifiedAt: previousWeek)

    let snapshot = WidgetCacheReader(
      containerURL: cacheDirectory,
      languageCode: "ko"
    ).snapshot(at: date)

    XCTAssertEqual(snapshot.meal, .lunch)
    XCTAssertTrue(snapshot.menu.isEmpty)
  }

  func testReadsEachConfiguredCafeteriaMenu() throws {
    let date = try kstDate(year: 2026, month: 8, day: 3, hour: 12, minute: 0)
    try writeInfoCache()
    try writeMealCache(modifiedAt: date)
    let reader = WidgetCacheReader(containerURL: cacheDirectory, languageCode: "ko")

    XCTAssertEqual(
      reader.snapshot(at: date, selection: .dormKorean).menu,
      ["쌀밥", "된장찌개"]
    )
    XCTAssertEqual(
      reader.snapshot(at: date, selection: .dormHalal).menu,
      ["할랄라이스", "치킨커리"]
    )
    XCTAssertEqual(
      reader.snapshot(at: date, selection: .student).menu,
      ["학생덮밥"]
    )
    XCTAssertEqual(
      reader.snapshot(at: date, selection: .faculty).menu,
      ["교직원백반"]
    )
  }

  func testEnglishMenuFallsBackToKorean() throws {
    let date = try kstDate(year: 2026, month: 8, day: 3, hour: 12, minute: 0)
    try writeInfoCache()
    try writeMealCache(modifiedAt: date)

    let snapshot = WidgetCacheReader(
      containerURL: cacheDirectory,
      languageCode: "en"
    ).snapshot(at: date, selection: .dormKorean)

    XCTAssertEqual(snapshot.menu, ["Rice", "된장찌개"])
  }

  func testConfiguredSelectionSurvivesMissingInfoCache() throws {
    let date = try kstDate(year: 2026, month: 8, day: 3, hour: 12, minute: 0)

    let snapshot = WidgetCacheReader(
      containerURL: cacheDirectory,
      languageCode: "ko"
    ).snapshot(at: date, selection: .faculty)

    XCTAssertEqual(snapshot.selection, .faculty)
    XCTAssertEqual(snapshot.meal, .lunch)
    XCTAssertTrue(snapshot.menu.isEmpty)
    XCTAssertEqual(snapshot.status, .unavailable)
  }

  func testDormHalalUsesDormitoryOperatingHours() throws {
    let date = try kstDate(year: 2026, month: 8, day: 3, hour: 12, minute: 0)
    try writeInfoCache()
    try writeMealCache(modifiedAt: date)

    let snapshot = WidgetCacheReader(
      containerURL: cacheDirectory,
      languageCode: "ko"
    ).snapshot(at: date, selection: .dormHalal)

    XCTAssertEqual(snapshot.selection, .dormHalal)
    XCTAssertEqual(snapshot.status, .open)
  }

  func testFoodTypeLabelExistsOnlyForDormitorySelections() {
    XCTAssertNotNil(WidgetMenuSelection.dormKorean.localizedFoodTypeName)
    XCTAssertNotNil(WidgetMenuSelection.dormHalal.localizedFoodTypeName)
    XCTAssertNil(WidgetMenuSelection.student.localizedFoodTypeName)
    XCTAssertNil(WidgetMenuSelection.faculty.localizedFoodTypeName)
  }

  func testIntentRawValueMappingAndFallback() {
    XCTAssertEqual(WidgetMenuSelection(intentRawValue: 1), .dormKorean)
    XCTAssertEqual(WidgetMenuSelection(intentRawValue: 2), .dormHalal)
    XCTAssertEqual(WidgetMenuSelection(intentRawValue: 3), .student)
    XCTAssertEqual(WidgetMenuSelection(intentRawValue: 4), .faculty)
    XCTAssertEqual(WidgetMenuSelection(intentRawValue: nil), .dormKorean)
    XCTAssertEqual(WidgetMenuSelection(intentRawValue: 999), .dormKorean)
  }

  func testDisplayMenuItemsAddsOverflowMarkerOnlyAfterLimit() {
    XCTAssertEqual(
      displayMenuItems(["1", "2", "3", "4", "5"]),
      ["1", "2", "3", "4", "5"]
    )
    XCTAssertEqual(
      displayMenuItems(["1", "2", "3", "4", "5", "6"]),
      ["1", "2", "3", "4", "5…"]
    )
  }

  func testTimelineIncludesMealAndOperatingBoundaries() throws {
    let date = try kstDate(year: 2026, month: 8, day: 3, hour: 8, minute: 0)
    try writeInfoCache()

    let dates = WidgetCacheReader(containerURL: cacheDirectory).timelineDates(after: date)
    let minuteValues = dates.map(kstMinuteOfDay)

    XCTAssertTrue(minuteValues.contains(8 * 60 + 20))
    XCTAssertTrue(minuteValues.contains(9 * 60 + 21))
    XCTAssertTrue(minuteValues.contains(12 * 60 + 45))
    XCTAssertTrue(minuteValues.contains(13 * 60 + 30))
    XCTAssertTrue(minuteValues.contains(13 * 60 + 31))
  }

  func testMondayUsesSundayPrefetchedNextWeekCache() throws {
    let sunday = try kstDate(year: 2026, month: 8, day: 9, hour: 20, minute: 0)
    let monday = try kstDate(year: 2026, month: 8, day: 10, hour: 12, minute: 0)
    try writeInfoCache()
    try writeMealCache(modifiedAt: sunday)
    try writeMealCache(
      fileName: "meal-next.json",
      weekStart: "2026-08-10",
      modifiedAt: sunday
    )

    let snapshot = WidgetCacheReader(containerURL: cacheDirectory).snapshot(at: monday)

    XCTAssertEqual(snapshot.meal, .lunch)
    XCTAssertEqual(snapshot.menu, ["쌀밥", "된장찌개"])
  }

  func testCanonicalMealCacheWinsWhenBothFilesMatchMonday() throws {
    let date = try kstDate(year: 2026, month: 8, day: 10, hour: 12, minute: 0)
    try writeInfoCache()
    try writeMealCache(weekStart: "2026-08-10", modifiedAt: date, menuName: "canonical")
    try writeMealCache(
      fileName: "meal-next.json",
      weekStart: "2026-08-10",
      modifiedAt: date,
      menuName: "prefetched"
    )

    XCTAssertEqual(
      WidgetCacheReader(containerURL: cacheDirectory).snapshot(at: date).menu.first,
      "canonical"
    )
  }

  func testCorruptCanonicalMealCacheFallsBackToMatchingNextCache() throws {
    let date = try kstDate(year: 2026, month: 8, day: 10, hour: 12, minute: 0)
    try writeInfoCache()
    try #"{"week":{"startDate":"2026-08-10"},"data":"broken"}"#.write(
      to: cacheDirectory.appendingPathComponent("meal.json"),
      atomically: true,
      encoding: .utf8
    )
    try writeMealCache(
      fileName: "meal-next.json",
      weekStart: "2026-08-10",
      modifiedAt: date
    )

    XCTAssertEqual(
      WidgetCacheReader(containerURL: cacheDirectory).snapshot(at: date).menu.first,
      "쌀밥"
    )
  }

  private func writeInfoCache() throws {
    let json = #"""
    {
      "operatingHours": {
        "weekday": {
          "dormitory": {
            "breakfast": {"start": "08:20", "end": "09:20"},
            "lunch": {"start": "11:30", "end": "13:30"},
            "dinner": {"start": "17:30", "end": "19:20"}
          },
          "student": {
            "lunch": {"start": "11:00", "end": "13:30"}
          },
          "faculty": {
            "lunch": {"start": "11:30", "end": "13:30"}
          }
        },
        "weekend": {
          "dormitory": {
            "breakfast": {"start": "08:20", "end": "09:20"},
            "lunch": {"start": "11:30", "end": "13:30"},
            "dinner": {"start": "17:30", "end": "19:00"}
          }
        }
      }
    }
    """#
    try json.write(
      to: cacheDirectory.appendingPathComponent("info.json"),
      atomically: true,
      encoding: .utf8
    )
  }

  private func writeMealCache(
    fileName: String = "meal.json",
    weekStart: String = "2026-08-03",
    modifiedAt: Date,
    menuName: String = "쌀밥"
  ) throws {
    let json = #"""
    {
      "week": {"startDate": "\(weekStart)"},
      "data": [
        {
          "cafeteria": "DORMITORY",
          "meals": [{
            "dayOfWeek": "MON",
            "timeType": "LUNCH",
            "menusByType": [
              {
                "menuType": "KOREAN",
                "sections": [
                  {"sectionType": "REGULAR", "menus": [
                    {"ko": "\(menuName)", "en": "Rice"},
                    {"ko": "된장찌개", "en": null}
                  ]},
                  {"sectionType": "SALAD", "menus": [
                    {"ko": "샐러드", "en": "Salad"}
                  ]}
                ]
              },
              {
                "menuType": "HALAL",
                "sections": [{"sectionType": "REGULAR", "menus": [
                  {"ko": "할랄라이스", "en": "Halal Rice"},
                  {"ko": "치킨커리", "en": "Chicken Curry"}
                ]}]
              }
            ]
          }]
        },
        {
          "cafeteria": "STUDENT",
          "meals": [{
            "dayOfWeek": "MON",
            "timeType": "LUNCH",
            "menusByType": [{
              "menuType": "KOREAN",
              "sections": [{"sectionType": "REGULAR", "menus": [
                {"ko": "학생덮밥", "en": "Student Rice Bowl"}
              ]}]
            }]
          }]
        },
        {
          "cafeteria": "FACULTY",
          "meals": [{
            "dayOfWeek": "MON",
            "timeType": "LUNCH",
            "menusByType": [{
              "menuType": "KOREAN",
              "sections": [{"sectionType": "REGULAR", "menus": [
                {"ko": "교직원백반", "en": "Faculty Set Menu"}
              ]}]
            }]
          }]
        }
      ]
    }
    """#
    let url = cacheDirectory.appendingPathComponent(fileName)
    try json.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.modificationDate: modifiedAt],
      ofItemAtPath: url.path
    )
  }

  private func kstDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int
  ) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
    return try XCTUnwrap(calendar.date(from: DateComponents(
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute
    )))
  }

  private func kstMinuteOfDay(_ date: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
  }
}
