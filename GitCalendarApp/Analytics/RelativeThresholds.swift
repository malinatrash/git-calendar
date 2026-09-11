import Foundation

struct MetricThresholds: Hashable, Sendable {
    var codeLines: Double
    var cyclomaticComplexity: Double
    var maximumNesting: Double
    var dependencyCount: Double
    var functionCount: Double
    var maximumFunctionLength: Double
    var longLineRatio: Double

    static let fallback = MetricThresholds(
        codeLines: 400,
        cyclomaticComplexity: 24,
        maximumNesting: 4,
        dependencyCount: 16,
        functionCount: 20,
        maximumFunctionLength: 60,
        longLineRatio: 0.10
    )
}

struct RelativeThresholds: Sendable {
    private let byLanguage: [String: MetricThresholds]

    init(samples: [(path: String, metrics: SourceMetrics)]) {
        let grouped = Dictionary(grouping: samples) { SourceClassifier.languageKey(for: $0.path) }
        byLanguage = grouped.mapValues { values in
            guard values.count >= 8 else { return .fallback }
            let metrics = values.map(\.metrics)
            return MetricThresholds(
                codeLines: max(MetricThresholds.fallback.codeLines, Self.percentile(metrics.map { Double($0.codeLines) }, 0.90)),
                cyclomaticComplexity: max(MetricThresholds.fallback.cyclomaticComplexity, Self.percentile(metrics.map { Double($0.cyclomaticComplexity) }, 0.90)),
                maximumNesting: max(MetricThresholds.fallback.maximumNesting, Self.percentile(metrics.map { Double($0.maximumNesting) }, 0.90)),
                dependencyCount: max(MetricThresholds.fallback.dependencyCount, Self.percentile(metrics.map { Double($0.dependencyCount) }, 0.90)),
                functionCount: max(MetricThresholds.fallback.functionCount, Self.percentile(metrics.map { Double($0.functionCount) }, 0.90)),
                maximumFunctionLength: max(MetricThresholds.fallback.maximumFunctionLength, Self.percentile(metrics.map { Double($0.maximumFunctionLength) }, 0.90)),
                longLineRatio: max(MetricThresholds.fallback.longLineRatio, Self.percentile(metrics.map(\.longLineRatio), 0.90))
            )
        }
    }

    func values(for path: String) -> MetricThresholds {
        byLanguage[SourceClassifier.languageKey(for: path)] ?? .fallback
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * percentile).rounded(.up))
        return sorted[min(index, sorted.count - 1)]
    }
}

enum RelativeRiskAnalyzer {
    static func assess(
        path: String,
        before: SourceMetrics,
        after: SourceMetrics,
        thresholds: MetricThresholds
    ) -> FileQualityChange {
        var issues: [RiskReason] = []
        var improvements: [RiskReason] = []
        var severities: [Double] = []

        compare(before.codeLines, after.codeLines, threshold: thresholds.codeLines, reason: .highFileSize, issues: &issues, improvements: &improvements, severities: &severities)
        compare(before.cyclomaticComplexity, after.cyclomaticComplexity, threshold: thresholds.cyclomaticComplexity, reason: .highComplexity, issues: &issues, improvements: &improvements, severities: &severities)
        compare(before.maximumNesting, after.maximumNesting, threshold: thresholds.maximumNesting, reason: .deepNesting, issues: &issues, improvements: &improvements, severities: &severities)
        compare(before.dependencyCount, after.dependencyCount, threshold: thresholds.dependencyCount, reason: .highCoupling, issues: &issues, improvements: &improvements, severities: &severities)
        compare(before.maximumFunctionLength, after.maximumFunctionLength, threshold: thresholds.maximumFunctionLength, reason: .longFunction, issues: &issues, improvements: &improvements, severities: &severities)
        compare(before.functionCount, after.functionCount, threshold: thresholds.functionCount, reason: .functionalityOverload, issues: &issues, improvements: &improvements, severities: &severities)

        let readabilityWasPoor = isPoorReadability(before, thresholds: thresholds)
        let readabilityIsPoor = isPoorReadability(after, thresholds: thresholds)
        if readabilityIsPoor && (!readabilityWasPoor || after.longLineRatio > before.longLineRatio + 0.02) {
            issues.append(.poorReadability)
            severities.append(0.45)
        } else if readabilityWasPoor && !readabilityIsPoor {
            improvements.append(.poorReadability)
        }

        let combined = severities.reduce(0) { 1 - (1 - $0) * (1 - $1) }
        return FileQualityChange(
            path: path,
            before: before,
            after: after,
            issues: issues,
            improvements: improvements,
            riskScore: min(1, combined)
        )
    }

    private static func compare(
        _ before: Int,
        _ after: Int,
        threshold: Double,
        reason: RiskReason,
        issues: inout [RiskReason],
        improvements: inout [RiskReason],
        severities: inout [Double]
    ) {
        let old = Double(before)
        let new = Double(after)
        let wasHigh = old > threshold
        let isHigh = new > threshold
        let worsened = new > old && (!wasHigh || new >= old * 1.05)
        if isHigh && worsened {
            issues.append(reason)
            severities.append(min(0.80, 0.30 + (new - threshold) / max(threshold, 1) * 0.50))
        } else if wasHigh && new < old {
            improvements.append(reason)
        }
    }

    private static func isPoorReadability(_ metrics: SourceMetrics, thresholds: MetricThresholds) -> Bool {
        guard metrics.codeLines >= 80 else { return false }
        return metrics.longLineRatio > thresholds.longLineRatio
            || metrics.commentRatio < 0.015
            || metrics.commentRatio > 0.45
    }
}
