import AppKit
import OpenClawChatUI
import OpenClawDiscovery
import OpenClawIPC
import OpenClawProtocol
import SwiftUI

extension OnboardingView {
    @ViewBuilder
    func pageView(for pageIndex: Int) -> some View {
        switch pageIndex {
        case 0:
            self.welcomePage()
        case 1:
            self.connectionPage()
        case 2:
            self.anthropicAuthPage()
        case 3:
            self.wizardPage()
        case 5:
            self.permissionsPage()
        case 6:
            self.cliPage()
        case 7:
            self.qqChannelPage()
        case 8:
            self.onboardingChatPage()
        case 9:
            self.readyPage()
        default:
            EmptyView()
        }
    }

    func welcomePage() -> some View {
        self.onboardingPage {
            VStack(spacing: 22) {
                Text("欢迎使用 OpenClaw")
                    .font(.largeTitle.weight(.semibold))
                Text("OpenClaw 是一款功能强大的个人 AI 助手，连接 QQ ，打造您专属的Jarvis 私人助理")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 560)
                    .fixedSize(horizontal: false, vertical: true)

                self.onboardingCard(spacing: 10, padding: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color(nsColor: .systemOrange))
                            .frame(width: 22)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("安全提示")
                                .font(.headline)
                            Text(
                                "连接的 AI 代理（如 Claude）可以在您的 Mac 上执行强大的操作，" +
                                    "包括运行命令、读写文件和截取屏幕——" +
                                    "具体取决于您授予的权限。\n\n" +
                                    "请确保您了解风险并信任所使用的提示词和集成功能后，再启用 OpenClaw。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: 520)
            }
            .padding(.top, 16)
        }
    }

    func connectionPage() -> some View {
        self.onboardingPage {
            Text("选择您的网关")
                .font(.largeTitle.weight(.semibold))
            Text(
                "OpenClaw 使用一个持续运行的网关。选择本机、" +
                    "连接附近发现的网关，或稍后配置。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)

            self.onboardingCard(spacing: 12, padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    let hasBundledRuntime = CommandResolver.hasBundledRuntime()
                    let localSubtitle: String = {
                        if hasBundledRuntime {
                            return "已内置运行时，网关将在本机自动启动。"
                        }
                        guard let probe = self.localGatewayProbe else {
                            return "网关将在本机自动启动。"
                        }
                        let base = probe.expected
                            ? "检测到现有网关"
                            : "端口 \(probe.port) 已被占用"
                        let command = probe.command.isEmpty ? "" : " (\(probe.command) pid \(probe.pid))"
                        return "\(base)\(command)。将自动连接。"
                    }()
                    self.connectionChoiceButton(
                        title: "本机",
                        subtitle: localSubtitle,
                        selected: self.state.connectionMode == .local)
                    {
                        self.selectLocalGateway()
                    }

                    Divider().padding(.vertical, 4)

                    HStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(self.gatewayDiscovery.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if self.gatewayDiscovery.gateways.isEmpty {
                            ProgressView().controlSize(.small)
                            Button("刷新") {
                                self.gatewayDiscovery.refreshWideAreaFallbackNow(timeoutSeconds: 5.0)
                            }
                            .buttonStyle(.link)
                            .help("重试 Tailscale 发现 (DNS-SD)。")
                        }
                        Spacer(minLength: 0)
                    }

                    if self.gatewayDiscovery.gateways.isEmpty {
                        Text("正在搜索附近的网关…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("附近的网关")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                            ForEach(self.gatewayDiscovery.gateways.prefix(6)) { gateway in
                                self.connectionChoiceButton(
                                    title: gateway.displayName,
                                    subtitle: self.gatewaySubtitle(for: gateway),
                                    selected: self.isSelectedGateway(gateway))
                                {
                                    self.selectRemoteGateway(gateway)
                                }
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor)))
                    }

                    self.connectionChoiceButton(
                        title: "稍后配置",
                        subtitle: "暂不启动网关。",
                        selected: self.state.connectionMode == .unconfigured)
                    {
                        self.selectUnconfiguredGateway()
                    }

                    Button(self.showAdvancedConnection ? "隐藏高级选项" : "高级选项…") {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            self.showAdvancedConnection.toggle()
                        }
                        if self.showAdvancedConnection, self.state.connectionMode != .remote {
                            self.state.connectionMode = .remote
                        }
                    }
                    .buttonStyle(.link)

                    if self.showAdvancedConnection {
                        let labelWidth: CGFloat = 110
                        let fieldWidth: CGFloat = 320

                        VStack(alignment: .leading, spacing: 10) {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                GridRow {
                                    Text("传输方式")
                                        .font(.callout.weight(.semibold))
                                        .frame(width: labelWidth, alignment: .leading)
                                    Picker("传输方式", selection: self.$state.remoteTransport) {
                                        Text("SSH 隧道").tag(AppState.RemoteTransport.ssh)
                                        Text("直连 (ws/wss)").tag(AppState.RemoteTransport.direct)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: fieldWidth)
                                }
                                if self.state.remoteTransport == .direct {
                                    GridRow {
                                        Text("网关 URL")
                                            .font(.callout.weight(.semibold))
                                            .frame(width: labelWidth, alignment: .leading)
                                        TextField("wss://gateway.example.ts.net", text: self.$state.remoteUrl)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: fieldWidth)
                                    }
                                }
                                if self.state.remoteTransport == .ssh {
                                    GridRow {
                                        Text("SSH 目标")
                                            .font(.callout.weight(.semibold))
                                            .frame(width: labelWidth, alignment: .leading)
                                        TextField("user@host[:port]", text: self.$state.remoteTarget)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: fieldWidth)
                                    }
                                    if let message = CommandResolver.sshTargetValidationMessage(self.state.remoteTarget) {
                                        GridRow {
                                            Text("")
                                                .frame(width: labelWidth, alignment: .leading)
                                            Text(message)
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                                .frame(width: fieldWidth, alignment: .leading)
                                        }
                                    }
                                    GridRow {
                                        Text("密钥文件")
                                            .font(.callout.weight(.semibold))
                                            .frame(width: labelWidth, alignment: .leading)
                                        TextField("/Users/you/.ssh/id_ed25519", text: self.$state.remoteIdentity)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: fieldWidth)
                                    }
                                    GridRow {
                                        Text("项目根目录")
                                            .font(.callout.weight(.semibold))
                                            .frame(width: labelWidth, alignment: .leading)
                                        TextField("/home/you/Projects/openclaw", text: self.$state.remoteProjectRoot)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: fieldWidth)
                                    }
                                    GridRow {
                                        Text("CLI 路径")
                                            .font(.callout.weight(.semibold))
                                            .frame(width: labelWidth, alignment: .leading)
                                        TextField(
                                            "/Applications/OpenClaw.app/.../openclaw",
                                            text: self.$state.remoteCliPath)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: fieldWidth)
                                    }
                                }
                            }

                            Text(self.state.remoteTransport == .direct
                                ? "提示：使用 Tailscale Serve 以获取有效的 HTTPS 证书。"
                                : "提示：保持 Tailscale 启用，以确保网关可访问。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }

    func gatewaySubtitle(for gateway: GatewayDiscoveryModel.DiscoveredGateway) -> String? {
        if self.state.remoteTransport == .direct {
            return GatewayDiscoveryHelpers.directUrl(for: gateway) ?? "仅限网关配对"
        }
        if let host = GatewayDiscoveryHelpers.sanitizedTailnetHost(gateway.tailnetDns) ?? gateway.lanHost {
            let portSuffix = gateway.sshPort != 22 ? " · ssh \(gateway.sshPort)" : ""
            return "\(host)\(portSuffix)"
        }
        return "仅限网关配对"
    }

    func isSelectedGateway(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) -> Bool {
        guard self.state.connectionMode == .remote else { return false }
        let preferred = self.preferredGatewayID ?? GatewayDiscoveryPreferences.preferredStableID()
        return preferred == gateway.stableID
    }

    func connectionChoiceButton(
        title: String,
        subtitle: String?,
        selected: Bool,
        action: @escaping () -> Void) -> some View
    {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                action()
            }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "arrow.right.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor.opacity(0.45) : Color.clear,
                        lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    func anthropicAuthPage() -> some View {
        self.onboardingPage {
            Text("连接 Claude")
                .font(.largeTitle.weight(.semibold))
            Text("为您的模型提供所需的令牌！")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 540)
                .fixedSize(horizontal: false, vertical: true)
            Text("OpenClaw 支持任何模型——我们强烈推荐使用 Opus 4.5 以获得最佳体验。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 540)
                .fixedSize(horizontal: false, vertical: true)

            self.onboardingCard(spacing: 12, padding: 16) {
                HStack(alignment: .center, spacing: 10) {
                    Circle()
                        .fill(self.anthropicAuthVerified ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(
                        self.anthropicAuthConnected
                            ? (self.anthropicAuthVerified
                                ? "Claude 已连接 (OAuth) — 已验证"
                                : "Claude 已连接 (OAuth)")
                            : "尚未连接")
                        .font(.headline)
                    Spacer()
                }

                if self.anthropicAuthConnected, self.anthropicAuthVerifying {
                    Text("正在验证 OAuth…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !self.anthropicAuthConnected {
                    Text(self.anthropicAuthDetectedStatus.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if self.anthropicAuthVerified, let date = self.anthropicAuthVerifiedAt {
                    Text("检测到有效的 OAuth (\(date.formatted(date: .abbreviated, time: .shortened)))。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(
                    "这让 OpenClaw 可以立即使用 Claude。凭据存储在 " +
                        "`~/.openclaw/credentials/oauth.json`（仅限所有者访问）。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Text(OpenClawOAuthStore.oauthURL().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([OpenClawOAuthStore.oauthURL()])
                    }
                    .buttonStyle(.bordered)

                    Button("刷新") {
                        self.refreshAnthropicOAuthStatus()
                    }
                    .buttonStyle(.bordered)
                }

                Divider().padding(.vertical, 2)

                HStack(spacing: 12) {
                    if !self.anthropicAuthVerified {
                        if self.anthropicAuthConnected {
                            Button("验证") {
                                Task { await self.verifyAnthropicOAuthIfNeeded(force: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(self.anthropicAuthBusy || self.anthropicAuthVerifying)

                            if self.anthropicAuthVerificationFailed {
                                Button("重新认证 (OAuth)") {
                                    self.startAnthropicOAuth()
                                }
                                .buttonStyle(.bordered)
                                .disabled(self.anthropicAuthBusy || self.anthropicAuthVerifying)
                            }
                        } else {
                            Button {
                                self.startAnthropicOAuth()
                            } label: {
                                if self.anthropicAuthBusy {
                                    ProgressView()
                                } else {
                                    Text("打开 Claude 登录 (OAuth)")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(self.anthropicAuthBusy)
                        }
                    }
                }

                if !self.anthropicAuthVerified, self.anthropicAuthPKCE != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("粘贴 `code#state` 值")
                            .font(.headline)
                        TextField("code#state", text: self.$anthropicAuthCode)
                            .textFieldStyle(.roundedBorder)

                        Toggle("从剪贴板自动检测", isOn: self.$anthropicAuthAutoDetectClipboard)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .disabled(self.anthropicAuthBusy)

                        Toggle("检测到后自动连接", isOn: self.$anthropicAuthAutoConnectClipboard)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .disabled(self.anthropicAuthBusy)

                        Button("连接") {
                            Task { await self.finishAnthropicOAuth() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            self.anthropicAuthBusy ||
                                self.anthropicAuthCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .onReceive(Self.clipboardPoll) { _ in
                        self.pollAnthropicClipboardIfNeeded()
                    }
                }

                self.onboardingCard(spacing: 8, padding: 12) {
                    Text("API 密钥（高级）")
                        .font(.headline)
                    Text(
                        "您也可以使用 Anthropic API 密钥，但此界面目前仅提供说明 " +
                            "（GUI 应用不会自动继承您的 shell 环境变量，如 `ANTHROPIC_API_KEY`）。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .shadow(color: .clear, radius: 0)
                .background(Color.clear)

                if let status = self.anthropicAuthStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task { await self.verifyAnthropicOAuthIfNeeded() }
    }

    func permissionsPage() -> some View {
        self.onboardingPage {
            Text("授予权限")
                .font(.largeTitle.weight(.semibold))
            Text("这些 macOS 权限允许 OpenClaw 在本机上自动化应用程序并获取上下文。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)

            self.onboardingCard(spacing: 8, padding: 12) {
                ForEach(Capability.allCases, id: \.self) { cap in
                    PermissionRow(
                        capability: cap,
                        status: self.permissionMonitor.status[cap] ?? false,
                        compact: true)
                    {
                        Task { await self.request(cap) }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await self.refreshPerms() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("刷新状态")
                    if self.isRequesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    func cliPage() -> some View {
        self.onboardingPage {
            Text("安装命令行工具")
                .font(.largeTitle.weight(.semibold))
            Text("本地模式必需：安装 `openclaw` 以便 launchd 可以运行网关。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)

            self.onboardingCard(spacing: 10) {
                HStack(spacing: 12) {
                    Button {
                        Task { await self.installCLI() }
                    } label: {
                        let title = self.cliInstalled ? "重新安装 CLI" : "安装 CLI"
                        ZStack {
                            Text(title)
                                .opacity(self.installingCLI ? 0 : 1)
                            if self.installingCLI {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(self.installingCLI)

                    Button(self.copied ? "已复制" : "复制安装命令") {
                        self.copyToPasteboard(self.devLinkCommand)
                    }
                    .disabled(self.installingCLI)

                    if self.cliInstalled, let loc = self.cliInstallLocation {
                        Label("已安装至 \(loc)", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }

                if let cliStatus {
                    Text(cliStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !self.cliInstalled, self.cliInstallLocation == nil {
                    Text(
                        """
                        安装用户空间的 Node 22+ 运行时和 CLI（无需 Homebrew）。
                        随时可重新运行以重装或更新。
                        """)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    func workspacePage() -> some View {
        self.onboardingPage {
            Text("代理工作区")
                .font(.largeTitle.weight(.semibold))
            Text(
                "OpenClaw 从专用工作区运行代理，以便它可以加载 `AGENTS.md` " +
                    "并在那里写入文件，而不会与您的其他项目混淆。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                .fixedSize(horizontal: false, vertical: true)

            self.onboardingCard(spacing: 10) {
                if self.state.connectionMode == .remote {
                    Text("检测到远程网关")
                        .font(.headline)
                    Text(
                        "请在远程主机上创建工作区（先通过 SSH 连接）。" +
                            "macOS 应用目前无法通过 SSH 在您的网关上写入文件。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(self.copied ? "已复制" : "复制设置命令") {
                        self.copyToPasteboard(self.workspaceBootstrapCommand)
                    }
                    .buttonStyle(.bordered)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("工作区文件夹")
                            .font(.headline)
                        TextField(
                            AgentWorkspace.displayPath(for: OpenClawConfigFile.defaultWorkspaceURL()),
                            text: self.$workspacePath)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 12) {
                            Button {
                                Task { await self.applyWorkspace() }
                            } label: {
                                if self.workspaceApplying {
                                    ProgressView()
                                } else {
                                    Text("创建工作区")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(self.workspaceApplying)

                            Button("打开文件夹") {
                                let url = AgentWorkspace.resolveWorkspaceURL(from: self.workspacePath)
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(.bordered)
                            .disabled(self.workspaceApplying)

                            Button("保存到配置") {
                                Task {
                                    let url = AgentWorkspace.resolveWorkspaceURL(from: self.workspacePath)
                                    let saved = await self.saveAgentWorkspace(AgentWorkspace.displayPath(for: url))
                                    if saved {
                                        self.workspaceStatus =
                                            "已保存到 ~/.openclaw/openclaw.json (agents.defaults.workspace)"
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(self.workspaceApplying)
                        }
                    }

                    if let workspaceStatus {
                        Text(workspaceStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text(
                            "提示：编辑此文件夹中的 AGENTS.md 来定制助手的行为。" +
                                "为了备份，可以将工作区设为私有 git 仓库，这样您的代理的" +
                                "「记忆」就有版本控制了。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    func onboardingChatPage() -> some View {
        VStack(spacing: 16) {
            Text("认识您的代理")
                .font(.largeTitle.weight(.semibold))
            Text(
                "这是一个专属的入门聊天。您的代理将自我介绍，" +
                    "了解您是谁，并帮助您连接 WhatsApp 或 Telegram（如果需要）。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)

            self.onboardingGlassCard(padding: 8) {
                OpenClawChatView(viewModel: self.onboardingChatModel, style: .onboarding)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 28)
        .frame(width: self.pageWidth, height: self.contentHeight, alignment: .top)
    }

    func readyPage() -> some View {
        self.onboardingPage {
            Text("设置完成")
                .font(.largeTitle.weight(.semibold))
            self.onboardingCard {
                if self.state.connectionMode == .unconfigured {
                    self.featureRow(
                        title: "稍后配置",
                        subtitle: "准备好后，在 设置 → 通用 中选择本地或远程。",
                        systemImage: "gearshape")
                    Divider()
                        .padding(.vertical, 6)
                }
                if self.state.connectionMode == .remote {
                    self.featureRow(
                        title: "远程网关检查清单",
                        subtitle: """
                        在您的网关主机上：安装/更新 `openclaw` 包并确保凭据存在
                        （通常是 `~/.openclaw/credentials/oauth.json`）。然后根据需要重新连接。
                        """,
                        systemImage: "network")
                    Divider()
                        .padding(.vertical, 6)
                }
                self.featureRow(
                    title: "打开菜单栏面板",
                    subtitle: "点击 OpenClaw 菜单栏图标即可快速聊天和查看状态。",
                    systemImage: "bubble.left.and.bubble.right")
                self.featureActionRow(
                    title: "连接 WhatsApp 或 Telegram",
                    subtitle: "打开 设置 → 频道 来关联频道并监控状态。",
                    systemImage: "link",
                    buttonTitle: "打开 设置 → 频道")
                {
                    self.openSettings(tab: .channels)
                }
                self.featureRow(
                    title: "试试语音唤醒",
                    subtitle: "在设置中启用语音唤醒，通过实时转录叠加层实现免提命令。",
                    systemImage: "waveform.circle")
                self.featureRow(
                    title: "使用面板 + 画布",
                    subtitle: "打开菜单栏面板快速聊天；代理可以在画布中显示预览" +
                        "和更丰富的视觉效果。",
                    systemImage: "rectangle.inset.filled.and.person.filled")
                self.featureActionRow(
                    title: "赋予代理更多能力",
                    subtitle: "从 设置 → 技能 启用可选技能（Peekaboo、oracle、camsnap 等）。",
                    systemImage: "sparkles",
                    buttonTitle: "打开 设置 → 技能")
                {
                    self.openSettings(tab: .skills)
                }
                self.skillsOverview
                Toggle("登录时启动", isOn: self.$state.launchAtLogin)
                    .onChange(of: self.state.launchAtLogin) { _, newValue in
                        AppStateStore.updateLaunchAtLogin(enabled: newValue)
                    }
            }
        }
        .task { await self.maybeLoadOnboardingSkills() }
    }

    private func maybeLoadOnboardingSkills() async {
        guard !self.didLoadOnboardingSkills else { return }
        self.didLoadOnboardingSkills = true
        await self.onboardingSkillsModel.refresh()
    }

    func qqChannelPage() -> some View {
        self.onboardingPage {
            Text("Configure QQ Channel")
                .font(.largeTitle.weight(.semibold))
            Text("QQ Channel 是腾讯 QQ 开放平台提供的机器人服务。配置完成后，您可以通过 QQ 频道与 AI 助手进行交互。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)

            self.onboardingCard(spacing: 14, padding: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("QQ 开放平台配置")
                        .font(.headline)

                    Text("请在 QQ 开放平台创建应用，获取 App ID 和 App Secret，然后填写到下方。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("App ID")
                                .font(.callout.weight(.semibold))
                            TextField("请输入 App ID", text: self.$qqAppId)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 360)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("App Secret")
                                .font(.callout.weight(.semibold))
                            TextField("请输入 App Secret", text: self.$qqAppSecret)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 360)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await self.saveQQConfig() }
                        } label: {
                            if self.qqConfigSaving {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Save Configuration")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(self.qqConfigSaving || self.qqAppId.isEmpty || self.qqAppSecret.isEmpty)

                        Button("Skip") {
                            self.handleNext()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let status = self.qqConfigStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(status.contains("Error") ? .red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("您也可以稍后在设置 → Channels → QQ 中配置此信息。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func saveQQConfig() async {
        self.qqConfigSaving = true
        self.qqConfigStatus = nil
        defer { self.qqConfigSaving = false }

        do {
            let config: [String: AnyCodable] = [
                "channels": AnyCodable([
                    "qq": [
                        "appId": self.qqAppId,
                        "appSecret": self.qqAppSecret
                    ]
                ])
            ]
            let _: AnyCodable = try await GatewayConnection.shared.requestDecoded(
                method: .configSet,
                params: ["config": AnyCodable(config)])
            self.qqConfigStatus = "Configuration saved successfully!"
        } catch {
            self.qqConfigStatus = "Error: \(error.localizedDescription)"
        }
    }

    private var skillsOverview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 6)

            HStack(spacing: 10) {
                Text("已包含的技能")
                    .font(.headline)
                Spacer(minLength: 0)
                if self.onboardingSkillsModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("刷新") {
                        Task { await self.onboardingSkillsModel.refresh() }
                    }
                    .buttonStyle(.link)
                }
            }

            if let error = self.onboardingSkillsModel.error {
                VStack(alignment: .leading, spacing: 4) {
                    Text("无法从网关加载技能。")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(
                        "请确保网关正在运行并已连接，" +
                            "然后点击刷新（或打开 设置 → 技能）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("详情：\(error)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if self.onboardingSkillsModel.skills.isEmpty {
                Text("暂无技能报告。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(self.onboardingSkillsModel.skills) { skill in
                            HStack(alignment: .top, spacing: 10) {
                                Text(skill.emoji ?? "✨")
                                    .font(.callout)
                                    .frame(width: 22, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(skill.name)
                                        .font(.callout.weight(.semibold))
                                    Text(skill.description)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(NSColor.windowBackgroundColor)))
                }
                .frame(maxHeight: 160)
            }
        }
    }
}
