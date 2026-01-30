import SwiftUI

// MARK: - 引导页模型配置

extension OnboardingView {
    /// 大模型快速配置页面
    func modelConfigPage() -> some View {
        self.onboardingPage {
            VStack(spacing: 16) {
                Text("配置大模型")
                    .font(.largeTitle.weight(.semibold))
                Text("选择并配置您想要使用的 AI 模型提供商，以获得最佳体验")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)

                self.onboardingCard(spacing: 14, padding: 16) {
                    OnboardingModelConfigContent()
                }
            }
        }
    }
}

// MARK: - 引导页模型配置内容

@MainActor
struct OnboardingModelConfigContent: View {
    @Bindable private var store = ChannelsStore.shared
    @State private var selectedTemplate: ProviderTemplate?
    @State private var configuredProviders: [ProviderConfigState] = []
    @State private var selectedModel: String = ""
    @State private var isSavingModel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 已配置的提供商（简化显示）
            if !self.configuredProviders.isEmpty {
                self.configuredSection
            }

            // 添加提供商（简化版）
            self.addProviderSection

            // 模型选择
            self.modelSelectionSection
        }
        .onAppear {
            self.loadConfiguredProviders()
            self.selectedModel = self.store.currentDefaultModel() ?? ""
        }
        .onChange(of: self.store.configDirty) { _, _ in
            self.loadConfiguredProviders()
        }
        .sheet(item: self.$selectedTemplate) { template in
            ProviderConfigSheet(
                store: self.store,
                template: template,
                onDismiss: {
                    self.selectedTemplate = nil
                })
        }
    }

    // MARK: - 已配置的提供商

    private var configuredSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("已配置", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
                Text("\(self.configuredProviders.count) 个提供商")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(self.configuredProviders, id: \.template.id) { config in
                        OnboardingConfiguredProviderBadge(
                            config: config,
                            onEdit: { self.selectedTemplate = config.template })
                    }
                }
            }
        }
    }

    // MARK: - 添加提供商

    private var addProviderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("添加提供商")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)], spacing: 8) {
                ForEach(ProviderTemplates.all.filter { template in
                    !self.configuredProviders.contains { $0.template.id == template.id }
                }) { template in
                    OnboardingProviderButton(template: template) {
                        self.selectedTemplate = template
                    }
                }
            }
        }
    }

    // MARK: - 模型选择

    private var modelSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("默认模型")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if self.isSavingModel {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
            }

            if self.availableModels.isEmpty {
                Text("请先配置一个提供商以选择模型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                Picker("选择模型", selection: self.$selectedModel) {
                    Text("选择模型...").tag("")
                    ForEach(self.availableModels) { model in
                        HStack {
                            Image(systemName: model.providerIcon)
                                .foregroundStyle(.secondary)
                            Text(model.displayName)
                        }
                        .tag(model.fullRef)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: self.selectedModel) { _, newValue in
                    Task { await self.saveSelectedModel(newValue) }
                }

                // 当前模型信息
                if let currentModel = self.currentModelInfo {
                    HStack(spacing: 10) {
                        Image(systemName: currentModel.providerIcon)
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentModel.displayName)
                                .font(.caption.weight(.medium))
                            HStack(spacing: 8) {
                                if currentModel.reasoning {
                                    Label("推理", systemImage: "brain")
                                        .font(.caption2)
                                        .foregroundStyle(.purple)
                                }
                                Text("\(currentModel.contextWindow / 1000)K")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.1)))
                }
            }
        }
    }

    // MARK: - Model Info

    private struct OnboardingModelInfo: Identifiable {
        let id: String
        let fullRef: String
        let displayName: String
        let providerId: String
        let providerIcon: String
        let description: String?
        let reasoning: Bool
        let contextWindow: Int
        let maxTokens: Int

        init(provider: ProviderTemplate, model: ProviderModel) {
            self.id = "\(provider.id)/\(model.id)"
            self.fullRef = "\(provider.id)/\(model.id)"
            self.displayName = "\(provider.name) - \(model.name)"
            self.providerId = provider.id
            self.providerIcon = provider.icon
            self.description = model.description
            self.reasoning = model.reasoning
            self.contextWindow = model.contextWindow
            self.maxTokens = model.maxTokens
        }
    }

    private var availableModels: [OnboardingModelInfo] {
        var models: [OnboardingModelInfo] = []
        for template in ProviderTemplates.all {
            if self.store.providerStatus(for: template.id).isConfigured || template.isLocal {
                for model in template.models {
                    models.append(OnboardingModelInfo(provider: template, model: model))
                }
            }
        }
        return models
    }

    private var currentModelInfo: OnboardingModelInfo? {
        self.availableModels.first { $0.fullRef == self.selectedModel }
    }

    private func saveSelectedModel(_ model: String) async {
        guard !model.isEmpty else { return }

        // 检查模型是否真的改变，避免不必要的保存和 toast
        let currentModel = self.store.currentDefaultModel() ?? ""
        guard model != currentModel else { return }
        
        self.isSavingModel = true
        defer { self.isSavingModel = false }

        self.store.updateConfigValue(
            path: [.key("agents"), .key("defaults"), .key("model"), .key("primary")],
            value: model)

        await self.store.saveConfigDraft()
    }

    // MARK: - Helper Methods

    private func loadConfiguredProviders() {
        var providers: [ProviderConfigState] = []
        for template in ProviderTemplates.all {
            if self.isProviderConfigured(template) {
                let status = self.store.providerStatus(for: template.id)
                providers.append(ProviderConfigState(template: template, status: status))
            }
        }
        self.configuredProviders = providers
    }

    private func isProviderConfigured(_ template: ProviderTemplate) -> Bool {
        let draft = self.store.configDraft
        guard !draft.isEmpty else { return false }
        if template.isLocal { return true }
        let envDict = draft["env"] as? [String: Any] ?? [:]
        for envKey in template.envKeys {
            if let value = envDict[envKey] as? String, !value.isEmpty {
                return true
            }
        }
        return false
    }
}

// MARK: - 引导页提供商按钮

private struct OnboardingProviderButton: View {
    let template: ProviderTemplate
    let onSelect: () -> Void

    var body: some View {
        Button {
            self.onSelect()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: self.template.icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text(self.template.name)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 引导页已配置提供商徽章

private struct OnboardingConfiguredProviderBadge: View {
    let config: ProviderConfigState
    let onEdit: () -> Void

    var body: some View {
        Button {
            self.onEdit()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: self.config.template.icon)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text(self.config.template.name)
                    .font(.caption.weight(.medium))
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                Capsule()
                    .stroke(Color.green.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
