import Foundation

/// Startup diagnostics for verifying runtime environment on app launch.
/// Logs detailed status of Node, Gateway, and extension plugins.
enum StartupDiagnostics {
    private static let logger = Logger(subsystem: "ai.openclaw", category: "startup.diagnostics")

    struct DiagnosticResult {
        let nodeStatus: NodeStatus
        let gatewayStatus: GatewayStatus
        let extensionStatus: [ExtensionStatus]
        let timestamp: Date

        var summary: String {
            var lines: [String] = []
            lines.append("=== OpenClaw Startup Diagnostics ===")
            lines.append("Timestamp: \(ISO8601DateFormatter().string(from: self.timestamp))")
            lines.append("")
            lines.append("--- Node Runtime ---")
            lines.append("Status: \(self.nodeStatus.ok ? "OK" : "ERROR")")
            lines.append("Path: \(self.nodeStatus.path ?? "not found")")
            lines.append("Version: \(self.nodeStatus.version ?? "unknown")")
            lines.append("Bundled: \(self.nodeStatus.isBundled ? "yes" : "no")")
            if let error = self.nodeStatus.error {
                lines.append("Error: \(error)")
            }
            lines.append("")
            lines.append("--- Gateway ---")
            lines.append("Status: \(self.gatewayStatus.ok ? "OK" : "ERROR")")
            lines.append("CLI Path: \(self.gatewayStatus.cliPath ?? "not found")")
            lines.append("Version: \(self.gatewayStatus.version ?? "unknown")")
            lines.append("Port: \(self.gatewayStatus.port)")
            lines.append("Bind: \(self.gatewayStatus.bind ?? "default")")
            lines.append("Launchd Loaded: \(self.gatewayStatus.launchdLoaded ? "yes" : "no")")
            if let error = self.gatewayStatus.error {
                lines.append("Error: \(error)")
            }
            lines.append("")
            lines.append("--- Extensions ---")
            if self.extensionStatus.isEmpty {
                lines.append("No extensions configured")
            } else {
                for ext in self.extensionStatus {
                    lines.append("\(ext.name) (\(ext.id)):")
                    lines.append("  Enabled: \(ext.enabled ? "yes" : "no")")
                    lines.append("  Configured: \(ext.configured ? "yes" : "no")")
                    if let accounts = ext.accounts {
                        lines.append("  Accounts: \(accounts)")
                    }
                    if let error = ext.error {
                        lines.append("  Error: \(error)")
                    }
                }
            }
            lines.append("")
            lines.append("=== End Diagnostics ===")
            return lines.joined(separator: "\n")
        }
    }

    struct NodeStatus {
        let ok: Bool
        let path: String?
        let version: String?
        let isBundled: Bool
        let error: String?
    }

    struct GatewayStatus {
        let ok: Bool
        let cliPath: String?
        let version: String?
        let port: Int
        let bind: String?
        let launchdLoaded: Bool
        let error: String?
    }

    struct ExtensionStatus {
        let id: String
        let name: String
        let enabled: Bool
        let configured: Bool
        let accounts: Int?
        let error: String?
    }

    /// Run startup diagnostics and log results.
    static func runAndLog() async -> DiagnosticResult {
        self.logger.info("Starting startup diagnostics...")
        let result = await self.run()

        // Log summary
        self.logger.info("\(result.summary)")

        // Log individual status for easier filtering
        if result.nodeStatus.ok {
            self.logger.info(
                """
                node: OK path=\(result.nodeStatus.path ?? "nil", privacy: .public) \
                version=\(result.nodeStatus.version ?? "nil", privacy: .public) \
                bundled=\(result.nodeStatus.isBundled, privacy: .public)
                """)
        } else {
            self.logger.error(
                """
                node: ERROR error=\(result.nodeStatus.error ?? "unknown", privacy: .public)
                """)
        }

        if result.gatewayStatus.ok {
            self.logger.info(
                """
                gateway: OK cli=\(result.gatewayStatus.cliPath ?? "nil", privacy: .public) \
                version=\(result.gatewayStatus.version ?? "nil", privacy: .public) \
                port=\(result.gatewayStatus.port, privacy: .public) \
                launchdLoaded=\(result.gatewayStatus.launchdLoaded, privacy: .public)
                """)
        } else {
            self.logger.error(
                """
                gateway: ERROR error=\(result.gatewayStatus.error ?? "unknown", privacy: .public)
                """)
        }

        for ext in result.extensionStatus {
            if ext.enabled {
                self.logger.info(
                    """
                    extension: \(ext.id, privacy: .public) name=\(ext.name, privacy: .public) \
                    enabled=\(ext.enabled, privacy: .public) \
                    configured=\(ext.configured, privacy: .public) \
                    accounts=\(ext.accounts ?? 0, privacy: .public)
                    """)
            } else {
                self.logger.debug(
                    """
                    extension: \(ext.id, privacy: .public) disabled
                    """)
            }
        }

        return result
    }

    /// Run startup diagnostics without logging.
    static func run() async -> DiagnosticResult {
        async let nodeStatus = Self.checkNodeStatus()
        async let gatewayStatus = Self.checkGatewayStatus()
        async let extensionStatus = Self.checkExtensionStatus()

        return DiagnosticResult(
            nodeStatus: await nodeStatus,
            gatewayStatus: await gatewayStatus,
            extensionStatus: await extensionStatus,
            timestamp: Date())
    }

    // MARK: - Node Status

    private static func checkNodeStatus() async -> NodeStatus {
        // Check bundled node first
        if let bundledNode = CommandResolver.bundledNodePath() {
            let version = await Self.getNodeVersion(path: bundledNode)
            return NodeStatus(
                ok: version != nil,
                path: bundledNode,
                version: version,
                isBundled: true,
                error: version == nil ? "Failed to get bundled node version" : nil)
        }

        // Check system node
        let searchPaths = CommandResolver.preferredPaths()
        let result = RuntimeLocator.resolve(searchPaths: searchPaths)
        switch result {
        case let .success(runtime):
            return NodeStatus(
                ok: true,
                path: runtime.path,
                version: runtime.version.description,
                isBundled: false,
                error: nil)
        case let .failure(err):
            return NodeStatus(
                ok: false,
                path: nil,
                version: nil,
                isBundled: false,
                error: RuntimeLocator.describeFailure(err))
        }
    }

    private static func getNodeVersion(path: String) async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--version"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }.value
    }

    // MARK: - Gateway Status

    private static func checkGatewayStatus() async -> GatewayStatus {
        let port = GatewayEnvironment.gatewayPort()
        let resolution = await Task.detached(priority: .utility) {
            GatewayEnvironment.resolveGatewayCommand()
        }.value
        let launchdLoaded = await GatewayLaunchAgentManager.isLoaded()

        // Determine CLI path
        var cliPath: String?
        if let bundledEntry = CommandResolver.bundledCLIEntrypoint() ??
            CommandResolver.bundledCLIDistEntrypoint()
        {
            cliPath = bundledEntry
        } else {
            cliPath = CommandResolver.openclawExecutable()
        }

        let ok = resolution.status.kind == .ok
        return GatewayStatus(
            ok: ok,
            cliPath: cliPath,
            version: resolution.status.gatewayVersion,
            port: port,
            bind: nil,
            launchdLoaded: launchdLoaded,
            error: ok ? nil : resolution.status.message)
    }

    // MARK: - Extension Status

    private static func checkExtensionStatus() async -> [ExtensionStatus] {
        // Read config to check extension status
        let config = OpenClawConfigFile.loadDict()

        var extensions: [ExtensionStatus] = []

        // Check QQBot
        if let qqbot = Self.checkQQBotExtension(config: config) {
            extensions.append(qqbot)
        }

        // Check other common extensions
        if let msteams = Self.checkMSTeamsExtension(config: config) {
            extensions.append(msteams)
        }

        if let matrix = Self.checkMatrixExtension(config: config) {
            extensions.append(matrix)
        }

        if let zalo = Self.checkZaloExtension(config: config) {
            extensions.append(zalo)
        }

        // Check built-in channels
        extensions.append(contentsOf: Self.checkBuiltinChannels(config: config))

        return extensions
    }

    private static func checkQQBotExtension(config: [String: Any]) -> ExtensionStatus? {
        guard let channels = config["channels"] as? [String: Any],
              let qqbot = channels["qqbot"] as? [String: Any]
        else {
            return ExtensionStatus(
                id: "qqbot",
                name: "QQ Bot",
                enabled: false,
                configured: false,
                accounts: nil,
                error: nil)
        }

        let enabled = (qqbot["enabled"] as? Bool) ?? true
        let accounts = (qqbot["accounts"] as? [[String: Any]])?.count ?? 1
        let appId = qqbot["appId"] as? String
        let configured = appId != nil && !appId!.isEmpty

        return ExtensionStatus(
            id: "qqbot",
            name: "QQ Bot",
            enabled: enabled,
            configured: configured,
            accounts: accounts,
            error: configured ? nil : "Missing appId or clientSecret")
    }

    private static func checkMSTeamsExtension(config: [String: Any]) -> ExtensionStatus? {
        guard let channels = config["channels"] as? [String: Any],
              let msteams = channels["msteams"] as? [String: Any]
        else {
            return nil
        }

        let enabled = (msteams["enabled"] as? Bool) ?? true
        return ExtensionStatus(
            id: "msteams",
            name: "Microsoft Teams",
            enabled: enabled,
            configured: true,
            accounts: nil,
            error: nil)
    }

    private static func checkMatrixExtension(config: [String: Any]) -> ExtensionStatus? {
        guard let channels = config["channels"] as? [String: Any],
              let matrix = channels["matrix"] as? [String: Any]
        else {
            return nil
        }

        let enabled = (matrix["enabled"] as? Bool) ?? true
        return ExtensionStatus(
            id: "matrix",
            name: "Matrix",
            enabled: enabled,
            configured: true,
            accounts: nil,
            error: nil)
    }

    private static func checkZaloExtension(config: [String: Any]) -> ExtensionStatus? {
        guard let channels = config["channels"] as? [String: Any],
              let zalo = channels["zalo"] as? [String: Any]
        else {
            return nil
        }

        let enabled = (zalo["enabled"] as? Bool) ?? true
        return ExtensionStatus(
            id: "zalo",
            name: "Zalo",
            enabled: enabled,
            configured: true,
            accounts: nil,
            error: nil)
    }

    private static func checkBuiltinChannels(config: [String: Any]) -> [ExtensionStatus] {
        var results: [ExtensionStatus] = []
        guard let channels = config["channels"] as? [String: Any] else {
            return results
        }

        let builtinChannels: [(String, String)] = [
            ("telegram", "Telegram"),
            ("discord", "Discord"),
            ("slack", "Slack"),
            ("signal", "Signal"),
            ("imessage", "iMessage"),
            ("whatsapp", "WhatsApp"),
        ]

        for (id, name) in builtinChannels {
            guard let channelConfig = channels[id] as? [String: Any] else {
                continue
            }

            let enabled = (channelConfig["enabled"] as? Bool) ?? true
            // Check if channel has any configuration beyond just enabled
            let configured = channelConfig.keys.contains { $0 != "enabled" }

            results.append(ExtensionStatus(
                id: id,
                name: name,
                enabled: enabled,
                configured: configured,
                accounts: nil,
                error: nil))
        }

        return results
    }
}
