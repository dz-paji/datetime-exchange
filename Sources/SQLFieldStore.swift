import Foundation

/// Stores only SQL field preferences; time inputs and generated SQL remain in memory.
final class SQLFieldStore {
    private let preferences: UserDefaults
    private let fieldsKey = "sql.fields.v1"
    private(set) var fields: [SQLField]
    private static let builtInNames = ["created_at", "updated_at"]

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let decoded = preferences.data(forKey: fieldsKey)
            .flatMap { try? JSONDecoder().decode([SQLField].self, from: $0) } ?? []
        var valid: [SQLField] = []
        for field in decoded {
            guard let name = try? SQLGeneration.validatedField(field.name),
                  !valid.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            valid.append(SQLField(name: name, valueType: field.valueType))
        }
        var result: [SQLField] = Self.builtInNames.map { name in
            SQLField(name: name, valueType: valid.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.valueType ?? .datetime)
        }
        result.append(contentsOf: valid.filter { field in
            !Self.builtInNames.contains(where: { $0.caseInsensitiveCompare(field.name) == .orderedSame })
        })
        fields = result
    }

    var selectedName: String {
        get {
            let saved = preferences.string(forKey: "sql.selectedField") ?? "created_at"
            return fields.contains(where: { $0.name == saved }) ? saved : "created_at"
        }
        set { preferences.set(newValue, forKey: "sql.selectedField") }
    }

    var style: SQLSnippetStyle {
        get { SQLSnippetStyle(rawValue: preferences.string(forKey: "sql.style") ?? "") ?? .greaterOrEqual }
        set { preferences.set(newValue.rawValue, forKey: "sql.style") }
    }

    var hasChosenStyle: Bool { preferences.string(forKey: "sql.style") != nil }

    /// 0 = conversion result, 1 = UTC, 2 = GMT+8.
    var zoneIndex: Int {
        get { min(2, max(0, preferences.integer(forKey: "sql.zoneIndex"))) }
        set { preferences.set(newValue, forKey: "sql.zoneIndex") }
    }

    func add(name raw: String, type: SQLValueType) throws {
        let name = try SQLGeneration.validatedField(raw)
        guard !fields.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw FieldError.duplicate
        }
        fields.append(SQLField(name: name, valueType: type))
        selectedName = name
        save()
    }

    func setType(_ type: SQLValueType, for name: String) {
        guard let index = fields.firstIndex(where: { $0.name == name }) else { return }
        fields[index].valueType = type
        save()
    }

    func canRemove(_ name: String) -> Bool { !Self.builtInNames.contains(name) }

    func remove(_ name: String) {
        guard canRemove(name) else { return }
        let wasSelected = selectedName == name
        fields.removeAll(where: { $0.name == name })
        if wasSelected { selectedName = "created_at" }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(fields) { preferences.set(data, forKey: fieldsKey) }
    }

    private enum FieldError: LocalizedError {
        case duplicate
        var errorDescription: String? { "字段已存在，可在下拉菜单中选择并修改类型。" }
    }
}
