import Foundation

struct QualityAdvice: Identifiable, Hashable, Sendable {
    enum Level: Int, Hashable, Sendable {
        case positive
        case information
        case warning
        case critical
    }

    let id: String
    let level: Level
    let title: String
    let detail: String
}

enum AdviceEngine {
    static func makeAdvice(snapshot: CalendarSnapshot, now: Date = Date()) -> [QualityAdvice] {
        let recent = snapshot.commits.filter { $0.authorDate >= now.addingTimeInterval(-90 * 86_400) }
        let issueCounts = Dictionary(grouping: recent.flatMap(\.riskReasons), by: { $0 }).mapValues(\.count)
        var advice: [QualityAdvice] = []

        if let interval = snapshot.summary.averageCommitIntervalDays, interval > 2 {
            advice.append(QualityAdvice(
                id: "cadence",
                level: .critical,
                title: "Интервал между активными днями выше 2 суток",
                detail: "Сейчас \(interval.formatted(.number.precision(.fractionLength(1)))) дня. Делайте содержательные промежуточные коммиты; merge-коммиты здесь не учитываются."
            ))
        }

        let recentChanged = recent.compactMap(\.quality).reduce(0) { $0 + $1.changedCodeLines }
        let recentRework = recent.compactMap(\.quality).reduce(0) { $0 + $1.recentReworkLines }
        if recentChanged > 0, Double(recentRework) / Double(recentChanged) >= 0.05 {
            advice.append(QualityAdvice(
                id: "rework",
                level: .information,
                title: "Высокая доля повторных правок — проверьте причину",
                detail: "\(percent(recentRework, of: recentChanged))% строк менялись повторно в течение 14 дней. Это может быть потерей работы, а может быть полезным рефакторингом; показатель не ухудшает Aberrant proxy."
            ))
        }

        if let dominant = maintainabilityIssues
            .compactMap({ reason in issueCounts[reason].map { (reason, $0) } })
            .max(by: { $0.1 < $1.1 }) {
            advice.append(adviceFor(reason: dominant.0, count: dominant.1))
        }

        if let tests = issueCounts[.sourceWithoutTests], tests > 0 {
            advice.append(QualityAdvice(
                id: "tests",
                level: .warning,
                title: "Крупные изменения без сопутствующих тестов",
                detail: "За 90 дней найдено: \(tests). Это отдельный инженерный сигнал и не входит в расчёт Aberrant proxy."
            ))
        }

        if let coverage = snapshot.summary.analyzedCommitPercent, coverage < 70 {
            advice.append(QualityAdvice(
                id: "coverage",
                level: .information,
                title: "Ограниченное покрытие статическим анализом",
                detail: "Разобрано \(coverage.formatted(.number.precision(.fractionLength(0))))% коммитов с исходным кодом. Прокси оценивает последние 180 дней и не более 240 коммитов за одно сканирование."
            ))
        }

        if advice.isEmpty {
            advice.append(QualityAdvice(
                id: "healthy",
                level: .positive,
                title: "Явных структурных ухудшений не найдено",
                detail: "Продолжайте небольшие цельные изменения и проверяйте тренд. Низкий proxy не заменяет ревью и официальный отчёт BlueOptima."
            ))
        }
        return Array(advice.prefix(4))
    }

    private static let maintainabilityIssues: [RiskReason] = [
        .highComplexity, .highCoupling, .longFunction, .deepNesting,
        .functionalityOverload, .highFileSize, .poorReadability
    ]

    private static func adviceFor(reason: RiskReason, count: Int) -> QualityAdvice {
        let detail: String
        switch reason {
        case .highCoupling:
            detail = "В \(count) изменениях выросло число зависимостей выше относительного порога. Отделите инфраструктуру интерфейсом и уменьшите fan-out."
        case .highComplexity, .deepNesting:
            detail = "В \(count) изменениях усложнился поток управления. Используйте guard/early return и выделите независимые операции."
        case .longFunction:
            detail = "В \(count) изменениях выросли слишком длинные функции. Разделите оркестрацию и чистые преобразования."
        case .functionalityOverload, .highFileSize:
            detail = "В \(count) изменениях файл получил слишком много ответственности. Разнесите домен, I/O и представление по компонентам."
        case .poorReadability:
            detail = "В \(count) изменениях ухудшились сигналы читаемости. Упростите выражения и добавляйте только полезные пояснения причин."
        default:
            detail = "Найдено \(count) изменений с этим сигналом. Откройте день и проверьте конкретные файлы."
        }
        return QualityAdvice(id: reason.rawValue, level: .warning, title: reason.title, detail: detail)
    }

    private static func percent(_ part: Int, of total: Int) -> String {
        (Double(part) / Double(total) * 100).formatted(.number.precision(.fractionLength(1)))
    }
}
