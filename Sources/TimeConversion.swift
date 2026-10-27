import Foundation

enum ConversionZone: String, CaseIterable {
    case utc
    case gmt8

    var title: String {
        switch self {
        case .utc: return "UTC"
        case .gmt8: return "GMT+8"
        }
    }

    var opposite: ConversionZone {
        switch self {
        case .utc: return .gmt8
        case .gmt8: return .utc
        }
    }

    fileprivate var secondsFromUTC: Int64 {
        switch self {
        case .utc: return 0
        case .gmt8: return 8 * 60 * 60
        }
    }
}

enum TimeConversionError: LocalizedError {
    case invalidFormat
    case invalidDate
    case invalidTime
    case outOfRange

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "格式无效：请输入 YYYY-MM-DD，可选填 HH、HH:mm 或 HH:mm:ss。"
        case .invalidDate:
            return "日期无效：请输入有效的公历日期，年份范围为 0001 至 9999。"
        case .invalidTime:
            return "时间无效：小时、分钟和秒必须分别在 00–23、00–59、00–59 范围内。"
        case .outOfRange:
            return "转换结果超出支持范围（0001-01-01 至 9999-12-31）。"
        }
    }
}

struct ConversionIssue {
    let line: Int
    let message: String
}

struct BatchConversion {
    let output: String
    let inputCount: Int
    let issues: [ConversionIssue]
}

enum TimeConversion {
    private struct Components {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let second: Int
    }

    private struct CivilDate {
        let year: Int
        let month: Int
        let day: Int
    }

    private static let secondsPerDay: Int64 = 86_400
    private static let firstSupportedDay = daysFromCivil(year: 1, month: 1, day: 1)
    private static let firstUnsupportedDay = daysFromCivil(year: 10_000, month: 1, day: 1)

    /// Converts a wall-clock time from one fixed zone to the other.
    /// GMT+8 is always exactly eight hours ahead of UTC, independent of DST or host settings.
    static func convert(_ text: String, from zone: ConversionZone) throws -> String {
        let value = try parse(text)
        let inputSeconds = wallClockSeconds(value)
        let utcSeconds = inputSeconds - zone.secondsFromUTC
        let targetSeconds = utcSeconds + zone.opposite.secondsFromUTC
        return try formatSupportedWallClock(secondsSinceEpoch: targetSeconds)
    }

    /// Validates and normalizes an accepted input without changing its time zone.
    static func canonical(_ text: String) throws -> String {
        let value = try parse(text)
        return format(value)
    }

    /// Formats the supplied instant in UTC or fixed GMT+8. Returns an empty string only for
    /// Date values outside the supported Gregorian years 0001...9999.
    static func current(in zone: ConversionZone, at date: Date = Date()) -> String {
        let unixSeconds = floor(date.timeIntervalSince1970)
        guard unixSeconds.isFinite else { return "" }

        let localSeconds = unixSeconds + Double(zone.secondsFromUTC)
        let firstSupportedSecond = Double(firstSupportedDay * secondsPerDay)
        let firstUnsupportedSecond = Double(firstUnsupportedDay * secondsPerDay)
        guard localSeconds >= firstSupportedSecond, localSeconds < firstUnsupportedSecond else {
            return ""
        }

        // The supported range is far inside Int64 and below Double's exact-integer limit.
        return formatWallClock(secondsSinceEpoch: Int64(localSeconds))
    }

    /// Converts each nonblank line independently, retaining blank-line positions. Invalid lines
    /// become blank output lines and are reported with their original 1-based line numbers.
    static func batch(_ text: String, from zone: ConversionZone) -> BatchConversion {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var outputLines: [String] = []
        var issues: [ConversionIssue] = []
        var inputCount = 0

        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                outputLines.append("")
                continue
            }

            inputCount += 1
            do {
                outputLines.append(try convert(line, from: zone))
            } catch let error as LocalizedError {
                outputLines.append("")
                issues.append(ConversionIssue(
                    line: index + 1,
                    message: error.errorDescription ?? "无法转换此行。"
                ))
            } catch {
                outputLines.append("")
                issues.append(ConversionIssue(line: index + 1, message: "无法转换此行。"))
            }
        }

        // A blank-only buffer has no values or useful line positions to preserve.
        let output = inputCount == 0 ? "" : outputLines.joined(separator: "\n")
        return BatchConversion(output: output, inputCount: inputCount, issues: issues)
    }

    private static func parse(_ text: String) throws -> Components {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Array(trimmed.utf8)
        guard [10, 13, 16, 19].contains(bytes.count),
              bytes[4] == 45, bytes[7] == 45,
              let year = decimal(bytes, from: 0, to: 4),
              let month = decimal(bytes, from: 5, to: 7),
              let day = decimal(bytes, from: 8, to: 10) else {
            throw TimeConversionError.invalidFormat
        }

        var hour = 0
        var minute = 0
        var second = 0
        if bytes.count >= 13 {
            guard bytes[10] == 32 || bytes[10] == 84,
                  let parsedHour = decimal(bytes, from: 11, to: 13) else {
                throw TimeConversionError.invalidFormat
            }
            hour = parsedHour
        }
        if bytes.count >= 16 {
            guard bytes[13] == 45 || bytes[13] == 58,
                  let parsedMinute = decimal(bytes, from: 14, to: 16) else {
                throw TimeConversionError.invalidFormat
            }
            minute = parsedMinute
        }
        if bytes.count == 19 {
            guard bytes[16] == bytes[13],
                  let parsedSecond = decimal(bytes, from: 17, to: 19) else {
                throw TimeConversionError.invalidFormat
            }
            second = parsedSecond
        }

        guard (1...9999).contains(year),
              (1...12).contains(month),
              (1...daysInMonth(year: year, month: month)).contains(day) else {
            throw TimeConversionError.invalidDate
        }
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            throw TimeConversionError.invalidTime
        }

        return Components(year: year, month: month, day: day,
                          hour: hour, minute: minute, second: second)
    }

    private static func decimal(_ bytes: [UInt8], from start: Int, to end: Int) -> Int? {
        var result = 0
        for index in start..<end {
            let byte = bytes[index]
            guard (48...57).contains(byte) else { return nil }
            result = result * 10 + Int(byte - 48)
        }
        return result
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private static func wallClockSeconds(_ value: Components) -> Int64 {
        let days = daysFromCivil(year: value.year, month: value.month, day: value.day)
        return days * secondsPerDay
            + Int64(value.hour * 3_600 + value.minute * 60 + value.second)
    }

    /// Proleptic Gregorian day count relative to 1970-01-01 (Howard Hinnant's civil-date
    /// decomposition, using integer arithmetic only).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int64 {
        let adjustedYear = year - (month <= 2 ? 1 : 0)
        let era = adjustedYear / 400
        let yearOfEra = adjustedYear - era * 400
        let shiftedMonth = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return Int64(era * 146_097 + dayOfEra - 719_468)
    }

    private static func civilFromDays(_ daysSinceEpoch: Int64) -> CivilDate {
        let shiftedDays = daysSinceEpoch + 719_468
        let era = floorDivision(shiftedDays, by: 146_097)
        let dayOfEra = shiftedDays - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        var year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPrime = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
        let month = monthPrime + (monthPrime < 10 ? 3 : -9)
        year += month <= 2 ? 1 : 0
        return CivilDate(year: Int(year), month: Int(month), day: Int(day))
    }

    private static func floorDivision(_ value: Int64, by divisor: Int64) -> Int64 {
        let quotient = value / divisor
        let remainder = value % divisor
        return remainder < 0 ? quotient - 1 : quotient
    }

    private static func formatSupportedWallClock(secondsSinceEpoch seconds: Int64) throws -> String {
        let day = floorDivision(seconds, by: secondsPerDay)
        let secondOfDay = seconds - day * secondsPerDay
        let civil = civilFromDays(day)
        guard (1...9999).contains(civil.year) else { throw TimeConversionError.outOfRange }
        return format(Components(
            year: civil.year,
            month: civil.month,
            day: civil.day,
            hour: Int(secondOfDay / 3_600),
            minute: Int((secondOfDay % 3_600) / 60),
            second: Int(secondOfDay % 60)
        ))
    }

    private static func formatWallClock(secondsSinceEpoch seconds: Int64) -> String {
        let day = floorDivision(seconds, by: secondsPerDay)
        let secondOfDay = seconds - day * secondsPerDay
        let civil = civilFromDays(day)
        return format(Components(
            year: civil.year,
            month: civil.month,
            day: civil.day,
            hour: Int(secondOfDay / 3_600),
            minute: Int((secondOfDay % 3_600) / 60),
            second: Int(secondOfDay % 60)
        ))
    }

    private static func format(_ value: Components) -> String {
        "\(padded(value.year, width: 4))-\(padded(value.month, width: 2))-\(padded(value.day, width: 2)) "
            + "\(padded(value.hour, width: 2)):\(padded(value.minute, width: 2)):\(padded(value.second, width: 2))"
    }

    private static func padded(_ value: Int, width: Int) -> String {
        let string = String(value)
        return String(repeating: "0", count: max(0, width - string.count)) + string
    }
}
