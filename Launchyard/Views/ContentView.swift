import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = LaunchyardViewModel()
    @State private var showCreateSheet = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.selectedScope) {
                ForEach(LaunchServiceScope.allCases) { scope in
                Label(scope.rawValue, systemImage: icon(for: scope))
                        .tag(scope)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
            .navigationTitle("Launchyard")
        } content: {
            ServiceListView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 500)
        } detail: {
            ServiceDetailView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 400, ideal: 600, max: 900)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                ToolbarButton(title: "Create User Agent", icon: "plus") {
                    showCreateSheet = true
                }
                ToolbarButton(title: "Reload Services", icon: "arrow.clockwise") {
                    viewModel.refresh()
                }
            }

            ToolbarItemGroup(placement: .principal) {
                ToolbarButton(title: "Load Service", icon: "tray.and.arrow.down.fill") {
                    viewModel.runAction({ try LaunchctlService.load(service: $0) }, label: "Loading")
                }
                .disabled(viewModel.selectedService == nil || viewModel.isWorking || viewModel.selectedService?.runtimeStatus != .stopped)

                ToolbarButton(title: "Unload Service", icon: "tray.and.arrow.up.fill") {
                    viewModel.runAction({ try LaunchctlService.unload(service: $0) }, label: "Unloading")
                }
                .disabled(viewModel.selectedService == nil || viewModel.isWorking || viewModel.selectedService?.runtimeStatus == .stopped)

                ToolbarButton(title: "Start Service", icon: "play.fill") {
                    viewModel.runAction({ try LaunchctlService.start(service: $0) }, label: "Starting")
                }
                .disabled(viewModel.selectedService == nil || viewModel.isWorking || viewModel.selectedService?.runtimeStatus == .running)

                ToolbarButton(title: "Stop Service", icon: "stop.fill") {
                    viewModel.runAction({ try LaunchctlService.stop(service: $0) }, label: "Stopping")
                }
                .disabled(viewModel.selectedService == nil || viewModel.isWorking || viewModel.selectedService?.runtimeStatus != .running)

                ToolbarButton(title: "Enable Service", icon: "checkmark.circle") {
                    viewModel.runAction({ try LaunchctlService.enable(service: $0) }, label: "Enabling")
                }
                .disabled(viewModel.selectedService == nil || viewModel.isWorking || viewModel.selectedService?.enabled == true)

                ToolbarButton(title: "Disable Service", icon: "xmark.circle") {
                    viewModel.runAction({ try LaunchctlService.disable(service: $0) }, label: "Disabling")
                }
                .disabled(viewModel.selectedService == nil || viewModel.isWorking || viewModel.selectedService?.enabled == false)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                ToolbarButton(title: "Reveal in Finder", icon: "folder") {
                    if let url = viewModel.selectedService?.plistURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .disabled(viewModel.selectedService == nil)

                ToolbarButton(title: "Delete Selected User Agent", icon: "trash") {
                    showDeleteConfirmation = true
                }
                .disabled(viewModel.selectedService?.scope != .userAgents)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateServiceSheet(viewModel: viewModel)
        }
        .confirmationDialog(
            "Delete this user agent plist?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.deleteSelectedUserAgent()
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: Binding(get: {
            viewModel.errorMessage != nil
        }, set: { _ in
            viewModel.errorMessage = nil
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .overlay {
            if let status = viewModel.actionStatus {
                switch status {
                case .inProgress(let msg):
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .transition(.opacity)
                default:
                    EmptyView()
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let status = viewModel.actionStatus {
                switch status {
                case .success(let msg):
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                case .failure(let msg):
                    Label(msg, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                default:
                    EmptyView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.actionStatus)
        .onAppear {
            viewModel.refresh()
            viewModel.startHeartbeat()
        }
        .onDisappear {
            viewModel.stopHeartbeat()
        }
    }

    private func icon(for scope: LaunchServiceScope) -> String {
        switch scope {
        case .userAgents:
            return "person"
        case .globalAgents:
            return "person.2"
        case .globalDaemons:
            return "gearshape.2"
        }
    }
}

private struct CreateServiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: LaunchyardViewModel

    @State private var filename: String = ""
    @State private var draft: LaunchPlistDraft = LaunchPlistDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create User Agent")
                .font(.headline)

            TextField("Filename (e.g. com.example.task)", text: $filename)

            ScrollView {
                ServiceEditorView(
                    service: LaunchService(
                        plistURL: URL(fileURLWithPath: "/tmp/new.plist"),
                        scope: .userAgents,
                        label: "",
                        kind: .agent,
                        enabled: true,
                        runtimeStatus: .stopped,
                        pid: nil,
                        plistDictionary: [:]
                    ),
                    onSave: { _, _, _ in }
                )
                .disabled(false)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalName = trimmed.hasSuffix(".plist") ? trimmed : "\(trimmed).plist"
                    do {
                        let dict = try draft.toDictionary()
                        viewModel.createUserAgent(filename: finalName, dictionary: dict)
                        dismiss()
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 640, height: 600)
    }
}


private struct ToolbarButton: NSViewRepresentable {
    let title: String
    let icon: String
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .toolbar
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        button.toolTip = title
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.isBordered = true
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.toolTip = title
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: title)
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func performAction() { action() }
    }
}
