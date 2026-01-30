import SwiftUI

// MARK: - 模型配置设置视图

/// 模型配置设置的主视图，整合快速设置、当前配置和高级设置
struct ModelConfigSettingsView: View {
    @Bindable var store: ChannelsStore
    @State private var selectedTemplate: ProviderTemplate?
    @State private var showingConfigForm = false
    @State private var viewMode: ViewMode = .simple

    enum ViewMode: String, CaseIterable {
        case simple = "简单模式"
        case advanced = "高级模式"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部模式切换
            modeSelector
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 12)

            Divider()

            // 内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch viewMode {
                    case .simple:
                        simpleConfigView
                    case .advanced:
                        advancedConfigView
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingConfigForm) {
            if let template = selectedTemplate {
                ProviderConfigFormView(
                    template: template,
                    store: store,
                    onSave: {
                        showingConfigForm = false
                        selectedTemplate = nil
                    },
                    onCancel: {
                        showingConfigForm = false
                        selectedTemplate = nil
                    })
            }
        }
    }

    // MARK: - 模式选择器

    private var modeSelector: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("模型配置")
                    .font(.title3.weight(.semibold))
                Text("配置 AI 模型提供商和默认模型")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("视图模式", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
    }

    // MARK: - 简单配置视图

    private var simpleConfigView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 当前配置概览
            currentConfigOverview

            // 快速设置 - 模板网格
            ProviderTemplateGrid(store: store) { template in
                selectedTemplate = template
                showingConfigForm = true
            }

            // 模型选择器
            ModelSelectorView(store: store, onModelChanged: nil)

            // 连接测试
            BatchConnectionTestView(store: store)
        }
    }

    // MARK: - 当前配置概览

    private var currentConfigOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前配置")
                .font(.headline)

            HStack(spacing: 20) {
                // 已配置提供商数量
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(store.configuredProviders().count)")
                            .font(.title2.weight(.semibold))
                    }
                    Text("已配置提供商")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // 当前默认模型
                VStack(alignment: .leading, spacing: 4) {
                    if let model = store.currentDefaultModel() {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text(formatModelName(model))
                                .font(.callout.weight(.medium))
                        }
                    } else {
                        Text("未设置")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("默认模型")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Spacer()
            }

            // 已配置提供商列表
            if !store.configuredProviders().isEmpty {
                configuredProviderChips
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor)))
    }

    private var configuredProviderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.configuredProviders()) { template in
                    Button {
                        selectedTemplate = template
                        showingConfigForm = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: template.icon)
                                .font(.caption)
                            Text(template.name)
                                .font(.caption)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 高级配置视图

    @State private var activeSectionKey: String?
    @State private var activeSubsection: SubsectionSelection?

    private enum SubsectionSelection: Hashable {
        case all
        case key(String)
    }

    private var advancedConfigView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("高级设置")
                .font(.headline)
            Text("使用 JSON Schema 驱动的表单编辑完整配置")
                .font(.callout)
                .foregroundStyle(.secondary)

            // 使用现有的 Schema 表单
            if store.configSchemaLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("加载配置架构...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let schema = store.configSchema {
                // 分区导航
                advancedSectionNav(schema)

                // 操作按钮
                advancedActionRow

                // 表单内容
                if let sectionKey = activeSectionKey,
                   let sectionNode = schema.properties[sectionKey] {
                    ConfigSchemaForm(
                        store: store,
                        schema: sectionNode,
                        path: [.key(sectionKey)])
                }
            } else {
                Text("配置架构不可用")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func advancedSectionNav(_ schema: ConfigSchemaNode) -> some View {
        let keys = schema.properties.keys.sorted()

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    Button {
                        activeSectionKey = key
                    } label: {
                        Text(humanize(key))
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(activeSectionKey == key
                                ? Color.accentColor.opacity(0.18)
                                : Color(nsColor: .controlBackgroundColor))
                            .foregroundStyle(activeSectionKey == key ? Color.accentColor : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            if activeSectionKey == nil, let first = keys.first {
                activeSectionKey = first
            }
        }
    }

    private var advancedActionRow: some View {
        HStack(spacing: 10) {
            Button("重新加载") {
                Task { await store.reloadConfigDraft() }
            }
            .buttonStyle(.bordered)
            .disabled(!store.configLoaded)

            Button {
                Task { await store.saveConfigDraft() }
            } label: {
                HStack(spacing: 6) {
                    if store.isSavingConfig {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(store.isSavingConfig ? "保存中..." : "保存")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isSavingConfig || !store.configDirty)

            if store.configDirty {
                Text("有未保存的更改")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - 辅助方法

    private func formatModelName(_ ref: String) -> String {
        let parts = ref.split(separator: "/")
        if parts.count >= 2 {
            return String(parts.last ?? Substring(ref))
        }
        return ref
    }

    private func humanize(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

// MARK: - Preview

#Preview {
    ModelConfigSettingsView(store: .shared)
        .frame(width: 800, height: 600)
}
