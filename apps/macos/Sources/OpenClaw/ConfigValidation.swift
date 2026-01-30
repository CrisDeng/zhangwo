import SwiftUI

// MARK: - 配置验证错误

/// 配置验证错误类型
enum ConfigValidationError: LocalizedError {
    case emptyApiKey(providerName: String)
    case invalidApiKeyFormat(providerName: String, expectedFormat: String)
    case missingRequiredField(fieldName: String)
    case invalidUrl(url: String)
    case networkError(underlyingError: Error)
    case authenticationFailed(reason: String)
    case serviceUnavailable(serviceName: String)
    case unknown(message: String)

    var errorDescription: String? {
        switch self {
        case .emptyApiKey(let providerName):
            return "\(providerName) API 密钥不能为空"
        case .invalidApiKeyFormat(let providerName, let expectedFormat):
            return "\(providerName) API 密钥格式无效，期望格式: \(expectedFormat)"
        case .missingRequiredField(let fieldName):
            return "缺少必填字段: \(fieldName)"
        case .invalidUrl(let url):
            return "无效的 URL: \(url)"
        case .networkError(let underlyingError):
            return "网络错误: \(underlyingError.localizedDescription)"
        case .authenticationFailed(let reason):
            return "认证失败: \(reason)"
        case .serviceUnavailable(let serviceName):
            return "\(serviceName) 服务不可用"
        case .unknown(let message):
            return message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .emptyApiKey(let providerName):
            return "请输入有效的 \(providerName) API 密钥"
        case .invalidApiKeyFormat(_, let expectedFormat):
            return "请确保 API 密钥以 \(expectedFormat) 开头"
        case .missingRequiredField(let fieldName):
            return "请填写 \(fieldName) 字段"
        case .invalidUrl:
            return "请输入有效的 URL，例如 https://api.example.com"
        case .networkError:
            return "请检查网络连接后重试"
        case .authenticationFailed:
            return "请检查您的凭据是否正确"
        case .serviceUnavailable(let serviceName):
            return "请确保 \(serviceName) 服务正在运行"
        case .unknown:
            return "请稍后重试或联系支持"
        }
    }
}

// MARK: - API 密钥格式验证

/// API 密钥格式验证器
enum APIKeyValidator {
    /// 验证 Anthropic API 密钥格式
    static func validateAnthropic(_ key: String) -> ConfigValidationError? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .emptyApiKey(providerName: "Anthropic")
        }
        if !trimmed.hasPrefix("sk-ant-") {
            return .invalidApiKeyFormat(providerName: "Anthropic", expectedFormat: "sk-ant-...")
        }
        return nil
    }

    /// 验证 OpenAI API 密钥格式
    static func validateOpenAI(_ key: String) -> ConfigValidationError? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .emptyApiKey(providerName: "OpenAI")
        }
        if !trimmed.hasPrefix("sk-") {
            return .invalidApiKeyFormat(providerName: "OpenAI", expectedFormat: "sk-...")
        }
        return nil
    }

    /// 验证 Venice API 密钥格式
    static func validateVenice(_ key: String) -> ConfigValidationError? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .emptyApiKey(providerName: "Venice")
        }
        if !trimmed.hasPrefix("vapi_") {
            return .invalidApiKeyFormat(providerName: "Venice", expectedFormat: "vapi_...")
        }
        return nil
    }

    /// 验证 OpenRouter API 密钥格式
    static func validateOpenRouter(_ key: String) -> ConfigValidationError? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .emptyApiKey(providerName: "OpenRouter")
        }
        if !trimmed.hasPrefix("sk-or-") {
            return .invalidApiKeyFormat(providerName: "OpenRouter", expectedFormat: "sk-or-...")
        }
        return nil
    }

    /// 通用验证（仅检查非空）
    static func validateGeneric(_ key: String, providerName: String) -> ConfigValidationError? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .emptyApiKey(providerName: providerName)
        }
        return nil
    }

    /// 根据提供商 ID 验证 API 密钥
    static func validate(_ key: String, for providerId: String) -> ConfigValidationError? {
        switch providerId {
        case "anthropic":
            return validateAnthropic(key)
        case "openai":
            return validateOpenAI(key)
        case "venice":
            return validateVenice(key)
        case "openrouter":
            return validateOpenRouter(key)
        default:
            return validateGeneric(key, providerName: ProviderTemplates.template(for: providerId)?.name ?? providerId)
        }
    }
}

// MARK: - 错误提示视图

/// 统一的错误消息显示视图
struct ConfigErrorView: View {
    let error: ConfigValidationError
    let onRetry: (() -> Void)?
    let onDismiss: (() -> Void)?

    init(error: ConfigValidationError, onRetry: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.error = error
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 6) {
                Text(error.errorDescription ?? "发生未知错误")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if onRetry != nil || onDismiss != nil {
                    HStack(spacing: 8) {
                        if let retry = onRetry {
                            Button("重试", action: retry)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        if let dismiss = onDismiss {
                            Button("关闭", action: dismiss)
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 帮助信息组件

/// 提供商帮助信息卡片
struct ProviderHelpCard: View {
    let template: ProviderTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.blue)
                Text("获取帮助")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                // API 密钥获取步骤
                if let apiKeyUrl = template.apiKeyUrl {
                    helpStep(
                        number: 1,
                        title: "获取 API 密钥",
                        description: getApiKeyInstructions(for: template.id),
                        link: apiKeyUrl,
                        linkTitle: "前往获取")
                }

                // 文档链接
                if let docUrl = template.documentationUrl {
                    helpStep(
                        number: template.apiKeyUrl != nil ? 2 : 1,
                        title: "查看文档",
                        description: "了解更多关于 \(template.name) 的配置选项和使用方法",
                        link: docUrl,
                        linkTitle: "打开文档")
                }
            }

            // 常见问题
            commonIssuesSection
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.blue.opacity(0.05)))
    }

    @ViewBuilder
    private func helpStep(
        number: Int,
        title: String,
        description: String,
        link: String,
        linkTitle: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = URL(string: link) {
                    Link(linkTitle, destination: url)
                        .font(.caption)
                }
            }
        }
    }

    private var commonIssuesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("常见问题")
                .font(.subheadline.weight(.semibold))
                .padding(.top, 8)

            ForEach(commonIssues(for: template.id), id: \.title) { issue in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(issue.title)
                            .font(.caption.weight(.medium))
                    }
                    Text(issue.solution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                }
            }
        }
    }

    private func getApiKeyInstructions(for providerId: String) -> String {
        switch providerId {
        case "anthropic":
            return "登录 Anthropic Console，在 Settings → API Keys 中创建新密钥"
        case "openai":
            return "登录 OpenAI Platform，在 API Keys 页面创建新密钥"
        case "venice":
            return "登录 Venice AI，在 Settings → API Keys 中创建新密钥"
        case "openrouter":
            return "登录 OpenRouter，在 Keys 页面创建新密钥"
        case "moonshot":
            return "登录 Moonshot 开放平台，在控制台创建 API 密钥"
        case "minimax":
            return "登录 MiniMax 平台，在用户中心获取接口密钥"
        case "zai":
            return "登录智谱开放平台，在用户中心获取 API 密钥"
        default:
            return "登录提供商官网获取 API 密钥"
        }
    }

    private struct CommonIssue {
        let title: String
        let solution: String
    }

    private func commonIssues(for providerId: String) -> [CommonIssue] {
        switch providerId {
        case "anthropic":
            return [
                CommonIssue(
                    title: "401 错误 / Token 无效",
                    solution: "重新运行 claude setup-token 并在网关主机上粘贴"),
                CommonIssue(
                    title: "OAuth token 刷新失败",
                    solution: "使用 setup-token 重新认证"),
                CommonIssue(
                    title: "未找到 API 密钥",
                    solution: "每个代理需要单独认证，重新运行 onboarding")
            ]
        case "openai":
            return [
                CommonIssue(
                    title: "API 密钥无效",
                    solution: "检查密钥是否以 sk- 开头，确认未过期"),
                CommonIssue(
                    title: "配额不足",
                    solution: "检查 OpenAI 账户余额或升级计划")
            ]
        case "ollama":
            return [
                CommonIssue(
                    title: "服务未检测到",
                    solution: "运行 ollama serve 启动服务"),
                CommonIssue(
                    title: "没有可用模型",
                    solution: "运行 ollama pull <模型名> 下载模型")
            ]
        case "venice":
            return [
                CommonIssue(
                    title: "API 密钥不被识别",
                    solution: "确保密钥以 vapi_ 开头"),
                CommonIssue(
                    title: "模型不可用",
                    solution: "某些模型可能暂时离线，请稍后重试")
            ]
        default:
            return [
                CommonIssue(
                    title: "连接失败",
                    solution: "检查网络连接和 API 密钥是否正确"),
                CommonIssue(
                    title: "认证失败",
                    solution: "确认 API 密钥未过期且有效")
            ]
        }
    }
}

// MARK: - 输入验证指示器

/// 实时输入验证指示器
struct ValidationIndicator: View {
    let isValid: Bool?
    let message: String?

    var body: some View {
        if let valid = isValid {
            HStack(spacing: 4) {
                Image(systemName: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(valid ? .green : .red)
                if let msg = message {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(valid ? .green : .red)
                }
            }
        }
    }
}

// MARK: - API 密钥输入框（带验证）

/// 带实时验证的 API 密钥输入框
struct ValidatedAPIKeyField: View {
    @Binding var apiKey: String
    let providerId: String
    let placeholder: String

    @State private var validationError: ConfigValidationError?
    @State private var showValidation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SecureField(placeholder, text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { _, newValue in
                        validateInput(newValue)
                    }

                if showValidation {
                    ValidationIndicator(
                        isValid: validationError == nil && !apiKey.isEmpty,
                        message: nil)
                }
            }

            if showValidation, let error = validationError {
                Text(error.errorDescription ?? "")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            // 延迟显示验证，避免初始空状态显示错误
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showValidation = true
                if !apiKey.isEmpty {
                    validateInput(apiKey)
                }
            }
        }
    }

    private func validateInput(_ value: String) {
        guard showValidation else { return }
        validationError = APIKeyValidator.validate(value, for: providerId)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ConfigErrorView(
            error: .invalidApiKeyFormat(providerName: "Anthropic", expectedFormat: "sk-ant-..."),
            onRetry: {},
            onDismiss: {})

        ProviderHelpCard(template: ProviderTemplates.anthropic)
    }
    .padding()
    .frame(width: 500)
}
