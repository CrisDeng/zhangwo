import Foundation

enum Launchctl {
    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    @discardableResult
    static func run(_ args: [String]) async -> Result {
        await Task.detached(priority: .utility) { () -> Result in
            let process = Process()
            process.launchPath = "/bin/launchctl"
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                let data = try process.runAndReadToEnd(from: pipe)
                let output = String(data: data, encoding: .utf8) ?? ""
                return Result(status: process.terminationStatus, output: output)
            } catch {
                return Result(status: -1, output: error.localizedDescription)
            }
        }.value
    }
}

struct LaunchAgentPlistSnapshot: Equatable, Sendable {
    let programArguments: [String]
    let environment: [String: String]
    let stdoutPath: String?
    let stderrPath: String?

    let port: Int?
    let bind: String?
    let token: String?
    let password: String?

    /// Returns the CLI entry point path from ProgramArguments (typically the second element after node path).
    /// For bundled runtime, this would be something like `/path/to/App.app/Contents/Resources/runtime/cli/openclaw.mjs`
    /// For dev/homebrew, this would be a path outside the app bundle.
    var cliEntryPath: String? {
        // ProgramArguments is typically: [node_path, cli_entry_path, "gateway", "--port", ...]
        guard self.programArguments.count >= 2 else { return nil }
        return self.programArguments[1]
    }

    /// Check if the LaunchAgent is configured to use a CLI path inside the given app bundle.
    func isUsingBundledRuntime(appBundlePath: String) -> Bool {
        guard let cliPath = self.cliEntryPath else { return false }
        // Normalize paths for comparison
        let normalizedCliPath = (cliPath as NSString).standardizingPath
        let normalizedBundlePath = (appBundlePath as NSString).standardizingPath
        return normalizedCliPath.hasPrefix(normalizedBundlePath + "/")
    }
}

enum LaunchAgentPlist {
    static func snapshot(url: URL) -> LaunchAgentPlistSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let rootAny: Any
        do {
            rootAny = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil)
        } catch {
            return nil
        }
        guard let root = rootAny as? [String: Any] else { return nil }
        let programArguments = root["ProgramArguments"] as? [String] ?? []
        let env = root["EnvironmentVariables"] as? [String: String] ?? [:]
        let stdoutPath = (root["StandardOutPath"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let stderrPath = (root["StandardErrorPath"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let port = Self.extractFlagInt(programArguments, flag: "--port")
        let bind = Self.extractFlagString(programArguments, flag: "--bind")?.lowercased()
        let token = env["OPENCLAW_GATEWAY_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let password = env["OPENCLAW_GATEWAY_PASSWORD"]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        return LaunchAgentPlistSnapshot(
            programArguments: programArguments,
            environment: env,
            stdoutPath: stdoutPath,
            stderrPath: stderrPath,
            port: port,
            bind: bind,
            token: token,
            password: password)
    }

    private static func extractFlagInt(_ args: [String], flag: String) -> Int? {
        guard let raw = self.extractFlagString(args, flag: flag) else { return nil }
        return Int(raw)
    }

    private static func extractFlagString(_ args: [String], flag: String) -> String? {
        guard let idx = args.firstIndex(of: flag) else { return nil }
        let valueIdx = args.index(after: idx)
        guard valueIdx < args.endIndex else { return nil }
        let token = args[valueIdx].trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
