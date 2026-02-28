export type QmdSearchMode = "query" | "vsearch" | "search";

export type QmdConfig = {
  collections?: string[];
  autoRecall?: boolean;
  autoCapture?: boolean;
  searchMode?: QmdSearchMode;
  maxResults?: number;
  minScore?: number;
};

const VALID_SEARCH_MODES = ["query", "vsearch", "search"] as const;
const DEFAULT_SEARCH_MODE: QmdSearchMode = "query";
const DEFAULT_MAX_RESULTS = 5;
const DEFAULT_MIN_SCORE = 0.15;  // 15% - balance between recall and precision

function assertAllowedKeys(
  value: Record<string, unknown>,
  allowed: string[],
  label: string,
) {
  const unknown = Object.keys(value).filter((key) => !allowed.includes(key));
  if (unknown.length === 0) return;
  throw new Error(`${label} has unknown keys: ${unknown.join(", ")}`);
}

export const qmdConfigSchema = {
  parse(value: unknown): QmdConfig {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      // No config is fine - use defaults
      return {
        autoRecall: true,
        autoCapture: true,
        searchMode: DEFAULT_SEARCH_MODE,
        maxResults: DEFAULT_MAX_RESULTS,
        minScore: DEFAULT_MIN_SCORE,
      };
    }

    const cfg = value as Record<string, unknown>;
    assertAllowedKeys(
      cfg,
      ["collections", "autoRecall", "autoCapture", "searchMode", "maxResults", "minScore"],
      "memory-qmd config",
    );

    const searchMode = typeof cfg.searchMode === "string"
      ? cfg.searchMode as QmdSearchMode
      : DEFAULT_SEARCH_MODE;

    if (!VALID_SEARCH_MODES.includes(searchMode as typeof VALID_SEARCH_MODES[number])) {
      throw new Error(`Invalid searchMode: ${searchMode}. Must be one of: ${VALID_SEARCH_MODES.join(", ")}`);
    }

    return {
      collections: Array.isArray(cfg.collections)
        ? cfg.collections.filter((c): c is string => typeof c === "string")
        : undefined,
      autoRecall: cfg.autoRecall !== false,
      autoCapture: cfg.autoCapture !== false,
      searchMode,
      maxResults: typeof cfg.maxResults === "number" ? cfg.maxResults : DEFAULT_MAX_RESULTS,
      minScore: typeof cfg.minScore === "number" ? cfg.minScore : DEFAULT_MIN_SCORE,
    };
  },
};
