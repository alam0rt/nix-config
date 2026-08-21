/**
 * auto-model
 *
 * Automatically pick a small or large model per user prompt based on a
 * keyword + length heuristic. No LLM classifier — keeps things zero-cost
 * and zero-latency.
 *
 *   small  -> Haiku  (cheap, fast, fine for tool-driven exec)
 *   large  -> Opus   (planning, design, refactor, ambiguous asks)
 *
 * If the user manually picks a model via /model, auto-switching disables
 * itself for the rest of the session. Toggle back on with /auto-model.
 */

import type { Api, Model } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const PROVIDER = "amazon-bedrock";
const SMALL_ID = "us.anthropic.claude-haiku-4-5-20251001-v1:0";
const LARGE_ID = "us.anthropic.claude-opus-4-7";

// Words that strongly suggest a planning / design / investigation task.
const PLAN_KEYWORDS = [
	"plan",
	"design",
	"architect",
	"architecture",
	"refactor",
	"redesign",
	"strategy",
	"investigate",
	"root cause",
	"trade-off",
	"tradeoff",
	"compare",
	"evaluate",
	"audit",
	"review",
	"approach",
	"brainstorm",
	"think through",
	"why is",
	"why does",
	"should we",
	"how would you",
	"propose",
	"options for",
];

function classify(prompt: string): "small" | "large" {
	const p = prompt.toLowerCase();
	if (PLAN_KEYWORDS.some((k) => p.includes(k))) return "large";
	if (prompt.length > 600) return "large";
	if ((prompt.match(/\n/g)?.length ?? 0) > 8) return "large";
	return "small";
}

export default function autoModel(pi: ExtensionAPI) {
	let enabled = true;
	let userOverride = false;
	// Suppress our own pi.setModel() calls from being treated as user overrides.
	let suppressNextSelect = false;

	pi.on("model_select", (event) => {
		if (suppressNextSelect) {
			suppressNextSelect = false;
			return;
		}
		if (event.source === "set") {
			userOverride = true;
		}
	});

	async function pick(kind: "small" | "large", ctx: ExtensionContext) {
		const targetId = kind === "large" ? LARGE_ID : SMALL_ID;
		if (ctx.model?.provider === PROVIDER && ctx.model?.id === targetId) return;
		const m = ctx.modelRegistry.find(PROVIDER, targetId);
		if (!m) {
			ctx.ui.notify(`auto-model: ${PROVIDER}/${targetId} not found`, "warning");
			return;
		}
		suppressNextSelect = true;
		await pi.setModel(m as Model<Api>);
	}

	pi.on("before_agent_start", async (event, ctx) => {
		if (!enabled || userOverride) return;
		const decision = classify(event.prompt ?? "");
		await pick(decision, ctx);
		pi.setThinkingLevel(decision === "large" ? "high" : "medium");
		ctx.ui.setStatus("auto-model", `auto:${decision}`);
	});

	pi.registerCommand("auto-model", {
		description: "Toggle automatic model switching (haiku/opus by prompt heuristic)",
		handler: async (args, ctx) => {
			const arg = (args ?? "").trim().toLowerCase();
			if (arg === "on") {
				enabled = true;
				userOverride = false;
			} else if (arg === "off") {
				enabled = false;
			} else {
				enabled = !enabled;
				if (enabled) userOverride = false;
			}
			ctx.ui.notify(`auto-model: ${enabled && !userOverride ? "ON" : "OFF"}`, "info");
			ctx.ui.setStatus(
				"auto-model",
				enabled && !userOverride ? "auto:on" : undefined,
			);
		},
	});

	pi.on("session_start", async (_event, ctx) => {
		ctx.ui.setStatus("auto-model", "auto:on");
	});
}
