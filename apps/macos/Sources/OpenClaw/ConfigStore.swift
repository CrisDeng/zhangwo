import OpenClawProtocol
import Foundation

enum ConfigStore {
    /// Error thrown when Gateway is unavailable
    enum ConfigError: LocalizedError {
        case gatewayUnavailable(String)
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .gatewayUnavailable(let reason):
                return "Gateway 不可用: \(reason)"
            case .encodingFailed:
                return "配置编码失败"
            }
        }
    }

    struct Overrides: Sendable {
        var isRemoteMode: (@Sendable () async -> Bool)?
        var loadRemote: (@MainActor @Sendable () async throws -> [String: Any])?
        var saveRemote: (@MainActor @Sendable ([String: Any]) async throws -> Void)?
    }

    private actor OverrideStore {
        var overrides = Overrides()

        func setOverride(_ overrides: Overrides) {
            self.overrides = overrides
        }
    }

    private static let overrideStore = OverrideStore()
    @MainActor private static var lastHash: String?

    private static func isRemoteMode() async -> Bool {
        let overrides = await self.overrideStore.overrides
        if let override = overrides.isRemoteMode {
            return await override()
        }
        return await MainActor.run { AppStateStore.shared.connectionMode == .remote }
    }

    /// Loads config from Gateway. Throws if Gateway is unavailable.
    /// No local fallback - Gateway is the single source of truth for channels/models config.
    @MainActor
    static func load() async throws -> [String: Any] {
        let overrides = await self.overrideStore.overrides
        if let override = overrides.loadRemote {
            return try await override()
        }
        return try await self.loadFromGateway()
    }

    /// Saves config to Gateway. Throws if Gateway is unavailable.
    /// No local fallback - Gateway is the single source of truth for channels/models config.
    @MainActor
    static func save(_ root: sending [String: Any]) async throws {
        let overrides = await self.overrideStore.overrides
        if let override = overrides.saveRemote {
            try await override(root)
        } else {
            try await self.saveToGateway(root)
        }
    }

    @MainActor
    private static func loadFromGateway() async throws -> [String: Any] {
        do {
            let snap: ConfigSnapshot = try await GatewayConnection.shared.requestDecoded(
                method: .configGet,
                params: nil,
                timeoutMs: 8000)
            self.lastHash = snap.hash
            return snap.config?.mapValues { $0.foundationValue } ?? [:]
        } catch {
            throw ConfigError.gatewayUnavailable(error.localizedDescription)
        }
    }

    @MainActor
    private static func saveToGateway(_ root: [String: Any]) async throws {
        if self.lastHash == nil {
            _ = try? await self.loadFromGateway()
        }
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw ConfigError.encodingFailed
        }
        guard let raw = String(data: data, encoding: .utf8) else {
            throw ConfigError.encodingFailed
        }
        var params: [String: AnyCodable] = ["raw": AnyCodable(raw)]
        if let baseHash = self.lastHash {
            params["baseHash"] = AnyCodable(baseHash)
        }
        // Use config.patch instead of config.set to merge with existing config
        // rather than completely overwriting it
        do {
            _ = try await GatewayConnection.shared.requestRaw(
                method: .configPatch,
                params: params,
                timeoutMs: 10000)
            _ = try await self.loadFromGateway()
        } catch {
            throw ConfigError.gatewayUnavailable(error.localizedDescription)
        }
    }

    #if DEBUG
    static func _testSetOverrides(_ overrides: Overrides) async {
        await self.overrideStore.setOverride(overrides)
    }

    static func _testClearOverrides() async {
        await self.overrideStore.setOverride(.init())
    }
    #endif
}
