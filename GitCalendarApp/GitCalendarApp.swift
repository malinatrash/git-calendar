import SwiftUI

@main
struct GitCalendarApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Git Calendar", id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 680)
                .onOpenURL { appState.handle(url: $0) }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Обновить выбранный календарь") {
                    if let id = appState.selectedCalendarID { appState.refresh(id) }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Проверить обновления…") {
                    Task { await appState.checkForUpdates(showErrors: true) }
                }
            }
        }

        MenuBarExtra("Git Calendar", systemImage: "square.grid.3x3.fill") {
            MenuBarView()
                .environmentObject(appState)
        }
    }
}
