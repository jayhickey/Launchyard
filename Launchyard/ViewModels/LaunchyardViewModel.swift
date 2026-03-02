import Foundation
import SwiftUI


enum ActionStatus: Equatable {
    case inProgress(String)
    case success(String)
    case failure(String)
}

@MainActor
class LaunchyardViewModel: ObservableObject {
    @Published var services: [LaunchService] = []
    @Published var selectedScope: LaunchServiceScope? = .userAgents
    @Published var selectedService: LaunchService?
    @Published var searchText: String = ""
    @Published var statusFilter: LaunchRuntimeStatus?
    @Published var enabledFilter: Bool?
    @Published var loadedFilter: Bool?
    @Published var kindFilter: LaunchServiceKind?

    @Published var isLoading = false
    @Published var isWorking = false
    @Published var actionStatus: ActionStatus?
    @Published var stdoutText: String = ""
    @Published var stderrText: String = ""
    @Published var unifiedLogText: String = ""
    @Published var logsLoading: Bool = false
    @Published var editorVersion: Int = 0
    @Published var logsInitialLoad: Bool = true
    @Published var infoMessage: String?
    @Published var errorMessage: String?

    private var heartbeatTask: Task<Void, Never>?

    func startHeartbeat() {
        stopHeartbeat()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                await self?.refreshRuntimeStatus()
            }
        }
    }

    func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// Lightweight refresh: only updates runtime status, PID, and enabled state without re-reading plists
    private func refreshRuntimeStatus() {
        guard !isWorking else { return }
        #if DEBUG
        if LaunchyardViewModel.isScreenshotMode { return }
        #endif

        Task.detached { [weak self] in
            guard let self else { return }
            let currentServices = await self.services
            var updated: [LaunchService] = []
            for service in currentServices {
                let (status, pid) = LaunchctlService.runtimeStatus(label: service.label, scope: service.scope)
                let enabled = LaunchctlService.isEnabled(label: service.label, scope: service.scope)
                updated.append(LaunchService(
                    plistURL: service.plistURL,
                    scope: service.scope,
                    label: service.label,
                    kind: service.kind,
                    enabled: enabled,
                    runtimeStatus: status,
                    pid: pid,
                    plistDictionary: service.plistDictionary
                ))
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.services = updated
                if let selected = self.selectedService,
                   let refreshed = updated.first(where: { $0.plistURL == selected.plistURL }) {
                    self.selectedService = refreshed
                }
            }
        }
    }

    var filteredServices: [LaunchService] {
        services.filter { service in
            if let selectedScope, service.scope != selectedScope {
                return false
            }

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !service.label.localizedCaseInsensitiveContains(searchText) {
                return false
            }

            if let statusFilter {
                if statusFilter == .stopped {
                    // "Not Running" = loaded or stopped (not running)
                    if service.runtimeStatus == .running { return false }
                } else if service.runtimeStatus != statusFilter {
                    return false
                }
            }
            if let enabledFilter, service.enabled != enabledFilter {
                return false
            }
            if let loadedFilter {
                let isLoaded = service.runtimeStatus != .stopped
                if isLoaded != loadedFilter { return false }
            }

            if let kindFilter, service.kind != kindFilter {
                return false
            }

            return true
        }
    }

    func refresh() {
        #if DEBUG
        if LaunchyardViewModel.isScreenshotMode {
            loadMockData()
            return
        }
        #endif
        isLoading = true
        Task.detached { [weak self] in
            let result: Result<[LaunchService], Error>
            do {
                let discovered = try LaunchctlService.discoverServices()
                result = .success(discovered)
            } catch {
                result = .failure(error)
            }
            await self?.applyRefresh(result)
        }
    }

    private func applyRefresh(_ result: Result<[LaunchService], Error>) {
        isLoading = false
        switch result {
        case .success(let discovered):
            let services = discovered
            self.services = services
            if let selectedService,
               let updated = services.first(where: { $0.plistURL == selectedService.plistURL }) {
                self.selectedService = updated
            }
            if selectedService == nil {
                selectedService = filteredServices.first
            }
            infoMessage = "Loaded \(services.count) services."
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func runAction(_ action: @escaping (LaunchService) throws -> Void, label: String = "Processing") {
        guard let service = selectedService else { return }
        isWorking = true
        actionStatus = .inProgress("\(label) \(service.label)...")

        Task.detached {
            let result: Result<Void, Error>
            do {
                try action(service)
                result = .success(())
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                self?.isWorking = false
                switch result {
                case .success:
                    self?.actionStatus = .success("\(label) completed")
                    self?.errorMessage = nil
                    self?.refresh()
                case .failure(let error):
                    self?.actionStatus = .failure(error.localizedDescription)
                    self?.errorMessage = error.localizedDescription
                }
                // Auto-dismiss success after 2 seconds
                let currentStatus = self?.actionStatus
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if self?.actionStatus == currentStatus {
                        self?.actionStatus = nil
                    }
                }
            }
        }
    }

    func reloadLogs() {
        guard let service = selectedService else {
            stdoutText = ""
            stderrText = ""
            unifiedLogText = ""
            logsInitialLoad = true
            return
        }
        logsInitialLoad = stdoutText.isEmpty && stderrText.isEmpty && unifiedLogText.isEmpty
        logsLoading = true
        Task.detached {
            let result = LaunchctlService.loadLogsSplit(service: service)
            await MainActor.run { [weak self] in
                self?.stdoutText = result.stdout
                self?.stderrText = result.stderr
                self?.unifiedLogText = result.unified
                self?.logsLoading = false
                self?.logsInitialLoad = false
            }
        }
    }

    func saveEditedService(dictionary: [String: Any], rawXML: String?, useRawXML: Bool) {
        guard let service = selectedService else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let finalDict: [String: Any]
            if useRawXML {
                guard let rawXML else {
                    throw CommandError.executionFailed("Raw XML content is missing.")
                }
                finalDict = try PlistEditorService.dictionary(fromRawXML: rawXML)
            } else {
                finalDict = dictionary
            }

            try PlistEditorService.validate(dictionary: finalDict)
            try PlistEditorService.writePlist(dictionary: finalDict, to: service.plistURL)
            
            // Re-read from disk (file is source of truth)
            let freshDict = try PlistEditorService.readPlist(at: service.plistURL)
            var updatedService = service
            updatedService.plistDictionary = freshDict
            
            // Update in services array
            if let idx = services.firstIndex(where: { $0.plistURL == service.plistURL }) {
                services[idx] = updatedService
            }
            selectedService = updatedService
            editorVersion += 1
            
            infoMessage = "Saved \(service.plistURL.lastPathComponent)."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createUserAgent(filename: String, dictionary: [String: Any]) {
        isWorking = true
        defer { isWorking = false }

        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Filename is required."
            return
        }

        let finalName = trimmed.hasSuffix(".plist") ? trimmed : "\(trimmed).plist"
        let url = LaunchServiceScope.userAgents.directoryURL.appendingPathComponent(finalName)

        do {
            try PlistEditorService.validate(dictionary: dictionary)
            try FileManager.default.createDirectory(at: LaunchServiceScope.userAgents.directoryURL, withIntermediateDirectories: true)
            try PlistEditorService.writePlist(dictionary: dictionary, to: url)
            infoMessage = "Created \(finalName)."
            errorMessage = nil
            selectedScope = .userAgents
            refresh()
            selectedService = services.count > 1 ? services[1] : services.first(where: { $0.plistURL == url })
        } catch {
            errorMessage = error.localizedDescription
        }
    }


    #if DEBUG
    static let isScreenshotMode = ProcessInfo.processInfo.arguments.contains("--screenshot")
    
    func loadMockData() {
        services = [
            LaunchService(plistURL: URL(fileURLWithPath: "~/Library/LaunchAgents/com.apple.bird.plist"), scope: .userAgents, label: "com.apple.bird", kind: .agent, enabled: true, runtimeStatus: .running, pid: 482, plistDictionary: ["Label": "com.apple.bird", "RunAtLoad": true, "KeepAlive": true]),
            LaunchService(plistURL: URL(fileURLWithPath: "~/Library/LaunchAgents/com.spotify.webhelper.plist"), scope: .userAgents, label: "com.spotify.webhelper", kind: .agent, enabled: true, runtimeStatus: .running, pid: 1205, plistDictionary: ["Label": "com.spotify.webhelper", "Program": "/Applications/Spotify.app/Contents/Frameworks/SpotifyWebHelper", "ProgramArguments": ["/Applications/Spotify.app/Contents/Frameworks/SpotifyWebHelper", "--port=4381"], "RunAtLoad": true, "KeepAlive": false, "StandardOutPath": "/tmp/spotify-webhelper.log", "StandardErrorPath": "/tmp/spotify-webhelper-err.log", "ThrottleInterval": 30]),
            LaunchService(plistURL: URL(fileURLWithPath: "~/Library/LaunchAgents/com.docker.helper.plist"), scope: .userAgents, label: "com.docker.helper", kind: .agent, enabled: true, runtimeStatus: .running, pid: 893, plistDictionary: ["Label": "com.docker.helper", "RunAtLoad": true, "KeepAlive": true]),
            LaunchService(plistURL: URL(fileURLWithPath: "~/Library/LaunchAgents/com.raycast.macos.plist"), scope: .userAgents, label: "com.raycast.macos", kind: .agent, enabled: true, runtimeStatus: .running, pid: 611, plistDictionary: ["Label": "com.raycast.macos", "RunAtLoad": true]),
            LaunchService(plistURL: URL(fileURLWithPath: "~/Library/LaunchAgents/com.1password.agent.plist"), scope: .userAgents, label: "com.1password.agent", kind: .agent, enabled: true, runtimeStatus: .running, pid: 744, plistDictionary: ["Label": "com.1password.agent", "RunAtLoad": true, "KeepAlive": true]),
            LaunchService(plistURL: URL(fileURLWithPath: "~/Library/LaunchAgents/com.apple.notificationcenterui.agent.plist"), scope: .userAgents, label: "com.apple.notificationcenterui.agent", kind: .agent, enabled: true, runtimeStatus: .running, pid: 301, plistDictionary: ["Label": "com.apple.notificationcenterui.agent", "RunAtLoad": true]),
            LaunchService(plistURL: URL(fileURLWithPath: "~/Library/LaunchAgents/homebrew.mxcl.postgresql@14.plist"), scope: .userAgents, label: "homebrew.mxcl.postgresql@14", kind: .agent, enabled: true, runtimeStatus: .running, pid: 1547, plistDictionary: ["Label": "homebrew.mxcl.postgresql@14", "RunAtLoad": true, "KeepAlive": true, "StandardOutPath": "/usr/local/var/log/postgresql@14.log", "StandardErrorPath": "/usr/local/var/log/postgresql@14.log"]),
            LaunchService(plistURL: URL(fileURLWithPath: "~/Library/LaunchAgents/com.github.desktop.helper.plist"), scope: .userAgents, label: "com.github.desktop.helper", kind: .agent, enabled: false, runtimeStatus: .stopped, pid: nil, plistDictionary: ["Label": "com.github.desktop.helper"]),
            LaunchService(plistURL: URL(fileURLWithPath: "~/Library/LaunchAgents/com.apple.SafariBookmarksSyncAgent.plist"), scope: .userAgents, label: "com.apple.SafariBookmarksSyncAgent", kind: .agent, enabled: true, runtimeStatus: .loaded, pid: nil, plistDictionary: ["Label": "com.apple.SafariBookmarksSyncAgent", "RunAtLoad": false]),
            LaunchService(plistURL: URL(fileURLWithPath: "~/Library/LaunchAgents/homebrew.mxcl.redis.plist"), scope: .userAgents, label: "homebrew.mxcl.redis", kind: .agent, enabled: true, runtimeStatus: .running, pid: 1548, plistDictionary: ["Label": "homebrew.mxcl.redis", "RunAtLoad": true, "KeepAlive": true]),
            LaunchService(plistURL: URL(fileURLWithPath: "/Library/LaunchAgents/com.adobe.AdobeCreativeCloud.plist"), scope: .globalAgents, label: "com.adobe.AdobeCreativeCloud", kind: .agent, enabled: true, runtimeStatus: .running, pid: 2103, plistDictionary: ["Label": "com.adobe.AdobeCreativeCloud", "RunAtLoad": true]),
            LaunchService(plistURL: URL(fileURLWithPath: "/Library/LaunchAgents/com.google.keystone.agent.plist"), scope: .globalAgents, label: "com.google.keystone.agent", kind: .agent, enabled: true, runtimeStatus: .running, pid: 1882, plistDictionary: ["Label": "com.google.keystone.agent", "RunAtLoad": true, "StartInterval": 3600]),
            LaunchService(plistURL: URL(fileURLWithPath: "/Library/LaunchDaemons/com.docker.vmnetd.plist"), scope: .globalDaemons, label: "com.docker.vmnetd", kind: .daemon, enabled: true, runtimeStatus: .running, pid: 205, plistDictionary: ["Label": "com.docker.vmnetd", "RunAtLoad": true, "KeepAlive": true]),
            LaunchService(plistURL: URL(fileURLWithPath: "/Library/LaunchDaemons/com.apple.installer.osmessagetracing.plist"), scope: .globalDaemons, label: "com.apple.installer.osmessagetracing", kind: .daemon, enabled: true, runtimeStatus: .loaded, pid: nil, plistDictionary: ["Label": "com.apple.installer.osmessagetracing"]),
        ]
        selectedService = services.count > 1 ? services[1] : services.first
        infoMessage = "Loaded \(services.count) services."
    }
    #endif

    func deleteSelectedUserAgent() {
        guard let service = selectedService else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try LaunchctlService.deleteUserAgent(service)
            infoMessage = "Deleted \(service.label)."
            errorMessage = nil
            selectedService = nil
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
