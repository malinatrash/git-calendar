import AppKit
import SwiftUI

struct CalendarEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: CalendarConfiguration
    @State private var authorText: String
    let onSave: (CalendarConfiguration) -> Void

    init(configuration: CalendarConfiguration, onSave: @escaping (CalendarConfiguration) -> Void) {
        _configuration = State(initialValue: configuration)
        _authorText = State(initialValue: configuration.authorPatterns.joined(separator: "\n"))
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Календарь") {
                    TextField("Название", text: $configuration.name)
                    LabeledContent("Папка") {
                        HStack {
                            Text(configuration.folderPath).lineLimit(1).truncationMode(.middle)
                            Button("Выбрать…", action: chooseFolder)
                        }
                    }
                    TextField("Часовой пояс", text: $configuration.timeZoneIdentifier)
                    LabeledContent("Начало статистики", value: "Первый коммит выбранного автора")
                    Stepper(
                        "Обновление: каждые \(configuration.refreshIntervalMinutes) мин",
                        value: $configuration.refreshIntervalMinutes,
                        in: 5...120,
                        step: 5
                    )
                }

                Section("Авторство") {
                    TextEditor(text: $authorText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 70)
                    Text("Имя или email — по одному на строке. Пустое поле учитывает всех авторов.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Git") {
                    Toggle("Учитывать все локальные ветки и refs", isOn: $configuration.includeAllRefs)
                    Toggle("Учитывать merge-коммиты", isOn: $configuration.includeMerges)
                }

                Section("Пороговые значения риска") {
                    Stepper(
                        "Крупное изменение: \(configuration.largeChangeThreshold) строк",
                        value: $configuration.largeChangeThreshold,
                        in: 100...5_000,
                        step: 50
                    )
                    Stepper(
                        "Ожидать тесты после: \(configuration.testsExpectedAfterLines) строк",
                        value: $configuration.testsExpectedAfterLines,
                        in: 20...1_000,
                        step: 20
                    )
                    Stepper(
                        "Широкое изменение: \(configuration.wideChangeFileThreshold) файлов",
                        value: $configuration.wideChangeFileThreshold,
                        in: 5...100,
                        step: 5
                    )
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        configuration.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || configuration.folderPath.isEmpty
                    )
            }
            .padding()
            .background(.regularMaterial)
        }
        .frame(width: 620, height: 700)
        .navigationTitle("Настройка календаря")
    }

    private func save() {
        configuration.authorPatterns = authorText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        onSave(configuration)
        dismiss()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: configuration.folderPath)
        if panel.runModal() == .OK, let url = panel.url {
            configuration.folderPath = url.path
            if configuration.name == "Новый календарь" { configuration.name = url.lastPathComponent }
        }
    }
}
