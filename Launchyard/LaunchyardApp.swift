import SwiftUI

@main
struct LaunchyardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1100, minHeight: 700)
        }
        .windowStyle(.automatic)
    }
}
