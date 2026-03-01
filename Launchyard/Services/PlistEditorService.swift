import Foundation

struct LaunchPlistDraft {
    enum ScheduleMode: String, CaseIterable, Identifiable {
        case interval = "Interval"
        case calendar = "Calendar"

        var id: String { rawValue }
    }

    struct CalendarEntry: Identifiable, Hashable {
        let id: UUID
        var minute: Int?
        var hour: Int?
        var day: Int?
        var weekday: Int?
        var month: Int?

        init(
            id: UUID = UUID(),
            minute: Int? = nil,
            hour: Int? = nil,
            day: Int? = nil,
            weekday: Int? = nil,
            month: Int? = nil
        ) {
            self.id = id
            self.minute = minute
            self.hour = hour
            self.day = day
            self.weekday = weekday
            self.month = month
        }

        init(dictionary: [String: Any]) {
            id = UUID()
            minute = Self.readInt(dictionary["Minute"])
            hour = Self.readInt(dictionary["Hour"])
            day = Self.readInt(dictionary["Day"])
            weekday = Self.readInt(dictionary["Weekday"])
            month = Self.readInt(dictionary["Month"])
        }

        var dictionaryValue: [String: Int] {
            var dict: [String: Int] = [:]
            if let minute { dict["Minute"] = minute }
            if let hour { dict["Hour"] = hour }
            if let day { dict["Day"] = day }
            if let weekday { dict["Weekday"] = weekday }
            if let month { dict["Month"] = month }
            return dict
        }

        private static func readInt(_ value: Any?) -> Int? {
            switch value {
            case let int as Int:
                return int
            case let number as NSNumber:
                return number.intValue
            case let string as String:
                return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
            default:
                return nil
            }
        }
    }

    private static let scheduleIntervalKey = "StartInterval"
    private static let scheduleCalendarKey = "StartCalendarInterval"

    var fields: [String: Any] = [:]
    var scheduleMode: ScheduleMode = .interval
    var intervalSeconds: Int = 3600
    var calendarEntries: [CalendarEntry] = []
    var hasSchedule: Bool = false

    static func from(dictionary: [String: Any]) -> LaunchPlistDraft {
        var draft = LaunchPlistDraft()
        draft.fields = dictionary

        if let interval = Self.asInt(dictionary[Self.scheduleIntervalKey]) {
            draft.hasSchedule = true
            draft.scheduleMode = .interval
            draft.intervalSeconds = max(interval, 1)
            draft.fields.removeValue(forKey: Self.scheduleIntervalKey)
            draft.fields.removeValue(forKey: Self.scheduleCalendarKey)
        } else if let calendarRaw = dictionary[Self.scheduleCalendarKey] {
            draft.hasSchedule = true
            draft.scheduleMode = .calendar
            draft.calendarEntries = Self.parseCalendarEntries(calendarRaw)
            if draft.calendarEntries.isEmpty {
                draft.calendarEntries = [CalendarEntry()]
            }
            draft.fields.removeValue(forKey: Self.scheduleIntervalKey)
            draft.fields.removeValue(forKey: Self.scheduleCalendarKey)
        }

        return draft
    }

    func toDictionary() throws -> [String: Any] {
        var dict = fields

        for (key, value) in dict {
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    dict.removeValue(forKey: key)
                } else {
                    dict[key] = trimmed
                }
            }
        }

        dict.removeValue(forKey: Self.scheduleIntervalKey)
        dict.removeValue(forKey: Self.scheduleCalendarKey)

        if hasSchedule {
            switch scheduleMode {
            case .interval:
                dict[Self.scheduleIntervalKey] = max(intervalSeconds, 1)
            case .calendar:
                let payload = calendarEntries
                    .map(\.dictionaryValue)
                    .filter { !$0.isEmpty }
                if payload.count == 1, let first = payload.first {
                    dict[Self.scheduleCalendarKey] = first
                } else if !payload.isEmpty {
                    dict[Self.scheduleCalendarKey] = payload
                }
            }
        }

        return dict
    }

    mutating func addField(_ key: String, defaultValue: Any) {
        if key == Self.scheduleIntervalKey {
            hasSchedule = true
            scheduleMode = .interval
            if intervalSeconds < 1 {
                intervalSeconds = 3600
            }
            return
        }
        if key == Self.scheduleCalendarKey {
            hasSchedule = true
            scheduleMode = .calendar
            if calendarEntries.isEmpty {
                calendarEntries = [CalendarEntry(minute: 0, hour: 9)]
            }
            return
        }
        fields[key] = defaultValue
    }

    mutating func removeField(_ key: String) {
        if key == Self.scheduleIntervalKey || key == Self.scheduleCalendarKey {
            hasSchedule = false
            return
        }
        fields.removeValue(forKey: key)
    }

    func isFieldConfigured(_ key: String) -> Bool {
        if key == Self.scheduleIntervalKey || key == Self.scheduleCalendarKey {
            return hasSchedule
        }
        return fields[key] != nil
    }

    func stringValue(for key: String) -> String {
        fields[key] as? String ?? ""
    }

    mutating func setStringValue(for key: String, value: String) {
        fields[key] = value
    }

    func boolValue(for key: String, default defaultValue: Bool = false) -> Bool {
        switch fields[key] {
        case let bool as Bool:
            return bool
        case let int as Int:
            return int != 0
        case let string as String:
            return (string as NSString).boolValue
        default:
            return defaultValue
        }
    }

    mutating func setBoolValue(for key: String, value: Bool) {
        fields[key] = value
    }

    func intValue(for key: String, default defaultValue: Int = 0) -> Int {
        Self.asInt(fields[key]) ?? defaultValue
    }

    mutating func setIntValue(for key: String, value: Int) {
        fields[key] = value
    }

    func stringArrayValue(for key: String) -> [String] {
        if let values = fields[key] as? [String] {
            return values
        }
        if let values = fields[key] as? [Any] {
            return values.compactMap { value in
                if let string = value as? String {
                    return string
                }
                return nil
            }
        }
        return []
    }

    mutating func setStringArrayValue(for key: String, values: [String]) {
        let trimmed = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        fields[key] = trimmed
    }

    func stringDictionaryValue(for key: String) -> [String: String] {
        guard let dict = fields[key] as? [String: Any] else {
            return [:]
        }
        var mapped: [String: String] = [:]
        for (dictKey, value) in dict {
            mapped[dictKey] = String(describing: value)
        }
        return mapped
    }

    mutating func setStringDictionaryValue(for key: String, values: [String: String]) {
        var dict: [String: Any] = [:]
        for (dictKey, value) in values {
            let trimmedKey = dictKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedKey.isEmpty {
                continue
            }
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let int = Int(trimmedValue) {
                dict[trimmedKey] = int
            } else if trimmedValue.caseInsensitiveCompare("true") == .orderedSame {
                dict[trimmedKey] = true
            } else if trimmedValue.caseInsensitiveCompare("false") == .orderedSame {
                dict[trimmedKey] = false
            } else {
                dict[trimmedKey] = trimmedValue
            }
        }
        fields[key] = dict
    }

    private static func parseCalendarEntries(_ value: Any) -> [CalendarEntry] {
        if let dict = value as? [String: Any] {
            return [CalendarEntry(dictionary: dict)]
        }
        if let list = value as? [[String: Any]] {
            return list.map(CalendarEntry.init(dictionary:))
        }
        if let list = value as? [Any] {
            return list.compactMap { item in
                guard let dict = item as? [String: Any] else { return nil }
                return CalendarEntry(dictionary: dict)
            }
        }
        return []
    }

    private static func asInt(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    // Compatibility properties used by CreateServiceSheet.
    var label: String {
        get { stringValue(for: "Label") }
        set { setStringValue(for: "Label", value: newValue) }
    }

    var program: String {
        get { stringValue(for: "Program") }
        set { setStringValue(for: "Program", value: newValue) }
    }

    var programArgumentsText: String {
        get { stringArrayValue(for: "ProgramArguments").joined(separator: "\n") }
        set {
            let values = newValue
                .split(separator: "\n")
                .map(String.init)
            setStringArrayValue(for: "ProgramArguments", values: values)
        }
    }

    var runAtLoad: Bool {
        get { boolValue(for: "RunAtLoad") }
        set { setBoolValue(for: "RunAtLoad", value: newValue) }
    }

    var keepAlive: Bool {
        get { boolValue(for: "KeepAlive") }
        set { setBoolValue(for: "KeepAlive", value: newValue) }
    }

    var startInterval: String {
        get { String(intervalSeconds) }
        set {
            if let value = Int(newValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                intervalSeconds = max(value, 1)
                hasSchedule = true
                scheduleMode = .interval
            }
        }
    }

    var startCalendarIntervalJSON: String {
        get {
            let payload = calendarEntries.map(\.dictionaryValue)
            guard !payload.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
                  let json = String(data: data, encoding: .utf8) else {
                return ""
            }
            return json
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                calendarEntries = []
                return
            }
            let data = Data(trimmed.utf8)
            if let parsed = try? JSONSerialization.jsonObject(with: data) {
                let entries = Self.parseCalendarEntries(parsed)
                if !entries.isEmpty {
                    calendarEntries = entries
                    hasSchedule = true
                    scheduleMode = .calendar
                }
            }
        }
    }

    var standardOutPath: String {
        get { stringValue(for: "StandardOutPath") }
        set { setStringValue(for: "StandardOutPath", value: newValue) }
    }

    var standardErrorPath: String {
        get { stringValue(for: "StandardErrorPath") }
        set { setStringValue(for: "StandardErrorPath", value: newValue) }
    }

    var workingDirectory: String {
        get { stringValue(for: "WorkingDirectory") }
        set { setStringValue(for: "WorkingDirectory", value: newValue) }
    }
}

enum PlistEditorService {
    static func readPlist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let format = UnsafeMutablePointer<PropertyListSerialization.PropertyListFormat>.allocate(capacity: 1)
        defer { format.deallocate() }
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: format)
        guard let dict = plist as? [String: Any] else {
            throw CommandError.executionFailed("Plist is not a dictionary: \(url.path)")
        }
        return dict
    }

    static func writePlist(dictionary: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    static func xmlString(from dictionary: [String: Any]) throws -> String {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CommandError.executionFailed("Could not convert plist to UTF-8 string")
        }
        return string
    }

    static func dictionary(fromRawXML raw: String) throws -> [String: Any] {
        let data = Data(raw.utf8)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: Any] else {
            throw CommandError.executionFailed("Raw plist is not a dictionary")
        }
        return dict
    }

    static func validate(dictionary: [String: Any]) throws {
        let label = (dictionary["Label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if label.isEmpty {
            throw CommandError.executionFailed("Label is required.")
        }

        let program = (dictionary["Program"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let args = dictionary["ProgramArguments"] as? [String] ?? []
        if program.isEmpty && args.isEmpty {
            throw CommandError.executionFailed("Provide Program or ProgramArguments.")
        }
    }
}
