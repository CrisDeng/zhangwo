import SwiftUI

// MARK: - 提供商配置表单容器

/// 提供商配置表单的统一容器视图
struct ProviderConfigFormView: View {
    let template: ProviderTemplate
    @Bindable var store: ChannelsStore
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var apiKey: String = ""
    @State private var selectedModel: String = ""
    @State private var customBaseUrl: String = ""
    @State private var authType: ProviderAuthType = .apiKey
    @State private var isSaving = false
    @State private var errorMessage: String?

    // 高级设置状态
    @State private var customApiType: String = ""
    @State private var inputTypes: Set<String> = ["text"]
    @State private var costInput: String = "15"
    @State private var costOutput: String = "60"
    @State private var costCacheRead: String = "2"
    @State private var costCacheWrite: String = "10"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 头部
            formHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 根据提供商类型显示不同的表单
                    switch template.id {
                    case "anthropic":
                        AnthropicConfigSection(
                            apiKey: $apiKey,
                            authType: $authType,
                            template: template)
                    case "openai":
                        OpenAIConfigSection(
                            apiKey: $apiKey,
                            authType: $authType,
                            template: template)
                    case "openai-codex":
                        CodexConfigSection(template: template)
                    case "ollama":
                        OllamaConfigSection(
                            customBaseUrl: $customBaseUrl,
                            selectedModel: $selectedModel,
                            template: template,
                            store: store)
                    case "qwen-portal":
                        QwenConfigSection(template: template)
                    default:
                        // 通用 API 密钥表单
                        SimpleAPIKeyConfigSection(
                            apiKey: $apiKey,
                            template: template)
                    }

                    // 模型选择（非 OAuth 和本地提供商）
                    if !template.authTypes.contains(.oauth) && !template.isLocal {
                        modelSelectionSection
                    }

                    // Base URL 配置（非本地提供商）
                    if !template.isLocal {
                        baseUrlSection
                    }

                    // 高级设置
                    if !template.isLocal {
                        advancedSettingsSection
                    }

                    // 帮助信息
                    helpInfoSection

                    // 错误显示
                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.callout)
                                .foregroundStyle(.red)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, 4)
            }

            Divider()

            // 底部操作按钮
            actionButtons
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            loadExistingConfig()
        }
    }

    // MARK: - 表单头部

    private var formHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: template.icon)
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("配置 \(template.name)")
                    .font(.title2.weight(.semibold))
                Text(template.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.providerStatus(for: template.id).isConfigured {
                Label("已配置", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - 模型选择

    private var modelSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("默认模型")
                .font(.headline)

            Picker("选择模型", selection: $selectedModel) {
                Text("选择模型...").tag("")
                ForEach(template.models) { model in
                    HStack {
                        Text(model.name)
                        if model.isDefault {
                            Text("(推荐)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(model.id)
                }
            }
            .pickerStyle(.menu)

            if let model = template.models.first(where: { $0.id == selectedModel }) {
                HStack(spacing: 16) {
                    if let desc = model.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.reasoning {
                        Label("推理", systemImage: "brain")
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }
                    Text("\(model.contextWindow / 1000)K 上下文")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - Base URL 配置

    private var baseUrlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Base URL")
                .font(.headline)

            TextField(
                template.baseUrl ?? "使用默认 URL",
                text: $customBaseUrl)
                .textFieldStyle(.roundedBorder)

            Text("留空使用默认值: \(template.baseUrl ?? "内置默认")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - 高级设置

    @State private var showAdvanced = false

    private var advancedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    showAdvanced.toggle()
                }
            } label: {
                HStack {
                    Text("高级设置")
                        .font(.headline)
                    Spacer()
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showAdvanced {
                VStack(alignment: .leading, spacing: 16) {
                    // API 类型选择
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API 类型")
                            .font(.callout.weight(.medium))
                        Picker("API 类型", selection: $customApiType) {
                            Text("使用默认 (\(template.apiType))").tag("")
                            Text("OpenAI Completions").tag("openai-completions")
                            Text("Anthropic Messages").tag("anthropic-messages")
                        }
                        .pickerStyle(.menu)
                        Text("指定 API 请求格式，不同提供商可能使用不同的 API 协议")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // 输入类型
                    VStack(alignment: .leading, spacing: 6) {
                        Text("输入类型")
                            .font(.callout.weight(.medium))
                        HStack(spacing: 12) {
                            Toggle("文本", isOn: Binding(
                                get: { inputTypes.contains("text") },
                                set: { if $0 { inputTypes.insert("text") } else { inputTypes.remove("text") } }
                            ))
                            Toggle("图片", isOn: Binding(
                                get: { inputTypes.contains("image") },
                                set: { if $0 { inputTypes.insert("image") } else { inputTypes.remove("image") } }
                            ))
                        }
                        .toggleStyle(.checkbox)
                        Text("指定模型支持的输入类型")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // 成本配置
                    VStack(alignment: .leading, spacing: 8) {
                        Text("成本配置 (每百万 token)")
                            .font(.callout.weight(.medium))

                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("输入成本")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("15", text: $costInput)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("输出成本")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("60", text: $costOutput)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("缓存读取")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("2", text: $costCacheRead)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("缓存写入")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("10", text: $costCacheWrite)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        Text("用于计算 API 调用费用的单价配置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - 帮助信息

    private var helpInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("获取帮助")
                .font(.headline)

            if let docUrl = template.documentationUrl {
                Link(destination: URL(string: docUrl)!) {
                    Label("查看官方文档", systemImage: "book")
                }
            }

            if let apiKeyUrl = template.apiKeyUrl {
                Link(destination: URL(string: apiKeyUrl)!) {
                    Label("获取 API 密钥", systemImage: "key")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.05)))
    }

    // MARK: - 操作按钮

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("取消") {
                onCancel()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                Task { await saveConfig() }
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(isSaving ? "保存中..." : "保存配置")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || !isValidConfig)
        }
    }

    // MARK: - 数据处理

    private var isValidConfig: Bool {
        // OAuth 和本地提供商不需要 API 密钥
        if template.authTypes.contains(.oauth) || template.isLocal {
            return true
        }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadExistingConfig() {
        // 加载现有的 API 密钥
        if let envKey = template.envKeys.first {
            let envDict = store.configDraft["env"] as? [String: Any] ?? [:]
            if let existingKey = envDict[envKey] as? String {
                apiKey = existingKey
            }
        }

        // 加载现有的默认模型
        if let currentModel = store.currentDefaultModel() {
            // 检查是否属于当前提供商
            if currentModel.hasPrefix(template.id + "/") {
                let modelId = String(currentModel.dropFirst(template.id.count + 1))
                selectedModel = modelId
            }
        }

        // 如果没有选择模型，使用默认模型
        if selectedModel.isEmpty {
            selectedModel = template.models.first(where: { $0.isDefault })?.id
                ?? template.models.first?.id
                ?? ""
        }

        // 设置默认认证类型
        authType = template.authTypes.first ?? .apiKey

        // 加载现有的高级配置
        if let modelsDict = store.configDraft["models"] as? [String: Any],
           let providersDict = modelsDict["providers"] as? [String: Any],
           let providerConfig = providersDict[template.id] as? [String: Any] {

            // 加载自定义 Base URL
            if let baseUrl = providerConfig["baseUrl"] as? String,
               baseUrl != template.baseUrl {
                customBaseUrl = baseUrl
            }

            // 加载自定义 API 类型
            if let apiType = providerConfig["api"] as? String,
               apiType != template.apiType {
                customApiType = apiType
            }

            // 加载 API 密钥（如果 env 中没有）
            if apiKey.isEmpty, let key = providerConfig["apiKey"] as? String {
                apiKey = key
            }

            // 从第一个模型加载 input 类型和 cost 配置
            if let models = providerConfig["models"] as? [[String: Any]],
               let firstModel = models.first {

                // 加载 input 类型
                if let inputs = firstModel["input"] as? [String] {
                    inputTypes = Set(inputs)
                }

                // 加载 cost 配置
                if let cost = firstModel["cost"] as? [String: Any] {
                    if let input = cost["input"] as? Int {
                        costInput = String(input)
                    }
                    if let output = cost["output"] as? Int {
                        costOutput = String(output)
                    }
                    if let cacheRead = cost["cacheRead"] as? Int {
                        costCacheRead = String(cacheRead)
                    }
                    if let cacheWrite = cost["cacheWrite"] as? Int {
                        costCacheWrite = String(cacheWrite)
                    }
                }
            }
        }
    }

    private func saveConfig() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        // 构建成本配置
        let cost = ModelCost(
            input: Int(costInput) ?? 15,
            output: Int(costOutput) ?? 60,
            cacheRead: Int(costCacheRead) ?? 2,
            cacheWrite: Int(costCacheWrite) ?? 10
        )

        // 创建配置
        let config = ProviderConfig(
            providerId: template.id,
            apiKey: trimmedKey.isEmpty ? nil : trimmedKey,
            selectedModel: selectedModel.isEmpty ? nil : selectedModel,
            customBaseUrl: customBaseUrl.isEmpty ? nil : customBaseUrl,
            customApiType: customApiType.isEmpty ? nil : customApiType,
            inputTypes: Array(inputTypes),
            modelCost: cost)

        // 更新配置
        store.updateProviderConfig(config)

        // 保存到文件
        await store.saveConfigDraft()

        // 检查保存结果
        if case .error(let msg) = store.configSaveResult {
            errorMessage = msg
        } else {
            onSave()
        }
    }
}

// MARK: - Anthropic 配置区

struct AnthropicConfigSection: View {
    @Binding var apiKey: String
    @Binding var authType: ProviderAuthType
    let template: ProviderTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("认证方式")
                .font(.headline)

            Picker("认证方式", selection: $authType) {
                Text("API 密钥").tag(ProviderAuthType.apiKey)
                Text("Setup Token").tag(ProviderAuthType.setupToken)
            }
            .pickerStyle(.segmented)

            switch authType {
            case .apiKey:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Anthropic API 密钥")
                        .font(.callout.weight(.medium))
                    SecureField("sk-ant-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("在 Anthropic Console 创建 API 密钥")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .setupToken:
                VStack(alignment: .leading, spacing: 8) {
                    Text("使用 Setup Token")
                        .font(.callout.weight(.medium))
                    Text("""
                        Setup Token 由 Claude Code CLI 创建，而非 Anthropic Console。
                        
                        运行以下命令获取 token：
                        """)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("claude setup-token")
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("claude setup-token", forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("复制命令")
                    }

                    Text("然后将 token 粘贴到 API 密钥字段")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("粘贴 setup-token...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
            default:
                EmptyView()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - OpenAI 配置区

struct OpenAIConfigSection: View {
    @Binding var apiKey: String
    @Binding var authType: ProviderAuthType
    let template: ProviderTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("认证方式")
                .font(.headline)

            Picker("认证方式", selection: $authType) {
                Text("API 密钥").tag(ProviderAuthType.apiKey)
                Text("Codex 订阅").tag(ProviderAuthType.oauth)
            }
            .pickerStyle(.segmented)

            switch authType {
            case .apiKey:
                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenAI API 密钥")
                        .font(.callout.weight(.medium))
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("在 OpenAI Platform 获取 API 密钥")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .oauth:
                VStack(alignment: .leading, spacing: 8) {
                    Text("使用 Codex 订阅")
                        .font(.callout.weight(.medium))
                    Text("Codex 订阅通过 ChatGPT 登录认证，而非 API 密钥。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        // TODO: 触发 OAuth 流程
                    } label: {
                        Label("使用 ChatGPT 登录", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            default:
                EmptyView()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - Codex 配置区

struct CodexConfigSection: View {
    let template: ProviderTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codex 订阅认证")
                .font(.headline)

            Text("通过 ChatGPT 登录使用您的 Codex 订阅额度。")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                // TODO: 触发 OAuth 流程
            } label: {
                Label("使用 ChatGPT 登录", systemImage: "person.crop.circle")
            }
            .buttonStyle(.borderedProminent)

            Text("注意：Codex Cloud 必须使用 ChatGPT 登录。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - Qwen 配置区

struct QwenConfigSection: View {
    let template: ProviderTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Qwen OAuth 认证")
                .font(.headline)

            Text("Qwen 提供免费层 OAuth 访问（每日 2000 次请求）。")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. 首先启用插件：")
                    .font(.caption.weight(.medium))

                HStack {
                    Text("openclaw plugins enable qwen-portal-auth")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("openclaw plugins enable qwen-portal-auth", forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }

                Text("2. 然后运行认证命令：")
                    .font(.caption.weight(.medium))

                HStack {
                    Text("openclaw models auth login --provider qwen-portal --set-default")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            "openclaw models auth login --provider qwen-portal --set-default",
                            forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - 简单 API 密钥配置区

struct SimpleAPIKeyConfigSection: View {
    @Binding var apiKey: String
    let template: ProviderTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API 密钥")
                .font(.headline)

            if let envKey = template.envKeys.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(template.name) API 密钥")
                        .font(.callout.weight(.medium))
                    SecureField("输入 API 密钥...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("环境变量: \(envKey)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 获取密钥的说明
            if let apiKeyUrl = template.apiKeyUrl {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Link("点击此处获取 API 密钥", destination: URL(string: apiKeyUrl)!)
                        .font(.caption)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - Ollama 配置区（将在任务 9 中完善）

struct OllamaConfigSection: View {
    @Binding var customBaseUrl: String
    @Binding var selectedModel: String
    let template: ProviderTemplate
    @Bindable var store: ChannelsStore

    @State private var isCheckingService = false
    @State private var serviceStatus: OllamaServiceStatus = .unknown
    @State private var availableModels: [String] = []

    enum OllamaServiceStatus {
        case unknown
        case running
        case notRunning
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ollama 本地服务")
                .font(.headline)

            // 服务状态
            HStack(spacing: 12) {
                switch serviceStatus {
                case .unknown:
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.secondary)
                    Text("未检测服务状态")
                        .foregroundStyle(.secondary)
                case .running:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Ollama 服务运行中")
                        .foregroundStyle(.green)
                case .notRunning:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Ollama 服务未运行")
                        .foregroundStyle(.red)
                case .error(let msg):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(msg)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button {
                    Task { await checkService() }
                } label: {
                    if isCheckingService {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                    } else {
                        Label("检测服务", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isCheckingService)
            }

            // 服务未运行时显示安装说明
            if case .notRunning = serviceStatus {
                VStack(alignment: .leading, spacing: 8) {
                    Text("安装 Ollama")
                        .font(.callout.weight(.medium))
                    Link("前往 ollama.ai 下载", destination: URL(string: "https://ollama.ai")!)

                    Text("启动服务")
                        .font(.callout.weight(.medium))
                        .padding(.top, 4)

                    HStack {
                        Text("ollama serve")
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("ollama serve", forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // 模型列表
            if case .running = serviceStatus, !availableModels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("可用模型")
                        .font(.callout.weight(.medium))

                    Picker("选择模型", selection: $selectedModel) {
                        Text("选择模型...").tag("")
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            // Base URL 配置
            VStack(alignment: .leading, spacing: 8) {
                Text("服务地址")
                    .font(.callout.weight(.medium))
                TextField("http://127.0.0.1:11434", text: $customBaseUrl)
                    .textFieldStyle(.roundedBorder)
                Text("默认地址: http://127.0.0.1:11434")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
        .onAppear {
            Task { await checkService() }
        }
    }

    private func checkService() async {
        isCheckingService = true
        defer { isCheckingService = false }

        let baseUrl = customBaseUrl.isEmpty ? "http://127.0.0.1:11434" : customBaseUrl
        guard let url = URL(string: "\(baseUrl)/api/tags") else {
            serviceStatus = .error("无效的 URL")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                serviceStatus = .notRunning
                return
            }

            // 解析模型列表
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                availableModels = models.compactMap { $0["name"] as? String }
                serviceStatus = .running
            } else {
                serviceStatus = .running
                availableModels = []
            }
        } catch {
            serviceStatus = .notRunning
        }
    }
}
