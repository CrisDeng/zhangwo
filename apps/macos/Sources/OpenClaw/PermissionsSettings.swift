import OpenClawIPC
import OpenClawKit
import CoreLocation
import SwiftUI

struct PermissionsSettings: View {
    let status: [Capability: Bool]
    let refresh: () async -> Void
    let showOnboarding: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SystemRunSettingsView()

            Text("请授予这些权限，以便 OpenClaw 在需要时进行通知和屏幕捕获。")
                .padding(.top, 4)

            PermissionStatusList(status: self.status, refresh: self.refresh)
                .padding(.horizontal, 2)
                .padding(.vertical, 6)

            LocationAccessSettings()

            Button("重新开始引导") { self.showOnboarding() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

private struct LocationAccessSettings: View {
    @AppStorage(locationModeKey) private var locationModeRaw: String = OpenClawLocationMode.off.rawValue
    @AppStorage(locationPreciseKey) private var locationPreciseEnabled: Bool = true
    @State private var lastLocationModeRaw: String = OpenClawLocationMode.off.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("位置访问")
                .font(.body)

            Picker("", selection: self.$locationModeRaw) {
                Text("关闭").tag(OpenClawLocationMode.off.rawValue)
                Text("使用期间").tag(OpenClawLocationMode.whileUsing.rawValue)
                Text("始终").tag(OpenClawLocationMode.always.rawValue)
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Toggle("精确位置", isOn: self.$locationPreciseEnabled)
                .disabled(self.locationMode == .off)

            Text("选择「始终」可能需要在系统设置中批准后台位置权限。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            self.lastLocationModeRaw = self.locationModeRaw
        }
        .onChange(of: self.locationModeRaw) { _, newValue in
            let previous = self.lastLocationModeRaw
            self.lastLocationModeRaw = newValue
            guard let mode = OpenClawLocationMode(rawValue: newValue) else { return }
            Task {
                let granted = await self.requestLocationAuthorization(mode: mode)
                if !granted {
                    await MainActor.run {
                        self.locationModeRaw = previous
                        self.lastLocationModeRaw = previous
                    }
                }
            }
        }
    }

    private var locationMode: OpenClawLocationMode {
        OpenClawLocationMode(rawValue: self.locationModeRaw) ?? .off
    }

    private func requestLocationAuthorization(mode: OpenClawLocationMode) async -> Bool {
        guard mode != .off else { return true }
        guard CLLocationManager.locationServicesEnabled() else {
            await MainActor.run { LocationPermissionHelper.openSettings() }
            return false
        }

        let status = CLLocationManager().authorizationStatus
        let requireAlways = mode == .always
        if PermissionManager.isLocationAuthorized(status: status, requireAlways: requireAlways) {
            return true
        }
        let updated = await LocationPermissionRequester.shared.request(always: requireAlways)
        return PermissionManager.isLocationAuthorized(status: updated, requireAlways: requireAlways)
    }
}

struct PermissionStatusList: View {
    let status: [Capability: Bool]
    let refresh: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Capability.allCases, id: \.self) { cap in
                PermissionRow(capability: cap, status: self.status[cap] ?? false) {
                    Task { await self.handle(cap) }
                }
            }
            Button {
                Task { await self.refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.footnote)
            .padding(.top, 2)
            .help("刷新权限状态")
        }
    }

    @MainActor
    private func handle(_ cap: Capability) async {
        _ = await PermissionManager.ensure([cap], interactive: true)
        await self.refresh()
    }
}

struct PermissionRow: View {
    let capability: Capability
    let status: Bool
    let compact: Bool
    let action: () -> Void

    init(capability: Capability, status: Bool, compact: Bool = false, action: @escaping () -> Void) {
        self.capability = capability
        self.status = status
        self.compact = compact
        self.action = action
    }

    var body: some View {
        HStack(spacing: self.compact ? 10 : 12) {
            ZStack {
                Circle().fill(self.status ? Color.green.opacity(0.2) : Color.gray.opacity(0.15))
                    .frame(width: self.iconSize, height: self.iconSize)
                Image(systemName: self.icon)
                    .foregroundStyle(self.status ? Color.green : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(self.title).font(.body.weight(.semibold))
                Text(self.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if self.status {
                Label("已授权", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("授权") { self.action() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, self.compact ? 4 : 6)
    }

    private var iconSize: CGFloat { self.compact ? 28 : 32 }

    private var title: String {
        switch self.capability {
        case .appleScript: "自动化 (AppleScript)"
        case .notifications: "通知"
        case .accessibility: "辅助功能"
        case .screenRecording: "屏幕录制"
        case .microphone: "麦克风"
        case .speechRecognition: "语音识别"
        case .camera: "相机"
        case .location: "位置"
        }
    }

    private var subtitle: String {
        switch self.capability {
        case .appleScript:
            "控制其他应用（如终端）执行自动化操作"
        case .notifications: "显示代理活动的桌面通知"
        case .accessibility: "在需要时控制界面元素"
        case .screenRecording: "捕获屏幕用于上下文或截图"
        case .microphone: "允许语音唤醒和音频捕获"
        case .speechRecognition: "在设备上转录语音唤醒触发词"
        case .camera: "从相机拍摄照片和视频"
        case .location: "在代理请求时共享位置"
        }
    }

    private var icon: String {
        switch self.capability {
        case .appleScript: "applescript"
        case .notifications: "bell"
        case .accessibility: "hand.raised"
        case .screenRecording: "display"
        case .microphone: "mic"
        case .speechRecognition: "waveform"
        case .camera: "camera"
        case .location: "location"
        }
    }
}

#if DEBUG
struct PermissionsSettings_Previews: PreviewProvider {
    static var previews: some View {
        PermissionsSettings(
            status: [
                .appleScript: true,
                .notifications: true,
                .accessibility: false,
                .screenRecording: false,
                .microphone: true,
                .speechRecognition: false,
            ],
            refresh: {},
            showOnboarding: {})
            .frame(width: SettingsTab.windowWidth, height: SettingsTab.windowHeight)
    }
}
#endif
