import SwiftUI

struct ServiceEditorView: View {
    let service: LaunchService
    let onSave: ([String: Any], String?, Bool) -> Void

    @State private var draft: LaunchPlistDraft
    @State private var rawXML: String
    @State private var useRawEditor: Bool = false
    @State private var validationMessage: String?
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var hasUnsavedXML: Bool = false
    @State private var draftVersion: Int = 0

    init(service: LaunchService, onSave: @escaping ([String: Any], String?, Bool) -> Void) {
        self.service = service
        self.onSave = onSave
        _draft = State(initialValue: LaunchPlistDraft.from(dictionary: service.plistDictionary))
        _rawXML = State(initialValue: (try? PlistEditorService.xmlString(from: service.plistDictionary)) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(!useRawEditor ? Color.accentColor : Color.secondary)
                    .font(.system(size: 13))
                Toggle("", isOn: $useRawEditor.animation(.easeInOut(duration: 0.2)))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                Text("</>" )
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(useRawEditor ? Color.accentColor : Color.secondary)
            }

            if useRawEditor {
                TextEditor(text: $rawXML)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 260)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(hasUnsavedXML ? Color.orange : Color.gray.opacity(0.3))
                    }
                    .onChange(of: rawXML) { _, _ in
                        hasUnsavedXML = true
                    }

            } else {
                Form {
                    ForEach(fieldCategories, id: \.self) { category in
                        let fields = visibleDefinitions(in: category)
                        if !fields.isEmpty {
                            Section(category) {
                                ForEach(fields) { definition in
                                    fieldEditor(definition)
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -18)
                .padding(.top, -12)
                .onChange(of: draftVersion) { _, _ in
                    autoSaveTask?.cancel()
                    autoSaveTask = Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run { saveWYSIWYG() }
                    }
                }
            }

            HStack {
                if !useRawEditor {
                    Menu {
                        ForEach(fieldCategories, id: \.self) { category in
                            let fields = availableDefinitions(in: category)
                            if !fields.isEmpty {
                                Section(category) {
                                    ForEach(fields) { definition in
                                        Button(definition.title) {
                                            addField(definition)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Add Field", systemImage: "plus")
                    }
                }

                Spacer()
                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(validationMessage == "Validation passed." ? .green : .red)
                }
                if useRawEditor {
                    if hasUnsavedXML {
                        Text("Unsaved changes")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button("Save") {
                        saveXML()
                    }
                    .keyboardShortcut("s", modifiers: .command)
                }
            }
        }

        .onChange(of: service.id) { _, _ in
            draft = LaunchPlistDraft.from(dictionary: service.plistDictionary)
            rawXML = (try? PlistEditorService.xmlString(from: service.plistDictionary)) ?? ""
            validationMessage = nil
        }
    }

    @ViewBuilder
    private func fieldEditor(_ definition: LaunchdFieldDefinition) -> some View {
        switch definition.kind {
        case .string:
            VStack(alignment: .leading, spacing: 6) {
                fieldHeader(definition)
                TextField(definition.title, text: stringBinding(for: definition.key))
            }
        case .boolean:
            HStack {
                Toggle(definition.title, isOn: boolBinding(for: definition.key))
                removeButton(for: definition)
            }
        case .integer:
            VStack(alignment: .leading, spacing: 6) {
                fieldHeader(definition)
                TextField(definition.title, value: intBinding(for: definition.key), format: .number)
                    .textFieldStyle(.roundedBorder)
            }
        case .dictionary:
            VStack(alignment: .leading, spacing: 6) {
                fieldHeader(definition)
                DictionaryFieldEditor(entries: dictionaryBinding(for: definition.key))
            }
        case .array:
            VStack(alignment: .leading, spacing: 6) {
                fieldHeader(definition)
                StringArrayFieldEditor(values: arrayBinding(for: definition.key))
            }
        case .schedule:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Schedule")
                        .font(.headline)
                    Spacer()
                    removeButton(for: definition)
                }

                Picker("Mode", selection: $draft.scheduleMode) {
                    ForEach(LaunchPlistDraft.ScheduleMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch draft.scheduleMode {
                case .interval:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("", value: $draft.intervalSeconds, format: .number)
                                .onChange(of: draft.intervalSeconds) { _, _ in }
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("seconds")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Stepper("", value: $draft.intervalSeconds, in: 1...604_800)
                                .onChange(of: draft.intervalSeconds) { _, _ in draftVersion += 1 }
                                .labelsHidden()
                        }

                        HStack(spacing: 8) {
                            ForEach(intervalPresets, id: \.value) { preset in
                                Button(preset.label) {
                                    draft.intervalSeconds = preset.value
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(draft.intervalSeconds == preset.value ? .accentColor : nil)
                            }
                            Spacer()
                        }

                        Text(intervalPreview(seconds: draft.intervalSeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .calendar:
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(draft.calendarEntries.enumerated()), id: \.element.id) { index, _ in
                            CalendarEntryEditor(
                                entry: calendarEntryBinding(index),
                                index: index,
                                onRemove: {
                                    draft.calendarEntries.remove(at: index)
                                }
                            )
                        }

                        HStack {
                            Button {
                                draft.calendarEntries.append(.init(minute: 0, hour: 9))
                            } label: {
                                Label("Add Calendar Entry", systemImage: "plus")
                            }

                            Spacer()
                        }

                        Text(calendarPreview(entries: draft.calendarEntries))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fieldHeader(_ definition: LaunchdFieldDefinition) -> some View {
        HStack {
            Text(definition.title)
                .font(.headline)
            Spacer()
            removeButton(for: definition)
        }
    }

    @ViewBuilder
    private func removeButton(for definition: LaunchdFieldDefinition) -> some View {
        Button(role: .destructive) {
            draft.removeField(definition.key)
        } label: {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Remove \(definition.title)")
    }

    private var intervalSliderBinding: Binding<Double> {
        Binding(
            get: { Double(draft.intervalSeconds) },
            set: { draft.intervalSeconds = max(1, Int($0)) }
        )
    }

    private func calendarEntryBinding(_ index: Int) -> Binding<LaunchPlistDraft.CalendarEntry> {
        Binding(
            get: { draft.calendarEntries[index] },
            set: { draft.calendarEntries[index] = $0 }
        )
    }

    private func visibleDefinitions(in category: String) -> [LaunchdFieldDefinition] {
        supportedFieldDefinitions.filter { definition in
            definition.category == category && isVisible(definition)
        }
    }

    private func availableDefinitions(in category: String) -> [LaunchdFieldDefinition] {
        supportedFieldDefinitions.filter { definition in
            definition.category == category && isAvailable(definition)
        }
    }

    private func isVisible(_ definition: LaunchdFieldDefinition) -> Bool {
        if definition.kind == .schedule {
            let selectedKey = draft.scheduleMode == .interval ? "StartInterval" : "StartCalendarInterval"
            return draft.hasSchedule && definition.key == selectedKey
        }
        return draft.isFieldConfigured(definition.key)
    }

    private func isAvailable(_ definition: LaunchdFieldDefinition) -> Bool {
        if definition.kind == .schedule {
            return !draft.hasSchedule
        }
        return !draft.isFieldConfigured(definition.key)
    }

    private func addField(_ definition: LaunchdFieldDefinition) {
        draft.addField(definition.key, defaultValue: definition.defaultValue)
    }

    private func stringBinding(for key: String) -> Binding<String> {
        Binding(
            get: { draft.stringValue(for: key) },
            set: { draft.setStringValue(for: key, value: $0); draftVersion += 1 }
        )
    }

    private func boolBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { draft.boolValue(for: key) },
            set: { draft.setBoolValue(for: key, value: $0); draftVersion += 1 }
        )
    }

    private func intBinding(for key: String) -> Binding<Int> {
        Binding(
            get: { draft.intValue(for: key) },
            set: { draft.setIntValue(for: key, value: $0); draftVersion += 1 }
        )
    }

    private func arrayBinding(for key: String) -> Binding<[String]> {
        Binding(
            get: { draft.stringArrayValue(for: key) },
            set: { draft.setStringArrayValue(for: key, values: $0); draftVersion += 1 }
        )
    }

    private func dictionaryBinding(for key: String) -> Binding<[KeyValueEntry]> {
        Binding(
            get: {
                draft.stringDictionaryValue(for: key)
                    .sorted(by: { $0.key < $1.key })
                    .map { KeyValueEntry(key: $0.key, value: $0.value) }
            },
            set: { entries in
                var dict: [String: String] = [:]
                for entry in entries {
                    dict[entry.key] = entry.value
                }
                draft.setStringDictionaryValue(for: key, values: dict); draftVersion += 1
            }
        )
    }

    private func validateOnly() {
        do {
            if useRawEditor {
                let dict = try PlistEditorService.dictionary(fromRawXML: rawXML)
                try PlistEditorService.validate(dictionary: dict)
            } else {
                let dict = try draft.toDictionary()
                try PlistEditorService.validate(dictionary: dict)
            }
            validationMessage = "Validation passed."
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func saveWYSIWYG() {
        do {
            let dict = try draft.toDictionary()
            try PlistEditorService.validate(dictionary: dict)
            validationMessage = nil
            onSave(dict, nil, false)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func saveXML() {
        do {
            let parsed = try PlistEditorService.dictionary(fromRawXML: rawXML)
            try PlistEditorService.validate(dictionary: parsed)
            validationMessage = nil
            hasUnsavedXML = false
            onSave([:], rawXML, true)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func intervalPreview(seconds: Int) -> String {
        if seconds % 86_400 == 0 {
            let days = seconds / 86_400
            return days == 1 ? "Every day" : "Every \(days) days"
        }
        if seconds % 3_600 == 0 {
            let hours = seconds / 3_600
            return hours == 1 ? "Every hour" : "Every \(hours) hours"
        }
        if seconds % 60 == 0 {
            let minutes = seconds / 60
            return minutes == 1 ? "Every minute" : "Every \(minutes) minutes"
        }
        return seconds == 1 ? "Every second" : "Every \(seconds) seconds"
    }

    private func calendarPreview(entries: [LaunchPlistDraft.CalendarEntry]) -> String {
        if entries.isEmpty {
            return "No calendar entries configured"
        }
        return entries.map(calendarEntryDescription).joined(separator: "\n")
    }

    private func calendarEntryDescription(_ entry: LaunchPlistDraft.CalendarEntry) -> String {
        if let weekday = entry.weekday,
           let weekdayName = weekdayNames[safe: weekday],
           let hour = entry.hour {
            let minute = entry.minute ?? 0
            return "Every \(weekdayName) at \(formattedTime(hour: hour, minute: minute))"
        }

        if let day = entry.day,
           entry.weekday == nil,
           entry.month == nil,
           let hour = entry.hour {
            let minute = entry.minute ?? 0
            return "\(ordinal(day)) of every month at \(formattedTime(hour: hour, minute: minute))"
        }

        var parts: [String] = []
        if let month = entry.month,
           let monthName = monthNames[safe: month - 1] {
            parts.append("month=\(monthName)")
        }
        if let day = entry.day {
            parts.append("day=\(day)")
        }
        if let weekday = entry.weekday,
           let weekdayName = weekdayNames[safe: weekday] {
            parts.append("weekday=\(weekdayName)")
        }
        if let hour = entry.hour {
            parts.append("hour=\(hour)")
        }
        if let minute = entry.minute {
            parts.append("minute=\(minute)")
        }
        if parts.isEmpty {
            return "Every minute"
        }
        return "Runs when \(parts.joined(separator: ", "))"
    }

    private func ordinal(_ value: Int) -> String {
        let suffix: String
        switch value % 100 {
        case 11, 12, 13:
            suffix = "th"
        default:
            switch value % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(value)\(suffix)"
    }

    private func formattedTime(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let calendar = Calendar.current
        if let date = calendar.date(from: components) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            let text = formatter.string(from: date)
            if text == "12:00 AM" {
                return "midnight"
            }
            if text == "12:00 PM" {
                return "noon"
            }
            return text
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    private let fieldCategories: [String] = [
        "Identification",
        "Execution",
        "Scheduling",
        "Security",
        "Resources",
        "I/O",
        "Environment",
        "Networking",
        "Lifecycle",
        "System Integration"
    ]

    private var supportedFieldDefinitions: [LaunchdFieldDefinition] {
        [
            .init(key: "Label", title: "Label", category: "Identification", kind: .string, defaultValue: ""),
            .init(key: "Disabled", title: "Disabled", category: "Identification", kind: .boolean, defaultValue: false),

            .init(key: "Program", title: "Program", category: "Execution", kind: .string, defaultValue: ""),
            .init(key: "ProgramArguments", title: "ProgramArguments", category: "Execution", kind: .array, defaultValue: [""]),
            .init(key: "BundleProgram", title: "BundleProgram", category: "Execution", kind: .string, defaultValue: ""),
            .init(key: "EnableGlobbing", title: "EnableGlobbing", category: "Execution", kind: .boolean, defaultValue: false),

            .init(key: "RunAtLoad", title: "RunAtLoad", category: "Scheduling", kind: .boolean, defaultValue: false),
            .init(key: "StartInterval", title: "StartInterval", category: "Scheduling", kind: .schedule, defaultValue: 3600),
            .init(key: "StartCalendarInterval", title: "StartCalendarInterval", category: "Scheduling", kind: .schedule, defaultValue: [String: Int]()),
            .init(key: "KeepAlive", title: "KeepAlive", category: "Scheduling", kind: .boolean, defaultValue: false),
            .init(key: "WatchPaths", title: "WatchPaths", category: "Scheduling", kind: .array, defaultValue: [""]),
            .init(key: "QueueDirectories", title: "QueueDirectories", category: "Scheduling", kind: .array, defaultValue: [""]),

            .init(key: "UserName", title: "UserName", category: "Security", kind: .string, defaultValue: ""),
            .init(key: "GroupName", title: "GroupName", category: "Security", kind: .string, defaultValue: ""),
            .init(key: "InitGroups", title: "InitGroups", category: "Security", kind: .boolean, defaultValue: false),
            .init(key: "Umask", title: "Umask", category: "Security", kind: .integer, defaultValue: 0),
            .init(key: "RootDirectory", title: "RootDirectory", category: "Security", kind: .string, defaultValue: ""),

            .init(key: "SoftResourceLimits", title: "SoftResourceLimits", category: "Resources", kind: .dictionary, defaultValue: [String: String]()),
            .init(key: "HardResourceLimits", title: "HardResourceLimits", category: "Resources", kind: .dictionary, defaultValue: [String: String]()),
            .init(key: "Nice", title: "Nice", category: "Resources", kind: .integer, defaultValue: 0),
            .init(key: "ProcessType", title: "ProcessType", category: "Resources", kind: .string, defaultValue: "Background"),
            .init(key: "LowPriorityIO", title: "LowPriorityIO", category: "Resources", kind: .boolean, defaultValue: false),
            .init(key: "LowPriorityBackgroundIO", title: "LowPriorityBackgroundIO", category: "Resources", kind: .boolean, defaultValue: false),
            .init(key: "MaterializeDataless", title: "MaterializeDataless", category: "Resources", kind: .boolean, defaultValue: false),

            .init(key: "StandardOutPath", title: "StandardOutPath", category: "I/O", kind: .string, defaultValue: ""),
            .init(key: "StandardErrorPath", title: "StandardErrorPath", category: "I/O", kind: .string, defaultValue: ""),
            .init(key: "StandardInPath", title: "StandardInPath", category: "I/O", kind: .string, defaultValue: ""),
            .init(key: "Debug", title: "Debug", category: "I/O", kind: .boolean, defaultValue: false),

            .init(key: "EnvironmentVariables", title: "EnvironmentVariables", category: "Environment", kind: .dictionary, defaultValue: [String: String]()),
            .init(key: "WorkingDirectory", title: "WorkingDirectory", category: "Environment", kind: .string, defaultValue: ""),

            .init(key: "Sockets", title: "Sockets", category: "Networking", kind: .dictionary, defaultValue: [String: String]()),
            .init(key: "inetdCompatibility", title: "inetdCompatibility", category: "Networking", kind: .dictionary, defaultValue: ["Wait": "false"]),
            .init(key: "MachServices", title: "MachServices", category: "Networking", kind: .dictionary, defaultValue: [String: String]()),

            .init(key: "AbandonProcessGroup", title: "AbandonProcessGroup", category: "Lifecycle", kind: .boolean, defaultValue: false),
            .init(key: "EnablePressuredExit", title: "EnablePressuredExit", category: "Lifecycle", kind: .boolean, defaultValue: false),
            .init(key: "EnableTransactions", title: "EnableTransactions", category: "Lifecycle", kind: .boolean, defaultValue: false),
            .init(key: "ExitTimeOut", title: "ExitTimeOut", category: "Lifecycle", kind: .integer, defaultValue: 30),
            .init(key: "ThrottleInterval", title: "ThrottleInterval", category: "Lifecycle", kind: .integer, defaultValue: 10),
            .init(key: "Timeout", title: "Timeout", category: "Lifecycle", kind: .integer, defaultValue: 30),

            .init(key: "LaunchEvents", title: "LaunchEvents", category: "System Integration", kind: .dictionary, defaultValue: [String: String]()),
            .init(key: "AssociatedBundleIdentifiers", title: "AssociatedBundleIdentifiers", category: "System Integration", kind: .array, defaultValue: [""]),
            .init(key: "LegacyTimers", title: "LegacyTimers", category: "System Integration", kind: .boolean, defaultValue: false)
        ]
    }

    private let intervalPresets: [(label: String, value: Int)] = [
        ("1m", 60),
        ("5m", 300),
        ("15m", 900),
        ("30m", 1800),
        ("1h", 3600),
        ("6h", 21600),
        ("12h", 43200),
        ("24h", 86400),
    ]

    private let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private let monthNames = [
        "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"
    ]
}

private enum LaunchdFieldKind {
    case string
    case boolean
    case integer
    case dictionary
    case array
    case schedule
}

private struct LaunchdFieldDefinition: Identifiable {
    let key: String
    let title: String
    let category: String
    let kind: LaunchdFieldKind
    let defaultValue: Any

    var id: String { key }
}

private struct KeyValueEntry: Identifiable, Hashable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

private struct StringArrayFieldEditor: View {
    @Binding var values: [String]
    @State private var editableItems: [EditableItem] = []
    @State private var isSyncing = false

    struct EditableItem: Identifiable {
        let id = UUID()
        var value: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($editableItems) { $item in
                HStack {
                    TextField("Value", text: $item.value)
                        .onChange(of: item.value) { _, _ in
                            isSyncing = true
                            syncBack()
                            isSyncing = false
                        }
                    Button(role: .destructive) {
                        withAnimation {
                            editableItems.removeAll { $0.id == item.id }
                            syncBack()
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                editableItems.append(EditableItem(value: ""))
                syncBack()
            } label: {
                Label("Add Item", systemImage: "plus")
            }
        }
        .onAppear {
            editableItems = values.map { EditableItem(value: $0) }
        }
        .onChange(of: values) { _, newValues in
            guard !isSyncing else { return }
            let currentValues = editableItems.map { $0.value }
            if currentValues != newValues {
                editableItems = newValues.map { EditableItem(value: $0) }
            }
        }
    }

    private func syncBack() {
        values = editableItems.map { $0.value }
    }
}

private struct DictionaryFieldEditor: View {
    @Binding var entries: [KeyValueEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, _ in
                HStack {
                    TextField("Key", text: keyBinding(for: index))
                    TextField("Value", text: valueBinding(for: index))
                    Button(role: .destructive) {
                        entries.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                entries.append(KeyValueEntry())
            } label: {
                Label("Add Pair", systemImage: "plus")
            }
        }
    }

    private func keyBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { entries[index].key },
            set: { entries[index].key = $0 }
        )
    }

    private func valueBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { entries[index].value },
            set: { entries[index].value = $0 }
        )
    }
}

private struct CalendarEntryEditor: View {
    @Binding var entry: LaunchPlistDraft.CalendarEntry
    let index: Int
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Calendar Entry \(index + 1)")
                    .font(.subheadline)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .help("Remove entry")
            }

            OptionalIntPicker(
                title: "Minute",
                range: Array(0...59),
                selection: $entry.minute,
                valueLabel: { "\($0)" }
            )

            OptionalIntPicker(
                title: "Hour",
                range: Array(0...23),
                selection: $entry.hour,
                valueLabel: { "\($0)" }
            )

            OptionalIntPicker(
                title: "Day",
                range: Array(1...31),
                selection: $entry.day,
                valueLabel: { "\($0)" }
            )

            OptionalIntPicker(
                title: "Weekday",
                range: Array(0...6),
                selection: $entry.weekday,
                valueLabel: {
                    ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][$0]
                }
            )

            OptionalIntPicker(
                title: "Month",
                range: Array(1...12),
                selection: $entry.month,
                valueLabel: {
                    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][$0 - 1]
                }
            )
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        }
    }
}

private struct OptionalIntPicker: View {
    let title: String
    let range: [Int]
    @Binding var selection: Int?
    let valueLabel: (Int) -> String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Picker(title, selection: $selection) {
                Text("Any").tag(nil as Int?)
                ForEach(range, id: \.self) { value in
                    Text(valueLabel(value)).tag(Optional(value))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
