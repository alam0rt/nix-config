/**
 * firefox-cookies — read-only access to Firefox cookies for the agent.
 *
 * Surfaces a `firefox_cookie` tool. Looks up cookies by host (and optional
 * name) from the active Firefox profile's cookies.sqlite. Read-only; never
 * writes to the Firefox profile.
 *
 * Safety:
 *   - Per-host allowlist. Hosts not on the list trigger a confirm dialog
 *     (allow-once / allow-for-session / deny). Non-interactive sessions
 *     deny by default unless the host is preconfigured.
 *   - Strict input validation on host/name to avoid SQL injection in the
 *     sqlite3 CLI invocation (we shell out instead of taking a node-sqlite
 *     dependency).
 *   - Copies cookies.sqlite to a tempfile so we don't fight Firefox's lock.
 *
 * Caveats:
 *   - macOS paths only (~/Library/Application Support/Firefox). Trivial to
 *     extend; PRs welcome from future-you.
 *   - Plaintext cookies only. Saved logins (logins.json + key4.db) are NSS-
 *     encrypted and would need firefox_decrypt or libnss FFI. Not here.
 */

import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, readFileSync, unlinkSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Hosts that may be queried without an interactive confirm. Edit to taste.
// Suffix match: ".github.com" matches "api.github.com", "www.github.com", etc.
const PRECONFIGURED_HOSTS: string[] = [
	// e.g. ".github.com",
	// e.g. ".zendesk.com",
];

const FIREFOX_BASE = join(homedir(), "Library/Application Support/Firefox");
const HOST_RE = /^[a-zA-Z0-9._-]+$/;
const NAME_RE = /^[a-zA-Z0-9._%-]+$/;

// ---- Profile resolution ----------------------------------------------------

function resolveProfileDir(): string | undefined {
	const ini = join(FIREFOX_BASE, "profiles.ini");
	if (!existsSync(ini)) return undefined;
	const text = readFileSync(ini, "utf8");

	type Section = { name: string; kv: Record<string, string> };
	const sections: Section[] = [];
	let current: Section | undefined;
	for (const raw of text.split("\n")) {
		const line = raw.trim();
		if (!line || line.startsWith("#")) continue;
		const m = line.match(/^\[(.+)\]$/);
		if (m) {
			current = { name: m[1], kv: {} };
			sections.push(current);
			continue;
		}
		if (!current) continue;
		const kv = line.match(/^([^=]+)=(.*)$/);
		if (kv) current.kv[kv[1].trim()] = kv[2].trim();
	}

	// Most authoritative: an [InstallXXX] section's `Default=` points at the
	// profile directory for this Firefox install.
	const install = sections.find((s) => s.name.startsWith("Install") && s.kv.Default);
	const candidates: string[] = [];
	if (install?.kv.Default) candidates.push(install.kv.Default);

	// Then any [ProfileN] with Default=1.
	for (const s of sections) {
		if (s.name.startsWith("Profile") && s.kv.Default === "1" && s.kv.Path) {
			candidates.push(s.kv.Path);
		}
	}
	// Finally any [ProfileN] with a Path.
	for (const s of sections) {
		if (s.name.startsWith("Profile") && s.kv.Path) candidates.push(s.kv.Path);
	}

	for (const rel of candidates) {
		const abs = rel.startsWith("/") ? rel : join(FIREFOX_BASE, rel);
		if (existsSync(join(abs, "cookies.sqlite"))) return abs;
	}
	return undefined;
}

// ---- Allowlist -------------------------------------------------------------

function hostMatches(query: string, pattern: string): boolean {
	// pattern ".github.com" matches "api.github.com" and "github.com".
	if (pattern.startsWith(".")) {
		const bare = pattern.slice(1);
		return query === bare || query.endsWith(pattern);
	}
	return query === pattern;
}

// ---- Extension -------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	const sessionAllowed = new Set<string>(); // hosts allowed for this session

	const cookieTool = defineTool({
		name: "firefox_cookie",
		label: "ff cookie",
		description: [
			"Read cookies from the active Firefox profile (read-only).",
			"",
			"Returns matching cookies as one JSON object per line:",
			'  {"host":"...","name":"...","value":"...","path":"...","expiry":<unix>}',
			"",
			"Per-host confirm gates apply unless the host is preconfigured.",
			"Cannot read encrypted saved logins; cookies only.",
		].join("\n"),
		parameters: Type.Object({
			host: Type.String({
				description: "Cookie host. Substring match. e.g. 'github.com', 'zendesk.com'.",
			}),
			name: Type.Optional(Type.String({ description: "Exact cookie name." })),
			include_value: Type.Optional(
				Type.Boolean({ description: "Include cookie values (default true)." }),
			),
		}),

		async execute(_id, params, _signal, _onUpdate, ctx) {
			if (!HOST_RE.test(params.host)) {
				return { content: [{ type: "text", text: "invalid host" }], details: {} };
			}
			if (params.name !== undefined && !NAME_RE.test(params.name)) {
				return { content: [{ type: "text", text: "invalid name" }], details: {} };
			}

			// Authorization gate.
			const preconfigured = PRECONFIGURED_HOSTS.some((p) => hostMatches(params.host, p));
			const sessionOk = Array.from(sessionAllowed).some((p) => hostMatches(params.host, p));
			if (!preconfigured && !sessionOk) {
				if (!ctx?.hasUI) {
					return {
						content: [
							{
								type: "text",
								text: `denied: host '${params.host}' not in allowlist (non-interactive session)`,
							},
						],
						details: { denied: true, host: params.host },
					};
				}
				const choice = await ctx.ui.select(
					`Read Firefox cookies for '${params.host}'?`,
					["Allow once", "Allow for this session", "Deny"],
				);
				if (choice === "Deny" || !choice) {
					return {
						content: [{ type: "text", text: `denied by user: ${params.host}` }],
						details: { denied: true, host: params.host },
					};
				}
				if (choice === "Allow for this session") sessionAllowed.add(params.host);
			}

			const profile = resolveProfileDir();
			if (!profile) {
				return { content: [{ type: "text", text: "no firefox profile found" }], details: {} };
			}

			// Copy to dodge Firefox's exclusive lock on the WAL.
			// Must copy the -wal and -shm sidecars too — sqlite refuses to open
			// a WAL-mode db that references a missing wal file.
			const tmp = join(tmpdir(), `pi-ff-cookies-${process.pid}-${Date.now()}.sqlite`);
			const src = join(profile, "cookies.sqlite");
			try {
				copyFileSync(src, tmp);
				for (const ext of ["-wal", "-shm"]) {
					if (existsSync(src + ext)) copyFileSync(src + ext, tmp + ext);
				}
			} catch (e: any) {
				return {
					content: [{ type: "text", text: `cannot read cookies db: ${e.message}` }],
					details: {},
				};
			}

			const includeValue = params.include_value !== false;
			const cols = includeValue
				? "host,name,value,path,expiry"
				: "host,name,'<redacted>',path,expiry";
			const where = params.name
				? `host LIKE '%${params.host}%' AND name = '${params.name}'`
				: `host LIKE '%${params.host}%'`;
			const sql = `SELECT json_object('host',host,'name',name,'value',${
				includeValue ? "value" : "'<redacted>'"
			},'path',path,'expiry',expiry) FROM moz_cookies WHERE ${where};`;

			const r = spawnSync("sqlite3", ["-readonly", tmp, sql], { encoding: "utf8" });
			const out = (r.stdout || "").trim();
			const err = (r.stderr || "").trim();
			void cols; // silence unused

			// Cleanup tempfiles regardless of outcome.
			for (const p of [tmp, `${tmp}-wal`, `${tmp}-shm`]) {
				try { unlinkSync(p); } catch { /* ignore */ }
			}

			if (r.status !== 0) {
				return {
					content: [{ type: "text", text: `sqlite3 error: ${err || "unknown"}` }],
					details: { exitCode: r.status },
				};
			}

			const lines = out ? out.split("\n") : [];
			return {
				content: [{ type: "text", text: lines.length ? lines.join("\n") : "(no matches)" }],
				details: { host: params.host, count: lines.length, profile },
			};
		},
	});

	pi.registerTool(cookieTool);
}
