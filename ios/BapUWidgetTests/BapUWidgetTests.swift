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

    XCTAssertEqual(snapshot.cafeteria, .dormitory)
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

  private func writeMealCache(modifiedAt: Date) throws {
    let json = #"""
    {
      "data": [{
        "cafeteria": "DORMITORY",
        "meals": [{
          "dayOfWeek": "MON",
          "timeType": "LUNCH",
          "menusByType": [{
            "menuType": "KOREAN",
            "sections": [
              {"sectionType": "REGULAR", "menus": [
                {"ko": "쌀밥", "en": "Rice"},
                {"ko": "된장찌개", "en": null}
              ]},
              {"sectionType": "SALAD", "menus": [
                {"ko": "샐러드", "en": "Salad"}
              ]}
            ]
          }]
        }]
      }]
    }
    """#
    let url = cacheDirectory.appendingPathComponent("meal.json")
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
