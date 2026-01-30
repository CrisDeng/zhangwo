import AppKit
import OpenClawDiscovery
import OpenClawIPC
import OpenClawKit
import Observation
import SwiftUI

struct GeneralSettings: View {
    @Bindable var state: AppState
    @AppStorage(cameraEnabledKey) private var cameraEnabled: Bool = false
    private let healthStore = HealthStore.shared
    private let gatewayManager = GatewayProcessManager.shared
    @State private var gatewayDiscovery = GatewayDiscoveryModel(
        localDisplayName: InstanceIdentity.displayName)
    @State private var gatewayStatus: GatewayEnvironmentStatus = .checking
    @State private var remoteStatus: RemoteStatus = .idle
    @State private var showRemoteAdvanced = false
    private let isPreview = ProcessInfo.processInfo.isPreview
    private var isNixMode: Bool { ProcessInfo.processInfo.isNixMode }
    private var remoteLabelWidth: CGFloat { 88 }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggleRow(
                        title: "OpenClaw 激活",
                        subtitle: "暂停以停止 OpenClaw 网关；消息将不会被处理。",
                        binding: self.activeBinding)

                    self.connectionSection

                    Divider()

                    SettingsToggleRow(
                        title: "登录时启动",
                        subtitle: "登录后自动启动 OpenClaw。",
                        binding: self.$state.launchAtLogin)

                    SettingsToggleRow(
                        title: "显示 Dock 图标",
                        subtitle: "在 Dock 中显示 OpenClaw，而不是仅在菜单栏显示。",
                        binding: self.$state.showDockIcon)

                    SettingsToggleRow(
                        title: "播放菜单栏图标动画",
                        subtitle: "启用状态图标的闲置眨眼和摆动动画。",
                        binding: self.$state.iconAnimationsEnabled)

                    SettingsToggleRow(
                        title: "允许 Canvas",
                        subtitle: "允许代理显示和控制 Canvas 面板。",
                        binding: self.$state.canvasEnabled)

                    SettingsToggleRow(
                        title: "允许相机",
                        subtitle: "允许代理通过内置相机拍摄照片或短视频。",
                        binding: self.$cameraEnabled)

                    SettingsToggleRow(
                        title: "启用 Peekaboo Bridge",
                        subtitle: "允许签名工具（如 `peekaboo`）通过 PeekabooBridge 驱动 UI 自动化。",
                        binding: self.$state.peekabooBridgeEnabled)

                    SettingsToggleRow(
                        title: "启用调试工具",
                        subtitle: "显示包含开发工具的调试选项卡。",
                        binding: self.$state.debugPaneEnabled)
                }

                Spacer(minLength: 12)
                HStack {
                    Spacer()
                    Button("退出 OpenClaw") { NSApp.terminate(nil) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .onAppear {
            guard !self.isPreview else { return }
            self.refreshGatewayStatus()
        }
        .onChange(of: self.state.canvasEnabled) { _, enabled in
            if !enabled {
                CanvasManager.shared.hideAll()
            }
        }
    }

    private var activeBinding: Binding<Bool> {
        Binding(
            get: { !self.state.isPaused },
            set: { self.state.isPaused = !$0 })
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OpenClaw 运行方式")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("模式", selection: self.$state.connectionMode) {
                Text("未配置").tag(AppState.ConnectionMode.unconfigured)
                Text("本地（此 Mac）").tag(AppState.ConnectionMode.local)
                Text("远程（其他主机）").tag(AppState.ConnectionMode.remote)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 260, alignment: .leading)

            if self.state.connectionMode == .unconfigured {
                Text("选择本地或远程以启动网关。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if self.state.connectionMode == .local {
                // In Nix mode, gateway is managed declaratively - no install buttons.
                if !self.isNixMode {
                    self.gatewayInstallerCard
                }
                TailscaleIntegrationSection(
                    connectionMode: self.state.connectionMode,
                    isPaused: self.state.isPaused)
                self.healthRow
            }

            if self.state.connectionMode == .remote {
                self.remoteCard
            }
        }
    }

    private var remoteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.remoteTransportRow

            if self.state.remoteTransport == .ssh {
                self.remoteSshRow
            } else {
                self.remoteDirectRow
            }

            GatewayDiscoveryInlineList(
                discovery: self.gatewayDiscovery,
                currentTarget: self.state.remoteTarget,
                currentUrl: self.state.remoteUrl,
                transport: self.state.remoteTransport)
            { gateway in
                self.applyDiscoveredGateway(gateway)
            }
            .padding(.leading, self.remoteLabelWidth + 10)

            self.remoteStatusView
                .padding(.leading, self.remoteLabelWidth + 10)

            if self.state.remoteTransport == .ssh {
                DisclosureGroup(isExpanded: self.$showRemoteAdvanced) {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("身份文件") {
                            TextField("/Users/you/.ssh/id_ed25519", text: self.$state.remoteIdentity)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 280)
                        }
                        LabeledContent("项目根目录") {
                            TextField("/home/you/Projects/openclaw", text: self.$state.remoteProjectRoot)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 280)
                        }
                        LabeledContent("CLI 路径") {
                            TextField("/Applications/OpenClaw.app/.../openclaw", text: self.$state.remoteCliPath)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 280)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("高级")
                        .font(.callout.weight(.semibold))
                }
            }

            // Diagnostics
            VStack(alignment: .leading, spacing: 4) {
                Text("控制通道")
                    .font(.caption.weight(.semibold))
                if !self.isControlStatusDuplicate || ControlChannel.shared.lastPingMs != nil {
                    let status = self.isControlStatusDuplicate ? nil : self.controlStatusLine
                    let ping = ControlChannel.shared.lastPingMs.map { "延迟 \(Int($0)) ms" }
                    let line = [status, ping].compactMap(\.self).joined(separator: " · ")
                    if !line.isEmpty {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let hb = HeartbeatStore.shared.lastEvent {
                    let ageText = age(from: Date(timeIntervalSince1970: hb.ts / 1000))
                    Text("最近心跳: \(hb.status) · \(ageText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let authLabel = ControlChannel.shared.authSourceLabel {
                    Text(authLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if self.state.remoteTransport == .ssh {
                Text("提示：启用 Tailscale 以获得稳定的远程访问。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("提示：使用 Tailscale Serve 以便网关获得有效的 HTTPS 证书。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .transition(.opacity)
        .onAppear { self.gatewayDiscovery.start() }
        .onDisappear { self.gatewayDiscovery.stop() }
    }

    private var remoteTransportRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("传输方式")
                .font(.callout.weight(.semibold))
                .frame(width: self.remoteLabelWidth, alignment: .leading)
            Picker("传输方式", selection: self.$state.remoteTransport) {
                Text("SSH 隧道").tag(AppState.RemoteTransport.ssh)
                Text("直连 (ws/wss)").tag(AppState.RemoteTransport.direct)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
        }
    }

    private var remoteSshRow: some View {
        let trimmedTarget = self.state.remoteTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let validationMessage = CommandResolver.sshTargetValidationMessage(trimmedTarget)
        let canTest = !trimmedTarget.isEmpty && validationMessage == nil

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Text("SSH 目标")
                    .font(.callout.weight(.semibold))
                    .frame(width: self.remoteLabelWidth, alignment: .leading)
                TextField("user@host[:22]", text: self.$state.remoteTarget)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                Button {
                    Task { await self.testRemote() }
                } label: {
                    if self.remoteStatus == .checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("测试远程连接")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.remoteStatus == .checking || !canTest)
            }
            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, self.remoteLabelWidth + 10)
            }
        }
    }

    private var remoteDirectRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text("网关")
                    .font(.callout.weight(.semibold))
                    .frame(width: self.remoteLabelWidth, alignment: .leading)
                TextField("wss://gateway.example.ts.net", text: self.$state.remoteUrl)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                Button {
                    Task { await self.testRemote() }
                } label: {
                    if self.remoteStatus == .checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("测试远程连接")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.remoteStatus == .checking || self.state.remoteUrl
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("直连模式需要 ws:// 或 wss:// URL（Tailscale Serve 使用 wss://<magicdns>）。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, self.remoteLabelWidth + 10)
        }
    }

    private var controlStatusLine: String {
        switch ControlChannel.shared.state {
        case .connected: "已连接"
        case .connecting: "连接中…"
        case .disconnected: "已断开"
        case let .degraded(msg): msg
        }
    }

    @ViewBuilder
    private var remoteStatusView: some View {
        switch self.remoteStatus {
        case .idle:
            EmptyView()
        case .checking:
            Text("测试中…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .ok:
            Label("就绪", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case let .failed(message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var isControlStatusDuplicate: Bool {
        guard case let .failed(message) = self.remoteStatus else { return false }
        return message == self.controlStatusLine
    }

    private var gatewayInstallerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(self.gatewayStatusColor)
                    .frame(width: 10, height: 10)
                Text(self.gatewayStatus.message)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let gatewayVersion = self.gatewayStatus.gatewayVersion,
               let required = self.gatewayStatus.requiredGateway,
               gatewayVersion != required
            {
                Text("已安装: \(gatewayVersion) · 需要: \(required)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let gatewayVersion = self.gatewayStatus.gatewayVersion {
                Text("检测到网关 \(gatewayVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let node = self.gatewayStatus.nodeVersion {
                Text("Node \(node)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case let .attachedExisting(details) = self.gatewayManager.status {
                Text(details ?? "使用现有网关实例")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let failure = self.gatewayManager.lastFailureReason {
                Text("最近失败: \(failure)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("重新检查") { self.refreshGatewayStatus() }
                .buttonStyle(.bordered)

            Text("网关在本地模式下通过 launchd (\(gatewayLaunchdLabel)) 自动启动。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }

    private func refreshGatewayStatus() {
        Task {
            let status = await Task.detached(priority: .utility) {
                GatewayEnvironment.check()
            }.value
            self.gatewayStatus = status
        }
    }

    private var gatewayStatusColor: Color {
        switch self.gatewayStatus.kind {
        case .ok: .green
        case .checking: .secondary
        case .missingNode, .missingGateway, .incompatible, .error: .orange
        }
    }

    private var healthCard: some View {
        let snapshot = self.healthStore.snapshot
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(self.healthStore.state.tint)
                    .frame(width: 10, height: 10)
                Text(self.healthStore.summaryLine)
                    .font(.callout.weight(.semibold))
            }

            if let snap = snapshot {
                let linkId = snap.channelOrder?.first(where: {
                    if let summary = snap.channels[$0] { return summary.linked != nil }
                    return false
                }) ?? snap.channels.keys.first(where: {
                    if let summary = snap.channels[$0] { return summary.linked != nil }
                    return false
                })
                let linkLabel =
                    linkId.flatMap { snap.channelLabels?[$0] } ??
                    linkId?.capitalized ??
                    "Link channel"
                let linkAge = linkId.flatMap { snap.channels[$0]?.authAgeMs }
                Text("\(linkLabel) auth age: \(healthAgeString(linkAge))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Session store: \(snap.sessions.path) (\(snap.sessions.count) entries)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let recent = snap.sessions.recent.first {
                    let lastActivity = recent.updatedAt != nil
                        ? relativeAge(from: Date(timeIntervalSince1970: (recent.updatedAt ?? 0) / 1000))
                        : "unknown"
                    Text("Last activity: \(recent.key) \(lastActivity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Last check: \(relativeAge(from: self.healthStore.lastSuccess))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = self.healthStore.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Health check pending…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await self.healthStore.refresh(onDemand: true) }
                } label: {
                    if self.healthStore.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("运行健康检查", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(self.healthStore.isRefreshing)

                Divider().frame(height: 18)

                Button {
                    self.revealLogs()
                } label: {
                    Label("显示日志", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }
}

private enum RemoteStatus: Equatable {
    case idle
    case checking
    case ok
    case failed(String)
}

extension GeneralSettings {
    private var healthRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle()
                    .fill(self.healthStore.state.tint)
                    .frame(width: 10, height: 10)
                Text(self.healthStore.summaryLine)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let detail = self.healthStore.detailLine {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("立即重试") {
                    Task { await HealthStore.shared.refresh(onDemand: true) }
                }
                .disabled(self.healthStore.isRefreshing)

                Button("打开日志") { self.revealLogs() }
                    .buttonStyle(.link)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    @MainActor
    func testRemote() async {
        self.remoteStatus = .checking
        let settings = CommandResolver.connectionSettings()
        if self.state.remoteTransport == .direct {
            let trimmedUrl = self.state.remoteUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedUrl.isEmpty else {
                self.remoteStatus = .failed("Set a gateway URL first")
                return
            }
            guard Self.isValidWsUrl(trimmedUrl) else {
                self.remoteStatus = .failed("Gateway URL must start with ws:// or wss://")
                return
            }
        } else {
            guard !settings.target.isEmpty else {
                self.remoteStatus = .failed("Set an SSH target first")
                return
            }

            // Step 1: basic SSH reachability check
            guard let sshCommand = Self.sshCheckCommand(
                target: settings.target,
                identity: settings.identity)
            else {
                self.remoteStatus = .failed("SSH target is invalid")
                return
            }
            let sshResult = await ShellExecutor.run(
                command: sshCommand,
                cwd: nil,
                env: nil,
                timeout: 8)

            guard sshResult.ok else {
                self.remoteStatus = .failed(self.formatSSHFailure(sshResult, target: settings.target))
                return
            }
        }

        // Step 2: control channel health check
        let originalMode = AppStateStore.shared.connectionMode
        do {
            try await ControlChannel.shared.configure(mode: .remote(
                target: settings.target,
                identity: settings.identity))
            let data = try await ControlChannel.shared.health(timeout: 10)
            if decodeHealthSnapshot(from: data) != nil {
                self.remoteStatus = .ok
            } else {
                self.remoteStatus = .failed("Control channel returned invalid health JSON")
            }
        } catch {
            self.remoteStatus = .failed(error.localizedDescription)
        }

        // Restore original mode if we temporarily switched
        switch originalMode {
        case .remote:
            break
        case .local:
            try? await ControlChannel.shared.configure(mode: .local)
        case .unconfigured:
            await ControlChannel.shared.disconnect()
        }
    }

    private static func isValidWsUrl(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "ws" || scheme == "wss" else { return false }
        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !host.isEmpty
    }

    private static func sshCheckCommand(target: String, identity: String) -> [String]? {
        guard let parsed = CommandResolver.parseSSHTarget(target) else { return nil }
        let options = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UpdateHostKeys=yes",
        ]
        let args = CommandResolver.sshArguments(
            target: parsed,
            identity: identity,
            options: options,
            remoteCommand: ["echo", "ok"])
        return ["/usr/bin/ssh"] + args
    }

    private func formatSSHFailure(_ response: Response, target: String) -> String {
        let payload = response.payload.flatMap { String(data: $0, encoding: .utf8) }
        let trimmed = payload?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        if let trimmed,
           trimmed.localizedCaseInsensitiveContains("host key verification failed")
        {
            let host = CommandResolver.parseSSHTarget(target)?.host ?? target
            return "SSH check failed: Host key verification failed. Remove the old key with " +
                "`ssh-keygen -R \(host)` and try again."
        }
        if let trimmed, !trimmed.isEmpty {
            if let message = response.message, message.hasPrefix("exit ") {
                return "SSH check failed: \(trimmed) (\(message))"
            }
            return "SSH check failed: \(trimmed)"
        }
        if let message = response.message {
            return "SSH check failed (\(message))"
        }
        return "SSH check failed"
    }

    private func revealLogs() {
        let target = LogLocator.bestLogFile()

        if let target {
            NSWorkspace.shared.selectFile(
                target.path,
                inFileViewerRootedAtPath: target.deletingLastPathComponent().path)
            return
        }

        let alert = NSAlert()
        alert.messageText = "未找到日志文件"
        alert.informativeText = """
        在 /tmp/openclaw/ 中查找 openclaw 日志。
        运行健康检查或发送消息以生成活动，然后重试。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func applyDiscoveredGateway(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) {
        MacNodeModeCoordinator.shared.setPreferredGatewayStableID(gateway.stableID)

        let host = gateway.tailnetDns ?? gateway.lanHost
        guard let host else { return }
        let user = NSUserName()
        if self.state.remoteTransport == .direct {
            if let url = GatewayDiscoveryHelpers.directUrl(for: gateway) {
                self.state.remoteUrl = url
            }
        } else {
            self.state.remoteTarget = GatewayDiscoveryModel.buildSSHTarget(
                user: user,
                host: host,
                port: gateway.sshPort)
            self.state.remoteCliPath = gateway.cliPath ?? ""
            OpenClawConfigFile.setRemoteGatewayUrl(host: host, port: gateway.gatewayPort)
        }
    }
}

private func healthAgeString(_ ms: Double?) -> String {
    guard let ms else { return "unknown" }
    return msToAge(ms)
}

#if DEBUG
struct GeneralSettings_Previews: PreviewProvider {
    static var previews: some View {
        GeneralSettings(state: .preview)
            .frame(width: SettingsTab.windowWidth, height: SettingsTab.windowHeight)
            .environment(TailscaleService.shared)
    }
}

@MainActor
extension GeneralSettings {
    static func exerciseForTesting() {
        let state = AppState(preview: true)
        state.connectionMode = .remote
        state.remoteTransport = .ssh
        state.remoteTarget = "user@host:2222"
        state.remoteUrl = "wss://gateway.example.ts.net"
        state.remoteIdentity = "/tmp/id_ed25519"
        state.remoteProjectRoot = "/tmp/openclaw"
        state.remoteCliPath = "/tmp/openclaw"

        let view = GeneralSettings(state: state)
        view.gatewayStatus = GatewayEnvironmentStatus(
            kind: .ok,
            nodeVersion: "1.0.0",
            gatewayVersion: "1.0.0",
            requiredGateway: nil,
            message: "Gateway ready")
        view.remoteStatus = .failed("SSH failed")
        view.showRemoteAdvanced = true
        _ = view.body

        state.connectionMode = .unconfigured
        _ = view.body

        state.connectionMode = .local
        view.gatewayStatus = GatewayEnvironmentStatus(
            kind: .error("Gateway offline"),
            nodeVersion: nil,
            gatewayVersion: nil,
            requiredGateway: nil,
            message: "Gateway offline")
        _ = view.body
    }
}
#endif
