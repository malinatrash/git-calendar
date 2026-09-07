import AppKit
import Foundation
import WidgetKit

struct SelectedDay: Identifiable, Equatable {
    var id: String { "\(calendarID.uuidString)-\(dayKey)" }
    var calendarID: UUID
    var dayKey: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var configurations: [CalendarConfiguration]
    @Published var snapshots: [UUID: CalendarSnapshot]
    @Published var selectedCalendarID: UUID?
    @Published var selectedDay: SelectedDay?
    @Published var editingConfiguration: CalendarConfiguration?
    @Published var refreshingIDs: Set<UUID> = []
    @Published var lastError: String?
    @Published var availableUpdate: AppRelease?
    @Published private(set) var isWidgetSharingAvailable: Bool

    private var refreshTimer: Timer?

    init() {
        let storedConfigurations = SharedStore.loadConfigurations()
        configurations = storedConfigurations
        snapshots = Dictionary(uniqueKeysWithValues: SharedStore.loadSnapshots().map { ($0.id, $0) })
        selectedCalendarID = storedConfigurations.first?.id
        isWidgetSharingAvailable = SharedStore.isAppGroupAvailable
        scheduleRefreshTimer()

        Task { [weak self] in
            self?.refreshAllIfNeeded(force: self?.snapshots.isEmpty == true)
            await self?.checkForUpdates()
        }
    }

    var selectedConfiguration: CalendarConfiguration? {
        guard let selectedCalendarID else { return nil }
        return configurations.first { $0.id == selectedCalendarID }
    }

    var selectedSnapshot: CalendarSnapshot? {
        guard let selectedCalendarID else { return nil }
        return snapshots[selectedCalendarID]
    }

    func addCalendar(folderURL: URL) {
        var configuration = CalendarConfiguration(
            name: folderURL.lastPathComponent,
            folderPath: folderURL.path,
            authorPatterns: []
        )
        if configuration.name.isEmpty { configuration.name = "Новый календарь" }
        editingConfiguration = configuration
    }

    func saveConfiguration(_ configuration: CalendarConfiguration) {
        if let index = configurations.firstIndex(where: { $0.id == configuration.id }) {
            configurations[index] = configuration
        } else {
            configurations.append(configuration)
        }
        selectedCalendarID = configuration.id
        persist()
        refresh(configuration.id)
    }

    func deleteConfiguration(_ id: UUID) {
        configurations.removeAll { $0.id == id }
        snapshots[id] = nil
        if selectedCalendarID == id { selectedCalendarID = configurations.first?.id }
        persist()
    }

    func refresh(_ id: UUID) {
        guard let configuration = configurations.first(where: { $0.id == id }), !refreshingIDs.contains(id) else { return }
        refreshingIDs.insert(id)
        lastError = nil

        Task {
            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    try GitScanner().scan(configuration: configuration)
                }.value
                snapshots[id] = snapshot
                persist()
            } catch {
                lastError = error.localizedDescription
            }
            refreshingIDs.remove(id)
        }
    }

    func refreshAllIfNeeded(force: Bool = false) {
        let now = Date()
        for configuration in configurations {
            let interval = TimeInterval(configuration.refreshIntervalMinutes * 60)
            let isStale = snapshots[configuration.id].map { now.timeIntervalSince($0.generatedAt) >= interval } ?? true
            if force || isStale { refresh(configuration.id) }
        }
    }

    func handle(url: URL) {
        guard url.scheme == "gitcalendar", url.host == "day" else { return }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2, let id = UUID(uuidString: components[0]) else { return }
        selectedCalendarID = id
        selectedDay = SelectedDay(calendarID: id, dayKey: components[1])
    }

    func commits(for selection: SelectedDay) -> [CommitRecord] {
        guard let snapshot = snapshots[selection.calendarID],
              let configuration = configurations.first(where: { $0.id == selection.calendarID }) else { return [] }
        return snapshot.commits.filter {
            CalendarSupport.dayKey(for: $0.authorDate, timeZoneIdentifier: configuration.timeZoneIdentifier) == selection.dayKey
        }
    }

    func checkForUpdates(showErrors: Bool = false) async {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        do {
            availableUpdate = try await UpdateChecker().latestReleaseIfNewer(currentVersion: version)
        } catch {
            if showErrors { lastError = "Не удалось проверить обновления: \(error.localizedDescription)" }
        }
    }

    private func scheduleRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAllIfNeeded() }
        }
    }

    private func persist() {
        do {
            try SharedStore.saveConfigurations(configurations)
            let orderedSnapshots = configurations.compactMap { snapshots[$0.id] }
            try SharedStore.saveSnapshots(orderedSnapshots)
            try SharedStore.saveWidgetSnapshots(orderedSnapshots.compactMap { snapshot in
                configurations.first(where: { $0.id == snapshot.id }).map {
                    snapshot.widgetSnapshot(name: $0.name, timeZoneIdentifier: $0.timeZoneIdentifier)
                }
            })
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastError = "Не удалось сохранить данные: \(error.localizedDescription)"
        }
    }
}
