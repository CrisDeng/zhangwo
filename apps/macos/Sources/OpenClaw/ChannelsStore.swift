import OpenClawProtocol
import Foundation
import Observation

struct ChannelsStatusSnapshot: Codable {
    struct WhatsAppSelf: Codable {
        let e164: String?
        let jid: String?
    }

    struct WhatsAppDisconnect: Codable {
        let at: Double
        let status: Int?
        let error: String?
        let loggedOut: Bool?
    }

    struct WhatsAppStatus: Codable {
        let configured: Bool
        let linked: Bool
        let authAgeMs: Double?
        let `self`: WhatsAppSelf?
        let running: Bool
        let connected: Bool
        let lastConnectedAt: Double?
        let lastDisconnect: WhatsAppDisconnect?
        let reconnectAttempts: Int
        let lastMessageAt: Double?
        let lastEventAt: Double?
        let lastError: String?
    }

    struct TelegramBot: Codable {
        let id: Int?
        let username: String?
    }

    struct TelegramWebhook: Codable {
        let url: String?
        let hasCustomCert: Bool?
    }

    struct TelegramProbe: Codable {
        let ok: Bool
        let status: Int?
        let error: String?
        let elapsedMs: Double?
        let bot: TelegramBot?
        let webhook: TelegramWebhook?
    }

    struct TelegramStatus: Codable {
        let configured: Bool
        let tokenSource: String?
        let running: Bool
        let mode: String?
        let lastStartAt: Double?
        let lastStopAt: Double?
        let lastError: String?
        let probe: TelegramProbe?
        let lastProbeAt: Double?
    }

    struct DiscordBot: Codable {
        let id: String?
        let username: String?
    }

    struct DiscordProbe: Codable {
        let ok: Bool
        let status: Int?
        let error: String?
        let elapsedMs: Double?
        let bot: DiscordBot?
    }

    struct DiscordStatus: Codable {
        let configured: Bool
        let tokenSource: String?
        let running: Bool
        let lastStartAt: Double?
        let lastStopAt: Double?
        let lastError: String?
        let probe: DiscordProbe?
        let lastProbeAt: Double?
    }

    struct GoogleChatProbe: Codable {
        let ok: Bool
        let status: Int?
        let error: String?
        let elapsedMs: Double?
    }

    struct GoogleChatStatus: Codable {
        let configured: Bool
        let credentialSource: String?
        let audienceType: String?
        let audience: String?
        let webhookPath: String?
        let webhookUrl: String?
        let running: Bool
        let lastStartAt: Double?
        let lastStopAt: Double?
        let lastError: String?
        let probe: GoogleChatProbe?
        let lastProbeAt: Double?
    }

    struct SignalProbe: Codable {
        let ok: Bool
        let status: Int?
        let error: String?
        let elapsedMs: Double?
        let version: String?
    }

    struct SignalStatus: Codable {
        let configured: Bool
        let baseUrl: String
        let running: Bool
        let lastStartAt: Double?
        let lastStopAt: Double?
        let lastError: String?
        let probe: SignalProbe?
        let lastProbeAt: Double?
    }

    struct IMessageProbe: Codable {
        let ok: Bool
        let error: String?
    }

    struct IMessageStatus: Codable {
        let configured: Bool
        let running: Bool
        let lastStartAt: Double?
        let lastStopAt: Double?
        let lastError: String?
        let cliPath: String?
        let dbPath: String?
        let probe: IMessageProbe?
        let lastProbeAt: Double?
    }

    struct QQProbe: Codable {
        let ok: Bool
        let status: Int?
        let error: String?
        let elapsedMs: Double?
    }

    struct QQStatus: Codable {
        let configured: Bool
        let running: Bool
        let connected: Bool
        let appId: String?
        let lastStartAt: Double?
        let lastStopAt: Double?
        let lastError: String?
        let probe: QQProbe?
        let lastProbeAt: Double?
    }

    struct ChannelAccountSnapshot: Codable {
        let accountId: String
        let name: String?
        let enabled: Bool?
        let configured: Bool?
        let linked: Bool?
        let running: Bool?
        let connected: Bool?
        let reconnectAttempts: Int?
        let lastConnectedAt: Double?
        let lastError: String?
        let lastStartAt: Double?
        let lastStopAt: Double?
        let lastInboundAt: Double?
        let lastOutboundAt: Double?
        let lastProbeAt: Double?
        let mode: String?
        let dmPolicy: String?
        let allowFrom: [String]?
        let tokenSource: String?
        let botTokenSource: String?
        let appTokenSource: String?
        let baseUrl: String?
        let allowUnmentionedGroups: Bool?
        let cliPath: String?
        let dbPath: String?
        let port: Int?
        let probe: AnyCodable?
        let audit: AnyCodable?
        let application: AnyCodable?
    }

    struct ChannelUiMetaEntry: Codable {
        let id: String
        let label: String
        let detailLabel: String
        let systemImage: String?
    }

    let ts: Double
    let channelOrder: [String]
    let channelLabels: [String: String]
    let channelDetailLabels: [String: String]?
    let channelSystemImages: [String: String]?
    let channelMeta: [ChannelUiMetaEntry]?
    let channels: [String: AnyCodable]
    let channelAccounts: [String: [ChannelAccountSnapshot]]
    let channelDefaultAccountId: [String: String]

    func decodeChannel<T: Decodable>(_ id: String, as type: T.Type) -> T? {
        guard let value = self.channels[id] else { return nil }
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}

struct ConfigSnapshot: Codable {
    struct Issue: Codable {
        let path: String
        let message: String
    }

    let path: String?
    let exists: Bool?
    let raw: String?
    let hash: String?
    let parsed: AnyCodable?
    let valid: Bool?
    let config: [String: AnyCodable]?
    let issues: [Issue]?
}

@MainActor
@Observable
final class ChannelsStore {
    static let shared = ChannelsStore()

    var snapshot: ChannelsStatusSnapshot?
    var lastError: String?
    var lastSuccess: Date?
    var isRefreshing = false

    var whatsappLoginMessage: String?
    var whatsappLoginQrDataUrl: String?
    var whatsappLoginConnected: Bool?
    var whatsappBusy = false
    var telegramBusy = false

    // QQ Channel 相关状态
    var qqTestingConnection = false
    var qqConnectionTestResult: QQConnectionTestResult?

    struct QQConnectionTestResult {
        let success: Bool
        let message: String?
    }

    var configStatus: String?
    var isSavingConfig = false
    var configSchemaLoading = false
    var configSchema: ConfigSchemaNode?
    var configUiHints: [String: ConfigUiHint] = [:]
    var configDraft: [String: Any] = [:]
    var configDirty = false

    // MARK: - 提供商配置相关状态

    /// 配置保存结果反馈
    enum ConfigSaveResult {
        case success
        case error(String)
    }
    var configSaveResult: ConfigSaveResult?
    var showConfigSaveToast = false

    /// 提供商配置状态缓存
    var providerConfigStatuses: [String: ProviderConfigStatus] = [:]

    /// 当前正在测试连接的提供商
    var testingProviders: Set<String> = []

    /// 连接测试结果
    var providerTestResults: [String: Bool] = [:]

    let interval: TimeInterval = 45
    let isPreview: Bool
    var pollTask: Task<Void, Never>?
    var configRoot: [String: Any] = [:]
    var configLoaded = false

    func channelMetaEntry(_ id: String) -> ChannelsStatusSnapshot.ChannelUiMetaEntry? {
        self.snapshot?.channelMeta?.first(where: { $0.id == id })
    }

    func resolveChannelLabel(_ id: String) -> String {
        if let meta = self.channelMetaEntry(id), !meta.label.isEmpty {
            return meta.label
        }
        if let label = self.snapshot?.channelLabels[id], !label.isEmpty {
            return label
        }
        return id
    }

    func resolveChannelDetailLabel(_ id: String) -> String {
        if let meta = self.channelMetaEntry(id), !meta.detailLabel.isEmpty {
            return meta.detailLabel
        }
        if let detail = self.snapshot?.channelDetailLabels?[id], !detail.isEmpty {
            return detail
        }
        return self.resolveChannelLabel(id)
    }

    func resolveChannelSystemImage(_ id: String) -> String {
        if let meta = self.channelMetaEntry(id), let symbol = meta.systemImage, !symbol.isEmpty {
            return symbol
        }
        if let symbol = self.snapshot?.channelSystemImages?[id], !symbol.isEmpty {
            return symbol
        }
        return "message"
    }

    func orderedChannelIds() -> [String] {
        if let meta = self.snapshot?.channelMeta, !meta.isEmpty {
            return meta.map(\.id)
        }
        return self.snapshot?.channelOrder ?? []
    }

    func testQQConnection() async {
        guard !self.qqTestingConnection else { return }
        self.qqTestingConnection = true
        self.qqConnectionTestResult = nil
        defer { self.qqTestingConnection = false }

        do {
            // 调用 gateway 的 channels.status 接口获取 QQ 连接状态
            let result: ChannelsStatusSnapshot = try await GatewayConnection.shared.requestDecoded(
                method: .channelsStatus,
                params: [:])
            if let qqStatus = result.decodeChannel("qqbot", as: ChannelsStatusSnapshot.QQStatus.self) {
                if qqStatus.connected {
                    self.qqConnectionTestResult = QQConnectionTestResult(success: true, message: nil)
                } else if qqStatus.running {
                    self.qqConnectionTestResult = QQConnectionTestResult(
                        success: false, message: "Running but not connected")
                } else if !qqStatus.configured {
                    self.qqConnectionTestResult = QQConnectionTestResult(
                        success: false, message: "Not configured")
                } else if let err = qqStatus.lastError {
                    self.qqConnectionTestResult = QQConnectionTestResult(success: false, message: err)
                } else {
                    self.qqConnectionTestResult = QQConnectionTestResult(
                        success: false, message: "Not connected")
                }
            } else {
                self.qqConnectionTestResult = QQConnectionTestResult(
                    success: false, message: "QQ channel not available")
            }
        } catch {
            self.qqConnectionTestResult = QQConnectionTestResult(success: false, message: error.localizedDescription)
        }
    }

    init(isPreview: Bool = ProcessInfo.processInfo.isPreview) {
        self.isPreview = isPreview
    }

    // MARK: - 提供商配置方法

    /// 获取提供商的配置状态
    func providerStatus(for providerId: String) -> ProviderConfigStatus {
        if let cached = providerConfigStatuses[providerId] {
            return cached
        }
        // 检查环境变量是否配置
        guard let template = ProviderTemplates.template(for: providerId) else {
            return .notConfigured
        }
        let envDict = configDraft["env"] as? [String: Any] ?? [:]
        let hasKey = template.envKeys.contains { key in
            if let value = envDict[key] as? String, !value.isEmpty {
                return true
            }
            return false
        }
        let status: ProviderConfigStatus = hasKey ? .configured : .notConfigured
        providerConfigStatuses[providerId] = status
        return status
    }

    /// 更新提供商配置
    func updateProviderConfig(_ config: ProviderConfig) {
        guard let template = ProviderTemplates.template(for: config.providerId) else { return }

        // 更新环境变量
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            if let envKey = template.envKeys.first {
                updateConfigValue(path: [.key("env"), .key(envKey)], value: apiKey)
            }
        }

        // 更新默认模型
        if let model = config.fullModelRef {
            updateConfigValue(
                path: [.key("agents"), .key("defaults"), .key("model"), .key("primary")],
                value: model)
        }

        // 更新 provider 配置（如果有自定义 baseUrl）
        if let baseUrl = config.customBaseUrl, !baseUrl.isEmpty {
            updateConfigValue(
                path: [.key("models"), .key("providers"), .key(config.providerId), .key("baseUrl")],
                value: baseUrl)
        }

        // 清除缓存状态
        providerConfigStatuses.removeValue(forKey: config.providerId)
    }

    /// 测试提供商连接
    func testProviderConnection(providerId: String) async -> Bool {
        guard !testingProviders.contains(providerId) else { return false }
        testingProviders.insert(providerId)
        defer { testingProviders.remove(providerId) }

        // 简单的连接测试 - 通过 gateway 验证
        do {
            // 使用 models list 接口检查提供商状态
            let params: [String: AnyCodable] = ["provider": AnyCodable(providerId)]
            let _: AnyCodable = try await GatewayConnection.shared.requestDecoded(
                method: .modelsList,
                params: params,
                timeoutMs: 10000)
            providerTestResults[providerId] = true
            providerConfigStatuses[providerId] = .verified
            return true
        } catch {
            providerTestResults[providerId] = false
            providerConfigStatuses[providerId] = .error(error.localizedDescription)
            return false
        }
    }

    /// 保存配置并显示反馈
    func saveConfigWithFeedback() async {
        guard !isSavingConfig else { return }
        isSavingConfig = true
        configSaveResult = nil
        defer { isSavingConfig = false }

        do {
            try await ConfigStore.save(configDraft)
            await loadConfig()
            configSaveResult = .success
            showConfigSaveToast = true

            // 清除提供商状态缓存，重新加载
            providerConfigStatuses.removeAll()

            // 3 秒后自动隐藏 toast
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.showConfigSaveToast = false
            }
        } catch {
            configSaveResult = .error(error.localizedDescription)
            showConfigSaveToast = true
            configStatus = error.localizedDescription
        }
    }

    /// 获取当前配置的默认模型
    func currentDefaultModel() -> String? {
        let agents = configDraft["agents"] as? [String: Any]
        let defaults = agents?["defaults"] as? [String: Any]
        let model = defaults?["model"] as? [String: Any]
        return model?["primary"] as? String
    }

    /// 获取已配置的提供商列表
    func configuredProviders() -> [ProviderTemplate] {
        return ProviderTemplates.all.filter { template in
            providerStatus(for: template.id).isConfigured
        }
    }
}