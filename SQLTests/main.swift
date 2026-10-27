import Foundation

private var checks = 0
private var failures: [String] = []

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { failures.append(message) }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    check(actual == expected, "\(message); got \(actual), expected \(expected)")
}

private func localizedMessage(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? String(describing: error)
}

private func expectError(
    containing fragment: String,
    _ message: String,
    operation: () throws -> Any
) {
    do {
        _ = try operation()
        check(false, "\(message); expected an error containing \(fragment)")
    } catch {
        let description = localizedMessage(error)
        check(description.contains(fragment), "\(message); got error: \(description)")
    }
}

private func generate(
    _ times: String,
    field: String = "created_at",
    type: SQLValueType = .string,
    style: SQLSnippetStyle = .equal
) throws -> String {
    try SQLGeneration.generate(times: times, field: field, valueType: type, style: style)
}

private func testValueTypesAndAllTemplates() throws {
    expectEqual(SQLValueType.allCases.map(\.rawValue), ["string", "datetime", "date"], "value types")
    for valueType in SQLValueType.allCases {
        expectEqual(valueType.title, valueType.rawValue, "value type title mirrors raw value")
    }
    expectEqual(SQLSnippetStyle.allCases.count, 9, "all snippet styles are exposed")
    check(SQLSnippetStyle.allCases.allSatisfy { !$0.title.isEmpty }, "every style has a display title")

    let time = "2026-10-27 08:00:00"
    expectEqual(try generate(time), "`created_at` = '2026-10-27 08:00:00'", "string equality")
    expectEqual(
        try generate(time, type: .datetime),
        "`created_at` = CAST('2026-10-27 08:00:00' AS DATETIME)",
        "datetime equality uses CAST"
    )
    expectEqual(
        try generate(time, type: .date),
        "`created_at` = CAST('2026-10-27' AS DATE)",
        "date equality truncates the time"
    )

    let templates: [(SQLSnippetStyle, String)] = [
        (.equal, "`created_at` = '2026-10-27 08:00:00'"),
        (.greaterOrEqual, "`created_at` >= '2026-10-27 08:00:00'"),
        (.greater, "`created_at` > '2026-10-27 08:00:00'"),
        (.lessOrEqual, "`created_at` <= '2026-10-27 08:00:00'"),
        (.less, "`created_at` < '2026-10-27 08:00:00'"),
        (.notEqual, "`created_at` <> '2026-10-27 08:00:00'"),
        (.between, "`created_at` BETWEEN '2026-10-27 08:00:00' AND '2026-10-28 08:00:00'"),
        (.range, "`created_at` >= '2026-10-27 08:00:00'\nAND `created_at` < '2026-10-28 08:00:00'"),
        (.assignment, "SET `created_at` = '2026-10-27 08:00:00'")
    ]
    for (style, expected) in templates {
        let rows = style == .between || style == .range
            ? "2026-10-27 08:00:00\n2026-10-28 08:00:00"
            : time
        expectEqual(try generate(rows, style: style), expected, "template \(style.rawValue)")
    }

    expectEqual(
        try generate("2026-10-27\n2026-10-28T09:30", style: .equal),
        "`created_at` IN ('2026-10-27 00:00:00', '2026-10-28 09:30:00')",
        "equal style turns multiple rows into an IN list"
    )
    expectEqual(
        try generate("2026-10-27 08:00:00\n2026-10-27 08:00:00", style: .between),
        "`created_at` BETWEEN '2026-10-27 08:00:00' AND '2026-10-27 08:00:00'",
        "between permits equal endpoints"
    )
}

private func testTimeNormalizationAndTypes() throws {
    expectEqual(
        try generate("2026-10-27", type: .string),
        "`created_at` = '2026-10-27 00:00:00'",
        "date-only value is padded"
    )
    expectEqual(
        try generate("2026-10-27T08", type: .datetime),
        "`created_at` = CAST('2026-10-27 08:00:00' AS DATETIME)",
        "partial hour is padded"
    )
    expectEqual(
        try generate("2026-10-27 08-09-10", type: .string),
        "`created_at` = '2026-10-27 08:09:10'",
        "legacy hyphen time delimiters are accepted"
    )
    expectEqual(
        try generate("2026-10-27 08:09:10", type: .date),
        "`created_at` = CAST('2026-10-27' AS DATE)",
        "date SQL literals use only the date portion"
    )
    expectEqual(
        try generate("2026-10-27 08:00:00\r\n\r\n2026-10-28 09:00:00", style: .equal),
        "`created_at` IN ('2026-10-27 08:00:00', '2026-10-28 09:00:00')",
        "CRLF, CR, and blank rows normalize and blanks are ignored"
    )
}

private func testFields() throws {
    expectEqual(try SQLGeneration.validatedField(" created_at \n"), "created_at", "field trims outer whitespace")
    expectEqual(try SQLGeneration.validatedField("orders.created_at"), "orders.created_at", "qualified name")
    expectEqual(
        try SQLGeneration.validatedField(" `select`.`order` "),
        "select.order",
        "one backtick pair per segment is normalized away"
    )
    expectEqual(
        try generate("2026-10-27", field: "select.orders.created_at"),
        "`select`.`orders`.`created_at` = '2026-10-27 00:00:00'",
        "reserved words and qualified fields are quoted segment by segment"
    )
    expectEqual(
        try generate("2026-10-27", field: "`orders`.`created_at`"),
        "`orders`.`created_at` = '2026-10-27 00:00:00'",
        "prequoted field is emitted consistently"
    )
    expectEqual(
        try SQLGeneration.validatedField("schema._value$2"),
        "schema._value$2",
        "field grammar accepts dollar sign after the first character in a segment"
    )
    expectEqual(try SQLGeneration.validatedField("a" + String(repeating: "b", count: 63)).count, 64,
                "64-character segment is accepted")

    let invalidNames = [
        "", "   ", "1created_at", "a b", "a; DROP TABLE users", "a--comment", "a/*comment*/",
        "a..b", ".a", "a.", "a.b.c.d", "中文", "$startsWithDollar", "a`b", "`a``b`",
        "`a.b`", "a .b", "a. b", String(repeating: "a", count: 65)
    ]
    for name in invalidNames {
        expectError(containing: "字段名无效", "invalid field \(name.debugDescription)") {
            try SQLGeneration.validatedField(name)
        }
    }

    let field = SQLField(name: "updated_at", valueType: .datetime)
    let encoded = try JSONEncoder().encode(field)
    expectEqual(try JSONDecoder().decode(SQLField.self, from: encoded), field, "SQLField is Codable and Equatable")
}

private func testMySQLYearBoundsAndInputErrors() throws {
    expectEqual(
        try generate("0001-01-01", type: .string),
        "`created_at` = '0001-01-01 00:00:00'",
        "string supports converter year 0001"
    )
    for type in [SQLValueType.datetime, .date] {
        expectError(containing: "第 1 行", "\(type.rawValue) rejects year 0999") {
            try generate("0999-12-31", type: type)
        }
        expectEqual(
            try generate("1000-01-01", type: type),
            "`created_at` = CAST('1000-01-01\(type == .date ? "' AS DATE)" : " 00:00:00' AS DATETIME)")",
            "\(type.rawValue) accepts year 1000"
        )
        expectEqual(
            try generate("9999-12-31", type: type),
            "`created_at` = CAST('9999-12-31\(type == .date ? "' AS DATE)" : " 00:00:00' AS DATETIME)")",
            "\(type.rawValue) accepts year 9999"
        )
    }

    expectError(containing: "第 3 行", "malformed batch reports original row after blanks and mixed line endings") {
        try generate("2026-10-27\r\n\rbad value\n2026-10-28")
    }
    expectError(containing: "第 1 行", "arbitrary SQL in time input is rejected") {
        try generate("2026-10-27'; DROP TABLE users; --")
    }
    expectError(containing: "第 1 行", "blank-only input reports a clear input error") {
        try generate(" \r\n \t\n")
    }
    expectError(containing: "第 1、2 行", "single comparison rejects multiple input rows") {
        try generate("2026-10-27\n2026-10-28", style: .greater)
    }
    expectError(containing: "第 1 行", "between rejects a single row") {
        try generate("2026-10-27", style: .between)
    }
}

private func testRangeOrdering() throws {
    expectError(containing: "第 1、2 行", "BETWEEN rejects reversed endpoints") {
        try generate("2026-10-28\n2026-10-27", style: .between)
    }
    expectEqual(
        try generate("2026-10-27 12:00:00\n2026-10-27 12:00:01", style: .range),
        "`created_at` >= '2026-10-27 12:00:00'\nAND `created_at` < '2026-10-27 12:00:01'",
        "range uses input order and accepts increasing datetimes"
    )
    expectError(containing: "第 1、2 行", "range rejects reversed datetimes without sorting") {
        try generate("2026-10-28\n2026-10-27", style: .range)
    }
    expectError(containing: "第 1、2 行", "range rejects equal endpoints") {
        try generate("2026-10-27 08:00:00\n2026-10-27 08:00:00", style: .range)
    }
    expectError(containing: "第 1、2 行", "date range compares the emitted date literal and rejects same-day endpoints") {
        try generate("2026-10-27 08:00:00\n2026-10-27 09:00:00", type: .date, style: .range)
    }
    expectEqual(
        try generate("2026-10-27 23:59:59\n2026-10-28 00:00:00", type: .date, style: .range),
        "`created_at` >= CAST('2026-10-27' AS DATE)\nAND `created_at` < CAST('2026-10-28' AS DATE)",
        "date range allows consecutive dates"
    )
}

do {
    try testValueTypesAndAllTemplates()
    try testTimeNormalizationAndTypes()
    try testFields()
    try testMySQLYearBoundsAndInputErrors()
    try testRangeOrdering()

    if failures.isEmpty {
        print("SQLGeneration tests passed: \(checks) checks")
    } else {
        for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
        fputs("\(failures.count) of \(checks) checks failed\n", stderr)
        exit(EXIT_FAILURE)
    }
} catch {
    fputs("Unexpected test error: \(localizedMessage(error))\n", stderr)
    exit(EXIT_FAILURE)
}
