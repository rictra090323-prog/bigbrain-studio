import Foundation
import NaturalLanguage
import SwiftUI

private typealias LocalState<Value> = SwiftUI.State<Value>

struct CandidateFixture: Decodable {
    struct Note: Decodable { let id: String; let text: String }
    struct Trial: Decodable { let id: String; let query: String; let expected: String? }
    let notes: [Note]
    let trials: [Trial]
}

enum ContextualCandidateTrial {
    static func evaluate(_ fixture: CandidateFixture) throws -> String {
        guard let model = NLContextualEmbedding(language: .swedish) else {
            return "Swedish contextual embedding unavailable"
        }
        var report = ["Model: \(model.modelIdentifier); assets present: \(model.hasAvailableAssets)"]
        guard model.hasAvailableAssets else { return report.joined(separator: "\n") }
        try model.load()
        func vector(_ text: String) throws -> [Double] {
            let result = try model.embeddingResult(for: text, language: nil)
            var total = Array(repeating: 0.0, count: model.dimension)
            let source = result.string
            result.enumerateTokenVectors(in: source.startIndex..<source.endIndex) { values, _ in
                for i in values.indices { total[i] += values[i] }
                return true
            }
            let norm = sqrt(total.reduce(0) { $0 + $1 * $1 })
            guard norm > 0 else { return total }
            return total.map { $0 / norm }
        }
        let vectors = try fixture.notes.map { ($0.id, try vector($0.text)) }
        var covered = 0
        for trial in fixture.trials {
            let query = try vector(trial.query)
            let scored = vectors.map { item in
                (item.0, zip(item.1, query).reduce(0) { $0 + $1.0 * $1.1 })
            }.sorted { $0.1 > $1.1 }
            let first = scored.prefix(3).map(\.0)
            if let target = trial.expected, first.contains(target) { covered += 1 }
            report.append("\(trial.id): \(first)")
        }
        report.append("Covered: \(covered)/\(fixture.trials.compactMap(\.expected).count)")
        return report.joined(separator: "\n")
    }
}


@main
struct CandidateTestApp: App {
    @LocalState private var report = "Running…"

    var body: some Scene {
        WindowGroup("BigBrain Contextual Candidate Test") {
            ScrollView {
                Text(report).textSelection(.enabled).padding()
            }
            .frame(minWidth: 550, minHeight: 300)
            .task {
                do {
                    guard let file = Bundle.main.url(forResource: "fixture", withExtension: "json") else { return }
                    let input = try JSONDecoder().decode(CandidateFixture.self, from: Data(contentsOf: file))
                    report = try ContextualCandidateTrial.evaluate(input)
                } catch {
                    report = String(describing: error)
                }
            }
        }
    }
}
