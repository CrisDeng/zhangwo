import Observation
import SwiftUI

struct QmdSettings: View {
    @State private var manager = QmdManager.shared
    @State private var newCollectionPath = ""
    @State private var newCollectionName = ""
    @State private var showAddCollection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    self.statusSection
                    self.modelsSection
                    if self.manager.modelsReady {
                        self.configSection
                        self.collectionsSection
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .task { await self.manager.checkStatus() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("本地记忆 (QMD)")
                    .font(.headline)
                Text("基于 BM25 + 向量语义 + LLM 重排序的本地混合检索，零 API 成本。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if self.manager.isChecking {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await self.manager.checkStatus() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.sectionTitle("状态")

            HStack(spacing: 12) {
                self.statusBadge(
                    title: "Bun",
                    ok: self.manager.bunInstalled,
                    detail: self.manager.bunInstalled ? "已安装" : "未安装")

                self.statusBadge(
                    title: "QMD",
                    ok: self.manager.qmdInstalled,
                    detail: self.manager.qmdInstalled ? "已安装" : "未安装")

                self.statusBadge(
                    title: "模型",
                    ok: self.manager.modelsReady,
                    detail: self.manager.modelsReady ? "就绪" : "需要下载")

                self.statusBadge(
                    title: "启用状态",
                    ok: self.manager.isQmdEnabled,
                    detail: self.manager.isQmdEnabled ? "已启用" : "未启用")

                // Show warmup status when QMD is enabled
                if self.manager.isQmdEnabled && self.manager.modelsReady {
                    self.statusBadge(
                        title: "预热",
                        ok: self.manager.modelsWarmed,
                        detail: self.manager.isWarming ? "预热中..." : (self.manager.modelsWarmed ? "已就绪" : "待预热"))
                }
            }

            // Installation flow
            if !self.manager.bunInstalled {
                self.installBunSection
            } else if !self.manager.qmdInstalled {
                self.installQmdSection
            }

            if let error = self.manager.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if let msg = self.manager.statusMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var installBunSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("需要安装 Bun 运行时")
                .font(.callout.weight(.medium))
            Text("Bun 是 QMD 的运行时依赖，点击下方按钮一键安装。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    Task { await self.manager.installBun() }
                } label: {
                    if self.manager.isInstalling {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text("安装中...")
                    } else {
                        Label("安装 Bun", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.manager.isInstalling)

                Link(destination: URL(string: "https://bun.sh")!) {
                    Text("了解 Bun")
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var installQmdSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("需要安装 QMD")
                .font(.callout.weight(.medium))
            Text("QMD 是本地混合检索引擎，点击下方按钮一键安装。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    Task { await self.manager.installQmd() }
                } label: {
                    if self.manager.isInstalling {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text("安装中...")
                    } else {
                        Label("安装 QMD", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.manager.isInstalling)

                Link(destination: URL(string: "https://github.com/tobi/qmd")!) {
                    Text("了解 QMD")
                        .font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(8)
    }

    private func statusBadge(title: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }

    // MARK: - Models

    @ViewBuilder
    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.sectionTitle("本地模型")

            ForEach(self.manager.models) { model in
                self.modelRow(model)
            }

            if !self.manager.modelsReady {
                let totalMB = self.manager.models
                    .filter { !$0.state.isCompleted }
                    .reduce(0) { $0 + $1.sizeMB }

                VStack(alignment: .leading, spacing: 8) {
                    if self.manager.isDownloading {
                        // Overall progress
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("下载中...")
                                    .font(.callout.weight(.medium))
                                Spacer()
                                Text("\(Int(self.manager.overallProgress * 100))%")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: self.manager.overallProgress)
                                .tint(.blue)
                        }

                        Button("取消下载") {
                            self.manager.cancelDownloads()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    } else {
                        HStack {
                            Button {
                                Task { await self.manager.downloadAllModels() }
                            } label: {
                                Label("下载全部模型 (~\(totalMB)MB)", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!self.manager.qmdInstalled)

                            Text("模型存储在 ~/.cache/qmd/models/，仅需下载一次")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private func modelRow(_ model: QmdModel) -> some View {
        HStack(spacing: 10) {
            self.modelStateIcon(model.state)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.callout)
                Text("\(model.sizeMB) MB")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            switch model.state {
            case .downloading(let progress):
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .frame(width: 100)
                        .tint(.blue)
                    Text("\(Int(progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            case .completed:
                Text("已就绪")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed(let msg):
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .frame(maxWidth: 200, alignment: .trailing)
            case .pending:
                Text("待下载")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func modelStateIcon(_ state: QmdModel.DownloadState) -> some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .downloading:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .pending:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Config

    @ViewBuilder
    private var configSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.sectionTitle("配置")

            VStack(alignment: .leading, spacing: 12) {
                // Search mode
                HStack {
                    Text("搜索模式")
                        .font(.callout)
                    Spacer()
                    Picker("", selection: self.$manager.searchMode) {
                        Text("混合搜索 (推荐)").tag("query")
                        Text("语义搜索").tag("vsearch")
                        Text("关键词搜索").tag("search")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 200)
                    .onChange(of: self.manager.searchMode) { _, _ in
                        Task { await self.manager.savePluginConfigIfEnabled() }
                    }
                }

                // Auto recall
                SettingsToggleRow(
                    title: "自动召回",
                    subtitle: "对话前自动搜索相关记忆并注入上下文",
                    binding: Binding(
                        get: { self.manager.autoRecall },
                        set: { newValue in
                            self.manager.autoRecall = newValue
                            Task { await self.manager.savePluginConfigIfEnabled() }
                        }
                    ))

                // Min score threshold (only show when autoRecall is enabled)
                if self.manager.autoRecall {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("召回阈值")
                                .font(.callout)
                            Spacer()
                            Text("\(Int(self.manager.minScore * 100))%")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: self.$manager.minScore, in: 0.05...0.5, step: 0.05)
                            .onChange(of: self.manager.minScore) { _, _ in
                                Task { await self.manager.savePluginConfigIfEnabled() }
                            }
                        Text("相似度低于此阈值的记忆不会被召回。值越低召回越多但可能不相关，值越高召回越精准但可能遗漏。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Auto capture
                SettingsToggleRow(
                    title: "自动同步",
                    subtitle: "对话后自动将 MEMORY.md 同步到 QMD 索引",
                    binding: Binding(
                        get: { self.manager.autoCapture },
                        set: { newValue in
                            self.manager.autoCapture = newValue
                            Task { await self.manager.savePluginConfigIfEnabled() }
                        }
                    ))

                // Single toggle button for enable/disable QMD
                HStack {
                    Spacer()
                    if self.manager.isQmdEnabled {
                        Button("停用 QMD") {
                            Task { await self.manager.disableQmd() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    } else {
                        Button("启用 QMD") {
                            Task { await self.manager.savePluginConfig() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.04))
            .cornerRadius(8)
        }
    }

    // MARK: - Collections

    @ViewBuilder
    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    self.sectionTitle("索引集合")
                    Text("支持 Markdown (.md) 文件索引")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if self.manager.isLoadingCollections {
                    ProgressView().controlSize(.small)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.showAddCollection.toggle()
                    }
                } label: {
                    Label(self.showAddCollection ? "收起" : "添加", systemImage: self.showAddCollection ? "chevron.up" : "plus")
                }
                .buttonStyle(.bordered)
            }

            // Add collection form - show at top when expanded
            if self.showAddCollection {
                self.addCollectionForm
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if self.manager.collections.isEmpty && !self.showAddCollection {
                Text("暂无索引集合。点击「添加」按钮选择文档目录开始使用。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(self.manager.collections) { collection in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collection.name)
                                .font(.callout.weight(.medium))
                            Text(collection.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if let count = collection.fileCount {
                            Text("\(count) 文件")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            Task { await self.manager.removeCollection(name: collection.name) }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("删除集合")
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(6)
                }
            }
        }
    }

    private var addCollectionForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("添加新集合")
                    .font(.callout.weight(.medium))
                Spacer()
                Text("支持目录或单个 .md 文件")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                TextField("目录或文件路径", text: self.$newCollectionPath)
                    .textFieldStyle(.roundedBorder)

                Button("选择目录...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.message = "选择包含 Markdown 文件的目录"
                    panel.prompt = "选择"
                    if panel.runModal() == .OK, let url = panel.url {
                        self.newCollectionPath = url.path
                        if self.newCollectionName.isEmpty {
                            self.newCollectionName = url.lastPathComponent
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button("选择文件...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.allowedContentTypes = [.init(filenameExtension: "md")!]
                    panel.message = "选择 Markdown 文件"
                    panel.prompt = "选择"
                    if panel.runModal() == .OK, let url = panel.url {
                        self.newCollectionPath = url.path
                        if self.newCollectionName.isEmpty {
                            // Use filename without extension as collection name
                            self.newCollectionName = url.deletingPathExtension().lastPathComponent
                        }
                    }
                }
                .buttonStyle(.bordered)
            }

            TextField("集合名称（用于标识）", text: self.$newCollectionName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)

            HStack {
                Button("取消") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.showAddCollection = false
                    }
                    self.newCollectionPath = ""
                    self.newCollectionName = ""
                }
                .buttonStyle(.bordered)

                Button("添加并索引") {
                    Task {
                        await self.manager.addCollection(path: self.newCollectionPath, name: self.newCollectionName)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.showAddCollection = false
                        }
                        self.newCollectionPath = ""
                        self.newCollectionName = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.newCollectionPath.isEmpty || self.newCollectionName.isEmpty)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
struct QmdSettings_Previews: PreviewProvider {
    static var previews: some View {
        QmdSettings()
            .frame(width: SettingsTab.windowWidth, height: SettingsTab.windowHeight)
    }
}
#endif
