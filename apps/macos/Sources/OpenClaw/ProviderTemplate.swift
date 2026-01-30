import Foundation

// MARK: - 认证类型枚举

/// 提供商支持的认证方式类型
enum ProviderAuthType: String, CaseIterable, Identifiable, Codable {
    case apiKey = "api_key"              // API 密钥
    case setupToken = "setup_token"      // Claude setup-token
    case oauth = "oauth"                 // OAuth 登录
    case local = "local"                 // 本地服务（如 Ollama）

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .apiKey: return "API 密钥"
        case .setupToken: return "Setup Token"
        case .oauth: return "OAuth 登录"
        case .local: return "本地服务"
        }
    }
}

// MARK: - 模型信息

/// 提供商推荐的模型信息
struct ProviderModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String?
    let reasoning: Bool
    let contextWindow: Int
    let maxTokens: Int
    let isDefault: Bool

    init(
        id: String,
        name: String,
        description: String? = nil,
        reasoning: Bool = false,
        contextWindow: Int = 131072,
        maxTokens: Int = 8192,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.reasoning = reasoning
        self.contextWindow = contextWindow
        self.maxTokens = maxTokens
        self.isDefault = isDefault
    }
}

// MARK: - 提供商模板

/// 模型提供商配置模板
struct ProviderTemplate: Identifiable, Codable {
    let id: String                       // 提供商唯一标识符
    let name: String                     // 显示名称
    let icon: String                     // SF Symbol 名称
    let description: String              // 简短描述
    let authTypes: [ProviderAuthType]    // 支持的认证方式
    let envKeys: [String]                // 需要配置的环境变量名
    let defaultModel: String             // 默认模型 ID（完整格式：provider/model）
    let baseUrl: String?                 // API 基础 URL（可选）
    let apiType: String                  // API 类型（openai-completions, anthropic-messages）
    let models: [ProviderModel]          // 推荐模型列表
    let documentationUrl: String?        // 官方文档链接
    let apiKeyUrl: String?               // 获取 API 密钥的链接
    let features: [String]               // 特性标签
    let isLocal: Bool                    // 是否为本地服务

    init(
        id: String,
        name: String,
        icon: String,
        description: String,
        authTypes: [ProviderAuthType],
        envKeys: [String],
        defaultModel: String,
        baseUrl: String? = nil,
        apiType: String = "openai-completions",
        models: [ProviderModel] = [],
        documentationUrl: String? = nil,
        apiKeyUrl: String? = nil,
        features: [String] = [],
        isLocal: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.authTypes = authTypes
        self.envKeys = envKeys
        self.defaultModel = defaultModel
        self.baseUrl = baseUrl
        self.apiType = apiType
        self.models = models
        self.documentationUrl = documentationUrl
        self.apiKeyUrl = apiKeyUrl
        self.features = features
        self.isLocal = isLocal
    }

    /// 模型引用格式 (provider/model)
    func modelRef(for modelId: String) -> String {
        return "\(id)/\(modelId)"
    }
}

// MARK: - 提供商模板目录

/// 所有支持的提供商模板
enum ProviderTemplates {

    // MARK: - Anthropic (Claude)

    static let anthropic = ProviderTemplate(
        id: "anthropic",
        name: "Anthropic (Claude)",
        icon: "brain.head.profile",
        description: "Claude 模型家族，支持 API 密钥和 setup-token 认证",
        authTypes: [.apiKey, .setupToken],
        envKeys: ["ANTHROPIC_API_KEY"],
        defaultModel: "anthropic/claude-opus-4-5",
        baseUrl: nil, // 使用默认
        apiType: "anthropic-messages",
        models: [
            ProviderModel(
                id: "claude-opus-4-5",
                name: "Claude Opus 4.5",
                description: "最强大的推理和编码能力",
                reasoning: true,
                contextWindow: 200000,
                maxTokens: 8192,
                isDefault: true
            ),
            ProviderModel(
                id: "claude-sonnet-4-5",
                name: "Claude Sonnet 4.5",
                description: "平衡性能与速度",
                reasoning: true,
                contextWindow: 200000,
                maxTokens: 8192
            ),
            ProviderModel(
                id: "claude-haiku-3-5",
                name: "Claude Haiku 3.5",
                description: "快速响应，适合简单任务",
                reasoning: false,
                contextWindow: 200000,
                maxTokens: 8192
            )
        ],
        documentationUrl: "https://docs.anthropic.com",
        apiKeyUrl: "https://console.anthropic.com/settings/keys",
        features: ["强大推理", "长上下文", "视觉能力"]
    )

    // MARK: - OpenAI

    static let openai = ProviderTemplate(
        id: "openai",
        name: "OpenAI",
        icon: "sparkles.rectangle.stack",
        description: "GPT 模型系列，支持 API 密钥和 Codex 订阅",
        authTypes: [.apiKey, .oauth],
        envKeys: ["OPENAI_API_KEY"],
        defaultModel: "openai/gpt-5.2",
        baseUrl: nil,
        apiType: "openai-completions",
        models: [
            ProviderModel(
                id: "gpt-5.2",
                name: "GPT-5.2",
                description: "最新 GPT 模型",
                reasoning: true,
                contextWindow: 262144,
                maxTokens: 16384,
                isDefault: true
            ),
            ProviderModel(
                id: "gpt-4.5-turbo",
                name: "GPT-4.5 Turbo",
                description: "高性能通用模型",
                reasoning: true,
                contextWindow: 128000,
                maxTokens: 8192
            ),
            ProviderModel(
                id: "o1",
                name: "o1",
                description: "高级推理模型",
                reasoning: true,
                contextWindow: 200000,
                maxTokens: 100000
            )
        ],
        documentationUrl: "https://platform.openai.com/docs",
        apiKeyUrl: "https://platform.openai.com/api-keys",
        features: ["函数调用", "JSON 模式", "视觉能力"]
    )

    // MARK: - OpenAI Codex

    static let openaiCodex = ProviderTemplate(
        id: "openai-codex",
        name: "OpenAI Codex",
        icon: "terminal.fill",
        description: "使用 ChatGPT/Codex 订阅访问",
        authTypes: [.oauth],
        envKeys: [],
        defaultModel: "openai-codex/gpt-5.2",
        baseUrl: nil,
        apiType: "openai-completions",
        models: [
            ProviderModel(
                id: "gpt-5.2",
                name: "GPT-5.2 (Codex)",
                description: "通过 Codex 订阅访问",
                reasoning: true,
                contextWindow: 262144,
                maxTokens: 16384,
                isDefault: true
            )
        ],
        documentationUrl: "https://platform.openai.com/docs",
        apiKeyUrl: nil,
        features: ["订阅访问", "无需 API 密钥"]
    )

    // MARK: - Venice AI

    static let venice = ProviderTemplate(
        id: "venice",
        name: "Venice AI",
        icon: "lock.shield",
        description: "隐私优先的 AI 推理服务，支持私有和匿名模式",
        authTypes: [.apiKey],
        envKeys: ["VENICE_API_KEY"],
        defaultModel: "venice/llama-3.3-70b",
        baseUrl: "https://api.venice.ai/api/v1",
        apiType: "openai-completions",
        models: [
            ProviderModel(
                id: "llama-3.3-70b",
                name: "Llama 3.3 70B",
                description: "全私有，通用模型",
                reasoning: false,
                contextWindow: 131072,
                maxTokens: 8192,
                isDefault: true
            ),
            ProviderModel(
                id: "claude-opus-45",
                name: "Claude Opus 4.5 (匿名)",
                description: "通过 Venice 代理访问 Claude",
                reasoning: true,
                contextWindow: 202000,
                maxTokens: 8192
            ),
            ProviderModel(
                id: "deepseek-v3.2",
                name: "DeepSeek V3.2",
                description: "强大推理，全私有",
                reasoning: true,
                contextWindow: 163840,
                maxTokens: 8192
            ),
            ProviderModel(
                id: "qwen3-coder-480b-a35b-instruct",
                name: "Qwen3 Coder 480B",
                description: "代码优化，262k 上下文",
                reasoning: false,
                contextWindow: 262144,
                maxTokens: 8192
            ),
            ProviderModel(
                id: "venice-uncensored",
                name: "Venice Uncensored",
                description: "无内容限制",
                reasoning: false,
                contextWindow: 32768,
                maxTokens: 8192
            )
        ],
        documentationUrl: "https://docs.venice.ai",
        apiKeyUrl: "https://venice.ai/settings",
        features: ["隐私优先", "无日志", "匿名代理"]
    )

    // MARK: - Ollama (本地)

    static let ollama = ProviderTemplate(
        id: "ollama",
        name: "Ollama",
        icon: "desktopcomputer",
        description: "本地运行开源模型，无需 API 密钥",
        authTypes: [.local],
        envKeys: ["OLLAMA_API_KEY"],
        defaultModel: "ollama/llama3.3",
        baseUrl: "http://127.0.0.1:11434/v1",
        apiType: "openai-completions",
        models: [
            ProviderModel(
                id: "llama3.3",
                name: "Llama 3.3",
                description: "Meta 最新开源模型",
                reasoning: false,
                contextWindow: 8192,
                maxTokens: 81920,
                isDefault: true
            ),
            ProviderModel(
                id: "qwen2.5-coder:32b",
                name: "Qwen 2.5 Coder 32B",
                description: "代码专用模型",
                reasoning: false,
                contextWindow: 32768,
                maxTokens: 327680
            ),
            ProviderModel(
                id: "deepseek-r1:32b",
                name: "DeepSeek R1 32B",
                description: "推理模型",
                reasoning: true,
                contextWindow: 32768,
                maxTokens: 327680
            ),
            ProviderModel(
                id: "mistral",
                name: "Mistral",
                description: "高效通用模型",
                reasoning: false,
                contextWindow: 32768,
                maxTokens: 327680
            )
        ],
        documentationUrl: "https://ollama.ai",
        apiKeyUrl: nil,
        features: ["本地运行", "免费", "隐私安全"],
        isLocal: true
    )

    // MARK: - OpenRouter

    static let openrouter = ProviderTemplate(
        id: "openrouter",
        name: "OpenRouter",
        icon: "arrow.triangle.branch",
        description: "统一 API 访问多种模型",
        authTypes: [.apiKey],
        envKeys: ["OPENROUTER_API_KEY"],
        defaultModel: "openrouter/anthropic/claude-sonnet-4-5",
        baseUrl: "https://openrouter.ai/api/v1",
        apiType: "openai-completions",
        models: [
            ProviderModel(
                id: "anthropic/claude-sonnet-4-5",
                name: "Claude Sonnet 4.5",
                description: "通过 OpenRouter 访问",
                reasoning: true,
                contextWindow: 200000,
                maxTokens: 8192,
                isDefault: true
            ),
            ProviderModel(
                id: "openai/gpt-5.2",
                name: "GPT-5.2",
                description: "通过 OpenRouter 访问",
                reasoning: true,
                contextWindow: 262144,
                maxTokens: 16384
            ),
            ProviderModel(
                id: "google/gemini-3-pro",
                name: "Gemini 3 Pro",
                description: "通过 OpenRouter 访问",
                reasoning: true,
                contextWindow: 200000,
                maxTokens: 8192
            )
        ],
        documentationUrl: "https://openrouter.ai/docs",
        apiKeyUrl: "https://openrouter.ai/keys",
        features: ["统一接口", "多模型", "灵活计费"]
    )

    // MARK: - Moonshot (Kimi)

    static let moonshot = ProviderTemplate(
        id: "moonshot",
        name: "Moonshot AI (Kimi)",
        icon: "moon.stars",
        description: "Kimi K2 系列模型，中国 AI 领先者",
        authTypes: [.apiKey],
        envKeys: ["MOONSHOT_API_KEY"],
        defaultModel: "moonshot/kimi-k2.5",
        baseUrl: "https://api.moonshot.ai/v1",
        apiType: "openai-completions",
        models: [
            ProviderModel(
                id: "kimi-k2.5",
                name: "Kimi K2.5",
                description: "最新 Kimi 模型",
                reasoning: false,
                contextWindow: 256000,
                maxTokens: 8192,
                isDefault: true
            ),
            ProviderModel(
                id: "kimi-k2-thinking",
                name: "Kimi K2 Thinking",
                description: "推理增强版",
                reasoning: true,
                contextWindow: 256000,
                maxTokens: 8192
            ),
            ProviderModel(
                id: "kimi-k2-turbo-preview",
                name: "Kimi K2 Turbo",
                description: "快速响应版",
                reasoning: false,
                contextWindow: 256000,
                maxTokens: 8192
            )
        ],
        documentationUrl: "https://platform.moonshot.cn/docs",
        apiKeyUrl: "https://platform.moonshot.cn/console/api-keys",
        features: ["长上下文", "中文优化", "快速"]
    )

    // MARK: - Kimi Code

    static let kimiCode = ProviderTemplate(
        id: "kimi-code",
        name: "Kimi Code",
        icon: "chevron.left.forwardslash.chevron.right",
        description: "Kimi 代码专用模型",
        authTypes: [.apiKey],
        envKeys: ["KIMICODE_API_KEY"],
        defaultModel: "kimi-code/kimi-for-coding",
        baseUrl: "https://api.kimi.com/coding/v1",
        apiType: "openai-completions",
        models: [
            ProviderModel(
                id: "kimi-for-coding",
                name: "Kimi For Coding",
                description: "代码生成优化",
                reasoning: true,
                contextWindow: 262144,
                maxTokens: 32768,
                isDefault: true
            )
        ],
        documentationUrl: "https://platform.moonshot.cn/docs",
        apiKeyUrl: "https://platform.moonshot.cn/console/api-keys",
        features: ["代码优化", "长上下文", "推理能力"]
    )

    // MARK: - MiniMax

    static let minimax = ProviderTemplate(
        id: "minimax",
        name: "MiniMax",
        icon: "m.square",
        description: "MiniMax M2.1 模型，强大的编码和推理能力",
        authTypes: [.apiKey],
        envKeys: ["MINIMAX_API_KEY"],
        defaultModel: "minimax/MiniMax-M2.1",
        baseUrl: "https://api.minimax.io/anthropic",
        apiType: "anthropic-messages",
        models: [
            ProviderModel(
                id: "MiniMax-M2.1",
                name: "MiniMax M2.1",
                description: "最新 M2.1 模型",
                reasoning: false,
                contextWindow: 200000,
                maxTokens: 8192,
                isDefault: true
            ),
            ProviderModel(
                id: "MiniMax-M2.1-lightning",
                name: "MiniMax M2.1 Lightning",
                description: "快速版本",
                reasoning: false,
                contextWindow: 200000,
                maxTokens: 8192
            )
        ],
        documentationUrl: "https://www.minimax.io/docs",
        apiKeyUrl: "https://platform.minimax.io/user-center/basic-information/interface-key",
        features: ["多语言编码", "复合指令", "工具兼容"]
    )

    // MARK: - GLM (Z.AI)

    static let glm = ProviderTemplate(
        id: "zai",
        name: "GLM (Z.AI)",
        icon: "brain.fill",
        description: "GLM 模型家族，通过 Z.AI 平台访问",
        authTypes: [.apiKey],
        envKeys: ["ZAI_API_KEY"],
        defaultModel: "zai/glm-4.7",
        baseUrl: nil,
        apiType: "openai-completions",
        models: [
            ProviderModel(
                id: "glm-4.7",
                name: "GLM 4.7",
                description: "最新 GLM 模型",
                reasoning: true,
                contextWindow: 202000,
                maxTokens: 8192,
                isDefault: true
            ),
            ProviderModel(
                id: "glm-4.6",
                name: "GLM 4.6",
                description: "稳定版本",
                reasoning: false,
                contextWindow: 128000,
                maxTokens: 8192
            )
        ],
        documentationUrl: "https://open.bigmodel.cn/dev/api",
        apiKeyUrl: "https://open.bigmodel.cn/usercenter/apikeys",
        features: ["中文优化", "推理能力", "多语言"]
    )

    // MARK: - Qwen (通义千问)

    static let qwen = ProviderTemplate(
        id: "qwen-portal",
        name: "Qwen (通义千问)",
        icon: "cloud.fill",
        description: "阿里云通义千问，免费 OAuth 访问",
        authTypes: [.oauth],
        envKeys: [],
        defaultModel: "qwen-portal/coder-model",
        baseUrl: "https://portal.qwen.ai/v1",
        apiType: "openai-completions",
        models: [
            ProviderModel(
                id: "coder-model",
                name: "Qwen Coder",
                description: "代码生成模型",
                reasoning: false,
                contextWindow: 131072,
                maxTokens: 8192,
                isDefault: true
            ),
            ProviderModel(
                id: "vision-model",
                name: "Qwen Vision",
                description: "视觉理解模型",
                reasoning: false,
                contextWindow: 131072,
                maxTokens: 8192
            )
        ],
        documentationUrl: "https://qwen.ai",
        apiKeyUrl: nil,
        features: ["免费层", "OAuth", "中文优化"]
    )

    // MARK: - Xiaomi MiMo

    static let xiaomi = ProviderTemplate(
        id: "xiaomi",
        name: "Xiaomi MiMo",
        icon: "iphone.gen3",
        description: "小米 MiMo 模型",
        authTypes: [.apiKey],
        envKeys: ["XIAOMI_API_KEY"],
        defaultModel: "xiaomi/mimo-vl",
        baseUrl: nil,
        apiType: "openai-completions",
        models: [
            ProviderModel(
                id: "mimo-vl",
                name: "MiMo VL",
                description: "视觉语言模型",
                reasoning: false,
                contextWindow: 131072,
                maxTokens: 8192,
                isDefault: true
            )
        ],
        documentationUrl: nil,
        apiKeyUrl: nil,
        features: ["视觉能力", "多模态"]
    )

    // MARK: - DeepSeek

    static let deepseek = ProviderTemplate(
        id: "deepseek",
        name: "DeepSeek",
        icon: "magnifyingglass.circle.fill",
        description: "DeepSeek 模型，强大的推理和编码能力",
        authTypes: [.apiKey],
        envKeys: ["DEEPSEEK_API_KEY"],
        defaultModel: "deepseek/deepseek-chat",
        baseUrl: "https://api.deepseek.com",
        apiType: "openai-completions",
        models: [
            ProviderModel(
                id: "deepseek-chat",
                name: "DeepSeek Chat",
                description: "通用对话模型",
                reasoning: false,
                contextWindow: 65536,
                maxTokens: 8192,
                isDefault: true
            ),
            ProviderModel(
                id: "deepseek-reasoner",
                name: "DeepSeek Reasoner",
                description: "深度推理模型",
                reasoning: true,
                contextWindow: 65536,
                maxTokens: 8192
            )
        ],
        documentationUrl: "https://platform.deepseek.com/api-docs",
        apiKeyUrl: "https://platform.deepseek.com/api_keys",
        features: ["推理能力", "代码优化", "高性价比"]
    )

    // MARK: - OpenCode Zen

    static let opencode = ProviderTemplate(
        id: "opencode",
        name: "OpenCode Zen",
        icon: "sparkle",
        description: "精选模型列表，简化配置",
        authTypes: [.apiKey],
        envKeys: ["OPENCODE_API_KEY"],
        defaultModel: "opencode/zen-1",
        baseUrl: nil,
        apiType: "openai-completions",
        models: [
            ProviderModel(
                id: "zen-1",
                name: "Zen 1",
                description: "默认精选模型",
                reasoning: false,
                contextWindow: 131072,
                maxTokens: 8192,
                isDefault: true
            )
        ],
        documentationUrl: nil,
        apiKeyUrl: nil,
        features: ["精选", "简化"]
    )

    // MARK: - 所有模板列表

    /// 所有支持的提供商模板（按推荐顺序排列）
    static let all: [ProviderTemplate] = [
        deepseek,
        moonshot,
        kimiCode,
        minimax,
        glm,
        qwen,
        xiaomi
    ]

    /// 常用/推荐的提供商模板
    static let recommended: [ProviderTemplate] = [
        deepseek,
        moonshot,
        kimiCode,
        minimax,
        glm,
        qwen,
        xiaomi
    ]

    /// 根据 ID 获取模板
    static func template(for id: String) -> ProviderTemplate? {
        return all.first { $0.id == id }
    }

    /// 根据环境变量名获取对应的模板
    static func template(forEnvKey key: String) -> ProviderTemplate? {
        return all.first { $0.envKeys.contains(key) }
    }
}

// MARK: - 配置状态

/// 提供商配置状态
enum ProviderConfigStatus: Equatable {
    case notConfigured      // 未配置
    case configured         // 已配置
    case verified           // 已验证连接
    case error(String)      // 配置错误

    var isConfigured: Bool {
        switch self {
        case .configured, .verified:
            return true
        default:
            return false
        }
    }
}

// MARK: - 模型成本配置

/// 模型成本配置
struct ModelCost: Codable, Equatable {
    var input: Int           // 输入成本（每百万 token）
    var output: Int          // 输出成本（每百万 token）
    var cacheRead: Int       // 缓存读取成本
    var cacheWrite: Int      // 缓存写入成本

    init(input: Int = 15, output: Int = 60, cacheRead: Int = 2, cacheWrite: Int = 10) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }
}

// MARK: - 用户配置

/// 用户的提供商配置
struct ProviderConfig: Identifiable, Codable {
    var id: String { providerId }

    let providerId: String              // 提供商 ID
    var apiKey: String?                 // API 密钥（加密存储）
    var selectedModel: String?          // 选择的模型 ID
    var customBaseUrl: String?          // 自定义 Base URL
    var customApiType: String?          // 自定义 API 类型
    var inputTypes: [String]?           // 输入类型（如 text, image）
    var modelCost: ModelCost?           // 模型成本配置
    var additionalSettings: [String: String]?  // 其他设置

    init(
        providerId: String,
        apiKey: String? = nil,
        selectedModel: String? = nil,
        customBaseUrl: String? = nil,
        customApiType: String? = nil,
        inputTypes: [String]? = nil,
        modelCost: ModelCost? = nil,
        additionalSettings: [String: String]? = nil
    ) {
        self.providerId = providerId
        self.apiKey = apiKey
        self.selectedModel = selectedModel
        self.customBaseUrl = customBaseUrl
        self.customApiType = customApiType
        self.inputTypes = inputTypes
        self.modelCost = modelCost
        self.additionalSettings = additionalSettings
    }

    /// 获取完整的模型引用
    var fullModelRef: String? {
        guard let model = selectedModel else { return nil }
        // 如果已经包含 provider 前缀，直接返回
        if model.contains("/") {
            return model
        }
        return "\(providerId)/\(model)"
    }
}
