import Foundation

enum GatewayLaunchAgentManager {
    private static let logger = Logger(subsystem: "ai.openclaw", category: "gateway.launchd")
    private static let disableLaunchAgentMarker = ".openclaw/disable-launchagent"

    private static var disableLaunchAgentMarkerURL: URL {
        FileManager().homeDirectoryForCurrentUser
            .appendingPathComponent(self.disableLaunchAgentMarker)
    }

    private static var plistURL: URL {
        FileManager().homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(gatewayLaunchdLabel).plist")
    }

    static func isLaunchAgentWriteDisabled() -> Bool {
        if FileManager().fileExists(atPath: self.disableLaunchAgentMarkerURL.path) { return true }
        return false
    }

    static func setLaunchAgentWriteDisabled(_ disabled: Bool) -> String? {
        let marker = self.disableLaunchAgentMarkerURL
        if disabled {
            do {
                try FileManager().createDirectory(
                    at: marker.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                if !FileManager().fileExists(atPath: marker.path) {
                    FileManager().createFile(atPath: marker.path, contents: nil)
                }
            } catch {
                return error.localizedDescription
            }
            return nil
        }

        if FileManager().fileExists(atPath: marker.path) {
            do {
                try FileManager().removeItem(at: marker)
            } catch {
                return error.localizedDescription
            }
        }
        return nil
    }

    static func isLoaded() async -> Bool {
        guard let loaded = await self.readDaemonLoaded() else { return false }
        return loaded
    }

    static func set(enabled: Bool, bundlePath: String, port: Int) async -> String? {
        _ = bundlePath
        guard !CommandResolver.connectionModeIsRemote() else {
            self.logger.info("launchd change skipped (remote mode)")
            return nil
        }
        if enabled, self.isLaunchAgentWriteDisabled() {
            self.logger.info("launchd enable skipped (disable marker set)")
            return nil
        }

        if enabled {
            let bind = GatewayEnvironment.preferredGatewayBind() ?? "lan"
            self.logger.info("launchd enable requested via CLI port=\(port) bind=\(bind)")
            return await self.runDaemonCommand([
                "install",
                "--force",
                "--port",
                "\(port)",
                "--bind",
                bind,
                "--runtime",
                "node",
            ])
        }

        self.logger.info("launchd disable requested via CLI")
        return await self.runDaemonCommand(["uninstall"])
    }

    static func kickstart() async {
        _ = await self.runDaemonCommand(["restart"], timeout: 20)
    }

    static func launchdConfigSnapshot() -> LaunchAgentPlistSnapshot? {
        LaunchAgentPlist.snapshot(url: self.plistURL)
    }

    static func launchdGatewayLogPath() -> String {
        let snapshot = self.launchdConfigSnapshot()
        if let stdout = snapshot?.stdoutPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stdout.isEmpty
        {
            return stdout
        }
        if let stderr = snapshot?.stderrPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stderr.isEmpty
        {
            return stderr
        }
        return LogLocator.launchdGatewayLogPath
    }

    /// Check if the daemon plist needs to be reinstalled due to bind mode mismatch.
    /// Returns true if the current plist bind mode is "loopback" but the expected default is "lan".
    static func needsBindModeUpdate() -> Bool {
        guard let snapshot = self.launchdConfigSnapshot() else { return false }
        let currentBind = snapshot.bind ?? "loopback"
        let expectedBind = GatewayEnvironment.preferredGatewayBind() ?? "lan"
        // Only trigger update if current is loopback and expected is lan
        // This handles the migration from old default (loopback) to new default (lan)
        if currentBind == "loopback" && expectedBind == "lan" {
            self.logger.info("bind mode update needed: current=\(currentBind) expected=\(expectedBind)")
            return true
        }
        return false
    }

    /// Check if the daemon plist CLI path points to a different location than the current app bundle.
    /// This detects when a user installs a new app version but the LaunchAgent still points to an old path.
    /// Returns true if reinstallation is needed.
    static func needsPathUpdate(currentBundlePath: String) -> Bool {
        guard let snapshot = self.launchdConfigSnapshot() else {
            // No plist exists, will be created fresh
            return false
        }

        let cliPath = snapshot.cliEntryPath ?? ""
        let normalizedBundlePath = (currentBundlePath as NSString).standardizingPath

        // Check if the current app is running from a "production" location
        // (i.e., /Applications or ~/Applications), meaning it's a distributed build
        // that should use bundled runtime
        let isProductionApp =
            normalizedBundlePath.hasPrefix("/Applications/") ||
            normalizedBundlePath.contains("/Applications/") ||
            normalizedBundlePath.hasPrefix(
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path)

        // Check if the current app bundle has bundled runtime
        let bundledCliPath = normalizedBundlePath + "/Contents/Resources/runtime/cli/openclaw.mjs"
        let hasBundledRuntime = FileManager.default.fileExists(atPath: bundledCliPath)

        // If running from production location with bundled runtime, plist should use the bundled CLI
        if isProductionApp && hasBundledRuntime {
            // Check if plist CLI path is already pointing to current bundle's runtime
            let normalizedCliPath = (cliPath as NSString).standardizingPath
            let expectedPrefix = normalizedBundlePath + "/Contents/Resources/runtime"

            if !normalizedCliPath.hasPrefix(expectedPrefix) {
                self.logger.info(
                    "path update needed: production app with bundled runtime, but plist CLI path '\(cliPath)' " +
                        "does not use current bundle's runtime (expected prefix: '\(expectedPrefix)')"
                )
                return true
            }
        }

        // Check if plist is using a bundled runtime path from a different app bundle
        let isBundledPath = cliPath.contains(".app/Contents/Resources/runtime")
        if isBundledPath {
            // It's a bundled path - verify it matches the current app bundle
            if !snapshot.isUsingBundledRuntime(appBundlePath: currentBundlePath) {
                self.logger.info(
                    "path update needed: plist CLI path '\(cliPath)' does not match current bundle '\(currentBundlePath)'"
                )
                return true
            }
        }

        // For non-bundled (dev/homebrew) setups running from dev locations, we don't auto-update
        // This prevents the app from hijacking a manually configured dev environment
        return false
    }
}

extension GatewayLaunchAgentManager {
    private static func readDaemonLoaded() async -> Bool? {
        let result = await self.runDaemonCommandResult(
            ["status", "--json", "--no-probe"],
            timeout: 15,
            quiet: true)
        guard result.success, let payload = result.payload else { return nil }
        guard
            let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let service = json["service"] as? [String: Any],
            let loaded = service["loaded"] as? Bool
        else {
            return nil
        }
        return loaded
    }

    private struct CommandResult {
        let success: Bool
        let payload: Data?
        let message: String?
    }

    private struct ParsedDaemonJson {
        let text: String
        let object: [String: Any]
    }

    private static func runDaemonCommand(
        _ args: [String],
        timeout: Double = 15,
        quiet: Bool = false) async -> String?
    {
        let result = await self.runDaemonCommandResult(args, timeout: timeout, quiet: quiet)
        if result.success { return nil }
        return result.message ?? "Gateway daemon command failed"
    }

    private static func runDaemonCommandResult(
        _ args: [String],
        timeout: Double,
        quiet: Bool) async -> CommandResult
    {
        let command = CommandResolver.openclawCommand(
            subcommand: "gateway",
            extraArgs: self.withJsonFlag(args),
            // Launchd management must always run locally, even if remote mode is configured.
            configRoot: ["gateway": ["mode": "local"]])
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = CommandResolver.preferredPaths().joined(separator: ":")
        let response = await ShellExecutor.runDetailed(command: command, cwd: nil, env: env, timeout: timeout)
        let parsed = self.parseDaemonJson(from: response.stdout) ?? self.parseDaemonJson(from: response.stderr)
        let ok = parsed?.object["ok"] as? Bool
        let message = (parsed?.object["error"] as? String) ?? (parsed?.object["message"] as? String)
        let payload = parsed?.text.data(using: .utf8)
            ?? (response.stdout.isEmpty ? response.stderr : response.stdout).data(using: .utf8)
        let success = ok ?? response.success
        if success {
            return CommandResult(success: true, payload: payload, message: nil)
        }

        if quiet {
            return CommandResult(success: false, payload: payload, message: message)
        }

        let detail = message ?? self.summarize(response.stderr) ?? self.summarize(response.stdout)
        let exit = response.exitCode.map { "exit \($0)" } ?? (response.errorMessage ?? "failed")
        let fullMessage = detail.map { "Gateway daemon command failed (\(exit)): \($0)" }
            ?? "Gateway daemon command failed (\(exit))"
        self.logger.error("\(fullMessage, privacy: .public)")
        return CommandResult(success: false, payload: payload, message: detail)
    }

    private static func withJsonFlag(_ args: [String]) -> [String] {
        if args.contains("--json") { return args }
        return args + ["--json"]
    }

    private static func parseDaemonJson(from raw: String) -> ParsedDaemonJson? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}")
        else {
            return nil
        }
        let jsonText = String(trimmed[start...end])
        guard let data = jsonText.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return ParsedDaemonJson(text: jsonText, object: object)
    }

    private static func summarize(_ text: String) -> String? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let last = lines.last else { return nil }
        let normalized = last.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return normalized.count > 200 ? String(normalized.prefix(199)) + "…" : normalized
    }
}
