/**
 * OpenClaw Memory (QMD) Plugin
 *
 * Local-only memory backend using QMD's hybrid search pipeline:
 * BM25 keyword search + vector semantic search + LLM reranking.
 *
 * All processing runs locally via GGUF models - zero API cost.
 * Models are downloaded on first use (~2GB total, cached at ~/.cache/qmd/models/).
 *
 * After models are downloaded, search is available immediately.
 */

import { Type } from "@sinclair/typebox";
import type { OpenClawPluginApi } from "openclaw/plugin-sdk";

import { qmdConfigSchema } from "./config.js";
import * as qmd from "./qmd-client.js";

// ============================================================================
// Plugin Definition
// ============================================================================

const memoryQmdPlugin = {
  id: "memory-qmd",
  name: "Memory (QMD)",
  description:
    "Local hybrid search memory (BM25 + vector + LLM reranking) via QMD. Zero API cost.",
  kind: "memory" as const,
  configSchema: qmdConfigSchema,

  register(api: OpenClawPluginApi) {
    const cfg = qmdConfigSchema.parse(api.pluginConfig);

    api.logger.info("memory-qmd: plugin registered");

    // ========================================================================
    // Tools
    // ========================================================================

    // memory_search - hybrid search through QMD-indexed documents
    api.registerTool(
      {
        name: "memory_search",
        label: "Memory Search (QMD)",
        description:
          "Search through indexed knowledge base using QMD local hybrid search " +
          "(BM25 + vector + LLM reranking). Use for recalling prior work, decisions, " +
          "preferences, meeting notes, or any indexed documents. Zero API cost.",
        parameters: Type.Object({
          query: Type.String({ description: "Search query" }),
          collection: Type.Optional(
            Type.String({ description: "Limit search to a specific collection" }),
          ),
          maxResults: Type.Optional(
            Type.Number({ description: "Max results (default: 5)" }),
          ),
          mode: Type.Optional(
            Type.String({
              description:
                "Search mode: query (hybrid, best quality), vsearch (semantic), search (keyword fastest)",
            }),
          ),
        }),
        async execute(_toolCallId, params) {
          const {
            query,
            collection,
            maxResults,
            mode,
          } = params as {
            query: string;
            collection?: string;
            maxResults?: number;
            mode?: string;
          };

          // Check readiness
          const readiness = await qmd.isReady();
          if (!readiness.ready) {
            return {
              content: [
                {
                  type: "text",
                  text: `QMD not ready: ${readiness.reason}`,
                },
              ],
              details: { ready: false, reason: readiness.reason },
            };
          }

          try {
            const results = await qmd.search(query, {
              mode: (mode as qmd.QmdSearchMode) ?? cfg.searchMode ?? "query",
              collection,
              maxResults: maxResults ?? cfg.maxResults,
              minScore: cfg.minScore,
              json: true,
            });

            if (results.length === 0) {
              return {
                content: [{ type: "text", text: "No relevant results found." }],
                details: { count: 0 },
              };
            }

            const text = results
              .map(
                (r, i) =>
                  `${i + 1}. [${(r.score * 100).toFixed(0)}%] ${r.path}\n   ${r.snippet.slice(0, 200)}`,
              )
              .join("\n\n");

            return {
              content: [
                {
                  type: "text",
                  text: `Found ${results.length} results:\n\n${text}`,
                },
              ],
              details: {
                count: results.length,
                results: results.map((r) => ({
                  docid: r.docid,
                  path: r.path,
                  score: r.score,
                  snippet: r.snippet.slice(0, 500),
                  collection: r.collection,
                })),
              },
            };
          } catch (err) {
            const message = err instanceof Error ? err.message : String(err);
            return {
              content: [{ type: "text", text: `QMD search error: ${message}` }],
              details: { error: message },
            };
          }
        },
      },
      { name: "memory_search" },
    );

    // memory_get - retrieve full document content
    api.registerTool(
      {
        name: "memory_get",
        label: "Memory Get (QMD)",
        description:
          "Retrieve a full document by file path or docid (e.g. #abc123) from QMD index. " +
          "Use after memory_search to read the complete content of a relevant result.",
        parameters: Type.Object({
          path: Type.String({
            description: "File path or docid (#abc123) from search results",
          }),
        }),
        async execute(_toolCallId, params) {
          const { path } = params as { path: string };

          const readiness = await qmd.isReady();
          if (!readiness.ready) {
            return {
              content: [
                { type: "text", text: `QMD not ready: ${readiness.reason}` },
              ],
              details: { ready: false, reason: readiness.reason },
            };
          }

          try {
            const content = await qmd.getDocument(path);
            return {
              content: [{ type: "text", text: content }],
              details: { path, length: content.length },
            };
          } catch (err) {
            const message = err instanceof Error ? err.message : String(err);
            return {
              content: [
                { type: "text", text: `Failed to get document: ${message}` },
              ],
              details: { path, error: message },
            };
          }
        },
      },
      { name: "memory_get" },
    );

    // ========================================================================
    // CLI Commands
    // ========================================================================

    api.registerCli(
      ({ program }) => {
        const mem = program
          .command("qmd")
          .description("QMD local memory backend commands");

        mem
          .command("status")
          .description("Show QMD installation and model status")
          .action(async () => {
            const status = await qmd.getStatus();

            if (!status.installed) {
              console.log("❌ QMD not installed");
              console.log("   Install: bun install -g github:tobi/qmd");
              return;
            }

            console.log("✅ QMD installed");

            if (!status.modelsReady) {
              const sizeMB = qmd.getModelDownloadSizeMB();
              console.log(
                `⚠️  Models not ready (missing: ${status.missingModels.join(", ")})`,
              );
              console.log(`   Download size: ~${sizeMB}MB`);
              console.log("   Run: openclaw qmd setup");
            } else {
              console.log("✅ All models ready");
            }

            if (status.collections.length > 0) {
              console.log(`\n📚 Collections (${status.collections.length}):`);
              for (const c of status.collections) {
                const files = c.fileCount !== undefined ? ` (${c.fileCount} files)` : "";
                console.log(`   ${c.name}: ${c.path}${files}`);
              }
            } else {
              console.log("\n📚 No collections indexed yet");
            }

            if (status.indexPath) {
              console.log(`\n📁 Index: ${status.indexPath}`);
            }
          });

        mem
          .command("setup")
          .description("Download QMD models (~2GB, one-time)")
          .action(async () => {
            const { ready, missing } = qmd.checkModels();
            if (ready) {
              console.log("✅ All QMD models already downloaded");
              return;
            }

            const sizeMB = qmd.getModelDownloadSizeMB();
            console.log(
              `⬇️  Downloading QMD models (${missing.join(", ")})...`,
            );
            console.log(`   Total: ~${sizeMB}MB`);
            console.log("   This only needs to be done once.\n");

            const success = await qmd.ensureModels();
            if (success) {
              console.log("\n✅ All models downloaded! QMD is ready to use.");
            } else {
              console.log("\n❌ Some models failed to download. Try again or run: qmd status");
            }
          });

        mem
          .command("add")
          .description("Add a directory to QMD index")
          .argument("<path>", "Directory path to index")
          .option("--name <name>", "Collection name")
          .option("--mask <glob>", "File glob pattern (default: **/*.md)")
          .action(async (dirPath, opts) => {
            const name = opts.name ?? dirPath.split("/").pop() ?? "unnamed";
            await qmd.addCollection(dirPath, name, opts.mask);
            console.log(`✅ Added collection "${name}": ${dirPath}`);

            console.log("📦 Generating embeddings...");
            await qmd.embed(false);
            console.log("✅ Embeddings generated. Search is ready!");
          });

        mem
          .command("search")
          .description("Search indexed documents")
          .argument("<query>", "Search query")
          .option("-n <num>", "Max results", "5")
          .option("-c, --collection <name>", "Limit to collection")
          .option(
            "-m, --mode <mode>",
            "Search mode: query|vsearch|search",
            "query",
          )
          .action(async (query, opts) => {
            const results = await qmd.search(query, {
              mode: opts.mode as qmd.QmdSearchMode,
              collection: opts.collection,
              maxResults: parseInt(opts.n),
            });

            if (results.length === 0) {
              console.log("No results found.");
              return;
            }

            for (const r of results) {
              console.log(
                `[${(r.score * 100).toFixed(0)}%] ${r.path}`,
              );
              if (r.snippet) {
                console.log(`   ${r.snippet.slice(0, 120)}...`);
              }
              console.log();
            }
          });

        mem
          .command("sync")
          .description("Sync current agent memory files into QMD")
          .action(async () => {
            const config = api.config;
            const agentDir = config?.agents?.defaults?.cwd;

            if (!agentDir) {
              console.log("⚠️  No agent directory configured");
              return;
            }

            console.log(`📦 Syncing memory from: ${agentDir}`);
            await qmd.syncMemoryDir(agentDir, "default");
            console.log("✅ Memory synced to QMD");
          });
      },
      { commands: ["qmd"] },
    );

    // ========================================================================
    // Lifecycle Hooks
    // ========================================================================

    // Auto-recall: inject relevant QMD results before agent starts
    if (cfg.autoRecall) {
      api.logger.info?.("memory-qmd: registering before_agent_start hook");
      api.on("before_agent_start", async (event) => {
        api.logger.info?.(`memory-qmd: before_agent_start triggered, prompt=${event.prompt?.slice(0, 50)}...`);
        if (!event.prompt || event.prompt.length < 5) {
          api.logger.info?.("memory-qmd: prompt too short, skipping");
          return;
        }

        const readiness = await qmd.isReady();
        api.logger.info?.(`memory-qmd: isReady=${readiness.ready}, reason=${readiness.reason ?? "ok"}`);
        if (!readiness.ready) return;

        try {
          const effectiveMinScore = cfg.minScore ?? 0.15;
          const results = await qmd.search(event.prompt, {
            mode: cfg.searchMode ?? "query",
            maxResults: 3,
            minScore: effectiveMinScore,
          });

          api.logger.info?.(`memory-qmd: search returned ${results.length} results (minScore=${effectiveMinScore})`);
          if (results.length === 0) return;

          const memoryContext = results
            .map(
              (r) =>
                `- [${r.path}] (${(r.score * 100).toFixed(0)}% match): ${r.snippet.slice(0, 300)}`,
            )
            .join("\n");

          api.logger.info?.(
            `memory-qmd: injecting ${results.length} results into context`,
          );

          return {
            prependContext:
              `<relevant-memories source="qmd-local">\n` +
              `The following local search results may be relevant:\n` +
              `${memoryContext}\n` +
              `</relevant-memories>`,
          };
        } catch (err) {
          api.logger.warn(
            `memory-qmd: auto-recall failed: ${String(err)}`,
          );
        }
      });
    }

    // Auto-capture: sync memory files into QMD after agent ends
    if (cfg.autoCapture) {
      api.on("agent_end", async (_event, ctx) => {
        const readiness = await qmd.isReady();
        if (!readiness.ready) return;

        try {
          const agentDir = ctx.workspaceDir;
          const agentId = ctx.agentId ?? "default";

          if (agentDir) {
            await qmd.syncMemoryDir(agentDir, agentId);
            api.logger.info?.("memory-qmd: synced memory files after agent end");
          }
        } catch (err) {
          api.logger.warn(
            `memory-qmd: auto-capture sync failed: ${String(err)}`,
          );
        }
      });
    }

    // Setup initial collections from config
    if (cfg.collections && cfg.collections.length > 0) {
      api.registerService({
        id: "memory-qmd",
        async start() {
          const readiness = await qmd.isReady();
          if (!readiness.ready) {
            api.logger.warn(
              `memory-qmd: ${readiness.reason}`,
            );
            return;
          }

          const existing = await qmd.listCollections();
          const existingNames = new Set(existing.map((c) => c.name));

          for (const entry of cfg.collections!) {
            // Format: "path:name" or just "path"
            const [dirPath, name] = entry.includes(":")
              ? entry.split(":", 2)
              : [entry, entry.split("/").pop() ?? "unnamed"];

            if (!existingNames.has(name)) {
              try {
                await qmd.addCollection(dirPath, name, "**/*.md");
                api.logger.info(`memory-qmd: added collection "${name}": ${dirPath}`);
              } catch (err) {
                api.logger.warn(
                  `memory-qmd: failed to add collection "${name}": ${String(err)}`,
                );
              }
            }
          }

          // Incremental embed
          try {
            await qmd.embed(false);
          } catch (err) {
            api.logger.warn(`memory-qmd: embed failed: ${String(err)}`);
          }
        },
        stop() {
          api.logger.info("memory-qmd: stopped");
        },
      });
    }
  },
};

export default memoryQmdPlugin;
