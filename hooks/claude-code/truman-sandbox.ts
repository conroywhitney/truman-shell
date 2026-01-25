/**
 * TrumanShell Sandbox Hook
 *
 * Single PreToolUse hook that intercepts all relevant Claude Code tools
 * and validates paths through TrumanShell's Sandbox.validate_path/3.
 *
 * Tools handled:
 *   Bash       -> Rewrites command to route through truman-shell execute
 *   Read       -> Validates file_path against sandbox
 *   Write      -> Validates file_path against sandbox
 *   Edit       -> Validates file_path against sandbox
 *   Glob       -> Validates path (optional) against sandbox
 *   Grep       -> Validates path (optional) against sandbox
 *   *          -> Allow passthrough
 *
 * Environment:
 *   TRUMAN_DOME         Sandbox root (default: CLAUDE_PROJECT_DIR or cwd)
 *   TRUMAN_SHELL_PATH   Path to truman-shell binary (set by shell wrapper)
 */

import * as readline from "readline";
import { execFileSync } from "child_process";
import { accessSync, existsSync, constants } from "fs";

// --- Interfaces ---

interface PreToolUseInput {
  session_id: string;
  cwd: string;
  tool_name: string;
  tool_input: Record<string, unknown>;
}

interface HookOutput {
  hookSpecificOutput: {
    hookEventName: "PreToolUse";
    permissionDecision: "allow" | "deny";
    permissionDecisionReason?: string;
    updatedInput?: Record<string, unknown>;
  };
}

// --- Configuration ---

const TRUMAN_SHELL_PATH = process.env.TRUMAN_SHELL_PATH;
if (!TRUMAN_SHELL_PATH) {
  console.error(
    "[TrumanShell] TRUMAN_SHELL_PATH not set. Use truman-sandbox.sh wrapper."
  );
  process.exit(2); // exit 2 = blocking error shown to Claude
}

try {
  accessSync(TRUMAN_SHELL_PATH, constants.X_OK);
} catch {
  console.error(
    `[TrumanShell] TRUMAN_SHELL_PATH not found or not executable: ${TRUMAN_SHELL_PATH}`
  );
  process.exit(2);
}

const explicitDome = process.env.TRUMAN_DOME;
if (explicitDome && !existsSync(explicitDome)) {
  console.error(
    `[TrumanShell] TRUMAN_DOME directory does not exist: ${explicitDome}`
  );
  process.exit(2);
}

// --- Tool Handlers ---

type ToolHandler = (input: PreToolUseInput) => HookOutput;

function handleBash(input: PreToolUseInput): HookOutput {
  const command = input.tool_input.command;
  if (!command) {
    return allow();
  }
  if (typeof command !== "string") {
    return deny("Expected string for command");
  }

  const dome = getDome(input.cwd);
  const escapedCmd = shellEscape(command);
  const wrappedCommand = `TRUMAN_DOME=${shellEscape(dome)} ${shellEscape(TRUMAN_SHELL_PATH!)} execute ${escapedCmd}`;

  return {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      updatedInput: {
        command: wrappedCommand,
      },
    },
  };
}

function makeFileToolHandler(pathField: string): ToolHandler {
  return (input: PreToolUseInput): HookOutput => {
    const filePath = input.tool_input[pathField];
    if (!filePath) {
      return allow();
    }
    if (typeof filePath !== "string") {
      return deny(`Expected string for ${pathField}, got ${typeof filePath}`);
    }

    const resolved = validatePath(filePath, input.cwd);
    if (resolved === null) {
      return deny(`No such file or directory: ${filePath}`);
    }

    return {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: {
          [pathField]: resolved,
        },
      },
    };
  };
}

function makeSearchToolHandler(pathField: string): ToolHandler {
  return (input: PreToolUseInput): HookOutput => {
    const searchPath = input.tool_input[pathField];
    if (!searchPath) {
      // No path = search cwd — validate cwd is inside sandbox
      const cwdResolved = validatePath(".", input.cwd);
      if (cwdResolved === null) {
        return deny("Working directory is outside sandbox");
      }
      return allow();
    }
    if (typeof searchPath !== "string") {
      return deny(`Expected string for ${pathField}, got ${typeof searchPath}`);
    }

    const resolved = validatePath(searchPath, input.cwd);
    if (resolved === null) {
      return deny(`No such file or directory: ${searchPath}`);
    }

    return {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        updatedInput: {
          [pathField]: resolved,
        },
      },
    };
  };
}

const TOOL_HANDLERS: Record<string, ToolHandler> = {
  Bash: handleBash,
  Read: makeFileToolHandler("file_path"),
  Write: makeFileToolHandler("file_path"),
  Edit: makeFileToolHandler("file_path"),
  Glob: makeSearchToolHandler("path"),
  Grep: makeSearchToolHandler("path"),
};

// --- Core Validation ---

function validatePath(path: string, cwd: string): string | null {
  const dome = getDome(cwd);

  try {
    const result = execFileSync(
      TRUMAN_SHELL_PATH!,
      ["validate-path", path, cwd],
      {
        encoding: "utf-8",
        timeout: 5000,
        stdio: ["pipe", "pipe", "pipe"],
        env: { ...process.env, TRUMAN_DOME: dome },
      }
    );
    // Exit 0 + stdout = resolved path
    return result.trim() || null;
  } catch (err) {
    // Exit 1 = outside sandbox (or error)
    console.error(
      "[TrumanShell] validatePath failed:",
      err instanceof Error ? err.message : err
    );
    return null;
  }
}

function getDome(cwd: string): string {
  return (
    process.env.TRUMAN_DOME ||
    process.env.CLAUDE_PROJECT_DIR ||
    cwd
  );
}

// --- Helpers ---

function shellEscape(s: string): string {
  // Wrap in single quotes, escape any embedded single quotes
  return `'${s.replace(/'/g, "'\\''")}'`;
}

function allow(): HookOutput {
  return {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
    },
  };
}

function deny(reason: string): HookOutput {
  return {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  };
}

// --- Main ---

async function readStdin(): Promise<string> {
  const rl = readline.createInterface({ input: process.stdin });
  const lines: string[] = [];
  for await (const line of rl) {
    lines.push(line);
  }
  return lines.join("\n");
}

async function main() {
  const raw = await readStdin();
  const input: PreToolUseInput = JSON.parse(raw);

  const handler = TOOL_HANDLERS[input.tool_name];
  if (handler) {
    const output = handler(input);
    console.log(JSON.stringify(output));
  } else {
    // Unknown tool = passthrough
    console.log(JSON.stringify(allow()));
  }
}

// Fail CLOSED: deny on error (not fail-open like the POC)
main().catch((err) => {
  console.error("[TrumanShell] Hook error:", err);
  console.log(JSON.stringify(deny("Sandbox validation error")));
});
