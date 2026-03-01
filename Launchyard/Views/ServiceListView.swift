import SwiftUI

struct ServiceListView: View {
    @ObservedObject var viewModel: LaunchyardViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    StatusChiclet(label: "All", isSelected: viewModel.statusFilter == nil && viewModel.enabledFilter == nil && viewModel.loadedFilter == nil) {
                        viewModel.statusFilter = nil
                        viewModel.enabledFilter = nil
                        viewModel.loadedFilter = nil
                    }

                    Divider().frame(height: 16)

                    StatusChiclet(label: "Running", color: .green, isSelected: viewModel.statusFilter == .running) {
                        viewModel.statusFilter = viewModel.statusFilter == .running ? nil : .running
                    }
                    StatusChiclet(label: "Not Running", color: .orange, isSelected: viewModel.statusFilter == .stopped) {
                        viewModel.statusFilter = viewModel.statusFilter == .stopped ? nil : .stopped
                    }

                    Divider().frame(height: 16)

                    StatusChiclet(label: "Loaded", color: .blue, isSelected: viewModel.loadedFilter == true) {
                        viewModel.loadedFilter = viewModel.loadedFilter == true ? nil : true
                    }
                    StatusChiclet(label: "Not Loaded", color: .gray, isSelected: viewModel.loadedFilter == false) {
                        viewModel.loadedFilter = viewModel.loadedFilter == false ? nil : false
                    }

                    Divider().frame(height: 16)

                    StatusChiclet(label: "Enabled", color: .green, isSelected: viewModel.enabledFilter == true) {
                        viewModel.enabledFilter = viewModel.enabledFilter == true ? nil : true
                    }
                    StatusChiclet(label: "Disabled", color: .red, isSelected: viewModel.enabledFilter == false) {
                        viewModel.enabledFilter = viewModel.enabledFilter == false ? nil : false
                    }
                }
                .padding(.horizontal, 8)
                
            }
            .frame(maxWidth: .infinity)

            List(selection: $viewModel.selectedService) {
                ForEach(viewModel.filteredServices) { service in
                    ServiceRow(service: service)
                        .tag(service)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.visible)
            
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Loading launchd services...")
                } else if viewModel.filteredServices.isEmpty {
                    ContentUnavailableView("No services", systemImage: "tray")
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search")
        .navigationTitle(viewModel.selectedScope?.rawValue ?? "Services")
    }
}

private struct ServiceRow: View {
    let service: LaunchService

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.label)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(service.runtimeStatus.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let pid = service.pid {
                        Text("· PID \(pid)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.quaternary)

                    Text(service.runtimeStatus == .stopped ? "Not Loaded" : "Loaded")
                        .font(.caption)
                        .foregroundStyle(service.runtimeStatus == .stopped ? Color.secondary : Color.blue)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.quaternary)

                    Text(service.enabled ? "Enabled" : "Disabled")
                        .font(.caption)
                        .foregroundStyle(service.enabled ? .green : .orange)
                }
                .lineLimit(1)
            }
            .layoutPriority(1)

        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch service.runtimeStatus {
        case .running:
            return .green
        case .loaded, .stopped:
            return .yellow
        }
    }
}

private struct StatusChiclet: View {
    let label: String
    var color: Color? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let color {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
