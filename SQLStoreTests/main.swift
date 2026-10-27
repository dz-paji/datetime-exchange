import Darwin
import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func runTests() throws -> (suiteName: String, assertions: Int) {
    let suiteName = "SQLFieldStoreTests.\(UUID().uuidString)"
    guard let preferences = UserDefaults(suiteName: suiteName) else {
        throw TestFailure(description: "Could not create isolated UserDefaults suite")
    }
    defer { preferences.removePersistentDomain(forName: suiteName) }

    var assertions = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        guard condition() else { throw TestFailure(description: message) }
    }
    func checkThrows(_ operation: () throws -> Void, _ message: String) throws {
        assertions += 1
        do {
            try operation()
            throw TestFailure(description: message)
        } catch let failure as TestFailure {
            throw failure
        } catch {
            // Any validation error satisfies this assertion.
        }
    }

    let expectedDefaults = ["created_at", "updated_at"]
    let initial = SQLFieldStore(preferences: preferences)
    try check(initial.fields.map(\.name) == expectedDefaults, "Store should start with exactly the two built-in fields")
    try check(initial.fields.allSatisfy { $0.valueType == .datetime }, "Both built-in fields should default to datetime")
    try check(initial.selectedName == "created_at", "The default selected field should be created_at")
    try check(initial.style == .greaterOrEqual && !initial.hasChosenStyle, "Style should default without being marked as chosen")

    try initial.add(name: "audit.createdOn", type: .date)
    let afterAdd = SQLFieldStore(preferences: preferences)
    try check(afterAdd.fields.map(\.name) == expectedDefaults + ["audit.createdOn"], "A custom field should persist after recreating the store")
    try check(afterAdd.fields.last?.valueType == .date, "The custom field type should persist after recreating the store")
    try check(afterAdd.selectedName == "audit.createdOn", "The added field should remain selected after recreating the store")

    try afterAdd.add(name: "last_seen", type: .string)
    afterAdd.setType(.datetime, for: "audit.createdOn")
    let withIndependentTypes = SQLFieldStore(preferences: preferences)
    let auditType = withIndependentTypes.fields.first(where: { $0.name == "audit.createdOn" })?.valueType
    let lastSeenType = withIndependentTypes.fields.first(where: { $0.name == "last_seen" })?.valueType
    try check(auditType == .datetime && lastSeenType == .string, "Each field should retain its own saved type")
    try check(withIndependentTypes.fields.prefix(2).allSatisfy { $0.valueType == .datetime }, "Changing a custom field type should not change built-in field types")

    let beforeInvalidAdds = withIndependentTypes.fields
    let selectionBeforeInvalidAdds = withIndependentTypes.selectedName
    try checkThrows({ try withIndependentTypes.add(name: "AUDIT.CREATEDON", type: .date) }, "Case-insensitive duplicate field names should be rejected")
    try check(withIndependentTypes.fields == beforeInvalidAdds && withIndependentTypes.selectedName == selectionBeforeInvalidAdds, "Rejecting a duplicate should leave fields and selection unchanged")
    try checkThrows({ try withIndependentTypes.add(name: "bad-name", type: .date) }, "Invalid field names should be rejected")
    try check(withIndependentTypes.fields == beforeInvalidAdds && withIndependentTypes.selectedName == selectionBeforeInvalidAdds, "Rejecting an invalid field should leave fields and selection unchanged")
    let afterRejectedAdds = SQLFieldStore(preferences: preferences)
    try check(afterRejectedAdds.fields == beforeInvalidAdds && afterRejectedAdds.selectedName == selectionBeforeInvalidAdds, "Rejected additions should not alter persisted state")

    try check(!afterRejectedAdds.canRemove("created_at") && !afterRejectedAdds.canRemove("updated_at"), "Built-in fields should not be removable")
    afterRejectedAdds.remove("created_at")
    afterRejectedAdds.remove("updated_at")
    try check(afterRejectedAdds.fields == beforeInvalidAdds, "Attempting to remove built-in fields should leave the fields unchanged")
    try check(afterRejectedAdds.canRemove("last_seen"), "Custom fields should be removable")
    afterRejectedAdds.remove("last_seen")
    try check(afterRejectedAdds.selectedName == "created_at", "Removing the selected custom field should select created_at")
    let afterRemoval = SQLFieldStore(preferences: preferences)
    try check(afterRemoval.fields.map(\.name) == expectedDefaults + ["audit.createdOn"], "Custom field removal should persist")
    try check(afterRemoval.selectedName == "created_at", "The fallback selection should persist after recreating the store")

    preferences.set(Data("{broken-json".utf8), forKey: "sql.fields.v1")
    let afterCorruptJSON = SQLFieldStore(preferences: preferences)
    try check(afterCorruptJSON.fields.map(\.name) == expectedDefaults, "Malformed field JSON should recover the built-in fields")
    try check(afterCorruptJSON.fields.allSatisfy { $0.valueType == .datetime }, "Malformed field JSON should recover default field types")

    let malformedFields = [
        SQLField(name: "bad-name", valueType: .date),
        SQLField(name: "temp_col", valueType: .date),
        SQLField(name: "TEMP_COL", valueType: .string)
    ]
    preferences.set(try JSONEncoder().encode(malformedFields), forKey: "sql.fields.v1")
    let afterInvalidAndDuplicateEntries = SQLFieldStore(preferences: preferences)
    try check(afterInvalidAndDuplicateEntries.fields.map(\.name) == expectedDefaults + ["temp_col"], "Invalid names should be skipped and case-insensitive duplicates collapsed")
    try check(afterInvalidAndDuplicateEntries.fields.first(where: { $0.name == "temp_col" })?.valueType == .date, "The first valid occurrence of a duplicate field should be retained")
    try check(afterInvalidAndDuplicateEntries.fields.prefix(2).allSatisfy { $0.valueType == .datetime }, "Invalid or duplicate saved entries should not remove or corrupt built-in defaults")

    afterInvalidAndDuplicateEntries.zoneIndex = 99
    try check(afterInvalidAndDuplicateEntries.zoneIndex == 2, "zoneIndex should clamp its upper bound")
    try check(SQLFieldStore(preferences: preferences).zoneIndex == 2, "The clamped upper zone index should persist")
    afterInvalidAndDuplicateEntries.zoneIndex = -100
    try check(afterInvalidAndDuplicateEntries.zoneIndex == 0, "zoneIndex should clamp its lower bound")
    try check(SQLFieldStore(preferences: preferences).zoneIndex == 0, "The clamped lower zone index should persist")

    afterInvalidAndDuplicateEntries.style = .range
    try check(afterInvalidAndDuplicateEntries.hasChosenStyle, "Saving a style should mark that a style has been chosen")
    let afterStyleSave = SQLFieldStore(preferences: preferences)
    try check(afterStyleSave.style == .range && afterStyleSave.hasChosenStyle, "The selected SQL template and chosen marker should persist")

    return (suiteName, assertions)
}

do {
    let result = try runTests()
    print("PASS \(result.assertions) assertions (isolated suite: \(result.suiteName))")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
