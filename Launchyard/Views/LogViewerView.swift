import SwiftUI

struct LogViewerView: View {
    let service: LaunchService
    let stdoutText: String
    let stderrText: String
    let unifiedText: String
    let isLoading: Bool
    let isInitialLoad: Bool
    let onRefresh: () -> Void

    @State private var showStderr = false

    private var hasStdout: Bool {
        service.plistDictionary["StandardOutPath"] as? String != nil
    }
    private var hasStderr: Bool {
        service.plistDictionary["StandardErrorPath"] as? String != nil
    }
    private var hasBoth: Bool {
        guard let out = service.plistDictionary["StandardOutPath"] as? String,
              let err = service.plistDictionary["StandardErrorPath"] as? String else { return false }
        return out != err
    }

    private var displayText: String {
        if hasStdout || hasStderr {
            return showStderr ? stderrText : stdoutText
        }
        return unifiedText
    }

    private var currentLogPath: String? {
        if showStderr {
            return service.plistDictionary["StandardErrorPath"] as? String
        }
        return service.plistDictionary["StandardOutPath"] as? String ?? service.plistDictionary["StandardErrorPath"] as? String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Service Logs")
                    .font(.headline)
                Spacer()
                if hasBoth {
                    HStack(spacing: 8) {
                        Image(systemName: "text.page")
                            .foregroundStyle(!showStderr ? Color.accentColor : Color.secondary)
                            .font(.system(size: 12))
                        Toggle("", isOn: $showStderr.animation(.easeInOut(duration: 0.2)))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.mini)
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(showStderr ? Color.accentColor : Color.secondary)
                            .font(.system(size: 12))
                    }
                }
            }

            ZStack {
                if isLoading && isInitialLoad {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading logs…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                ScrollViewReader { proxy in
                ScrollView {
                    if showStderr {
                        Text(stderrText.isEmpty ? "No stderr logs available." : stderrText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    } else if hasStdout {
                        Text(stdoutText.isEmpty ? "No stdout logs available." : stdoutText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    } else {
                        Text(unifiedText.isEmpty ? "No logs available." : unifiedText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                }
                .onChange(of: displayText) { _, _ in
                    proxy.scrollTo("bottom")
                }
                .onAppear {
                    onRefresh()
                }
            }
                }
            }

            HStack {
                Spacer()
                if let logPath = currentLogPath {
                    Button {
                        NSWorkspace.shared.selectFile(logPath, inFileViewerRootedAtPath: "")
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                }
                if isLoading && !isInitialLoad {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
    }
}
