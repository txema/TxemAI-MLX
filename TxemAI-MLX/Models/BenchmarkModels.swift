import Foundation

/// An event from the benchmark SSE stream (GET /admin/api/bench/{id}/stream).
struct BenchmarkEvent: Decodable {
    let type: String        // "progress" | "result" | "done" | "error"
    let phase: String?      // for "progress": "single" | "batch" | "cleanup"
    let message: String?    // for "progress" progress label and "error" message
    let current: Int?       // for "progress": current test index
    let total: Int?         // for "progress": total test count
    let data: ResultData?   // for "result"
    let summary: Summary?   // for "done"

    struct ResultData: Decodable {
        let testType: String        // "single" | "batch"
        let pp: Int                 // prompt length tokens
        let tg: Int                 // generation length tokens
        let genTps: Double          // token generation speed
        let processingTps: Double   // prompt prefill speed
        let ttftMs: Double?
        let batchSize: Int?         // set for batch tests
    }

    struct Summary: Decodable {
        let modelId: String
        let totalTime: Double
        let totalTests: Int
    }
}

/// A completed benchmark test row shown in the results list.
struct BenchmarkResult: Identifiable {
    let id = UUID()
    let label: String       // "pp1024 / tg128" or "batch 4×"
    let ppTps: Double       // processing_tps
    let tgTps: Double       // gen_tps
}
