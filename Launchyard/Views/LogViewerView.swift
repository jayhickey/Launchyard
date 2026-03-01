import SwiftUI

struct LogViewerView: View {
    let text: String
    let onRefresh: () -> Void

    @Namespace private var bottomAnchor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Service Logs")
                    .font(.headline)
                Spacer()
                Button {
                    onRefresh()
                } label: {
                    Label("Refresh Logs", systemImage: "arrow.clockwise")
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(text.isEmpty ? "No logs available." : text)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .onChange(of: text) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onAppear {
            onRefresh()
        }
    }
}
