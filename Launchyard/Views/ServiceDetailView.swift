import SwiftUI
import AppKit

struct ServiceDetailView: View {
    @ObservedObject var viewModel: LaunchyardViewModel
    @State private var selectedTab: DetailTab = .editor

    var body: some View {
        Group {
            if let service = viewModel.selectedService {
                VStack(alignment: .leading, spacing: 12) {
                    header(service)

                    FullWidthSegmentedControl(selection: $selectedTab)

                    switch selectedTab {
                    case .editor:
                        ServiceEditorView(service: service) { dict, rawXML, useRaw in
                            viewModel.saveEditedService(dictionary: dict, rawXML: rawXML, useRawXML: useRaw)
                        }
                        .id("\(service.plistURL)\(viewModel.editorVersion)")

                    case .logs:
                        LogViewerView(service: service, stdoutText: viewModel.stdoutText, stderrText: viewModel.stderrText, unifiedText: viewModel.unifiedLogText, isLoading: viewModel.logsLoading, isInitialLoad: viewModel.logsInitialLoad) {
                            viewModel.reloadLogs()
                        }
                    }
                }
                .padding()
                .onChange(of: viewModel.selectedService?.plistURL) { _, _ in
                    viewModel.stdoutText = ""
                    viewModel.stderrText = ""
                    viewModel.unifiedLogText = ""
                    selectedTab = .editor
                }
            } else {
                ContentUnavailableView("Select a Service", systemImage: "sidebar.left")
            }
        }
        .navigationTitle("Details")
    }

    @ViewBuilder
    private func header(_ service: LaunchService) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(service.label, forType: .string)
                    viewModel.actionStatus = .success("Copied \(service.label)")
                    Task { try? await Task.sleep(for: .seconds(2)); await MainActor.run { if case .success = viewModel.actionStatus { viewModel.actionStatus = nil } } }
                } label: {
                    Text(service.label)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .help("Click to copy service name")
            Text(service.plistURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Label(service.scope.rawValue, systemImage: "folder")
                if service.runtimeStatus == .loaded {
                    Label("Loaded", systemImage: "bolt")
                }
                Label(service.enabled ? "Enabled" : "Disabled", systemImage: service.enabled ? "checkmark.circle" : "xmark.circle")
                if service.runtimeStatus == .running, let pid = service.pid {
                    Label("Running · PID \(pid)", systemImage: "play.circle")
                        .foregroundStyle(.green)
                } else {
                    Label("Not Running", systemImage: "stop.circle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case editor = "Editor"
    case logs = "Logs"

    var id: String { rawValue }
}


private struct FullWidthSegmentedControl: NSViewRepresentable {
    @Binding var selection: DetailTab

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = DetailTab.allCases.count
        for (i, tab) in DetailTab.allCases.enumerated() {
            control.setLabel(tab.rawValue, forSegment: i)
        }
        control.segmentStyle = .automatic
        control.segmentDistribution = .fillEqually
        control.trackingMode = .selectOne
        control.selectedSegment = DetailTab.allCases.firstIndex(of: selection) ?? 0
        control.target = context.coordinator
        control.action = #selector(Coordinator.segmentChanged(_:))
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        control.selectedSegment = DetailTab.allCases.firstIndex(of: selection) ?? 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    class Coordinator: NSObject {
        var selection: Binding<DetailTab>
        init(selection: Binding<DetailTab>) { self.selection = selection }

        @objc func segmentChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            if index >= 0 && index < DetailTab.allCases.count {
                selection.wrappedValue = DetailTab.allCases[index]
            }
        }
    }
}
