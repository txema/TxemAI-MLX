import Foundation

/// A model entry from HuggingFace Hub (search results or recommended lists).
/// JSON keys use snake_case and are decoded via convertFromSnakeCase.
struct HFModel: Identifiable, Codable {
    /// Identifiable conformance — uses repoId which is unique per model.
    var id: String { repoId }

    let repoId: String
    let name: String
    let downloads: Int
    let likes: Int
    let trendingScore: Double
    let size: Int          // bytes; 0 if unknown
    let sizeFormatted: String
    let params: Int?
    let paramsFormatted: String?
}

/// A download task tracked by the oMLX HF downloader.
struct HFDownloadTask: Identifiable, Codable {
    let taskId: String
    let repoId: String
    let status: String   // "pending" | "downloading" | "completed" | "failed" | "cancelled"
    let progress: Double // 0.0–100.0
    let totalSize: Int
    let downloadedSize: Int
    let error: String
    let createdAt: Double
    let startedAt: Double
    let completedAt: Double
    let retryCount: Int

    var id: String { taskId }

    var isActive: Bool     { status == "pending" || status == "downloading" }
    var isCompleted: Bool  { status == "completed" }
}

// MARK: - Response wrappers

struct HFRecommendedResponse: Codable {
    let trending: [HFModel]
    let popular: [HFModel]
}

struct HFSearchResponse: Codable {
    let models: [HFModel]
    let total: Int
}

struct HFTasksResponse: Codable {
    let tasks: [HFDownloadTask]
}

struct HFDownloadStartResponse: Codable {
    let success: Bool
    let task: HFDownloadTask
}
