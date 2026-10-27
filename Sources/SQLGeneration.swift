import Foundation

enum SQLValueType: String, CaseIterable, Codable {
    case string
    case datetime
    case date

    var title: String { rawValue }
}

enum SQLSnippetStyle: String, CaseIterable {
    case equal
    case greaterOrEqual
    case greater
    case lessOrEqual
    case less
    case notEqual
    case between
    case range
    case assignment

    var title: String {
        switch self {
        case .equal: return "等于 (=)"
        case .greaterOrEqual: return "大于等于 (>=)"
        case .greater: return "大于 (>)"
        case .lessOrEqual: return "小于等于 (<=)"
        case .less: return "小于 (<)"
        case .notEqual: return "不等于 (<>)"
        case .between: return "区间 (BETWEEN ... AND ...)"
        case .range: return "半开区间 (>= ... AND < ...)"
        case .assignment: return "赋值 (SET ... = ...)"
        }
    }
}

struct SQLField: Codable, Equatable {
    var name: String
    var valueType: SQLValueType
}

enum SQLGenerationError: LocalizedError {
    case invalidField
    case emptyTimes
    case lineError(Int, String)
    case rowCount(style: SQLSnippetStyle, expected: String, lines: [Int])
    case invalidRange(startLine: Int, endLine: Int)
    case reversedBetween(startLine: Int, endLine: Int)

    var errorDescription: String? {
        switch self {
        case .invalidField:
            return "字段名无效：请输入 1 至 3 段 ASCII 标识符（每段最多 64 个字符），段之间用点号分隔。可使用字母或下划线开头，并包含字母、数字、下划线或美元符号。"
        case .emptyTimes:
            return "第 1 行：请输入至少一个时间值。"
        case let .lineError(line, message):
            return "第 \(line) 行：\(message)"
        case let .rowCount(style, expected, lines):
            let location = lines.isEmpty ? "第 1 行" : "第 " + lines.map(String.init).joined(separator: "、") + " 行"
            return "\(location)：\(style.title)需要\(expected)。"
        case let .invalidRange(startLine, endLine):
            return "第 \(startLine)、\(endLine) 行：半开区间的起始时间必须早于结束时间。"
        case let .reversedBetween(startLine, endLine):
            return "第 \(startLine)、\(endLine) 行：BETWEEN 的起始时间不能晚于结束时间。"
        }
    }
}

enum SQLGeneration {
    private struct ParsedTime {
        let line: Int
        let sqlValue: String
        let comparisonValue: String
    }

    /// Normalizes a user-entered MySQL field path and rejects SQL syntax or other input.
    static func validatedField(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SQLGenerationError.invalidField }

        let rawParts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(rawParts.count) else { throw SQLGenerationError.invalidField }

        var parts: [String] = []
        for rawPart in rawParts {
            var part = String(rawPart)
            if part.first == "`" || part.last == "`" {
                guard part.count >= 3, part.first == "`", part.last == "`" else {
                    throw SQLGenerationError.invalidField
                }
                part.removeFirst()
                part.removeLast()
                // An embedded quote is not part of the accepted identifier grammar.
                guard !part.contains("`") else { throw SQLGenerationError.invalidField }
            }

            let bytes = Array(part.utf8)
            guard (1...64).contains(bytes.count),
                  isIdentifierStart(bytes[0]),
                  bytes.dropFirst().allSatisfy(isIdentifierContinuation) else {
                throw SQLGenerationError.invalidField
            }
            parts.append(part)
        }

        return parts.joined(separator: ".")
    }

    /// Generates a MySQL condition or SET fragment from one or more time values.
    /// Each nonblank input row is normalized by TimeConversion without changing its time zone.
    static func generate(
        times: String,
        field: String,
        valueType: SQLValueType,
        style: SQLSnippetStyle
    ) throws -> String {
        let normalizedField = try validatedField(field)
        let quotedField = normalizedField
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { "`\($0)`" }
            .joined(separator: ".")

        let normalizedText = times.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rawLines = normalizedText.components(separatedBy: "\n")
        var parsedTimes: [ParsedTime] = []

        for (offset, rawLine) in rawLines.enumerated() {
            guard !rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let lineNumber = offset + 1
            let canonical: String
            do {
                canonical = try TimeConversion.canonical(rawLine)
            } catch let error as LocalizedError {
                throw SQLGenerationError.lineError(
                    lineNumber,
                    error.errorDescription ?? "时间格式无效。"
                )
            } catch {
                throw SQLGenerationError.lineError(lineNumber, "时间格式无效。")
            }

            let year = Int(canonical.prefix(4)) ?? 0
            if valueType != .string && year < 1000 {
                throw SQLGenerationError.lineError(
                    lineNumber,
                    "MySQL 的 \(valueType.rawValue.uppercased()) 类型年份范围为 1000 至 9999。"
                )
            }

            let comparisonValue: String
            let literal: String
            switch valueType {
            case .string:
                comparisonValue = canonical
                literal = "'\(canonical)'"
            case .datetime:
                comparisonValue = canonical
                literal = "CAST('\(canonical)' AS DATETIME)"
            case .date:
                let date = String(canonical.prefix(10))
                comparisonValue = date
                literal = "CAST('\(date)' AS DATE)"
            }
            parsedTimes.append(ParsedTime(
                line: lineNumber,
                sqlValue: literal,
                comparisonValue: comparisonValue
            ))
        }

        guard !parsedTimes.isEmpty else { throw SQLGenerationError.emptyTimes }

        switch style {
        case .equal:
            if parsedTimes.count == 1 {
                return "\(quotedField) = \(parsedTimes[0].sqlValue)"
            }
            return "\(quotedField) IN (" + parsedTimes.map(\.sqlValue).joined(separator: ", ") + ")"
        case .greaterOrEqual:
            try requireCount(parsedTimes, exactly: 1, style: style, expected: "一个时间值")
            return "\(quotedField) >= \(parsedTimes[0].sqlValue)"
        case .greater:
            try requireCount(parsedTimes, exactly: 1, style: style, expected: "一个时间值")
            return "\(quotedField) > \(parsedTimes[0].sqlValue)"
        case .lessOrEqual:
            try requireCount(parsedTimes, exactly: 1, style: style, expected: "一个时间值")
            return "\(quotedField) <= \(parsedTimes[0].sqlValue)"
        case .less:
            try requireCount(parsedTimes, exactly: 1, style: style, expected: "一个时间值")
            return "\(quotedField) < \(parsedTimes[0].sqlValue)"
        case .notEqual:
            try requireCount(parsedTimes, exactly: 1, style: style, expected: "一个时间值")
            return "\(quotedField) <> \(parsedTimes[0].sqlValue)"
        case .between:
            try requireCount(parsedTimes, exactly: 2, style: style, expected: "两个时间值")
            guard parsedTimes[0].comparisonValue <= parsedTimes[1].comparisonValue else {
                throw SQLGenerationError.reversedBetween(startLine: parsedTimes[0].line, endLine: parsedTimes[1].line)
            }
            return "\(quotedField) BETWEEN \(parsedTimes[0].sqlValue) AND \(parsedTimes[1].sqlValue)"
        case .range:
            try requireCount(parsedTimes, exactly: 2, style: style, expected: "两个时间值")
            let start = parsedTimes[0]
            let end = parsedTimes[1]
            guard start.comparisonValue < end.comparisonValue else {
                throw SQLGenerationError.invalidRange(startLine: start.line, endLine: end.line)
            }
            return "\(quotedField) >= \(start.sqlValue)\nAND \(quotedField) < \(end.sqlValue)"
        case .assignment:
            try requireCount(parsedTimes, exactly: 1, style: style, expected: "一个时间值")
            return "SET \(quotedField) = \(parsedTimes[0].sqlValue)"
        }
    }

    private static func requireCount(
        _ times: [ParsedTime],
        exactly count: Int,
        style: SQLSnippetStyle,
        expected: String
    ) throws {
        guard times.count == count else {
            throw SQLGenerationError.rowCount(style: style, expected: expected, lines: times.map(\.line))
        }
    }

    private static func isIdentifierStart(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || byte == 95
    }

    private static func isIdentifierContinuation(_ byte: UInt8) -> Bool {
        isIdentifierStart(byte) || (48...57).contains(byte) || byte == 36
    }
}
