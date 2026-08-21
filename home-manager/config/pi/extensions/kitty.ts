/**
 * kitty — six small kitty integrations for pi.
 *
 * Each section is independent; comment out any you don't want.
 *
 *   1. show_image / mermaid_render  — inline images via overlay window
 *   2. bash_detached / bash_peek    — long-running cmds in side window
 *   3. live jj-log tab              — spawned at session_start
 *   4. clipboard                    — read/write via OSC 52
 *   5. notify-on-needed-input       — desktop notifications
 *   6. tab title + colour           — ambient agent state
 *
 * Requires kitty with remote control enabled. In kitty.conf:
 *     allow_remote_control yes
 *     listen_on unix:/tmp/kitty-${KITTY_PID}
 * (or invoke kitty with --listen-on; pi will inherit KITTY_LISTEN_ON env var.)
 */

import { spawn, spawnSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { extname, join } from "node:path";
import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Image } from "@earendil-works/pi-tui";

// ---- helpers ---------------------------------------------------------------

function inKitty(): boolean {
	return Boolean(process.env.KITTY_PID || process.env.KITTY_WINDOW_ID);
}

// Prefer the unix socket (KITTY_LISTEN_ON) if available — same idea as $TMUX.
// Falls back to /dev/tty, which only works if the calling process has a
// controlling tty (pi subprocesses generally don't, hence the socket).
function kittyAt(args: string[]): { ok: boolean; stdout: string; stderr: string } {
	const extra = process.env.KITTY_LISTEN_ON ? ["--to", process.env.KITTY_LISTEN_ON] : [];
	const r = spawnSync("kitty", ["@", ...extra, ...args], { encoding: "utf8" });
	return {
		ok: r.status === 0,
		stdout: (r.stdout || "").trim(),
		stderr: (r.stderr || "").trim(),
	};
}

// True iff we have a viable transport for `kitty @` from non-tty subprocesses.
function canRemote(): boolean {
	return inKitty() && Boolean(process.env.KITTY_LISTEN_ON);
}

// ---- 1. inline images ------------------------------------------------------

const mermaidRender = defineTool({
	name: "mermaid_render",
	label: "mermaid",
	description: "Render mermaid source to PNG and display in kitty overlay. Requires `mmdc`.",
	parameters: Type.Object({
		source: Type.String({ description: "Mermaid diagram source" }),
	}),
	async execute(_id, params) {
		const src = join(tmpdir(), `pi-mermaid-${Date.now()}.mmd`);
		const out = src.replace(/\.mmd$/, ".png");
		writeFileSync(src, params.source);
		const mm = spawnSync("mmdc", ["-i", src, "-o", out], { encoding: "utf8" });
		if (mm.status !== 0) {
			return { content: [{ type: "text", text: `mmdc failed: ${mm.stderr}` }], details: {} };
		}
		const base64 = readFileSync(out).toString("base64");
		return {
			content: [{ type: "text", text: `rendered (${base64.length} b64 bytes)` }],
			details: { base64, mime: "image/png", maxWidth: 100, maxHeight: 30, path: out },
		};
	},
	renderResult(result, _options, theme, _ctx) {
		const d: any = result.details ?? {};
		if (!d.base64) return null as any;
		return new Image(d.base64, d.mime ?? "image/png", theme.image ?? theme, {
			maxWidthCells: d.maxWidth ?? 100,
			maxHeightCells: d.maxHeight ?? 30,
		});
	},
});

// ---- 2. detached bash ------------------------------------------------------

// in-memory map of window-id -> log path so bash_peek can find output
const detachedWindows = new Map<string, string>();

const bashDetached = defineTool({
	name: "bash_detached",
	label: "bash (detached)",
	description: [
		"Run a shell command in a fresh kitty window. Returns immediately with",
		"a window_id. Use bash_peek to read its output without flooding chat.",
		"Use this for: dev servers, watch-mode tests, long builds.",
	].join(" "),
	parameters: Type.Object({
		cmd: Type.String({ description: "Shell command to run" }),
		title: Type.Optional(Type.String()),
	}),
	async execute(_id, params) {
		if (!inKitty()) return { content: [{ type: "text", text: "not running in kitty" }], details: {} };
		const log = join(tmpdir(), `pi-detached-${Date.now()}.log`);
		// `tee` so output stays on screen AND is captured for bash_peek.
		const wrapped = `${params.cmd} 2>&1 | tee ${log}; echo; echo "[exit $?]"; exec bash`;
		const r = kittyAt([
			"launch", "--type=window", "--keep-focus",
			"--title", params.title ?? params.cmd.slice(0, 40),
			"--", "bash", "-c", wrapped,
		]);
		if (!r.ok) return { content: [{ type: "text", text: `launch failed: ${r.stderr}` }], details: {} };
		const wid = r.stdout;
		detachedWindows.set(wid, log);
		return {
			content: [{ type: "text", text: `window_id=${wid}\nlog=${log}` }],
			details: { window_id: wid, log },
		};
	},
});

const bashPeek = defineTool({
	name: "bash_peek",
	label: "bash peek",
	description: "Read the tail of a detached bash window's output.",
	parameters: Type.Object({
		window_id: Type.String(),
		lines: Type.Optional(Type.Number({ description: "Tail this many lines (default 50)" })),
	}),
	async execute(_id, params) {
		const log = detachedWindows.get(params.window_id);
		if (!log) return { content: [{ type: "text", text: "unknown window_id" }], details: {} };
		const n = params.lines ?? 50;
		const r = spawnSync("tail", ["-n", String(n), log], { encoding: "utf8" });
		return { content: [{ type: "text", text: r.stdout || "(empty)" }], details: { log } };
	},
});

// ---- 7. read_window: feed the agent what's on a side pane's screen --------

const readWindow = defineTool({
	name: "read_window",
	label: "read window",
	description: [
		"Read text from another kitty window. Useful for letting the agent see",
		"the dev server log, build output, or any side pane the user is",
		"watching, without you copy-pasting.",
		"",
		"Match by window_id (preferred) or by title substring.",
		"extent: screen (visible) | all (incl. scrollback) | first_cmd_output",
	].join("\n"),
	parameters: Type.Object({
		window_id: Type.Optional(Type.String()),
		title: Type.Optional(Type.String({ description: "Match window/tab title substring" })),
		extent: Type.Optional(
			Type.Union([Type.Literal("screen"), Type.Literal("all"), Type.Literal("first_cmd_output")]),
		),
	}),
	async execute(_id, params) {
		if (!inKitty()) return { content: [{ type: "text", text: "not running in kitty" }], details: {} };
		const args = ["get-text", "--extent", params.extent ?? "screen"];
		if (params.window_id) args.push("--match", `id:${params.window_id}`);
		else if (params.title) args.push("--match", `title:${params.title}`);
		else args.push("--match", "recent:1");
		const r = kittyAt(args);
		if (!r.ok) return { content: [{ type: "text", text: `failed: ${r.stderr}` }], details: {} };
		return {
			content: [{ type: "text", text: r.stdout || "(empty)" }],
			details: { bytes: r.stdout.length },
		};
	},
});

// ---- 8. hgrep: ripgrep with clickable terminal hyperlinks ------------------

const hgrep = defineTool({
	name: "hgrep",
	label: "hgrep",
	description: [
		"Run ripgrep and return matches with kitty OSC-8 hyperlinks so each",
		"match is cmd-clickable in the terminal. Same matches as plain rg,",
		"but the user can jump to any match with one keystroke.",
	].join("\n"),
	parameters: Type.Object({
		pattern: Type.String(),
		path: Type.Optional(Type.String({ description: "Search root (default: cwd)" })),
		max: Type.Optional(Type.Number({ description: "Max matches (default 50)" })),
	}),
	async execute(_id, params) {
		const root = params.path ?? process.cwd();
		const max = params.max ?? 50;
		const r = spawnSync(
			"rg",
			["--vimgrep", "--no-heading", "--color=never", "-m", String(max), "--", params.pattern, root],
			{ encoding: "utf8" },
		);
		if (r.status !== 0 && r.status !== 1) {
			return { content: [{ type: "text", text: `rg failed: ${r.stderr}` }], details: {} };
		}
		const lines = (r.stdout || "").trim().split("\n").filter(Boolean);
		if (!lines.length) return { content: [{ type: "text", text: "(no matches)" }], details: {} };
		const esc = (s: string) => `\x1b]8;;${s}\x1b\\`;
		const END = "\x1b]8;;\x1b\\";
		const formatted = lines.map((l) => {
			const m = l.match(/^([^:]+):(\d+):(\d+):(.*)$/);
			if (!m) return l;
			const [, file, line, col, content] = m;
			const abs = file.startsWith("/") ? file : `${root}/${file}`;
			const uri = `file://${abs}#L${line}`;
			return `${esc(uri)}${file}:${line}:${col}${END}: ${content}`;
		});
		return {
			content: [{ type: "text", text: formatted.join("\n") }],
			details: { matches: lines.length },
		};
	},
});

// ---- 4. clipboard ----------------------------------------------------------

const clipboard = defineTool({
	name: "clipboard",
	label: "clipboard",
	description: "Read or write the user's system clipboard via kitty (OSC 52).",
	parameters: Type.Object({
		mode: Type.Union([Type.Literal("read"), Type.Literal("write")]),
		content: Type.Optional(Type.String({ description: "Required for write" })),
	}),
	async execute(_id, params) {
		if (params.mode === "read") {
			const r = spawnSync("kitten", ["clipboard", "--get-clipboard"], { encoding: "utf8" });
			return {
				content: [{ type: "text", text: r.stdout || "(empty)" }],
				details: { bytes: (r.stdout ?? "").length },
			};
		}
		if (!params.content) {
			return { content: [{ type: "text", text: "content required for write" }], details: {} };
		}
		const r = spawnSync("kitten", ["clipboard"], {
			input: params.content,
			encoding: "utf8",
		});
		return {
			content: [{ type: "text", text: r.status === 0 ? "ok" : `failed: ${r.stderr}` }],
			details: { bytes: params.content.length },
		};
	},
});

// ---- main ------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	pi.registerTool(mermaidRender);
	pi.registerTool(bashDetached);
	pi.registerTool(bashPeek);
	pi.registerTool(clipboard);
	pi.registerTool(readWindow);
	pi.registerTool(hgrep);

	// ---- 3. live jj-log tab (spawned once per session) -----------------------
	pi.on("session_start", async () => {
		if (!inKitty()) return;
		// Don't spawn a duplicate if one already exists with our title.
		const ls = kittyAt(["ls"]);
		if (ls.ok && ls.stdout.includes('"title": "pi:jj-log"')) return;
		// Check we're in a jj repo before opening the tab.
		const isJj = spawnSync("jj", ["--no-pager", "root"]).status === 0;
		if (!isJj) return;
		kittyAt([
			"launch",
			"--type=tab",
			"--tab-title", "pi:jj-log",
			"--keep-focus",
			"--", "watch", "-n", "1", "-c",
			"jj", "--no-pager", "log", "--limit", "30",
		]);
	});

	// ---- 5. notifications ----------------------------------------------------
	function notify(title: string, body: string) {
		if (!inKitty()) return;
		// `kitten notify` is OSC 99; works inside the running kitty.
		spawn("kitten", ["notify", "--app-name", "pi", title, body], { detached: true, stdio: "ignore" });
	}

	pi.on("agent_end", async () => {
		// Only notify if the kitty window is *not* focused — otherwise it's noise.
		const ls = kittyAt(["ls"]);
		if (ls.ok && ls.stdout.includes('"is_focused": true')) return;
		notify("pi", "agent finished");
	});
	pi.on("session_before_fork", async () => notify("pi", "fork confirmation needed"));

	// ---- 6. tab title + colour as ambient state ------------------------------
	const setTab = (title?: string, color?: string) => {
		if (!inKitty()) return;
		if (title) kittyAt(["set-tab-title", title]);
		if (color) kittyAt(["set-tab-color", "active_bg", color]);
	};

	let currentModel = "?";
	pi.on("model_select", async (event) => {
		const m: any = (event as any).model;
		if (m) currentModel = `${m.provider}/${m.id}`;
		setTab(`pi · ${currentModel}`, "#1d3557"); // idle blue
	});
	pi.on("turn_start", async () => setTab(`pi · ${currentModel} · busy`, "#e29578")); // amber
	pi.on("turn_end", async () => setTab(`pi · ${currentModel}`, "#1d3557"));
	pi.on("session_before_fork", async () => setTab(`pi · waiting`, "#9d0208")); // red
	pi.on("agent_end", async () => setTab(`pi · ${currentModel} · idle`, "#588157")); // green
}
