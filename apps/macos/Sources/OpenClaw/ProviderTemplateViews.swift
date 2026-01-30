import SwiftUI

// MARK: - 提供商模板卡片视图

/// 单个提供商模板卡片视图
struct ProviderTemplateCard: View {
    let template: ProviderTemplate
    let isConfigured: Bool
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                // 顶部：图标和状态
                HStack(alignment: .top, spacing: 0) {
                    // 图标
                    Image(systemName: template.icon)
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        .frame(width: 32, height: 32)

                    Spacer(minLength: 0)

                    // 配置状态指示器
                    if isConfigured {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                // 名称
                Text(template.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .lineLimit(1)

                // 描述
                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                // 特性标签
                if !template.features.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(template.features.prefix(2), id: \.self) { feature in
                            Text(feature)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(12)
            .frame(width: 160, height: 140, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                        ? Color.accentColor.opacity(0.12)
                        : (isHovered ? Color(nsColor: .controlBackgroundColor) : Color.clear)))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.3) : Color.clear),
                        lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(tooltipText)
    }

    private var tooltipText: String {
        var text = template.name
        if !template.description.isEmpty {
            text += "\n" + template.description
        }
        if isConfigured {
            text += "\n\n✅ 已配置"
        }
        if let url = template.documentationUrl {
            text += "\n📚 文档: " + url
        }
        return text
    }
}

// MARK: - 提供商模板网格视图

/// 模板网格布局视图
struct ProviderTemplateGrid: View {
    @Bindable var store: ChannelsStore
    let onSelect: (ProviderTemplate) -> Void

    @State private var selectedTemplateId: String?

    // 网格列定义
    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            VStack(alignment: .leading, spacing: 4) {
                Text("快速设置")
                    .font(.headline)
                Text("选择一个模型提供商开始配置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 推荐提供商
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(ProviderTemplates.recommended) { template in
                    ProviderTemplateCard(
                        template: template,
                        isConfigured: store.providerStatus(for: template.id).isConfigured,
                        isSelected: selectedTemplateId == template.id,
                        action: {
                            selectedTemplateId = template.id
                            onSelect(template)
                        })
                }
            }
        }
    }


}

// MARK: - 已配置提供商列表视图

/// 显示当前已配置的提供商列表
struct ConfiguredProvidersList: View {
    @Bindable var store: ChannelsStore
    let onEdit: (ProviderTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("当前配置")
                    .font(.headline)
                Spacer()
                if let model = store.currentDefaultModel() {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text("默认: \(model)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            let configured = store.configuredProviders()
            if configured.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("尚未配置任何模型提供商")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(configured) { template in
                    ConfiguredProviderRow(
                        template: template,
                        store: store,
                        onEdit: { onEdit(template) })
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
    }
}

/// 已配置提供商行视图
struct ConfiguredProviderRow: View {
    let template: ProviderTemplate
    @Bindable var store: ChannelsStore
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: template.icon)
                .font(.title3)
                .frame(width: 28, height: 28)
                .foregroundStyle(Color.accentColor)

            // 信息
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.callout.weight(.medium))

                HStack(spacing: 6) {
                    // 状态指示
                    let status = store.providerStatus(for: template.id)
                    switch status {
                    case .verified:
                        Label("已验证", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .configured:
                        Label("已配置", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .error(let msg):
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    case .notConfigured:
                        EmptyView()
                    }
                }
            }

            Spacer()

            // 操作按钮
            HStack(spacing: 8) {
                // 测试连接按钮
                Button {
                    Task { await store.testProviderConnection(providerId: template.id) }
                } label: {
                    if store.testingProviders.contains(template.id) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(store.testingProviders.contains(template.id))
                .help("测试连接")

                // 编辑按钮
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("编辑配置")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor)))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ProviderTemplateCard(
            template: ProviderTemplates.anthropic,
            isConfigured: true,
            isSelected: false,
            action: {})

        ProviderTemplateCard(
            template: ProviderTemplates.openai,
            isConfigured: false,
            isSelected: true,
            action: {})
    }
    .padding()
}
