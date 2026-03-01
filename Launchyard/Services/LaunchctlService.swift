import Foundation

enum LaunchctlService {
    static func discoverServices() throws -> [LaunchService] {
        var services: [LaunchService] = []
        for scope in LaunchServiceScope.allCases {
            let url = scope.directoryURL
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "plist" else { continue }
                let plist: [String: Any]
                do {
                    plist = try PlistEditorService.readPlist(at: fileURL)
                } catch {
                    continue
                }

                let label = plist.launchLabel ?? fileURL.deletingPathExtension().lastPathComponent
                let kind = scope.kind
                let (status, pid) = runtimeStatus(label: label, scope: scope)
                let enabled = isEnabled(label: label, scope: scope)

                services.append(
                    LaunchService(
                        plistURL: fileURL,
                        scope: scope,
                        label: label,
                        kind: kind,
                        enabled: enabled,
                        runtimeStatus: status,
                        pid: pid,
                        plistDictionary: plist
                    )
                )
            }
        }

        return services.sorted { lhs, rhs in
            if lhs.scope != rhs.scope {
                return lhs.scope.rawValue < rhs.scope.rawValue
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    static func runtimeStatus(label: String, scope: LaunchServiceScope) -> (LaunchRuntimeStatus, Int?) {
        let target = "\(scope.launchDomain)/\(label)"
        guard let result = try? CommandRunner.run("/bin/launchctl", arguments: ["print", target]), result.isSuccess else {
            return (.stopped, nil)
        }

        let output = result.stdout + "\n" + result.stderr
        if let pid = parseFirstInt(in: output, after: "pid =") {
            return (.running, pid)
        }
        return (.loaded, nil)
    }

    static func isEnabled(label: String, scope: LaunchServiceScope) -> Bool {
        let domain = scope.launchDomain
        guard let result = try? CommandRunner.run("/bin/launchctl", arguments: ["print-disabled", domain]), result.isSuccess else {
            return true
        }

        let output = result.stdout
        // Check for both formats: '=> true' (older) and '=> disabled' (newer)
        if output.contains("\"\(label)\" => true") || output.contains("\(label) => true") {
            return false
        }
        if output.contains("\"\(label)\" => disabled") || output.contains("\(label) => disabled") {
            return false
        }
        return true
    }

    static func load(service: LaunchService) throws {
        let domain = service.scope.launchDomain
        let target = "\(domain)/\(service.label)"
        
        // Enable first if disabled, otherwise bootstrap will silently fail
        let _ = try? CommandRunner.run("/bin/launchctl", arguments: ["enable", target])
        
        // Try modern bootstrap
        let result = try CommandRunner.run("/bin/launchctl", arguments: ["bootstrap", domain, service.plistURL.path])
        if result.isSuccess { return }
        
        // Exit code 5 with "already loaded" is not an error
        let errText = result.stderr + result.stdout
        if errText.contains("already loaded") || errText.contains("service already loaded") { return }
        
        // Fallback to legacy load
        let legacy = try CommandRunner.run("/bin/launchctl", arguments: ["load", "-w", service.plistURL.path])
        if legacy.isSuccess { return }
        
        throw CommandError.executionFailed(nonEmptyError(from: result))
    }

    static func unload(service: LaunchService) throws {
        let domain = service.scope.launchDomain
        let target = "\(domain)/\(service.label)"
        
        // Check if actually loaded first
        if let printResult = try? CommandRunner.run("/bin/launchctl", arguments: ["print", target]),
           !printResult.isSuccess {
            return // Already not loaded
        }
        
        // Try modern bootout with target (more reliable)
        let result = try CommandRunner.run("/bin/launchctl", arguments: ["bootout", target])
        if result.isSuccess { return }
        
        // Try bootout with path
        let result2 = try CommandRunner.run("/bin/launchctl", arguments: ["bootout", domain, service.plistURL.path])
        if result2.isSuccess { return }
        
        // Fallback to legacy unload
        let legacy = try CommandRunner.run("/bin/launchctl", arguments: ["unload", service.plistURL.path])
        if legacy.isSuccess { return }
        
        // Exit code 5 often means already unloaded
        let errText = result.stderr + result.stdout
        if errText.contains("Input/output error") || result.exitCode == 5 {
            return
        }
        
        throw CommandError.executionFailed(nonEmptyError(from: result))
    }

    static func start(service: LaunchService) throws {
        let domain = service.scope.launchDomain
        let target = "\(domain)/\(service.label)"
        
        // Ensure enabled
        let _ = try? CommandRunner.run("/bin/launchctl", arguments: ["enable", target])
        
        // Ensure loaded (bootstrap, ignore "already loaded" errors)
        let _ = try? CommandRunner.run("/bin/launchctl", arguments: ["bootstrap", domain, service.plistURL.path])
        // Also try legacy load as backup
        let _ = try? CommandRunner.run("/bin/launchctl", arguments: ["load", "-w", service.plistURL.path])
        
        // Try kickstart (modern, forces immediate run)
        let result = try CommandRunner.run("/bin/launchctl", arguments: ["kickstart", "-kp", target])
        if result.isSuccess { return }
        
        // Fallback to legacy start
        let legacy = try CommandRunner.run("/bin/launchctl", arguments: ["start", service.label])
        if legacy.isSuccess { return }
        
        throw CommandError.executionFailed(nonEmptyError(from: result))
    }

    static func stop(service: LaunchService) throws {
        let domain = service.scope.launchDomain
        let keepAlive = service.plistDictionary["KeepAlive"]
        let isKeepAlive: Bool = {
            if let b = keepAlive as? Bool { return b }
            if keepAlive is [String: Any] { return true } // dictionary form = conditional keep alive
            return false
        }()
        
        if isKeepAlive {
            // For KeepAlive services, must unload to truly stop (kill just restarts)
            let result = try CommandRunner.run("/bin/launchctl", arguments: ["bootout", domain, service.plistURL.path])
            if result.isSuccess { return }
            let result2 = try CommandRunner.run("/bin/launchctl", arguments: ["bootout", "\(domain)/\(service.label)"])
            if result2.isSuccess { return }
            let legacy = try CommandRunner.run("/bin/launchctl", arguments: ["unload", service.plistURL.path])
            if legacy.isSuccess { return }
            throw CommandError.executionFailed(nonEmptyError(from: result))
        } else {
            // For non-KeepAlive, kill is sufficient
            let target = "\(domain)/\(service.label)"
            let result = try CommandRunner.run("/bin/launchctl", arguments: ["kill", "SIGTERM", target])
            if result.isSuccess { return }
            let legacy = try CommandRunner.run("/bin/launchctl", arguments: ["stop", service.label])
            if legacy.isSuccess { return }
            let errText = result.stderr + result.stdout
            if errText.contains("No such process") || errText.contains("Could not find service") {
                return
            }
            throw CommandError.executionFailed(nonEmptyError(from: result))
        }
    }

    static func enable(service: LaunchService) throws {
        let target = "\(service.scope.launchDomain)/\(service.label)"
        let result = try CommandRunner.run("/bin/launchctl", arguments: ["enable", target])
        guard result.isSuccess else {
            throw CommandError.executionFailed(nonEmptyError(from: result))
        }
    }

    static func disable(service: LaunchService) throws {
        let target = "\(service.scope.launchDomain)/\(service.label)"
        let result = try CommandRunner.run("/bin/launchctl", arguments: ["disable", target])
        guard result.isSuccess else {
            throw CommandError.executionFailed(nonEmptyError(from: result))
        }
    }

    static func deleteUserAgent(_ service: LaunchService) throws {
        guard service.scope == .userAgents else {
            throw CommandError.executionFailed("Only user agents can be deleted.")
        }

        if FileManager.default.fileExists(atPath: service.plistURL.path) {
            try FileManager.default.removeItem(at: service.plistURL)
        }
    }

    static func loadLogs(service: LaunchService) -> String {
        var sections: [String] = []

        if let outPath = service.plistDictionary.standardOutPath {
            sections.append(contentsOf: readLogFileSection(path: outPath, title: "StandardOutPath"))
        }

        if let errPath = service.plistDictionary.standardErrorPath {
            sections.append(contentsOf: readLogFileSection(path: errPath, title: "StandardErrorPath"))
        }

        if sections.isEmpty {
            let predicate = "eventMessage CONTAINS \"\(service.label.replacingOccurrences(of: "\"", with: "\\\""))\""
            let args = ["show", "--last", "1h", "--style", "compact", "--predicate", predicate]
            if let result = try? CommandRunner.run("/usr/bin/log", arguments: args), result.isSuccess {
                let lines = result.stdout.split(separator: "\n").suffix(200)
                let snippet = lines.joined(separator: "\n")
                sections.append("=== Unified Log (last 1h, filtered) ===\n\(snippet)")
            } else {
                sections.append("No log file paths found and unified log query returned no results.")
            }
        }

        return sections.joined(separator: "\n\n")
    }

    private static func readLogFileSection(path: String, title: String) -> [String] {
        let expanded = NSString(string: path).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            return ["=== \(title): \(expanded) ===\nFile does not exist."]
        }

        guard let data = FileManager.default.contents(atPath: expanded),
              let text = String(data: data, encoding: .utf8) else {
            return ["=== \(title): \(expanded) ===\nUnable to read file."]
        }

        let lines = text.split(separator: "\n").suffix(250)
        return ["=== \(title): \(expanded) ===\n\(lines.joined(separator: "\n"))"]
    }

    private static func parseFirstInt(in text: String, after token: String) -> Int? {
        guard let range = text.range(of: token) else { return nil }
        let suffix = text[range.upperBound...]
        let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.prefix { $0.isNumber }
        return Int(digits)
    }

    private static func nonEmptyError(from result: CommandResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty { return stderr }
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty { return stdout }
        return "launchctl command failed with code \(result.exitCode)."
    }
}
