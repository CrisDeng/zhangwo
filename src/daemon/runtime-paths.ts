import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

import { isSupportedNodeVersion } from "../infra/runtime-guard.js";

const VERSION_MANAGER_MARKERS = [
  "/.nvm/",
  "/.fnm/",
  "/.volta/",
  "/.asdf/",
  "/.n/",
  "/.nodenv/",
  "/.nodebrew/",
  "/nvs/",
];

function getPathModule(platform: NodeJS.Platform) {
  return platform === "win32" ? path.win32 : path.posix;
}

function normalizeForCompare(input: string, platform: NodeJS.Platform): string {
  const pathModule = getPathModule(platform);
  const normalized = pathModule.normalize(input).replaceAll("\\", "/");
  if (platform === "win32") {
    return normalized.toLowerCase();
  }
  return normalized;
}

function buildSystemNodeCandidates(
  env: Record<string, string | undefined>,
  platform: NodeJS.Platform,
): string[] {
  if (platform === "darwin") {
    return ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"];
  }
  if (platform === "linux") {
    return ["/usr/local/bin/node", "/usr/bin/node"];
  }
  if (platform === "win32") {
    const pathModule = getPathModule(platform);
    const programFiles = env.ProgramFiles ?? "C:\\Program Files";
    const programFilesX86 = env["ProgramFiles(x86)"] ?? "C:\\Program Files (x86)";
    return [
      pathModule.join(programFiles, "nodejs", "node.exe"),
      pathModule.join(programFilesX86, "nodejs", "node.exe"),
    ];
  }
  return [];
}

type ExecFileAsync = (
  file: string,
  args: readonly string[],
  options: { encoding: "utf8" },
) => Promise<{ stdout: string; stderr: string }>;

const execFileAsync = promisify(execFile) as unknown as ExecFileAsync;

async function resolveNodeVersion(
  nodePath: string,
  execFileImpl: ExecFileAsync,
): Promise<string | null> {
  try {
    const { stdout } = await execFileImpl(nodePath, ["-p", "process.versions.node"], {
      encoding: "utf8",
    });
    const value = stdout.trim();
    return value ? value : null;
  } catch {
    return null;
  }
}

export type SystemNodeInfo = {
  path: string;
  version: string | null;
  supported: boolean;
};

export function isVersionManagedNodePath(
  nodePath: string,
  platform: NodeJS.Platform = process.platform,
): boolean {
  const normalized = normalizeForCompare(nodePath, platform);
  return VERSION_MANAGER_MARKERS.some((marker) => normalized.includes(marker));
}

export function isSystemNodePath(
  nodePath: string,
  env: Record<string, string | undefined> = process.env,
  platform: NodeJS.Platform = process.platform,
): boolean {
  const normalized = normalizeForCompare(nodePath, platform);
  return buildSystemNodeCandidates(env, platform).some((candidate) => {
    const normalizedCandidate = normalizeForCompare(candidate, platform);
    return normalized === normalizedCandidate;
  });
}

export async function resolveSystemNodePath(
  env: Record<string, string | undefined> = process.env,
  platform: NodeJS.Platform = process.platform,
): Promise<string | null> {
  const candidates = buildSystemNodeCandidates(env, platform);
  for (const candidate of candidates) {
    try {
      await fs.access(candidate);
      return candidate;
    } catch {
      // keep going
    }
  }
  return null;
}

export async function resolveSystemNodeInfo(params: {
  env?: Record<string, string | undefined>;
  platform?: NodeJS.Platform;
  execFile?: ExecFileAsync;
}): Promise<SystemNodeInfo | null> {
  const env = params.env ?? process.env;
  const platform = params.platform ?? process.platform;
  const systemNode = await resolveSystemNodePath(env, platform);
  if (!systemNode) return null;

  const version = await resolveNodeVersion(systemNode, params.execFile ?? execFileAsync);
  return {
    path: systemNode,
    version,
    supported: isSupportedNodeVersion(version),
  };
}

export function renderSystemNodeWarning(
  systemNode: SystemNodeInfo | null,
  selectedNodePath?: string,
): string | null {
  if (!systemNode || systemNode.supported) return null;
  const versionLabel = systemNode.version ?? "unknown";
  const selectedLabel = selectedNodePath ? ` Using ${selectedNodePath} for the daemon.` : "";
  return `System Node ${versionLabel} at ${systemNode.path} is below the required Node 22+.${selectedLabel} Install Node 22+ from nodejs.org or Homebrew.`;
}

/**
 * Check if the current process is running from a bundled macOS app.
 * This detects paths like /Applications/掌握.app/Contents/Resources/runtime/node/node
 */
function isBundledMacAppNode(execPath: string): boolean {
  const normalized = execPath.replace(/\\/g, "/");
  // Match patterns like: *.app/Contents/Resources/runtime/node/node
  return /\.app\/Contents\/Resources\/runtime\/node\/node$/i.test(normalized);
}

/**
 * Try to find bundled node from the CLI entrypoint path (argv[1]).
 * This handles cases where the CLI is invoked from a bundled app but process.execPath
 * is not the bundled node (e.g., when ShellExecutor spawns a new shell process).
 */
function findBundledNodeFromArgv(): string | null {
  const argv1 = process.argv[1];
  if (!argv1) return null;

  const normalized = argv1.replace(/\\/g, "/");
  // Match patterns like: *.app/Contents/Resources/runtime/openclaw/...
  const appMatch = normalized.match(/^(.+\.app\/Contents\/Resources\/runtime)\//i);
  if (!appMatch) return null;

  const runtimeDir = appMatch[1];
  const bundledNodePath = `${runtimeDir}/node/node`;

  // Check if the bundled node exists
  try {
    const fs = require("node:fs");
    if (fs.existsSync(bundledNodePath)) {
      return bundledNodePath;
    }
  } catch {
    // Ignore errors
  }
  return null;
}

export async function resolvePreferredNodePath(params: {
  env?: Record<string, string | undefined>;
  runtime?: string;
  platform?: NodeJS.Platform;
  execFile?: ExecFileAsync;
}): Promise<string | undefined> {
  if (params.runtime !== "node") return undefined;

  // If running from a bundled macOS app, prefer the bundled node (process.execPath)
  // by returning undefined, which causes the caller to use process.execPath.
  if (isBundledMacAppNode(process.execPath)) {
    return undefined;
  }

  // Try to find bundled node from the CLI entrypoint path (argv[1]).
  // This handles cases where the app invokes CLI via shell but we want to use bundled node.
  const bundledNode = findBundledNodeFromArgv();
  if (bundledNode) {
    return bundledNode;
  }

  const systemNode = await resolveSystemNodeInfo(params);
  if (!systemNode?.supported) return undefined;
  return systemNode.path;
}
