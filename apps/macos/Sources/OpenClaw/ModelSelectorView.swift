import SwiftUI

// MARK: - 模型选择器视图

/// 全局模型选择器，用于设置默认模型和 fallback 模型
struct ModelSelectorView: View {
    @Bindable var store: ChannelsStore
    let onModelChanged: (() -> Void)?

    @State private var primaryModel: String = ""
    @State private var fallbackModels: [String] = []
    @State private var isSaving = false

    init(store: ChannelsStore, onModelChanged: (() -> Void)? = nil) {
        self.store = store
        self.onModelChanged = onModelChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            HStack {
                Text("默认模型")
                    .font(.headline)
                Spacer()
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                }
            }

            // 主模型选择
            VStack(alignment: .leading, spacing: 8) {
                Text("主要模型")
                    .font(.callout.weight(.medium))

                Picker("选择主要模型", selection: $primaryModel) {
                    Text("选择模型...").tag("")
                    ForEach(availableModels) { model in
                        HStack {
                            Image(systemName: model.providerIcon)
                                .foregroundStyle(.secondary)
                            Text(model.displayName)
                        }
                        .tag(model.fullRef)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: primaryModel) { _, newValue in
                    Task { await savePrimaryModel(newValue) }
                }

                if let current = currentModelInfo {
                    modelInfoRow(current)
                }
            }

            Divider()

            // Fallback 模型
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("备用模型 (Fallback)")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button {
                        addFallbackModel()
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(availableModelsForFallback.isEmpty)
                }

                if fallbackModels.isEmpty {
                    Text("未设置备用模型。当主模型不可用时，将无法自动切换。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(fallbackModels.enumerated()), id: \.offset) { index, model in
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let info = modelInfo(for: model) {
                                HStack {
                                    Image(systemName: info.providerIcon)
                                        .foregroundStyle(.secondary)
                                    Text(info.displayName)
                                }
                            } else {
                                Text(model)
                            }

                            Spacer()

                            Button {
                                removeFallbackModel(at: index)
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor)))
        .onAppear {
            loadCurrentConfig()
        }
    }

    // MARK: - 模型信息行

    @ViewBuilder
    private func modelInfoRow(_ model: ModelInfo) -> some View {
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
        .padding(.top, 4)
    }

    // MARK: - 数据模型

    struct ModelInfo: Identifiable {
        let id: String
        let fullRef: String
        let displayName: String
        let providerId: String
        let providerIcon: String
        let description: String?
        let reasoning: Bool
        let contextWindow: Int

        init(provider: ProviderTemplate, model: ProviderModel) {
            self.id = "\(provider.id)/\(model.id)"
            self.fullRef = "\(provider.id)/\(model.id)"
            self.displayName = "\(provider.name) - \(model.name)"
            self.providerId = provider.id
            self.providerIcon = provider.icon
            self.description = model.description
            self.reasoning = model.reasoning
            self.contextWindow = model.contextWindow
        }
    }

    // MARK: - 计算属性

    /// 所有可用的模型（来自已配置的提供商）
    private var availableModels: [ModelInfo] {
        var models: [ModelInfo] = []

        for template in ProviderTemplates.all {
            // 检查提供商是否已配置
            if store.providerStatus(for: template.id).isConfigured || template.isLocal {
                for model in template.models {
                    models.append(ModelInfo(provider: template, model: model))
                }
            }
        }

        return models
    }

    /// 可用于 fallback 的模型（排除已选择的主模型和已添加的 fallback）
    private var availableModelsForFallback: [ModelInfo] {
        let excluded = Set([primaryModel] + fallbackModels)
        return availableModels.filter { !excluded.contains($0.fullRef) }
    }

    /// 当前主模型的信息
    private var currentModelInfo: ModelInfo? {
        availableModels.first { $0.fullRef == primaryModel }
    }

    /// 根据模型引用获取模型信息
    private func modelInfo(for ref: String) -> ModelInfo? {
        availableModels.first { $0.fullRef == ref }
    }

    // MARK: - 数据操作

    private func loadCurrentConfig() {
        // 加载当前默认模型
        if let current = store.currentDefaultModel() {
            primaryModel = current
        }

        // 加载 fallback 模型
        let agents = store.configDraft["agents"] as? [String: Any]
        let defaults = agents?["defaults"] as? [String: Any]
        let model = defaults?["model"] as? [String: Any]

        if let fallbacks = model?["fallback"] as? [String] {
            fallbackModels = fallbacks
        } else if let fallbacks = model?["fallbacks"] as? [String] {
            fallbackModels = fallbacks
        }
    }

    private func savePrimaryModel(_ model: String) async {
        guard !model.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        store.updateConfigValue(
            path: [.key("agents"), .key("defaults"), .key("model"), .key("primary")],
            value: model)

        await store.saveConfigDraft()
        onModelChanged?()
    }

    private func addFallbackModel() {
        // 添加第一个可用的 fallback 模型
        guard let first = availableModelsForFallback.first else { return }
        fallbackModels.append(first.fullRef)
        Task { await saveFallbackModels() }
    }

    private func removeFallbackModel(at index: Int) {
        guard fallbackModels.indices.contains(index) else { return }
        fallbackModels.remove(at: index)
        Task { await saveFallbackModels() }
    }

    private func saveFallbackModels() async {
        isSaving = true
        defer { isSaving = false }

        if fallbackModels.isEmpty {
            store.updateConfigValue(
                path: [.key("agents"), .key("defaults"), .key("model"), .key("fallback")],
                value: nil)
        } else {
            store.updateConfigValue(
                path: [.key("agents"), .key("defaults"), .key("model"), .key("fallback")],
                value: fallbackModels)
        }

        await store.saveConfigDraft()
        onModelChanged?()
    }
}

// MARK: - 简化版模型选择器

/// 简化版模型选择器，仅用于快速选择主模型
struct SimpleModelSelector: View {
    @Bindable var store: ChannelsStore
    @Binding var selectedModel: String
    let providerId: String?

    var body: some View {
        Picker("模型", selection: $selectedModel) {
            Text("选择模型...").tag("")
            ForEach(filteredModels) { model in
                Text(model.displayName).tag(model.fullRef)
            }
        }
        .pickerStyle(.menu)
    }

    private var filteredModels: [ModelSelectorView.ModelInfo] {
        var models: [ModelSelectorView.ModelInfo] = []

        for template in ProviderTemplates.all {
            // 如果指定了 providerId，只显示该提供商的模型
            if let pid = providerId, template.id != pid {
                continue
            }

            for model in template.models {
                models.append(ModelSelectorView.ModelInfo(provider: template, model: model))
            }
        }

        return models
    }
}

// MARK: - Preview

#Preview {
    ModelSelectorView(store: .shared)
        .frame(width: 500)
        .padding()
}
