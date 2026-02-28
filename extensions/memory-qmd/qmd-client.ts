/**
 * QMD CLI Client
 *
 * Wraps the `qmd` command-line tool for use as a memory backend.
 * Handles:
 * - QMD binary detection / installation check
 * - Model download status and on-demand download
 * - Collection management (add/list/remove)
 * - Search (keyword, vector, hybrid)
 * - Document retrieval
 */

import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// ============================================================================
// Types
// ============================================================================

export type QmdSearchResult = {
  docid: string;
  path: string;
  score: number;
  snippet: string;
  collection?: string;
};

export type QmdCollection = {
  name: string;
  path: string;
  fileCount?: number;
};

export type QmdStatus = {
  installed: boolean;
  modelsReady: boolean;
  collections: QmdCollection[];
  indexPath?: string;
  missingModels: string[];
};

export type QmdSearchMode = "query" | "vsearch" | "search";

export type QmdSearchOptions = {
  mode?: QmdSearchMode;
  collection?: string;
  maxResults?: number;
  minScore?: number;
  json?: boolean;
};

// Model info
const QMD_MODELS = [
  { name: "embeddinggemma-300M", file: "embeddinggemma-300M-Q8_0.gguf", sizeMB: 300 },
  { name: "qwen3-reranker-0.6B", file: "Qwen.Qwen3-Reranker-0.6B.Q8_0.gguf", sizeMB: 640 },
  { name: "qmd-query-expansion-1.7B", file: "qmd-query-expansion-1.7B-q4_k_m.gguf", sizeMB: 1100 },
] as const;

const MODELS_DIR = join(homedir(), ".cache", "qmd", "models");
const INDEX_PATH = join(homedir(), ".cache", "qmd", "index.sqlite");

// ============================================================================
// CLI Execution
// ============================================================================

function findQmdBinary(): string | null {
  const candidates = [
    join(homedir(), ".bun", "bin", "qmd"),
    "/usr/local/bin/qmd",
    "/opt/homebrew/bin/qmd",
    "qmd", // fallback to PATH
  ];

  for (const candidate of candidates) {
    if (candidate === "qmd") return candidate; // PATH fallback always last
    if (existsSync(candidate)) return candidate;
  }

  return null;
}

function execQmd(args: string[], timeoutMs = 60_000): Promise<{ stdout: string; stderr: string }> {
  const binary = findQmdBinary();
  if (!binary) {
    return Promise.reject(new Error(
      "QMD not found. Install with: bun install -g github:tobi/qmd",
    ));
  }

  return new Promise((resolve, reject) => {
    execFile(binary, args, { timeout: timeoutMs, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) {
        reject(new Error(`qmd ${args[0]} failed: ${stderr || err.message}`));
        return;
      }
      resolve({ stdout, stderr });
    });
  });
}

// ============================================================================
// Status & Setup
// ============================================================================

/** Check which GGUF models are present locally */
export function checkModels(): { ready: boolean; missing: string[] } {
  const missing: string[] = [];
  for (const model of QMD_MODELS) {
    const modelPath = join(MODELS_DIR, model.file);
    if (!existsSync(modelPath)) {
      missing.push(model.name);
    }
  }
  return { ready: missing.length === 0, missing };
}

/** Get total size of models to download (in MB) */
export function getModelDownloadSizeMB(): number {
  const { missing } = checkModels();
  return QMD_MODELS
    .filter((m) => missing.includes(m.name))
    .reduce((sum, m) => sum + m.sizeMB, 0);
}

/** Check full QMD status */
export async function getStatus(): Promise<QmdStatus> {
  const binary = findQmdBinary();
  const installed = binary !== null;

  if (!installed) {
    return {
      installed: false,
      modelsReady: false,
      collections: [],
      missingModels: QMD_MODELS.map((m) => m.name),
    };
  }

  const modelCheck = checkModels();
  let collections: QmdCollection[] = [];

  try {
    collections = await listCollections();
  } catch {
    // QMD may not be initialized yet
  }

  return {
    installed: true,
    modelsReady: modelCheck.ready,
    collections,
    indexPath: existsSync(INDEX_PATH) ? INDEX_PATH : undefined,
    missingModels: modelCheck.missing,
  };
}

/**
 * Trigger model download by running a minimal QMD command.
 * QMD auto-downloads models on first use.
 * Returns true if successful.
 */
export async function ensureModels(): Promise<boolean> {
  const { ready } = checkModels();
  if (ready) return true;

  try {
    // `qmd status` triggers model download
    await execQmd(["status"], 300_000); // 5 min timeout for downloads
    return checkModels().ready;
  } catch {
    return false;
  }
}

// ============================================================================
// Collection Management
// ============================================================================

export async function listCollections(): Promise<QmdCollection[]> {
  try {
    const { stdout } = await execQmd(["collection", "list"]);
    const lines = stdout.trim().split("\n").filter(Boolean);
    const collections: QmdCollection[] = [];

    for (const line of lines) {
      // Parse output: "name: path (N files)"
      const match = line.match(/^(\S+):\s+(.+?)(?:\s+\((\d+)\s+files?\))?$/);
      if (match) {
        collections.push({
          name: match[1],
          path: match[2].trim(),
          fileCount: match[3] ? parseInt(match[3]) : undefined,
        });
      }
    }

    return collections;
  } catch {
    return [];
  }
}

export async function addCollection(path: string, name: string, mask?: string): Promise<void> {
  const args = ["collection", "add", path, "--name", name];
  if (mask) args.push("--mask", mask);
  await execQmd(args);
}

export async function removeCollection(name: string): Promise<void> {
  await execQmd(["collection", "remove", name]);
}

export async function addContext(path: string, description: string): Promise<void> {
  await execQmd(["context", "add", path, description]);
}

// ============================================================================
// Indexing
// ============================================================================

export async function embed(force = false): Promise<void> {
  const args = ["embed"];
  if (force) args.push("-f");
  await execQmd(args, 600_000); // 10 min timeout for large collections
}

// ============================================================================
// Search
// ============================================================================

export async function search(
  query: string,
  options: QmdSearchOptions = {},
): Promise<QmdSearchResult[]> {
  const {
    mode = "query",
    collection,
    maxResults = 5,
    minScore,
  } = options;

  const args = [mode, query, "--json", "-n", String(maxResults)];

  if (collection) args.push("-c", collection);
  if (minScore !== undefined) args.push("--min-score", String(minScore));

  try {
    const { stdout } = await execQmd(args, 120_000); // Increased timeout for model loading
    
    // QMD may output progress info before JSON, extract the JSON array
    const jsonMatch = stdout.match(/\[\s*\{[\s\S]*\}\s*\]/);
    if (!jsonMatch) {
      // No JSON array found, might be empty results
      if (stdout.includes("No results") || stdout.includes("no matches") || stdout.trim() === "[]") {
        return [];
      }
      throw new Error(`qmd ${mode} failed: ${stdout.slice(0, 200)}`);
    }
    
    const parsed = JSON.parse(jsonMatch[0]);

    if (Array.isArray(parsed)) {
      return parsed.map((item: Record<string, unknown>) => ({
        docid: String(item.docid ?? item.id ?? ""),
        path: String(item.path ?? item.file ?? ""),
        score: Number(item.score ?? 0),
        snippet: String(item.snippet ?? item.text ?? item.content ?? ""),
        collection: item.collection ? String(item.collection) : undefined,
      }));
    }

    return [];
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes("No results") || msg.includes("no matches")) return [];
    throw err;
  }
}

// ============================================================================
// Document Retrieval
// ============================================================================

export async function getDocument(pathOrDocid: string): Promise<string> {
  const { stdout } = await execQmd(["get", pathOrDocid], 10_000);
  return stdout;
}

export async function multiGet(pattern: string, json = false): Promise<string> {
  const args = ["multi-get", pattern];
  if (json) args.push("--json");
  const { stdout } = await execQmd(args, 30_000);
  return stdout;
}

// ============================================================================
// Sync helpers
// ============================================================================

/**
 * Sync an openclaw agent's memory directory into QMD as a collection.
 * This enables QMD to index MEMORY.md and memory/*.md files.
 */
export async function syncMemoryDir(agentDir: string, agentId: string): Promise<void> {
  const memoryDir = join(agentDir, "memory");
  const memoryMdPath = join(agentDir, "MEMORY.md");

  // Use agent dir as collection root so both MEMORY.md and memory/ are included
  const collectionName = `openclaw-${agentId}`;

  const existing = await listCollections();
  const alreadyAdded = existing.some((c) => c.name === collectionName);

  if (!alreadyAdded) {
    if (existsSync(memoryDir) || existsSync(memoryMdPath)) {
      await addCollection(agentDir, collectionName, "**/*.md");
      await addContext(
        `qmd://${collectionName}`,
        `OpenClaw agent ${agentId} memory files and conversation history`,
      );
    }
  }

  // Incremental re-embed (fast for unchanged files)
  await embed(false);
}

/**
 * Check if QMD is ready for immediate use.
 * Returns { ready, reason } - ready means search will work right now.
 */
export async function isReady(): Promise<{ ready: boolean; reason?: string }> {
  const binary = findQmdBinary();
  if (!binary) {
    return { ready: false, reason: "QMD not installed. Run: bun install -g github:tobi/qmd" };
  }

  const { ready, missing } = checkModels();
  if (!ready) {
    const sizeMB = getModelDownloadSizeMB();
    return {
      ready: false,
      reason: `QMD models not downloaded (${missing.join(", ")}). ~${sizeMB}MB needed. Run: qmd status`,
    };
  }

  return { ready: true };
}
