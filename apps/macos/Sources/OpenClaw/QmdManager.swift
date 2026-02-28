import Foundation
import Observation

private let logger = Logger(subsystem: "ai.openclaw", category: "qmd")

// Debug log file for download troubleshooting
private let debugLogFile: URL = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".cache/qmd/download.log")
}()

private func debugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"

    // Also log to system logger
    logger.info("\(message)")

    // Write to debug file
    let fm = FileManager.default
    let dir = debugLogFile.deletingLastPathComponent()
    if !fm.fileExists(atPath: dir.path) {
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    if !fm.fileExists(atPath: debugLogFile.path) {
        fm.createFile(atPath: debugLogFile.path, contents: nil)
    }

    if let handle = try? FileHandle(forWritingTo: debugLogFile) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        if let data = line.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }
}

// MARK: - QMD Model Definitions

struct QmdModel: Identifiable {
    let id: String
    let name: String
    let fileName: String
    let downloadUrl: URL
    let sizeMB: Int
    var state: DownloadState = .pending

    enum DownloadState: Equatable {
        case pending
        case downloading(progress: Double)
        case completed
        case failed(String)

        var isCompleted: Bool {
            if case .completed = self { return true }
            return false
        }

        var isDownloading: Bool {
            if case .downloading = self { return true }
            return false
        }
    }
}

// MARK: - QMD Manager

@MainActor
@Observable
final class QmdManager: NSObject {
    static let shared = QmdManager()

    // State
    var bunInstalled = false
    var qmdInstalled = false
    var modelsReady = false
    var modelsWarmed = false  // Whether models have been preloaded into memory
    var models: [QmdModel] = QmdManager.defaultModels
    var isChecking = false
    var isDownloading = false
    var isWarming = false  // Whether model warmup is in progress
    var overallProgress: Double = 0
    var statusMessage: String?
    var error: String?

    // Plugin config
    var isQmdEnabled = false  // Whether memory-qmd is the active memory slot
    var autoRecall = true
    var autoCapture = true
    var searchMode: String = "query"
    var minScore: Double = 0.15  // Minimum similarity score threshold (0.0-1.0)

    // Collections
    var collections: [QmdCollection] = []
    var isLoadingCollections = false

    // Private
    private var downloadSession: URLSession?
    private var activeDownloads: [URLSessionDownloadTask: String] = [:]
    private var downloadContinuations: [String: CheckedContinuation<URL, Error>] = [:]
    private var resumeData: [String: Data] = [:]  // Store resume data for failed downloads
    private var downloadProgress: [String: Double] = [:]  // Track progress for UI display
    private var lastReportedProgress: [String: Int] = [:]  // Track last reported progress percentage

    // Download config
    private static let maxRetries = 5  // Increased retry count
    private static let retryDelay: TimeInterval = 3.0

    private static let modelsDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cache/qmd/models")
    }()

    private static let tempDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cache/qmd/temp")
    }()

    private static let defaultModels: [QmdModel] = [
        QmdModel(
            id: "embedding",
            name: "Embedding (gemma-300M)",
            fileName: "embeddinggemma-300M-Q8_0.gguf",
            downloadUrl: URL(string: "https://huggingface.co/ggml-org/embeddinggemma-300M-GGUF/resolve/main/embeddinggemma-300M-Q8_0.gguf")!,
            sizeMB: 300),
        QmdModel(
            id: "reranker",
            name: "Reranker (qwen3-0.6B)",
            fileName: "Qwen.Qwen3-Reranker-0.6B.Q8_0.gguf",
            // Note: Original Qwen/Qwen3-Reranker-0.6B-GGUF repo doesn't exist, using DevQuasar mirror
            downloadUrl: URL(string: "https://huggingface.co/DevQuasar/Qwen.Qwen3-Reranker-0.6B-GGUF/resolve/main/Qwen.Qwen3-Reranker-0.6B.Q8_0.gguf")!,
            sizeMB: 640),
        QmdModel(
            id: "expansion",
            name: "Query Expansion (1.7B)",
            fileName: "qmd-query-expansion-1.7B-q4_k_m.gguf",
            // Note: Username is "tobil" not "tobi"
            downloadUrl: URL(string: "https://huggingface.co/tobil/qmd-query-expansion-1.7B-gguf/resolve/main/qmd-query-expansion-1.7B-q4_k_m.gguf")!,
            sizeMB: 1100),
    ]

    override private init() {
        super.init()
    }

    // MARK: - Status Check

    func checkStatus() async {
        guard !self.isChecking else { return }
        self.isChecking = true
        self.error = nil
        defer { self.isChecking = false }

        // Check Bun runtime
        self.bunInstalled = Self.isBunInstalled()

        // Check QMD binary
        self.qmdInstalled = Self.isQmdInstalled()

        // Check models
        self.refreshModelStates()
        self.modelsReady = self.models.allSatisfy { $0.state.isCompleted }

        // Load collections if QMD is ready
        if self.qmdInstalled && self.modelsReady {
            await self.loadCollections()
            // Auto-warmup models if QMD is enabled and not yet warmed
            if self.isQmdEnabled && !self.modelsWarmed && !self.isWarming {
                Task {
                    await self.warmupModels()
                }
            }
        }

        // Load plugin config from gateway
        await self.loadPluginConfig()

        logger.info("QMD status: bun=\(self.bunInstalled) installed=\(self.qmdInstalled) modelsReady=\(self.modelsReady) warmed=\(self.modelsWarmed)")
    }

    private static func isBunInstalled() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".bun/bin/bun").path,
            "/usr/local/bin/bun",
            "/opt/homebrew/bin/bun",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return true
            }
        }
        return false
    }

    private static func isQmdInstalled() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".bun/bin/qmd").path,
            "/usr/local/bin/qmd",
            "/opt/homebrew/bin/qmd",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return true
            }
        }
        // Check PATH via which
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["qmd"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func refreshModelStates() {
        let fm = FileManager.default
        for i in self.models.indices {
            let path = Self.modelsDir.appendingPathComponent(self.models[i].fileName).path
            if fm.fileExists(atPath: path) {
                if !self.models[i].state.isDownloading {
                    self.models[i].state = .completed
                }
            } else if !self.models[i].state.isDownloading {
                self.models[i].state = .pending
            }
        }
    }

    // MARK: - Install Bun & QMD

    var isInstalling = false

    func installBun() async {
        guard !self.isInstalling else { return }
        self.isInstalling = true
        self.error = nil
        self.statusMessage = "正在安装 Bun..."
        defer { self.isInstalling = false }

        do {
            // Download and run bun installer
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", "curl -fsSL https://bun.sh/install | bash"]
            process.environment = ProcessInfo.processInfo.environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                self.bunInstalled = true
                self.statusMessage = "Bun 安装成功"
                logger.info("Bun installed successfully")
            } else {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                self.error = "Bun 安装失败: \(output)"
                logger.error("Bun install failed: \(output)")
            }
        } catch {
            self.error = "Bun 安装失败: \(error.localizedDescription)"
            logger.error("Bun install error: \(error)")
        }
    }

    func installQmd() async {
        guard !self.isInstalling else { return }
        guard self.bunInstalled else {
            self.error = "请先安装 Bun"
            return
        }
        self.isInstalling = true
        self.error = nil
        self.statusMessage = "正在安装 QMD..."
        defer { self.isInstalling = false }

        do {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let bunPath = home.appendingPathComponent(".bun/bin/bun").path

            let process = Process()
            process.executableURL = URL(fileURLWithPath: bunPath)
            process.arguments = ["install", "-g", "github:tobi/qmd"]
            process.environment = ProcessInfo.processInfo.environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                self.qmdInstalled = Self.isQmdInstalled()
                if self.qmdInstalled {
                    self.statusMessage = "QMD 安装成功"
                    logger.info("QMD installed successfully")
                } else {
                    self.error = "QMD 安装完成但未找到可执行文件，请检查 PATH"
                }
            } else {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                self.error = "QMD 安装失败: \(output)"
                logger.error("QMD install failed: \(output)")
            }
        } catch {
            self.error = "QMD 安装失败: \(error.localizedDescription)"
            logger.error("QMD install error: \(error)")
        }
    }

    // MARK: - Model Download

    func downloadAllModels() async {
        guard !self.isDownloading else { return }
        self.isDownloading = true
        self.error = nil
        self.statusMessage = "准备下载模型..."

        // Create directories
        let fm = FileManager.default
        for dir in [Self.modelsDir, Self.tempDir] {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }

        debugLog("[Download] Starting model download session")

        // Create a single session for all downloads (reuse across models and retries)
        self.createDownloadSession()

        var completedCount = 0
        let totalModels = self.models.filter { !$0.state.isCompleted }.count

        for i in self.models.indices {
            guard !self.models[i].state.isCompleted else {
                completedCount += 1
                continue
            }

            let model = self.models[i]
            debugLog("[Download] Processing model: \(model.name) (\(model.sizeMB)MB)")

            self.statusMessage = "正在下载: \(model.name) (\(completedCount + 1)/\(totalModels + completedCount))"
            self.models[i].state = .downloading(progress: 0)

            // Retry loop
            var lastError: Error?
            for attempt in 1...Self.maxRetries {
                do {
                    // Check if we have resume data from previous attempt
                    let hasResumeData = self.resumeData[model.id] != nil
                    let previousProgress = self.downloadProgress[model.id] ?? 0

                    if hasResumeData && previousProgress > 0 {
                        debugLog("[Download] \(model.name) - Attempt \(attempt)/\(Self.maxRetries), resuming from \(Int(previousProgress * 100))%")
                        self.models[i].state = .downloading(progress: previousProgress)
                    } else {
                        debugLog("[Download] \(model.name) - Attempt \(attempt)/\(Self.maxRetries)")
                        self.models[i].state = .downloading(progress: 0)
                    }

                    // Only recreate session if it was invalidated (e.g., after a network error)
                    if self.downloadSession == nil {
                        self.createDownloadSession()
                    }

                    let tempUrl = try await self.downloadModel(self.models[i])
                    let destUrl = Self.modelsDir.appendingPathComponent(model.fileName)

                    // Verify download size
                    if let attrs = try? fm.attributesOfItem(atPath: tempUrl.path),
                       let fileSize = attrs[.size] as? Int64 {
                        let expectedSize = Int64(model.sizeMB) * 1024 * 1024
                        let tolerance = expectedSize / 10  // 10% tolerance
                        if fileSize < expectedSize - tolerance {
                            debugLog("[Download] \(model.name) - File size mismatch: got \(fileSize), expected ~\(expectedSize)")
                        } else {
                            debugLog("[Download] \(model.name) - File size OK: \(fileSize) bytes")
                        }
                    }

                    // Move to final location
                    if fm.fileExists(atPath: destUrl.path) {
                        try fm.removeItem(at: destUrl)
                    }
                    try fm.moveItem(at: tempUrl, to: destUrl)

                    // Clean up on success
                    self.resumeData.removeValue(forKey: model.id)
                    self.downloadProgress.removeValue(forKey: model.id)
                    self.lastReportedProgress.removeValue(forKey: model.id)

                    self.models[i].state = .completed
                    completedCount += 1
                    debugLog("[Download] ✅ \(model.name) - Download completed successfully")
                    lastError = nil
                    break
                } catch {
                    lastError = error
                    let errorDesc = self.describeError(error)
                    debugLog("[Download] ❌ \(model.name) - Attempt \(attempt) failed: \(errorDesc)")

                    // Only invalidate session on network errors that require a fresh connection
                    // For other errors (like file copy failures), we can reuse the session
                    if let urlError = error as? URLError {
                        switch urlError.code {
                        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
                            // Network issues - invalidate session for fresh connection
                            self.invalidateDownloadSession()
                        default:
                            // Other errors - session might still be usable
                            break
                        }
                    }

                    if attempt < Self.maxRetries {
                        // Keep the current progress in UI, don't reset to 0
                        let currentProgress = self.downloadProgress[model.id] ?? 0
                        let hasResumeData = self.resumeData[model.id] != nil
                        self.statusMessage = "下载失败（已完成 \(Int(currentProgress * 100))%\(hasResumeData ? "，可续传" : "")），\(Int(Self.retryDelay))秒后重试 (\(attempt)/\(Self.maxRetries))..."
                        debugLog("[Download] \(model.name) - Waiting \(Self.retryDelay)s before retry... (progress: \(Int(currentProgress * 100))%, hasResumeData: \(hasResumeData))")

                        try? await Task.sleep(nanoseconds: UInt64(Self.retryDelay * 1_000_000_000))
                    }
                }
            }

            if let error = lastError {
                let msg = self.describeError(error)
                self.models[i].state = .failed(msg)
                debugLog("[Download] \(model.name) - All \(Self.maxRetries) attempts failed")
            }

            self.updateOverallProgress()
        }

        // Clean up session after all downloads are done
        self.invalidateDownloadSession()

        self.modelsReady = self.models.allSatisfy { $0.state.isCompleted }

        if self.modelsReady {
            self.statusMessage = "所有模型下载完成！"
            self.error = nil
            debugLog("[Download] ✅ All models downloaded successfully")
        } else {
            let failed = self.models.filter {
                if case .failed = $0.state { return true }
                return false
            }
            self.error = "部分模型下载失败: \(failed.map(\.name).joined(separator: ", "))"
            self.statusMessage = nil
            debugLog("[Download] Some models failed: \(failed.map(\.name).joined(separator: ", "))")
        }

        self.isDownloading = false
    }

    private func createDownloadSession() {
        // If we already have a valid session, don't create a new one
        // This prevents race conditions where invalidation callbacks affect the new session
        if self.downloadSession != nil {
            debugLog("[Download] Reusing existing download session")
            return
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 7200 // 2 hours for large files
        config.timeoutIntervalForRequest = 300 // 5 min per request timeout
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true

        // Use a dedicated serial queue for delegate callbacks to avoid race conditions
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.name = "ai.openclaw.QmdDownloadDelegate"

        self.downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        debugLog("[Download] Created new download session")
    }

    private func invalidateDownloadSession() {
        // Safely invalidate the session - call this only when done with all downloads
        self.downloadSession?.invalidateAndCancel()
        self.downloadSession = nil
        debugLog("[Download] Download session invalidated")
    }

    private func downloadModel(_ model: QmdModel) async throws -> URL {
        // Use URLSession's resume data if available (most reliable method)
        if let resumeDataForModel = self.resumeData[model.id] {
            debugLog("[Download] \(model.name) - Resuming with URLSession resume data (\(resumeDataForModel.count) bytes)")
            return try await self.resumeDownloadTask(model, resumeData: resumeDataForModel)
        }

        // Start fresh download
        debugLog("[Download] \(model.name) - Starting fresh download")
        return try await self.startDownloadTask(model)
    }

    private func startDownloadTask(_ model: QmdModel) async throws -> URL {
        var request = URLRequest(url: model.downloadUrl)
        request.timeoutInterval = 300  // 5 min per request
        // Add User-Agent to avoid HuggingFace 401 errors
        request.setValue("OpenClaw/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        // Allow following redirects
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        return try await withCheckedThrowingContinuation { continuation in
            guard let session = self.downloadSession else {
                continuation.resume(throwing: URLError(.cancelled))
                return
            }
            let task = session.downloadTask(with: request)
            self.activeDownloads[task] = model.id
            self.downloadContinuations[model.id] = continuation
            task.resume()
            debugLog("[Download] \(model.name) - Download task started")
        }
    }

    private func resumeDownloadTask(_ model: QmdModel, resumeData: Data) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            guard let session = self.downloadSession else {
                continuation.resume(throwing: URLError(.cancelled))
                return
            }
            let task = session.downloadTask(withResumeData: resumeData)
            self.activeDownloads[task] = model.id
            self.downloadContinuations[model.id] = continuation
            task.resume()
            debugLog("[Download] \(model.name) - Resumed download task with resume data")
        }
    }

    private func describeError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            let code = urlError.code.rawValue
            switch urlError.code {
            case .timedOut:
                return "连接超时 (code: \(code))"
            case .notConnectedToInternet:
                return "网络未连接 (code: \(code))"
            case .networkConnectionLost:
                return "网络连接中断 (code: \(code))"
            case .cannotFindHost:
                return "无法找到服务器 (code: \(code))"
            case .cannotConnectToHost:
                return "无法连接到服务器 (code: \(code))"
            case .cancelled:
                return "下载已取消 (code: \(code))"
            case .badServerResponse:
                return "服务器响应错误 (code: \(code))"
            case .secureConnectionFailed:
                return "安全连接失败 (code: \(code))"
            default:
                return "网络错误 (code: \(code)): \(urlError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    private func updateOverallProgress() {
        let total = Double(self.models.count)
        var progress = 0.0
        for model in self.models {
            switch model.state {
            case .completed:
                progress += 1.0
            case .downloading(let p):
                progress += p
            default:
                break
            }
        }
        self.overallProgress = progress / total
    }

    func cancelDownloads() {
        debugLog("[Download] Cancelling all downloads...")

        // Cancel all active downloads and save resume data
        for (task, modelId) in self.activeDownloads {
            task.cancel { resumeData in
                Task { @MainActor in
                    if let resumeData {
                        self.resumeData[modelId] = resumeData
                        let progress = self.downloadProgress[modelId] ?? 0
                        debugLog("[Download] \(modelId) - Saved resume data on cancel: \(resumeData.count) bytes (at \(Int(progress * 100))%)")
                    }
                }
            }
        }

        self.invalidateDownloadSession()
        self.isDownloading = false
        self.statusMessage = nil

        for continuation in self.downloadContinuations.values {
            continuation.resume(throwing: URLError(.cancelled))
        }
        self.downloadContinuations.removeAll()
        self.activeDownloads.removeAll()

        self.refreshModelStates()
        debugLog("[Download] All downloads cancelled")
    }

    // MARK: - Model Warmup

    /// Preload QMD models into memory by running a minimal query.
    /// This significantly reduces latency for subsequent queries.
    func warmupModels() async {
        guard self.qmdInstalled && self.modelsReady else { return }
        guard !self.isWarming && !self.modelsWarmed else { return }

        self.isWarming = true
        self.statusMessage = "正在预热模型..."
        logger.info("QMD: Starting model warmup")

        do {
            // Run a minimal query to load all models into memory
            // Using "query" mode ensures embedding, reranker, and expansion models are all loaded
            _ = try await Self.runQmd(["query", "warmup", "--json", "-n", "1"], timeout: 120)
            self.modelsWarmed = true
            self.statusMessage = "模型预热完成"
            logger.info("QMD: Model warmup completed")

            // Clear status message after a short delay
            Task {
                try? await Task.sleep(for: .seconds(2))
                if self.statusMessage == "模型预热完成" {
                    self.statusMessage = nil
                }
            }
        } catch {
            logger.warning("QMD: Model warmup failed: \(error.localizedDescription)")
            // Don't show error to user - warmup is optional optimization
            self.statusMessage = nil
        }

        self.isWarming = false
    }

    // MARK: - Collections

    func loadCollections() async {
        guard self.qmdInstalled else { return }
        self.isLoadingCollections = true
        defer { self.isLoadingCollections = false }

        do {
            let output = try await Self.runQmd(["collection", "list"])
            self.collections = Self.parseCollections(output)
        } catch {
            logger.warning("Failed to load QMD collections: \(error.localizedDescription)")
            self.collections = []
        }
    }

    func addCollection(path: String, name: String) async {
        do {
            let fm = FileManager.default
            var isDir: ObjCBool = false

            guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
                self.error = "路径不存在: \(path)"
                return
            }

            if isDir.boolValue {
                // Directory: index all .md files
                _ = try await Self.runQmd(["collection", "add", path, "--name", name, "--mask", "**/*.md"])
            } else {
                // Single file: use the file's directory with exact filename mask
                let url = URL(fileURLWithPath: path)
                let dirPath = url.deletingLastPathComponent().path
                let filename = url.lastPathComponent
                _ = try await Self.runQmd(["collection", "add", dirPath, "--name", name, "--mask", filename])
            }

            self.statusMessage = "已添加集合: \(name)"
            _ = try? await Self.runQmd(["embed"])
            await self.loadCollections()
        } catch {
            self.error = "添加集合失败: \(error.localizedDescription)"
        }
    }

    func removeCollection(name: String) async {
        do {
            _ = try await Self.runQmd(["collection", "remove", name])
            self.statusMessage = "已删除集合: \(name)"
            await self.loadCollections()
        } catch {
            self.error = "删除集合失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Plugin Config

    func loadPluginConfig() async {
        do {
            let config = try await ConfigStore.load()
            let plugins = config["plugins"] as? [String: Any] ?? [:]
            let slots = plugins["slots"] as? [String: Any] ?? [:]
            let memorySlot = slots["memory"] as? String ?? "memory-core"

            // Check if QMD is enabled
            self.isQmdEnabled = memorySlot == "memory-qmd"
            if self.isQmdEnabled {
                let pluginConfigs = plugins["config"] as? [String: Any] ?? [:]
                let qmdConfig = pluginConfigs["memory-qmd"] as? [String: Any] ?? [:]
                self.autoRecall = (qmdConfig["autoRecall"] as? Bool) ?? true
                self.autoCapture = (qmdConfig["autoCapture"] as? Bool) ?? true
                self.searchMode = (qmdConfig["searchMode"] as? String) ?? "query"
                self.minScore = (qmdConfig["minScore"] as? Double) ?? 0.15
            }
        } catch {
            logger.warning("Failed to load plugin config: \(error.localizedDescription)")
        }
    }

    func savePluginConfig() async {
        do {
            var config = try await ConfigStore.load()

            // Ensure plugins structure
            var plugins = config["plugins"] as? [String: Any] ?? [:]
            var slots = plugins["slots"] as? [String: Any] ?? [:]
            var loadConfig = plugins["load"] as? [String: Any] ?? [:]
            var loadPaths = loadConfig["paths"] as? [String] ?? []

            // Ensure the bundled extensions directory is in load paths
            // This is necessary because Gateway needs to discover memory-qmd plugin
            if let bundledExtDir = Self.bundledExtensionsDirectory() {
                let memoryQmdPath = (bundledExtDir as NSString).appendingPathComponent("memory-qmd")
                if FileManager.default.fileExists(atPath: memoryQmdPath) {
                    // Add bundled extensions dir if not already present
                    if !loadPaths.contains(bundledExtDir) {
                        loadPaths.append(bundledExtDir)
                        loadConfig["paths"] = loadPaths
                        plugins["load"] = loadConfig
                        logger.info("Added bundled extensions path: \(bundledExtDir)")
                    }
                } else {
                    // Try global extensions directory as fallback
                    let globalExtDir = Self.globalExtensionsDirectory()
                    let globalMemoryQmdPath = (globalExtDir as NSString).appendingPathComponent("memory-qmd")
                    if FileManager.default.fileExists(atPath: globalMemoryQmdPath) {
                        if !loadPaths.contains(globalExtDir) {
                            loadPaths.append(globalExtDir)
                            loadConfig["paths"] = loadPaths
                            plugins["load"] = loadConfig
                            logger.info("Added global extensions path: \(globalExtDir)")
                        }
                    } else {
                        // memory-qmd plugin not found - try to copy it
                        logger.warning("memory-qmd plugin not found, attempting to install...")
                        if await Self.installMemoryQmdPlugin() {
                            if !loadPaths.contains(globalExtDir) {
                                loadPaths.append(globalExtDir)
                                loadConfig["paths"] = loadPaths
                                plugins["load"] = loadConfig
                            }
                        } else {
                            self.error = "保存配置失败: memory-qmd 插件未找到，请重新安装应用"
                            return
                        }
                    }
                }
            }

            // Enable memory-qmd plugin in entries with its config
            // The config goes inside entries.<plugin-id>.config, not plugins.config
            var entries = plugins["entries"] as? [String: Any] ?? [:]
            entries["memory-qmd"] = [
                "enabled": true,
                "config": [
                    "autoRecall": self.autoRecall,
                    "autoCapture": self.autoCapture,
                    "searchMode": self.searchMode,
                    "minScore": self.minScore,
                ] as [String: Any]
            ] as [String: Any]
            plugins["entries"] = entries

            // Set memory slot to QMD
            slots["memory"] = "memory-qmd"

            plugins["slots"] = slots
            config["plugins"] = plugins

            try await ConfigStore.save(config)
            self.isQmdEnabled = true
            self.statusMessage = "配置已保存，Gateway 正在重启以加载新配置..."

            // Wait a moment for gateway restart, then refresh status
            try? await Task.sleep(for: .seconds(2))
            await self.checkStatus()
            self.statusMessage = "配置已生效"

            // Trigger model warmup after enabling QMD
            if self.modelsReady && !self.modelsWarmed {
                Task {
                    await self.warmupModels()
                }
            }
        } catch {
            self.error = "保存配置失败: \(error.localizedDescription)"
        }
    }

    /// Save plugin config only if QMD is already enabled (for auto-save on config change)
    func savePluginConfigIfEnabled() async {
        guard self.isQmdEnabled else { return }
        do {
            var config = try await ConfigStore.load()
            var plugins = config["plugins"] as? [String: Any] ?? [:]
            var entries = plugins["entries"] as? [String: Any] ?? [:]

            // Update only the config part, keep enabled state
            entries["memory-qmd"] = [
                "enabled": true,
                "config": [
                    "autoRecall": self.autoRecall,
                    "autoCapture": self.autoCapture,
                    "searchMode": self.searchMode,
                    "minScore": self.minScore,
                ] as [String: Any]
            ] as [String: Any]
            plugins["entries"] = entries
            config["plugins"] = plugins

            try await ConfigStore.save(config)
            // Show brief auto-save confirmation
            self.statusMessage = "配置已自动保存"
            // Clear the message after a short delay
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if self.statusMessage == "配置已自动保存" {
                    self.statusMessage = nil
                }
            }
        } catch {
            self.error = "保存配置失败: \(error.localizedDescription)"
        }
    }

    private static func bundledExtensionsDirectory() -> String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let extDir = resourceURL
            .appendingPathComponent("runtime")
            .appendingPathComponent("openclaw")
            .appendingPathComponent("extensions")
            .path
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: extDir, isDirectory: &isDir), isDir.boolValue {
            return extDir
        }
        return nil
    }

    private static func globalExtensionsDirectory() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".clawdbot/extensions").path
    }

    private static func installMemoryQmdPlugin() async -> Bool {
        // This function would copy the memory-qmd plugin to the global extensions directory
        // For now, we just check if it exists in bundled or return false
        // In a production app, this could download/install the plugin
        guard let bundledExtDir = bundledExtensionsDirectory() else {
            return false
        }

        let sourcePath = (bundledExtDir as NSString).appendingPathComponent("memory-qmd")
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            return false
        }

        let globalExtDir = globalExtensionsDirectory()
        let destPath = (globalExtDir as NSString).appendingPathComponent("memory-qmd")

        do {
            // Create global extensions directory if needed
            try FileManager.default.createDirectory(
                atPath: globalExtDir,
                withIntermediateDirectories: true)

            // Remove existing if present
            if FileManager.default.fileExists(atPath: destPath) {
                try FileManager.default.removeItem(atPath: destPath)
            }

            // Copy from bundled to global
            try FileManager.default.copyItem(atPath: sourcePath, toPath: destPath)
            logger.info("Installed memory-qmd plugin to: \(destPath)")
            return true
        } catch {
            logger.error("Failed to install memory-qmd plugin: \(error.localizedDescription)")
            return false
        }
    }

    func disableQmd() async {
        do {
            var config = try await ConfigStore.load()
            var plugins = config["plugins"] as? [String: Any] ?? [:]
            var slots = plugins["slots"] as? [String: Any] ?? [:]
            slots["memory"] = "memory-core"
            plugins["slots"] = slots
            config["plugins"] = plugins
            try await ConfigStore.save(config)
            self.isQmdEnabled = false
            self.statusMessage = "已切换回默认 Memory 后端，Gateway 正在重启..."

            // Wait a moment for gateway restart
            try? await Task.sleep(for: .seconds(2))
            self.statusMessage = "已切换回默认 Memory 后端"
        } catch {
            self.error = "保存配置失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private static func runQmd(_ args: [String], timeout: TimeInterval = 60) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let candidates = [
                home.appendingPathComponent(".bun/bin/qmd").path,
                "/usr/local/bin/qmd",
                "/opt/homebrew/bin/qmd",
            ]
            let binary = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "qmd"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary == "qmd" ? "/usr/bin/env" : binary)
            process.arguments = binary == "qmd" ? ["qmd"] + args : args
            process.environment = ProcessInfo.processInfo.environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
                process.waitUntilExit()

                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errOutput = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: NSError(
                        domain: "QmdManager",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: errOutput]))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func parseCollections(_ output: String) -> [QmdCollection] {
        output.split(separator: "\n")
            .compactMap { line -> QmdCollection? in
                let str = String(line).trimmingCharacters(in: .whitespaces)
                guard !str.isEmpty else { return nil }
                // Parse: "name: /path (N files)" or just "name: /path"
                guard let colonIdx = str.firstIndex(of: ":") else { return nil }
                let name = String(str[str.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                var rest = String(str[str.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                var fileCount: Int?
                if let parenRange = rest.range(of: #"\((\d+)\s+files?\)"#, options: .regularExpression) {
                    let countStr = rest[parenRange].filter(\.isNumber)
                    fileCount = Int(countStr)
                    rest = String(rest[rest.startIndex..<parenRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                return QmdCollection(name: name, path: rest, fileCount: fileCount)
            }
    }
}

// MARK: - URLSessionDownloadDelegate

extension QmdManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // CRITICAL: Copy the file synchronously BEFORE this function returns!
        // URLSession deletes the temp file immediately after this callback returns.
        // We must NOT use Task{} or any async operation here.

        let fm = FileManager.default
        let tempUrl = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gguf")

        // Check HTTP status first (synchronously)
        var httpStatus = 0
        if let response = downloadTask.response as? HTTPURLResponse {
            httpStatus = response.statusCode
        }

        // Copy file synchronously - this is the critical fix!
        var copyError: Error?
        var fileSize: Int64 = 0
        do {
            try fm.copyItem(at: location, to: tempUrl)
            if let attrs = try? fm.attributesOfItem(atPath: tempUrl.path),
               let size = attrs[.size] as? Int64 {
                fileSize = size
            }
        } catch {
            copyError = error
        }

        // Now we can dispatch to main actor to update state
        Task { @MainActor in
            guard let modelId = self.activeDownloads.removeValue(forKey: downloadTask) else {
                debugLog("[Download] Received finish callback for unknown task")
                // Clean up temp file if we copied it but don't know which model
                try? fm.removeItem(at: tempUrl)
                return
            }

            debugLog("[Download] \(modelId) - HTTP \(httpStatus), received file at \(location.path)")

            // Check for HTTP errors (401, 403, etc.)
            if httpStatus != 200 && httpStatus != 206 {
                debugLog("[Download] \(modelId) - HTTP error: \(httpStatus)")
                // Clean up any temp file
                try? fm.removeItem(at: tempUrl)

                if let continuation = self.downloadContinuations.removeValue(forKey: modelId) {
                    let error = NSError(
                        domain: "QmdManager",
                        code: httpStatus,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpStatus): 服务器拒绝请求"])
                    continuation.resume(throwing: error)
                }
                return
            }

            if let continuation = self.downloadContinuations.removeValue(forKey: modelId) {
                if let error = copyError {
                    debugLog("[Download] \(modelId) - Failed to copy file: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    debugLog("[Download] \(modelId) - File copied to temp: \(fileSize) bytes")
                    continuation.resume(returning: tempUrl)
                }
            } else {
                // No continuation waiting, clean up
                try? fm.removeItem(at: tempUrl)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }

        // Calculate progress - URLSession handles resume internally,
        // so totalBytesWritten/totalBytesExpectedToWrite is always accurate
        let progress = min(1.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))

        Task { @MainActor in
            guard let modelId = self.activeDownloads[downloadTask] else { return }

            // Store progress for resume display
            self.downloadProgress[modelId] = progress

            if let idx = self.models.firstIndex(where: { $0.id == modelId }) {
                self.models[idx].state = .downloading(progress: progress)

                // Log progress at 10% intervals (avoid duplicate logs)
                let percent = Int(progress * 100)
                let lastPercent = self.lastReportedProgress[modelId] ?? -1
                if percent % 10 == 0 && percent > lastPercent {
                    self.lastReportedProgress[modelId] = percent
                    let downloadedMB = Double(totalBytesWritten) / (1024 * 1024)
                    let totalMB = Double(totalBytesExpectedToWrite) / (1024 * 1024)
                    debugLog("[Download] \(modelId) - Progress: \(percent)% (\(String(format: "%.1f", downloadedMB))/\(String(format: "%.1f", totalMB)) MB)")
                }
            }
            self.updateOverallProgress()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in
            if let downloadTask = task as? URLSessionDownloadTask,
               let modelId = self.activeDownloads.removeValue(forKey: downloadTask) {

                // Log the error details
                let errorDesc = self.describeError(error)
                let currentProgress = self.downloadProgress[modelId] ?? 0
                debugLog("[Download] \(modelId) - Task failed at \(Int(currentProgress * 100))%: \(errorDesc)")

                // Try to get resume data from the error
                var savedResumeData = false
                if let nsError = error as NSError? {
                    // Check multiple possible keys for resume data
                    if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                        self.resumeData[modelId] = resumeData
                        savedResumeData = true
                        debugLog("[Download] \(modelId) - Saved resume data: \(resumeData.count) bytes (can resume from \(Int(currentProgress * 100))%)")
                    }
                }

                if !savedResumeData {
                    debugLog("[Download] \(modelId) - No resume data available, will restart from beginning on retry")
                    // Clear stored progress since we can't resume
                    self.downloadProgress.removeValue(forKey: modelId)
                }

                // Log additional error info
                if let urlError = error as? URLError {
                    debugLog("[Download] \(modelId) - URLError code: \(urlError.code.rawValue)")
                }

                if let continuation = self.downloadContinuations.removeValue(forKey: modelId) {
                    continuation.resume(throwing: error)
                }
            } else {
                debugLog("[Download] Task completed with error but no matching download: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        didBecomeInvalidWithError error: Error?
    ) {
        Task { @MainActor in
            if let error {
                debugLog("[Download] Session invalidated with error: \(error.localizedDescription)")
            } else {
                debugLog("[Download] Session invalidated normally")
            }

            // Resume all pending continuations with cancellation error
            for (modelId, continuation) in self.downloadContinuations {
                debugLog("[Download] \(modelId) - Resuming with cancellation due to session invalidation")
                continuation.resume(throwing: URLError(.cancelled))
            }
            self.downloadContinuations.removeAll()
            self.activeDownloads.removeAll()
        }
    }

    // Handle HTTP redirects - ensure User-Agent is preserved on redirect
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var redirectRequest = request
        // Preserve User-Agent header on redirect (some CDNs need this)
        redirectRequest.setValue("OpenClaw/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        redirectRequest.setValue("*/*", forHTTPHeaderField: "Accept")

        Task { @MainActor in
            if let downloadTask = task as? URLSessionDownloadTask,
               let modelId = self.activeDownloads[downloadTask] {
                debugLog("[Download] \(modelId) - Following redirect to: \(request.url?.host ?? "unknown")")
            }
        }

        completionHandler(redirectRequest)
    }
}

// MARK: - Collection Type

struct QmdCollection: Identifiable {
    let name: String
    let path: String
    var fileCount: Int?

    var id: String { self.name }
}
