/**
 * mcp.ts — basic Model Context Protocol client for pi.
 *
 * Reads ~/.pi/agent/mcp.json (Claude Desktop format), spawns each configured
 * server over stdio, runs the initialize handshake, lists each server's
 * tools, and re-registers them as pi tools (namespaced as `mcp_<server>_<tool>`).
 *
 * Scope: tools only. Skips resources, prompts, sampling, roots — easy to
 * extend later. stdio transport only (no SSE/HTTP).
 *
 * Config format (~/.pi/agent/mcp.json):
 *
 *   {
 *     "mcpServers": {
 *       "filesystem": {
 *         "command": "npx",
 *         "args": ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"]
 *       },
 *       "fetch": {
 *         "command": "uvx",
 *         "args": ["mcp-server-fetch"]
 *       }
 *     }
 *   }
 *
 * Diagnostics: every server lifecycle event (start, init, tool count, errors,
 * exit) is appended to the session as `mcp-event` entries so silent failures
 * stop being silent — same pattern as jj-checkpoint.
 */

import { spawn, type ChildProcess } from "node:child_process";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const CONFIG_PATH = join(homedir(), ".pi", "agent", "mcp.json");
const PROTOCOL_VERSION = "2024-11-05";
const CLIENT_INFO = { name: "pi-mcp-extension", version: "0.1.0" };
const INIT_TIMEOUT_MS = 15000;
const CALL_TIMEOUT_MS = 60000;

// ---- types ----------------------------------------------------------------

interface ServerConfig {
	command: string;
	args?: string[];
	env?: Record<string, string>;
}

interface McpConfig {
	mcpServers?: Record<string, ServerConfig>;
}

interface JsonRpcRequest {
	jsonrpc: "2.0";
	id: number;
	method: string;
	params?: any;
}

interface JsonRpcNotification {
	jsonrpc: "2.0";
	method: string;
	params?: any;
}

interface JsonRpcResponse {
	jsonrpc: "2.0";
	id: number;
	result?: any;
	error?: { code: number; message: string; data?: any };
}

interface McpTool {
	name: string;
	description?: string;
	inputSchema: any;
}

// ---- JSON-RPC stdio client ------------------------------------------------

class McpClient {
	private proc!: ChildProcess;
	private nextId = 1;
	private pending = new Map<number, {
		resolve: (v: any) => void;
		reject: (e: Error) => void;
		timer: NodeJS.Timeout;
	}>();
	private buffer = "";

	constructor(public readonly name: string, private readonly cfg: ServerConfig) {}

	async start(pi: ExtensionAPI): Promise<void> {
		this.proc = spawn(this.cfg.command, this.cfg.args ?? [], {
			env: { ...process.env, ...(this.cfg.env ?? {}) },
			stdio: ["pipe", "pipe", "pipe"],
		});

		this.proc.on("error", (e) => {
			pi.appendEntry("mcp-event", { server: this.name, kind: "spawn-error", error: String(e.message) });
		});
		this.proc.on("exit", (code, signal) => {
			pi.appendEntry("mcp-event", { server: this.name, kind: "exit", code, signal });
			// Reject any in-flight requests
			for (const [, pending] of this.pending) {
				clearTimeout(pending.timer);
				pending.reject(new Error(`mcp server '${this.name}' exited (code=${code}, signal=${signal})`));
			}
			this.pending.clear();
		});

		this.proc.stdout?.on("data", (chunk: Buffer) => {
			this.buffer += chunk.toString("utf8");
			this.drainBuffer(pi);
		});

		// Tee stderr to diagnostic entries (truncated). Helps debug servers
		// that emit useful logs to stderr.
		let stderrBuf = "";
		this.proc.stderr?.on("data", (chunk: Buffer) => {
			stderrBuf += chunk.toString("utf8");
			if (stderrBuf.length > 4096) stderrBuf = stderrBuf.slice(-4096);
		});
		this.proc.on("exit", () => {
			if (stderrBuf.trim()) {
				pi.appendEntry("mcp-event", {
					server: this.name,
					kind: "stderr-tail",
					stderr: stderrBuf.slice(-2000),
				});
			}
		});

		// Initialize handshake
		const initResult = await this.request("initialize", {
			protocolVersion: PROTOCOL_VERSION,
			capabilities: { tools: {} },
			clientInfo: CLIENT_INFO,
		}, INIT_TIMEOUT_MS);

		this.notify("notifications/initialized");

		pi.appendEntry("mcp-event", {
			server: this.name,
			kind: "initialized",
			serverInfo: initResult?.serverInfo,
			protocolVersion: initResult?.protocolVersion,
			capabilities: initResult?.capabilities,
		});
	}

	private drainBuffer(pi: ExtensionAPI) {
		// stdio transport: newline-delimited JSON, one message per line.
		let nl: number;
		while ((nl = this.buffer.indexOf("\n")) >= 0) {
			const line = this.buffer.slice(0, nl).trim();
			this.buffer = this.buffer.slice(nl + 1);
			if (!line) continue;
			let msg: any;
			try {
				msg = JSON.parse(line);
			} catch (e: any) {
				pi.appendEntry("mcp-event", {
					server: this.name,
					kind: "parse-error",
					error: e.message,
					line: line.slice(0, 500),
				});
				continue;
			}
			this.handleMessage(msg);
		}
	}

	private handleMessage(msg: JsonRpcResponse | JsonRpcNotification) {
		if ("id" in msg && msg.id !== undefined && msg.id !== null) {
			const id = msg.id as number;
			const pending = this.pending.get(id);
			if (!pending) return;
			this.pending.delete(id);
			clearTimeout(pending.timer);
			if ("error" in msg && msg.error) {
				pending.reject(new Error(`MCP error ${msg.error.code}: ${msg.error.message}`));
			} else {
				pending.resolve((msg as JsonRpcResponse).result);
			}
		}
		// Notifications from server: ignored for now (e.g. tool list changed).
	}

	private send(payload: JsonRpcRequest | JsonRpcNotification): void {
		this.proc.stdin?.write(`${JSON.stringify(payload)}\n`);
	}

	request(method: string, params?: any, timeoutMs = CALL_TIMEOUT_MS): Promise<any> {
		const id = this.nextId++;
		return new Promise((resolve, reject) => {
			const timer = setTimeout(() => {
				this.pending.delete(id);
				reject(new Error(`MCP request '${method}' timed out after ${timeoutMs}ms`));
			}, timeoutMs);
			this.pending.set(id, { resolve, reject, timer });
			this.send({ jsonrpc: "2.0", id, method, params });
		});
	}

	notify(method: string, params?: any): void {
		this.send({ jsonrpc: "2.0", method, params });
	}

	async listTools(): Promise<McpTool[]> {
		const result = await this.request("tools/list");
		return (result?.tools ?? []) as McpTool[];
	}

	async callTool(name: string, args: any): Promise<{ content: any[]; isError?: boolean }> {
		return this.request("tools/call", { name, arguments: args });
	}

	stop() {
		try {
			this.proc?.kill("SIGTERM");
		} catch {
			/* ignore */
		}
	}
}

// ---- config loading -------------------------------------------------------

function loadConfig(pi: ExtensionAPI): McpConfig {
	try {
		const raw = readFileSync(CONFIG_PATH, "utf8");
		return JSON.parse(raw) as McpConfig;
	} catch (e: any) {
		if (e.code !== "ENOENT") {
			pi.appendEntry("mcp-event", { kind: "config-error", error: e.message, path: CONFIG_PATH });
		}
		return {};
	}
}

// ---- extension ------------------------------------------------------------

// Defer all real work to session_start — the extension runtime isn't fully
// initialized during the factory call, so action methods like appendEntry
// throw "Extension runtime not initialized" if invoked there.
export default function mcpExtension(pi: ExtensionAPI) {
	const clients: McpClient[] = [];

	pi.on("session_start", async (_event) => {
		const config = loadConfig(pi);
		const servers = config.mcpServers ?? {};
		const serverNames = Object.keys(servers);
		if (serverNames.length === 0) {
			pi.appendEntry("mcp-event", { kind: "no-servers", path: CONFIG_PATH });
			return;
		}

		for (const [name, cfg] of Object.entries(servers)) {
			const client = new McpClient(name, cfg);
			try {
				await client.start(pi);
				const tools = await client.listTools();
				pi.appendEntry("mcp-event", { server: name, kind: "tools-listed", count: tools.length });

				for (const tool of tools) {
					const toolName = `mcp_${name}_${tool.name}`;
					pi.registerTool({
						name: toolName,
						label: `mcp:${name}/${tool.name}`,
						description: tool.description ?? `MCP tool ${tool.name} from server ${name}`,
						parameters: tool.inputSchema ?? { type: "object", properties: {} },

						async execute(_id, params) {
							try {
								const r = await client.callTool(tool.name, params);
								const text = (r.content ?? [])
									.filter((c) => c?.type === "text")
									.map((c) => c.text)
									.join("\n");
								const nonText = (r.content ?? []).filter((c) => c?.type !== "text").length;
								return {
									content: [{
										type: "text",
										text: text + (nonText ? `\n\n(${nonText} non-text content items omitted)` : ""),
									}],
									details: {
										server: name,
										tool: tool.name,
										isError: r.isError ?? false,
										contentTypes: (r.content ?? []).map((c) => c?.type),
									},
								};
							} catch (e: any) {
								return {
									content: [{ type: "text", text: `MCP call failed: ${e.message}` }],
									details: { server: name, tool: tool.name, error: e.message },
								};
							}
						},
					});
				}
				clients.push(client);
			} catch (e: any) {
				pi.appendEntry("mcp-event", {
					server: name,
					kind: "init-failed",
					error: e.message,
				});
				client.stop();
			}
		}
	});

	pi.on("session_shutdown", async () => {
		for (const c of clients) c.stop();
		clients.length = 0;
	});
}
