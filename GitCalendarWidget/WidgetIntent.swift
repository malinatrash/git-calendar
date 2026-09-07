import AppIntents
import Foundation

struct CalendarEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Git-календарь")
    static var defaultQuery = CalendarEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CalendarEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CalendarEntity] {
        let requested = Set(identifiers)
        return SharedStore.loadConfigurations()
            .filter { requested.contains($0.id) }
            .map { CalendarEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [CalendarEntity] {
        SharedStore.loadConfigurations().map { CalendarEntity(id: $0.id, name: $0.name) }
    }

    func defaultResult() async -> CalendarEntity? {
        SharedStore.loadConfigurations().first.map { CalendarEntity(id: $0.id, name: $0.name) }
    }
}

struct CalendarWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Git-календарь"
    static var description = IntentDescription("Выберите папку-календарь, которую нужно показать.")

    @Parameter(title: "Календарь")
    var calendar: CalendarEntity?
}
