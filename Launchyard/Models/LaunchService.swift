import Foundation

enum LaunchServiceScope: String, CaseIterable, Identifiable {
    case userAgents = "User Agents"
    case globalAgents = "Global Agents"
    case globalDaemons = "Global Daemons"

    var id: String { rawValue }

    var directoryURL: URL {
        switch self {
        case .userAgents:
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library")
                .appendingPathComponent("LaunchAgents")
        case .globalAgents:
            return URL(fileURLWithPath: "/Library/LaunchAgents")
        case .globalDaemons:
            return URL(fileURLWithPath: "/Library/LaunchDaemons")
        }
    }

    var launchDomain: String {
        switch self {
        case .userAgents, .globalAgents:
            // Both user and global agents run in the user's GUI domain
            return "gui/\(getuid())"
        case .globalDaemons:
            // Only daemons use the system domain
            return "system"
        }
    }

    var kind: LaunchServiceKind {
        switch self {
        case .globalDaemons:
            return .daemon
        case .userAgents, .globalAgents:
            return .agent
        }
    }
}

enum LaunchServiceKind: String, CaseIterable, Identifiable {
    case agent = "Agent"
    case daemon = "Daemon"

    var id: String { rawValue }
}

enum LaunchRuntimeStatus: String, CaseIterable, Identifiable {
    case running = "Running"
    case loaded = "Loaded"
    case stopped = "Not Running"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .running: return "Running"
        case .loaded, .stopped: return "Not Running"
        }
    }
}

struct LaunchService: Identifiable, Hashable {
    var id: String { plistURL.path }
    let plistURL: URL
    let scope: LaunchServiceScope
    var label: String
    var kind: LaunchServiceKind
    var enabled: Bool
    var runtimeStatus: LaunchRuntimeStatus
    var pid: Int?
    var plistDictionary: [String: Any]

    init(
        plistURL: URL,
        scope: LaunchServiceScope,
        label: String,
        kind: LaunchServiceKind,
        enabled: Bool,
        runtimeStatus: LaunchRuntimeStatus,
        pid: Int?,
        plistDictionary: [String: Any]
    ) {
        self.plistURL = plistURL
        self.scope = scope
        self.label = label
        self.kind = kind
        self.enabled = enabled
        self.runtimeStatus = runtimeStatus
        self.pid = pid
        self.plistDictionary = plistDictionary
    }

    static func == (lhs: LaunchService, rhs: LaunchService) -> Bool {
        lhs.plistURL == rhs.plistURL
        && lhs.runtimeStatus == rhs.runtimeStatus
        && lhs.pid == rhs.pid
        && lhs.enabled == rhs.enabled
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(plistURL)
        hasher.combine(runtimeStatus)
        hasher.combine(pid)
        hasher.combine(enabled)
    }
}

extension Dictionary where Key == String, Value == Any {
    var launchLabel: String? { self["Label"] as? String }
    var standardOutPath: String? { self["StandardOutPath"] as? String }
    var standardErrorPath: String? { self["StandardErrorPath"] as? String }
}
