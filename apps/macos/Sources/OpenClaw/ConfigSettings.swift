import SwiftUI

@MainActor
struct ConfigSettings: View {
    private let isPreview = ProcessInfo.processInfo.isPreview
    private let isNixMode = ProcessInfo.processInfo.isNixMode
    @Bindable var store: ChannelsStore
    @State private var hasLoaded = false
    @State private var activeSectionKey: String?
    @State private var activeSubsection: SubsectionSelection?
    // 用于 models 分区的 Tab 切换
    @State private var modelsTabSelection: ModelsTabSelection = .quickSetup

    init(store: ChannelsStore = .shared) {
        self.store = store
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 16) {
                self.sidebar
                self.detail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // 保存状态 Toast
            if self.store.showConfigSaveToast {
                self.saveToastView
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: self.store.showConfigSaveToast)
        .task {
            guard !self.hasLoaded else { return }
            guard !self.isPreview else { return }
            self.hasLoaded = true
            await self.store.loadConfigSchema()
            await self.store.loadConfig()
        }
        .onAppear { self.ensureSelection() }
        .onChange(of: self.store.configSchemaLoading) { _, loading in
            if !loading { self.ensureSelection() }
        }
    }
}

// MARK: - Models Tab Selection

extension ConfigSettings {
    enum ModelsTabSelection: String, CaseIterable {
        case quickSetup = "快速设置"
        case classic = "自定义"
    }
}

// MARK: - Toast View

extension ConfigSettings {
    @ViewBuilder
    private var saveToastView: some View {
        let isSuccess = {
            if case .success = self.store.configSaveResult {
                return true
            }
            return false
        }()
        let errorMessage: String? = {
            if case let .error(msg) = self.store.configSaveResult {
                return msg
            }
            return nil
        }()

        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(isSuccess ? .green : .red)

            VStack(alignment: .leading, spacing: 2) {
                Text(isSuccess ? "配置保存成功" : "保存失败")
                    .font(.callout.weight(.semibold))
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Button {
                self.store.showConfigSaveToast = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4))
        .padding(.top, 16)
    }
}

// MARK: - Sidebar & Detail

extension ConfigSettings {
    private enum SubsectionSelection: Hashable {
        case all
        case key(String)
    }

    private struct ConfigSection: Identifiable {
        let key: String
        let label: String
        let help: String?
        let node: ConfigSchemaNode

        var id: String { self.key }
    }

    private struct ConfigSubsection: Identifiable {
        let key: String
        let label: String
        let help: String?
        let node: ConfigSchemaNode
        let path: ConfigPath

        var id: String { self.key }
    }

    private var sections: [ConfigSection] {
        guard let schema = self.store.configSchema else { return [] }
        return self.resolveSections(schema)
    }

    private var activeSection: ConfigSection? {
        self.sections.first { $0.key == self.activeSectionKey }
    }

    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if self.sections.isEmpty {
                    Text("没有可用的配置分区。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                } else {
                    ForEach(self.sections) { section in
                        self.sidebarRow(section)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 16) {
            if self.store.configSchemaLoading {
                ProgressView().controlSize(.small)
            } else if let section = self.activeSection {
                // 判断是否为 models 分区
                if section.key == "models" {
                    self.modelsDetail(section)
                } else {
                    self.sectionDetail(section)
                }
            } else if self.store.configSchema != nil {
                self.emptyDetail
            } else {
                Text("Schema 不可用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.header
            Text("选择一个配置分区以查看设置。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    // MARK: - Models 分区详情（带 Tab 切换）

    private func modelsDetail(_ section: ConfigSection) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                self.header
                if let status = self.store.configStatus {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                self.actionRow
                self.sectionHeader(section)

                // Tab 切换
                Picker("", selection: self.$modelsTabSelection) {
                    ForEach(ModelsTabSelection.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                // 根据 Tab 显示不同内容
                switch self.modelsTabSelection {
                case .quickSetup:
                    // 快速设置：使用新的模板化界面
                    ModelsQuickSetupView(store: self.store)
                case .classic:
                    // 经典设置：使用原来的 Schema 表单
                    self.subsectionNav(section)
                    self.sectionForm(section)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .groupBoxStyle(PlainSettingsGroupBoxStyle())
        }
    }

    // MARK: - 其他分区详情（原有逻辑）

    private func sectionDetail(_ section: ConfigSection) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                self.header
                if let status = self.store.configStatus {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                self.actionRow
                self.sectionHeader(section)
                self.subsectionNav(section)
                self.sectionForm(section)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .groupBoxStyle(PlainSettingsGroupBoxStyle())
        }
    }

    @ViewBuilder
    private var header: some View {
        Text("配置")
            .font(.title3.weight(.semibold))
        Text(self.isNixMode
            ? "在 Nix 模式下此标签页为只读。请通过 Nix 编辑配置并重新构建。"
            : "使用 Schema 驱动的表单编辑 ~/.openclaw/openclaw.json。")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func sectionHeader(_ section: ConfigSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.label)
                .font(.title3.weight(.semibold))
            if let help = section.help {
                Text(help)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button("重新加载") {
                Task { await self.store.reloadConfigDraft() }
            }
            .disabled(!self.store.configLoaded)

            Button {
                Task { await self.store.saveConfigDraft() }
            } label: {
                HStack(spacing: 6) {
                    if self.store.isSavingConfig {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(self.store.isSavingConfig ? "保存中…" : "保存")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(self.isNixMode || self.store.isSavingConfig || !self.store.configDirty)

            if self.store.configDirty {
                Text("有未保存的更改")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func sidebarRow(_ section: ConfigSection) -> some View {
        let isSelected = self.activeSectionKey == section.key
        return Button {
            self.selectSection(section)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.label)
                if let help = section.help {
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func subsectionNav(_ section: ConfigSection) -> some View {
        let subsections = self.resolveSubsections(for: section)
        if subsections.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    self.subsectionButton(
                        title: "全部",
                        isSelected: self.activeSubsection == .all)
                    {
                        self.activeSubsection = .all
                    }
                    ForEach(subsections) { subsection in
                        self.subsectionButton(
                            title: subsection.label,
                            isSelected: self.activeSubsection == .key(subsection.key))
                        {
                            self.activeSubsection = .key(subsection.key)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func subsectionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sectionForm(_ section: ConfigSection) -> some View {
        let subsection = self.activeSubsection
        let defaultPath: ConfigPath = [.key(section.key)]
        let subsections = self.resolveSubsections(for: section)
        let resolved: (ConfigSchemaNode, ConfigPath) = {
            if case let .key(key) = subsection,
               let match = subsections.first(where: { $0.key == key })
            {
                return (match.node, match.path)
            }
            return (self.resolvedSchemaNode(section.node), defaultPath)
        }()

        return ConfigSchemaForm(store: self.store, schema: resolved.0, path: resolved.1)
            .disabled(self.isNixMode)
    }

    private func ensureSelection() {
        guard let schema = self.store.configSchema else { return }
        let sections = self.resolveSections(schema)
        guard !sections.isEmpty else { return }

        let active = sections.first { $0.key == self.activeSectionKey } ?? sections[0]
        if self.activeSectionKey != active.key {
            self.activeSectionKey = active.key
        }
        self.ensureSubsection(for: active)
    }

    private func ensureSubsection(for section: ConfigSection) {
        let subsections = self.resolveSubsections(for: section)
        guard !subsections.isEmpty else {
            self.activeSubsection = nil
            return
        }

        switch self.activeSubsection {
        case .all:
            return
        case let .key(key):
            if subsections.contains(where: { $0.key == key }) { return }
        case .none:
            break
        }

        if let first = subsections.first {
            self.activeSubsection = .key(first.key)
        }
    }

    private func selectSection(_ section: ConfigSection) {
        guard self.activeSectionKey != section.key else { return }
        self.activeSectionKey = section.key
        let subsections = self.resolveSubsections(for: section)
        if let first = subsections.first {
            self.activeSubsection = .key(first.key)
        } else {
            self.activeSubsection = nil
        }
    }

    private func resolveSections(_ root: ConfigSchemaNode) -> [ConfigSection] {
        let node = self.resolvedSchemaNode(root)
        let hints = self.store.configUiHints
        let keys = node.properties.keys.sorted { lhs, rhs in
            let orderA = hintForPath([.key(lhs)], hints: hints)?.order ?? 0
            let orderB = hintForPath([.key(rhs)], hints: hints)?.order ?? 0
            if orderA != orderB { return orderA < orderB }
            return lhs < rhs
        }

        return keys.compactMap { key in
            guard let child = node.properties[key] else { return nil }
            let path: ConfigPath = [.key(key)]
            let hint = hintForPath(path, hints: hints)
            let label = hint?.label
                ?? child.title
                ?? self.humanize(key)
            let help = hint?.help ?? child.description
            return ConfigSection(key: key, label: label, help: help, node: child)
        }
    }

    private func resolveSubsections(for section: ConfigSection) -> [ConfigSubsection] {
        let node = self.resolvedSchemaNode(section.node)
        guard node.schemaType == "object" else { return [] }
        let hints = self.store.configUiHints
        let keys = node.properties.keys.sorted { lhs, rhs in
            let orderA = hintForPath([.key(section.key), .key(lhs)], hints: hints)?.order ?? 0
            let orderB = hintForPath([.key(section.key), .key(rhs)], hints: hints)?.order ?? 0
            if orderA != orderB { return orderA < orderB }
            return lhs < rhs
        }

        return keys.compactMap { key in
            guard let child = node.properties[key] else { return nil }
            let path: ConfigPath = [.key(section.key), .key(key)]
            let hint = hintForPath(path, hints: hints)
            let label = hint?.label
                ?? child.title
                ?? self.humanize(key)
            let help = hint?.help ?? child.description
            return ConfigSubsection(
                key: key,
                label: label,
                help: help,
                node: child,
                path: path)
        }
    }

    private func resolvedSchemaNode(_ node: ConfigSchemaNode) -> ConfigSchemaNode {
        let variants = node.anyOf.isEmpty ? node.oneOf : node.anyOf
        if !variants.isEmpty {
            let nonNull = variants.filter { !$0.isNullSchema }
            if nonNull.count == 1, let only = nonNull.first { return only }
        }
        return node
    }

    private func humanize(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

// MARK: - Models 快速设置视图

@MainActor
struct ModelsQuickSetupView: View {
    @Bindable var store: ChannelsStore
    @State private var selectedTemplate: ProviderTemplate?
    @State private var configuredProviders: [ProviderConfigState] = []
    @State private var selectedModel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 已配置的提供商
            if !self.configuredProviders.isEmpty {
                self.configuredProvidersSection
            }

            // 添加新提供商
            self.addProviderSection

            // 模型选择
            self.modelSelectionSection

            // 连接测试（暂时屏蔽）
            // if !self.configuredProviders.isEmpty {
            //     self.connectionTestSection
            // }
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

    private var configuredProvidersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已配置的提供商")
                    .font(.headline)
                Spacer()
                Text("\(self.configuredProviders.count) 个")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)], spacing: 12) {
                ForEach(self.configuredProviders, id: \.template.id) { config in
                    ConfiguredProviderCard(
                        config: config,
                        onEdit: {
                            self.selectedTemplate = config.template
                        },
                        onDelete: {
                            self.deleteProvider(config.template)
                        })
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5)))
    }

    // MARK: - 添加新提供商

    private var addProviderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加提供商")
                .font(.headline)

            Text("选择一个模型提供商模板来快速配置")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)], spacing: 12) {
                ForEach(ProviderTemplates.all.filter { template in
                    !self.configuredProviders.contains { $0.template.id == template.id }
                }) { template in
                    ProviderTemplateSmallCard(template: template) {
                        self.selectedTemplate = template
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5)))
    }

    // MARK: - 模型选择

    private var modelSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("模型选择")
                .font(.headline)

            Text("设置默认使用的模型")
                .font(.caption)
                .foregroundStyle(.secondary)

            SimpleModelSelector(store: self.store, selectedModel: self.$selectedModel, providerId: nil)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5)))
    }

    // MARK: - 连接测试

    private var connectionTestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("连接测试")
                .font(.headline)

            BatchConnectionTestView(store: self.store)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5)))
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

        // 本地服务（如 Ollama）默认视为已配置
        if template.isLocal {
            return true
        }

        // 检查环境变量是否配置
        let envDict = draft["env"] as? [String: Any] ?? [:]
        for envKey in template.envKeys {
            if let value = envDict[envKey] as? String, !value.isEmpty {
                return true
            }
        }

        return false
    }

    private func getConfigValue(at path: String, in draft: [String: Any]) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        var current: Any = draft

        for component in components {
            if let dict = current as? [String: Any] {
                if let next = dict[component] {
                    current = next
                } else {
                    return nil
                }
            } else {
                return nil
            }
        }

        return current
    }

    private func deleteProvider(_ template: ProviderTemplate) {
        // 清空该提供商的环境变量配置
        for envKey in template.envKeys {
            self.store.setConfigValue(at: [.key("env"), .key(envKey)], value: nil)
        }
    }
}

// MARK: - 提供商配置状态

struct ProviderConfigState {
    let template: ProviderTemplate
    let status: ProviderConfigStatus
}

// MARK: - 已配置提供商卡片

struct ConfiguredProviderCard: View {
    let config: ProviderConfigState
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: self.config.template.icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text(self.config.template.name)
                    .font(.headline)
                Spacer()
                self.statusIndicator
            }

            Text(self.config.template.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Button("编辑") {
                    self.onEdit()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    self.onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(self.borderColor, lineWidth: 1))
    }

    private var statusIndicator: some View {
        Circle()
            .fill(self.statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch self.config.status {
        case .configured, .verified:
            return .green
        case .notConfigured:
            return .gray
        case .error:
            return .red
        }
    }

    private var borderColor: Color {
        switch self.config.status {
        case .configured, .verified:
            return .green.opacity(0.3)
        case .notConfigured:
            return .gray.opacity(0.3)
        case .error:
            return .red.opacity(0.3)
        }
    }
}

// MARK: - 小型提供商模板卡片

struct ProviderTemplateSmallCard: View {
    let template: ProviderTemplate
    let onSelect: () -> Void

    var body: some View {
        Button {
            self.onSelect()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: self.template.icon)
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                Text(self.template.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 提供商配置弹窗

struct ProviderConfigSheet: View {
    @Bindable var store: ChannelsStore
    let template: ProviderTemplate
    let onDismiss: () -> Void

    var body: some View {
        ProviderConfigFormView(
            template: self.template,
            store: self.store,
            onSave: {
                // 注意: ProviderConfigFormView.saveConfig() 已经调用了 saveConfigDraft()
                // 这里不需要再次调用，直接关闭弹窗即可
                self.onDismiss()
            },
            onCancel: {
                self.onDismiss()
            })
    }
}

// MARK: - Preview

struct ConfigSettings_Previews: PreviewProvider {
    static var previews: some View {
        ConfigSettings()
    }
}
