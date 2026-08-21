/**
 * ed_edit — toy file-editing tool that drives `ed`, the standard line editor.
 *
 * The model supplies a path and a raw ed script. We append `w` and `q` for
 * convenience, run `ed -s <path>`, and return a minimal status line plus a
 * unified diff (so the model can verify what it just did without us echoing
 * the whole file).
 *
 * Why: experiment with whether ed's terse line-addressing syntax
 * (e.g. `5,7d`, `/foo/s//bar/`, `2a\n...\n.`) is more token-efficient than
 * the built-in edit tool's full-context oldText/newText replacement.
 *
 * Drop into ~/.pi/agent/extensions/ and it auto-loads.
 */

import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import * as path from "node:path";
import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

function runEd(filePath: string, script: string, signal: AbortSignal): Promise<{ code: number; stdout: string; stderr: string }> {
	return new Promise((resolve, reject) => {
		const child = spawn("ed", ["-s", filePath], { stdio: ["pipe", "pipe", "pipe"] });
		let stdout = "";
		let stderr = "";
		child.stdout.on("data", (b) => (stdout += b.toString()));
		child.stderr.on("data", (b) => (stderr += b.toString()));
		child.on("error", reject);
		child.on("close", (code) => resolve({ code: code ?? -1, stdout, stderr }));

		signal.addEventListener("abort", () => child.kill("SIGTERM"), { once: true });

		// Ensure the script ends with a save+quit. ed is happy to see them twice.
		const finalScript = script.endsWith("\n") ? script : `${script}\n`;
		child.stdin.write(finalScript);
		child.stdin.write("w\nq\n");
		child.stdin.end();
	});
}

function unifiedDiff(before: string, after: string, label: string): string {
	// Tiny diff: just line-by-line, no hunking. Good enough to skim.
	const a = before.split("\n");
	const b = after.split("\n");
	const out: string[] = [`--- ${label} (before)`, `+++ ${label} (after)`];
	const max = Math.max(a.length, b.length);
	for (let i = 0; i < max; i++) {
		if (a[i] === b[i]) continue;
		if (a[i] !== undefined) out.push(`-${i + 1}: ${a[i]}`);
		if (b[i] !== undefined) out.push(`+${i + 1}: ${b[i]}`);
	}
	if (out.length === 2) return "(no change)";
	return out.join("\n");
}

const edTool = defineTool({
	name: "ed_edit",
	label: "ed",
	description: [
		"Edit a file by piping commands to `ed -s` (the classic line editor).",
		"Provide an ed script in `script`. `w` and `q` are appended automatically.",
		"",
		"Common ed commands:",
		"  Na          append after line N (terminate input with a single '.')",
		"  Ni          insert before line N (terminate with '.')",
		"  Nc          change line N (terminate with '.')",
		"  N,Md        delete lines N..M",
		"  N,Ms/re/repl/   substitute on lines N..M (g flag for all matches)",
		"  ,p          print whole file",
		"  $           last line",
		"",
		"Example script to replace lines 5-7 with one line:",
		"  5,7c",
		"  new content",
		"  .",
		"",
		"If the file does not exist it will be created empty before the script runs.",
	].join("\n"),
	parameters: Type.Object({
		path: Type.String({ description: "Path to the file to edit (relative or absolute)" }),
		script: Type.String({ description: "ed commands, newline-separated. Do not include trailing w/q." }),
		show_diff: Type.Optional(Type.Boolean({ description: "Return a small diff. Default true." })),
	}),

	async execute(_id, params, signal, _onUpdate, _ctx) {
		const filePath = path.resolve(params.path);
		let before = "";
		try {
			before = await fs.readFile(filePath, "utf8");
		} catch (e: any) {
			if (e.code === "ENOENT") {
				await fs.mkdir(path.dirname(filePath), { recursive: true });
				await fs.writeFile(filePath, "");
			} else {
				throw e;
			}
		}

		const { code, stdout, stderr } = await runEd(filePath, params.script, signal);
		const after = await fs.readFile(filePath, "utf8");

		const ok = code === 0 && !stderr.includes("?");
		const showDiff = params.show_diff !== false;

		const lines: string[] = [];
		lines.push(ok ? `ok (${after.split("\n").length} lines)` : `ed exited ${code}`);
		if (stderr.trim()) lines.push(`stderr: ${stderr.trim()}`);
		if (stdout.trim()) lines.push(`stdout: ${stdout.trim()}`);
		if (showDiff) lines.push(unifiedDiff(before, after, params.path));

		return {
			content: [{ type: "text", text: lines.join("\n") }],
			details: { path: params.path, exitCode: code, bytesBefore: before.length, bytesAfter: after.length },
		};
	},
});

export default function (pi: ExtensionAPI) {
	pi.registerTool(edTool);
}
