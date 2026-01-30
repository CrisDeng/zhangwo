import SwiftUI

extension ChannelsSettings {
    func formSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    func channelHeaderActions(_ channel: ChannelItem) -> some View {
        HStack(spacing: 8) {
            if channel.id == "whatsapp" {
                Button("Logout") {
                    Task { await self.store.logoutWhatsApp() }
                }
                .buttonStyle(.bordered)
                .disabled(self.store.whatsappBusy)
            }

            if channel.id == "telegram" {
                Button("Logout") {
                    Task { await self.store.logoutTelegram() }
                }
                .buttonStyle(.bordered)
                .disabled(self.store.telegramBusy)
            }

            Button {
                Task { await self.store.refresh(probe: true) }
            } label: {
                if self.store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Refresh")
                }
            }
            .buttonStyle(.bordered)
            .disabled(self.store.isRefreshing)
        }
        .controlSize(.small)
    }

    var whatsAppSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.formSection("Linking") {
                if let message = self.store.whatsappLoginMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let qr = self.store.whatsappLoginQrDataUrl, let image = self.qrImage(from: qr) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 180, height: 180)
                        .cornerRadius(8)
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await self.store.startWhatsAppLogin(force: false) }
                    } label: {
                        if self.store.whatsappBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Show QR")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(self.store.whatsappBusy)

                    Button("Relink") {
                        Task { await self.store.startWhatsAppLogin(force: true) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(self.store.whatsappBusy)
                }
                .font(.caption)
            }

            self.configEditorSection(channelId: "whatsapp")
        }
    }

    var qqSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.formSection("About QQ Channel") {
                Text("QQ Channel 是腾讯 QQ 开放平台提供的机器人服务。配置完成后，您可以通过 QQ 频道与 AI 助手进行交互。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("您需要在 QQ 开放平台创建应用并获取 App ID 和 App Secret。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            self.formSection("Connection") {
                HStack(spacing: 12) {
                    Button {
                        Task { await self.store.testQQConnection() }
                    } label: {
                        if self.store.qqTestingConnection {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(self.store.qqTestingConnection)

                    if let result = self.store.qqConnectionTestResult {
                        if result.success {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Label(result.message ?? "Connection failed", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }
            }

            self.qqConfigSection
        }
    }

    private var qqConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.formSection("Configuration") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("App ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Enter App ID", text: self.qqAppIdBinding)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("App Secret")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Enter App Secret", text: self.qqAppSecretBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            self.configStatusMessage

            HStack(spacing: 12) {
                Button {
                    Task { await self.store.saveConfigDraft() }
                } label: {
                    if self.store.isSavingConfig {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.store.isSavingConfig || !self.store.configDirty)

                Button("Reload") {
                    Task { await self.store.reloadConfigDraft() }
                }
                .buttonStyle(.bordered)
                .disabled(self.store.isSavingConfig)

                Spacer()
            }
            .font(.caption)
        }
    }

    private var qqAppIdBinding: Binding<String> {
        Binding(
            get: {
                let path: ConfigPath = [.key("channels"), .key("qqbot"), .key("appId")]
                return self.store.configValue(at: path) as? String ?? ""
            },
            set: { newValue in
                let path: ConfigPath = [.key("channels"), .key("qqbot"), .key("appId")]
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                self.store.updateConfigValue(path: path, value: trimmed.isEmpty ? nil : trimmed)
            }
        )
    }

    private var qqAppSecretBinding: Binding<String> {
        Binding(
            get: {
                let path: ConfigPath = [.key("channels"), .key("qqbot"), .key("clientSecret")]
                return self.store.configValue(at: path) as? String ?? ""
            },
            set: { newValue in
                let path: ConfigPath = [.key("channels"), .key("qqbot"), .key("clientSecret")]
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                self.store.updateConfigValue(path: path, value: trimmed.isEmpty ? nil : trimmed)
            }
        )
    }

    @ViewBuilder
    func genericChannelSection(_ channel: ChannelItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            self.configEditorSection(channelId: channel.id)
        }
    }

    @ViewBuilder
    private func configEditorSection(channelId: String) -> some View {
        self.formSection("Configuration") {
            ChannelConfigForm(store: self.store, channelId: channelId)
        }

        self.configStatusMessage

        HStack(spacing: 12) {
            Button {
                Task { await self.store.saveConfigDraft() }
            } label: {
                if self.store.isSavingConfig {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Save")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(self.store.isSavingConfig || !self.store.configDirty)

            Button("Reload") {
                Task { await self.store.reloadConfigDraft() }
            }
            .buttonStyle(.bordered)
            .disabled(self.store.isSavingConfig)

            Spacer()
        }
        .font(.caption)
    }

    @ViewBuilder
    var configStatusMessage: some View {
        if let status = self.store.configStatus {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
