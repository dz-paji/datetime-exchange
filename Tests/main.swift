import Foundation

private struct FixedRandom {
    private var state: UInt64 = 0xD1B5_4A32_D192_ED03

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

private enum TimeConversionTests {
    private static var checks = 0
    private static var failures: [String] = []

    static func main() throws {
        testZoneMetadata()
        testCommonConversions()
        testLeapYearsAndProlepticGregorian()
        testLowAndHighYearBoundaries()
        testPartialTimeInputs()
        testInputValidation()
        testBatchConversion()
        testCurrentFormatting()
        try testFixedSeedReferences()

        if failures.isEmpty {
            print("PASS: \(checks) checks")
        } else {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            fputs("\(failures.count) of \(checks) checks failed\n", stderr)
            exit(1)
        }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        if !condition() { failures.append(label) }
    }

    private static func expectError(
        _ expected: TimeConversionError,
        _ operation: () throws -> String,
        _ label: String
    ) {
        checks += 1
        do {
            let unexpected = try operation()
            failures.append("\(label): expected error, got \(unexpected)")
        } catch let error as TimeConversionError {
            guard String(describing: error) == String(describing: expected) else {
                failures.append("\(label): expected \(expected), got \(error)")
                return
            }
            check(!error.localizedDescription.isEmpty, "\(label) has a localized description")
        } catch {
            failures.append("\(label): unexpected error type \(error)")
        }
    }

    private static func testZoneMetadata() {
        check(ConversionZone.utc.title == "UTC", "UTC title")
        check(ConversionZone.gmt8.title == "GMT+8", "GMT+8 title")
        check(ConversionZone.utc.opposite == .gmt8, "UTC opposite")
        check(ConversionZone.gmt8.opposite == .utc, "GMT+8 opposite")
        check(ConversionZone.allCases == [.utc, .gmt8], "zone cases")
    }

    private static func testCommonConversions() {
        check(try! TimeConversion.convert("2024-05-01 16:30:45", from: .utc)
              == "2024-05-02 00:30:45", "UTC to GMT+8 across day")
        check(try! TimeConversion.convert("2024-05-02 00-30-45", from: .gmt8)
              == "2024-05-01 16:30:45", "GMT+8 to UTC across day")
        check(try! TimeConversion.convert("2024-12-31 20-00-00", from: .utc)
              == "2025-01-01 04:00:00", "conversion across year")
        check(try! TimeConversion.convert("2025-01-01 04:00:00", from: .gmt8)
              == "2024-12-31 20:00:00", "reverse conversion across year")
        check(try! TimeConversion.canonical(" 2024-05-01T16:30:45 ")
              == "2024-05-01 16:30:45", "T separator and trimmed spaces")
        check(try! TimeConversion.canonical("0099-03-04 05-06-07")
              == "0099-03-04 05:06:07", "low year formatting")
        check(try! TimeConversion.canonical("0001-01-01 00:00:00")
              == "0001-01-01 00:00:00", "minimum input year formatting")
    }

    private static func testLeapYearsAndProlepticGregorian() {
        check(try! TimeConversion.canonical("2000-02-29 12:00:00")
              == "2000-02-29 12:00:00", "2000 is a leap year")
        check(try! TimeConversion.canonical("2024-02-29 12:00:00")
              == "2024-02-29 12:00:00", "2024 is a leap year")
        expectError(.invalidDate, { try TimeConversion.canonical("1900-02-29 12:00:00") }, "1900 is not a leap year")
        expectError(.invalidDate, { try TimeConversion.canonical("2100-02-29 12:00:00") }, "2100 is not a leap year")

        check(try! TimeConversion.convert("2000-02-28 20:00:00", from: .utc)
              == "2000-02-29 04:00:00", "leap day rollover")
        check(try! TimeConversion.convert("2024-02-29 20:00:00", from: .utc)
              == "2024-03-01 04:00:00", "leap day to March rollover")

        check(try! TimeConversion.convert("1582-10-04 23:30:00", from: .utc)
              == "1582-10-05 07:30:00", "1582 proleptic Gregorian day rollover")
        check(try! TimeConversion.canonical("1582-10-10 12:00:00")
              == "1582-10-10 12:00:00", "Gregorian reform gap is not applied")
        check(try! TimeConversion.convert("1582-10-15 00:00:00", from: .utc)
              == "1582-10-15 08:00:00", "post-reform date remains continuous")
    }

    private static func testLowAndHighYearBoundaries() {
        check(try! TimeConversion.convert("0001-01-01 00:00:00", from: .utc)
              == "0001-01-01 08:00:00", "minimum date safely shifts forward")
        check(try! TimeConversion.convert("0001-01-01 08:00:00", from: .gmt8)
              == "0001-01-01 00:00:00", "minimum date is reachable from GMT+8")
        expectError(.outOfRange, { try TimeConversion.convert("0001-01-01 07:59:59", from: .gmt8) }, "conversion below year 0001")

        check(try! TimeConversion.convert("9999-12-31 15:59:59", from: .utc)
              == "9999-12-31 23:59:59", "last supported GMT+8 second")
        check(try! TimeConversion.convert("9999-12-31 23:59:59", from: .gmt8)
              == "9999-12-31 15:59:59", "last supported UTC second")
        expectError(.outOfRange, { try TimeConversion.convert("9999-12-31 16:00:00", from: .utc) }, "conversion above year 9999")
    }

    private static func testPartialTimeInputs() {
        check(try! TimeConversion.canonical("2024-05-01")
              == "2024-05-01 00:00:00", "date-only input defaults to midnight")
        check(try! TimeConversion.canonical(" 2024-05-01 07 ")
              == "2024-05-01 07:00:00", "hour-only input defaults minutes and seconds")
        check(try! TimeConversion.canonical("2024-05-01T07")
              == "2024-05-01 07:00:00", "T-separated hour-only input")
        check(try! TimeConversion.canonical("2024-05-01 07:08")
              == "2024-05-01 07:08:00", "hour-minute input defaults seconds")
        check(try! TimeConversion.canonical("2024-05-01T07:08")
              == "2024-05-01 07:08:00", "T and colon hour-minute input")
        check(try! TimeConversion.canonical("2024-05-01 07-08")
              == "2024-05-01 07:08:00", "hyphen hour-minute input canonicalizes to colons")
        check(try! TimeConversion.canonical("2024-05-01T07-08-09")
              == "2024-05-01 07:08:09", "hyphen full time input remains supported")

        check(try! TimeConversion.convert("2024-05-01", from: .utc)
              == "2024-05-01 08:00:00", "date-only UTC conversion")
        check(try! TimeConversion.convert("2024-05-01", from: .gmt8)
              == "2024-04-30 16:00:00", "date-only GMT+8 conversion crosses day")
        check(try! TimeConversion.convert("2024-05-01 20", from: .utc)
              == "2024-05-02 04:00:00", "hour-only UTC conversion crosses day")
        check(try! TimeConversion.convert("2024-05-02T00-30", from: .gmt8)
              == "2024-05-01 16:30:00", "hyphen hour-minute GMT+8 conversion crosses day")
        check(try! TimeConversion.convert("2024-12-31 20", from: .utc)
              == "2025-01-01 04:00:00", "hour-only conversion crosses year")
        check(try! TimeConversion.convert("2025-01-01T04:00", from: .gmt8)
              == "2024-12-31 20:00:00", "hour-minute reverse conversion crosses year")
        check(try! TimeConversion.convert("2024-02-29 20", from: .utc)
              == "2024-03-01 04:00:00", "partial-time conversion crosses leap day")
        check(try! TimeConversion.convert("2024-03-01 04:00", from: .gmt8)
              == "2024-02-29 20:00:00", "partial-time reverse conversion reaches leap day")
        expectError(.outOfRange, { try TimeConversion.convert("0001-01-01", from: .gmt8) },
                    "date-only reverse conversion below year 0001")
        expectError(.outOfRange, { try TimeConversion.convert("0001-01-01 00", from: .gmt8) },
                    "hour-only reverse conversion below year 0001")
    }

    private static func testInputValidation() {
        expectError(.invalidFormat, { try TimeConversion.canonical("") }, "empty input")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024-01-01 12:00:00Z") }, "Z suffix rejected")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024-01-01 12:00:00+08:00") }, "offset rejected")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024-01-01 12:00:00.123") }, "fractional seconds rejected")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024-01-01 12:00-00") }, "mixed time delimiters rejected")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024/01/01 12:00:00") }, "alternate date delimiters rejected")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024-01-01   12:00:00") }, "multiple internal spaces rejected")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024-01-01t12:00:00") }, "lowercase t rejected")
        expectError(.invalidDate, { try TimeConversion.canonical("0000-01-01 00:00:00") }, "year zero rejected")
        expectError(.invalidDate, { try TimeConversion.canonical("2024-00-01 00:00:00") }, "month zero rejected")
        expectError(.invalidDate, { try TimeConversion.canonical("2024-13-01 00:00:00") }, "month thirteen rejected")
        expectError(.invalidDate, { try TimeConversion.canonical("2024-04-31 00:00:00") }, "April 31 rejected")
        expectError(.invalidTime, { try TimeConversion.canonical("2024-01-01 24:00:00") }, "hour 24 rejected")
        expectError(.invalidTime, { try TimeConversion.canonical("2024-01-01 23:60:00") }, "minute 60 rejected")
        expectError(.invalidTime, { try TimeConversion.canonical("2024-01-01 23:59:60") }, "second 60 rejected")
        expectError(.invalidTime, { try TimeConversion.canonical("2024-01-01 24") }, "partial hour 24 rejected")
        expectError(.invalidTime, { try TimeConversion.canonical("2024-01-01T23:60") }, "partial minute 60 rejected")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024-01-01 12:") }, "trailing colon rejected")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024-01-01 12-") }, "trailing hyphen rejected")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024-01-01 1") }, "single-digit hour rejected")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024-01-01 123456") }, "compact HHmmss rejected")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024-01-01 12:345") }, "overwide partial minute rejected")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024-01-01 12::34") }, "empty middle time component rejected")
        expectError(.invalidFormat, { try TimeConversion.canonical("2024-01-01 12:34-56") }, "mixed partial time delimiters rejected")
    }

    private static func testBatchConversion() {
        let input = "2024-01-01 00:00:00\r\n  \r2024-01-01T07-00-00\nbad time"
        let result = TimeConversion.batch(input, from: .utc)
        check(result.output == "2024-01-01 08:00:00\n\n2024-01-01 15:00:00\n", "batch output preserves blank and invalid line positions")
        check(result.inputCount == 3, "batch counts nonblank lines including invalid lines")
        check(result.issues.count == 1, "batch reports invalid lines")
        check(result.issues.first?.line == 4, "batch reports original 1-based line")
        check(result.issues.first?.message.contains("格式") == true, "batch issue has localized message")

        let trailing = TimeConversion.batch("\n2024-01-01 00-00-00\n\n", from: .utc)
        check(trailing.output == "\n2024-01-01 08:00:00\n\n", "batch retains leading and trailing blank rows")
        check(trailing.inputCount == 1 && trailing.issues.isEmpty, "batch result counts a single valid row")

        for blankInput in ["", "   ", "\n\n", " \r\n\t "] {
            let blank = TimeConversion.batch(blankInput, from: .gmt8)
            check(blank.output.isEmpty, "blank-only input produces empty output")
            check(blank.inputCount == 0 && blank.issues.isEmpty, "blank-only input has no values or issues")
        }

        let mixedLineEnds = TimeConversion.batch("2024-01-01 00-00-00\r2024-01-01 01-00-00\r\n", from: .utc)
        check(mixedLineEnds.output == "2024-01-01 08:00:00\n2024-01-01 09:00:00\n", "batch normalizes CR, CRLF, and LF")

        let mixedFormats = TimeConversion.batch(
            "2024-01-01\n2024-01-01 01\n2024-01-01T02:03\n2024-01-01 03-04\n\n2024-01-01T05-06-07",
            from: .utc
        )
        check(mixedFormats.output == "2024-01-01 08:00:00\n2024-01-01 09:00:00\n2024-01-01 10:03:00\n2024-01-01 11:04:00\n\n2024-01-01 13:06:07",
              "batch supports mixed partial and full formats with a blank row")
        check(mixedFormats.inputCount == 5 && mixedFormats.issues.isEmpty,
              "mixed-format batch counts valid nonblank rows")
    }

    private static func testCurrentFormatting() {
        let epoch = Date(timeIntervalSince1970: 0)
        check(TimeConversion.current(in: .utc, at: epoch) == "1970-01-01 00:00:00", "current UTC uses fixed UTC")
        check(TimeConversion.current(in: .gmt8, at: epoch) == "1970-01-01 08:00:00", "current GMT+8 adds fixed offset")
        let beforeEpoch = Date(timeIntervalSince1970: -0.1)
        check(TimeConversion.current(in: .utc, at: beforeEpoch) == "1969-12-31 23:59:59", "current floors fractional pre-epoch seconds")
        check(TimeConversion.current(in: .gmt8, at: Date(timeIntervalSince1970: -62_135_596_800))
              == "0001-01-01 08:00:00", "current handles the minimum supported year")
        check(TimeConversion.current(in: .utc, at: Date(timeIntervalSince1970: -62_135_596_801)).isEmpty,
              "current returns empty outside the supported range")
    }

    /// Uses Foundation Calendar as an independent reference for 600 deterministic samples,
    /// then checks both reverse conversion and the reverse direction against Calendar.
    private static func testFixedSeedReferences() throws {
        var random = FixedRandom()
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var gmt8Calendar = Calendar(identifier: .gregorian)
        gmt8Calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]

        for sample in 0..<600 {
            let year = 200 + Int(random.next() % 9_601)
            let month = 1 + Int(random.next() % 12)
            let day = 1 + Int(random.next() % UInt64(daysInMonth(year: year, month: month)))
            let hour = Int(random.next() % 24)
            let minute = Int(random.next() % 60)
            let second = Int(random.next() % 60)
            let input = render(year, month, day, hour, minute, second)

            let utcDate = utcCalendar.date(from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute, second: second
            ))!
            let expectedGmt8 = render(gmt8Calendar.dateComponents(fields, from: utcDate))
            let actualGmt8 = try TimeConversion.convert(input, from: .utc)
            check(actualGmt8 == expectedGmt8,
                  "seeded UTC reference sample \(sample): \(input) => \(actualGmt8), expected \(expectedGmt8)")
            let utcRoundTrip = try TimeConversion.convert(actualGmt8, from: .gmt8)
            check(utcRoundTrip == input, "seeded UTC round trip sample \(sample)")

            let gmt8Date = gmt8Calendar.date(from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute, second: second
            ))!
            let expectedUtc = render(utcCalendar.dateComponents(fields, from: gmt8Date))
            let actualUtc = try TimeConversion.convert(input, from: .gmt8)
            check(actualUtc == expectedUtc, "seeded GMT+8 reference sample \(sample)")
            let gmt8RoundTrip = try TimeConversion.convert(actualUtc, from: .utc)
            check(gmt8RoundTrip == input, "seeded GMT+8 round trip sample \(sample)")

            if sample % 60 == 0 {
                let partialKind = (sample / 60) % 3 // date, hour, hour-minute
                let partialHour = partialKind == 0 ? 0 : hour
                let partialMinute = partialKind == 2 ? minute : 0
                let partialInput = renderPartial(
                    year, month, day, partialHour, partialMinute,
                    precision: partialKind,
                    delimiter: sample % 120 == 60 ? "-" : ":",
                    dateTimeSeparator: sample % 120 == 0 ? "T" : " "
                )

                let partialUtcDate = utcCalendar.date(from: DateComponents(
                    year: year, month: month, day: day,
                    hour: partialHour, minute: partialMinute, second: 0
                ))!
                let expectedPartialGmt8 = render(gmt8Calendar.dateComponents(fields, from: partialUtcDate))
                let actualPartialGmt8 = try TimeConversion.convert(partialInput, from: .utc)
                check(actualPartialGmt8 == expectedPartialGmt8,
                      "seeded partial UTC reference sample \(sample): \(partialInput)")
                let expectedPartialUtc = render(utcCalendar.dateComponents(fields, from: partialUtcDate))
                let partialUtcRoundTrip = try TimeConversion.convert(actualPartialGmt8, from: .gmt8)
                check(partialUtcRoundTrip == expectedPartialUtc,
                      "seeded partial UTC reverse reference sample \(sample)")

                let partialGmt8Date = gmt8Calendar.date(from: DateComponents(
                    year: year, month: month, day: day,
                    hour: partialHour, minute: partialMinute, second: 0
                ))!
                let expectedPartialReverse = render(utcCalendar.dateComponents(fields, from: partialGmt8Date))
                let actualPartialReverse = try TimeConversion.convert(partialInput, from: .gmt8)
                check(actualPartialReverse == expectedPartialReverse,
                      "seeded partial GMT+8 reference sample \(sample): \(partialInput)")
                let expectedPartialGmt8RoundTrip = render(gmt8Calendar.dateComponents(fields, from: partialGmt8Date))
                let partialGmt8RoundTrip = try TimeConversion.convert(actualPartialReverse, from: .utc)
                check(partialGmt8RoundTrip == expectedPartialGmt8RoundTrip,
                      "seeded partial GMT+8 reverse reference sample \(sample)")
            }
        }
    }

    private static func isLeapYear(year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year: year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private static func render(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> String {
        "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2)) \(pad(hour, 2)):\(pad(minute, 2)):\(pad(second, 2))"
    }

    private static func renderPartial(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int,
        precision: Int, delimiter: Character, dateTimeSeparator: Character
    ) -> String {
        let date = "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
        guard precision > 0 else { return date }
        let hourText = pad(hour, 2)
        guard precision > 1 else { return "\(date)\(dateTimeSeparator)\(hourText)" }
        return "\(date)\(dateTimeSeparator)\(hourText)\(delimiter)\(pad(minute, 2))"
    }

    private static func render(_ components: DateComponents) -> String {
        render(components.year!, components.month!, components.day!,
               components.hour!, components.minute!, components.second!)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let string = String(value)
        return String(repeating: "0", count: max(0, width - string.count)) + string
    }
}

try TimeConversionTests.main()
