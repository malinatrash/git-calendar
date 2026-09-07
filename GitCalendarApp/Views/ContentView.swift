import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedCalendarID) {
                Section("Календари") {
                    ForEach(appState.configurations) { configuration in
                        Label(configuration.name, systemImage: "calendar")
                            .tag(configuration.id)
                            .contextMenu {
                                Button("Настроить") { appState.editingConfiguration = configuration }
                                Button("Удалить", role: .destructive) { appState.deleteConfiguration(configuration.id) }
                            }
                    }
                }
            }
            .navigationTitle("Git Calendar")
            .toolbar {
                Button(action: chooseFolder) {
                    Label("Добавить календарь", systemImage: "plus")
                }
            }
        } detail: {
            if let configuration = appState.selectedConfiguration {
                DashboardView(
                    configuration: configuration,
                    snapshot: appState.selectedSnapshot,
                    isRefreshing: appState.refreshingIDs.contains(configuration.id),
                    onRefresh: { appState.refresh(configuration.id) },
                    onEdit: { appState.editingConfiguration = configuration },
                    onSelectDay: { appState.selectedDay = SelectedDay(calendarID: configuration.id, dayKey: $0) }
                )
            } else {
                ContentUnavailableView(
                    "Добавьте календарь",
                    systemImage: "calendar.badge.plus",
                    description: Text("Выберите папку, содержащую один или несколько Git-репозиториев.")
                )
            }
        }
        .sheet(item: $appState.editingConfiguration) { configuration in
            CalendarEditorView(configuration: configuration) { appState.saveConfiguration($0) }
        }
        .sheet(item: $appState.selectedDay) { selection in
            DayDetailView(
                selection: selection,
                commits: appState.commits(for: selection)
            )
        }
        .alert("Ошибка", isPresented: Binding(
            get: { appState.lastError != nil },
            set: { if !$0 { appState.lastError = nil } }
        )) {
            Button("Закрыть", role: .cancel) { appState.lastError = nil }
        } message: {
            Text(appState.lastError ?? "Неизвестная ошибка")
        }
        .alert(item: $appState.availableUpdate) { release in
            Alert(
                title: Text("Доступен Git Calendar \(release.version)"),
                message: Text(release.notes.isEmpty ? "На GitHub опубликована новая версия." : release.notes),
                primaryButton: .default(Text("Скачать DMG")) {
                    NSWorkspace.shared.open(release.downloadURL)
                },
                secondaryButton: .cancel(Text("Позже"))
            )
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Выберите папку с Git-репозиториями"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            appState.addCalendar(folderURL: url)
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(appState.configurations) { configuration in
            let summary = appState.snapshots[configuration.id]?.summary
            Button {
                appState.selectedCalendarID = configuration.id
                openWindow(id: "main")
            } label: {
                Text("\(configuration.name): \(summary?.totalCommits ?? 0) коммитов")
            }
        }
        Divider()
        Button("Обновить всё") { appState.refreshAllIfNeeded(force: true) }
        Button("Проверить обновления") { Task { await appState.checkForUpdates(showErrors: true) } }
        Button("Завершить Git Calendar") { NSApplication.shared.terminate(nil) }
    }
}
