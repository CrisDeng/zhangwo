import SwiftUI

// MARK: - 连接测试按钮组件

/// 连接测试按钮，带有加载指示器和结果状态显示
struct ConnectionTestButton: View {
    let providerId: String
    @Bindable var store: ChannelsStore
    let onTestComplete: ((Bool) -> Void)?

    @State private var testResult: TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    init(
        providerId: String,
        store: ChannelsStore,
        onTestComplete: ((Bool) -> Void)? = nil
    ) {
        self.providerId = providerId
        self.store = store
        self.onTestComplete = onTestComplete
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await runTest() }
            } label: {
                HStack(spacing: 6) {
                    if store.testingProviders.contains(providerId) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(store.testingProviders.contains(providerId) ? "测试中..." : "测试连接")
                }
            }
            .buttonStyle(.bordered)
            .disabled(store.testingProviders.contains(providerId))

            // 测试结果指示器
            if let result = testResult {
                switch result {
                case .success:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("连接成功")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                    .transition(.opacity.combined(with: .scale))
                case .failure(let message):
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: testResult != nil)
    }

    private func runTest() async {
        testResult = nil
        let success = await store.testProviderConnection(providerId: providerId)
        testResult = success ? .success : .failure("连接失败")
        onTestComplete?(success)
    }
}

// MARK: - 连接状态指示器

/// 显示提供商连接状态的指示器
struct ConnectionStatusIndicator: View {
    let status: ProviderConfigStatus

    var body: some View {
        HStack(spacing: 6) {
            switch status {
            case .notConfigured:
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                Text("未配置")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .configured:
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 8, height: 8)
                Text("已配置")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .verified:
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("已验证")
                    .font(.caption)
                    .foregroundStyle(.green)

            case .error(let message):
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 批量连接测试视图

/// 批量测试所有已配置提供商的连接
struct BatchConnectionTestView: View {
    @Bindable var store: ChannelsStore

    @State private var testResults: [String: Bool] = [:]
    @State private var isTesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("连接状态")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await runBatchTest() }
                } label: {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        }
                        Text(isTesting ? "测试中..." : "全部测试")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isTesting)
            }

            let configured = store.configuredProviders()
            if configured.isEmpty {
                Text("没有已配置的提供商")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(configured) { template in
                    HStack(spacing: 12) {
                        Image(systemName: template.icon)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)

                        Text(template.name)
                            .font(.callout)

                        Spacer()

                        if let result = testResults[template.id] {
                            if result {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        } else {
                            ConnectionStatusIndicator(status: store.providerStatus(for: template.id))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func runBatchTest() async {
        isTesting = true
        testResults.removeAll()

        for template in store.configuredProviders() {
            let result = await store.testProviderConnection(providerId: template.id)
            testResults[template.id] = result
        }

        isTesting = false
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ConnectionTestButton(providerId: "anthropic", store: .shared, onTestComplete: nil)

        ConnectionStatusIndicator(status: .configured)
        ConnectionStatusIndicator(status: .verified)
        ConnectionStatusIndicator(status: .error("API 密钥无效"))

        BatchConnectionTestView(store: .shared)
    }
    .padding()
    .frame(width: 400)
}
