import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const once = process.argv.includes("--once");

const config = {
  baseUrl: requiredEnv("FIZZY_BASE_URL").replace(/\/$/, ""),
  token: requiredEnv("FIZZY_RUNNER_TOKEN"),
  repo: process.env.FIZZY_RUNNER_REPO || process.cwd(),
  mode: process.env.FIZZY_RUNNER_MODE || "sandcastle",
  pollIntervalMs: numberEnv("FIZZY_RUNNER_POLL_INTERVAL_MS", 5000),
  heartbeatIntervalMs: numberEnv("FIZZY_RUNNER_HEARTBEAT_INTERVAL_MS", 15000),
  idleTimeoutSeconds: numberEnv("FIZZY_RUNNER_IDLE_TIMEOUT_SECONDS", 600),
  sandboxImage: process.env.FIZZY_SANDBOX_IMAGE,
  dockerNetwork: process.env.FIZZY_DOCKER_NETWORK,
};

await mkdir(path.join(config.repo, ".fizzy-factory", "logs"), { recursive: true }).catch(() => {});
await main();

async function main() {
  log(`Runner online for ${config.baseUrl}`);
  await api("/factory/runner/heartbeat", {
    method: "POST",
    body: { metadata: runnerMetadata() },
  });

  while (true) {
    const claimedRun = await api("/factory/runner/claim", {
      method: "POST",
      body: { metadata: runnerMetadata() },
    });

    if (claimedRun) {
      await executeRun(claimedRun);
    } else if (once) {
      log("No claimable run.");
      return;
    } else {
      await sleep(config.pollIntervalMs);
    }
  }
}

async function executeRun(run) {
  const stopHeartbeat = startRunHeartbeat(run.id);

  try {
    await postLog(run.id, "system", `Starting ${selectedMode(run)} run in ${config.repo}`);

    if (selectedMode(run) === "dry-run") {
      await executeDryRun(run);
    } else {
      await executeSandcastleRun(run);
    }
  } catch (error) {
    const message = error instanceof Error ? error.stack || error.message : String(error);
    await failRun(run.id, message);
  } finally {
    stopHeartbeat();
  }
}

async function executeDryRun(run) {
  const verification = await runHostVerification(run);

  if (verification.status === "failed") {
    await failRun(run.id, verification.summary, verification.metadata);
  } else {
    await completeRun(run.id, {
      summary: verification.summary,
      branch_name: run.branch_name,
      verification_status: verification.status,
      metadata: verification.metadata,
    });
  }
}

async function executeSandcastleRun(run) {
  const { createSandbox, codex } = await import("@ai-hero/sandcastle");
  const { docker } = await import("@ai-hero/sandcastle/sandboxes/docker");

  if (run.profile.brain_provider !== "codex_cli") {
    await blockRun(run.id, `Unsupported brain provider: ${run.profile.brain_provider}`);
    return;
  }

  const sandbox = await createSandbox({
    branch: sanitizeBranchName(run.branch_name),
    cwd: config.repo,
    sandbox: docker(dockerOptions()),
  });

  try {
    const result = await sandbox.run({
      agent: codex(run.profile.brain_model || "gpt-5.4"),
      prompt: run.prompt,
      maxIterations: run.max_iterations || 1,
      idleTimeoutSeconds: config.idleTimeoutSeconds,
      logging: {
        type: "file",
        path: path.join(config.repo, ".fizzy-factory", "logs", `${run.id}.log`),
        onAgentStreamEvent: (event) => {
          void postLog(run.id, "agent", formatAgentEvent(event)).catch((error) => {
            log(`Failed to stream agent log: ${error.message}`);
          });
        },
      },
    });

    const verification = await runSandboxVerification(run, sandbox);

    if (verification.status === "failed") {
      await failRun(run.id, verification.summary, verification.metadata);
      return;
    }

    await completeRun(run.id, {
      summary: buildSummary(result, verification),
      commit_sha: result.commits.at(-1)?.sha,
      branch_name: sandbox.branch,
      verification_status: verification.status,
      metadata: {
        commits: result.commits,
        log_file_path: result.logFilePath,
        preserved_worktree_path: result.preservedWorktreePath,
        verification: verification.metadata,
      },
    });
  } finally {
    await sandbox.close();
  }
}

async function runSandboxVerification(run, sandbox) {
  if (!run.verification_command) {
    await postLog(run.id, "verification", "No verification command configured.");
    return {
      status: "skipped",
      summary: "Sandcastle run completed. No verification command was configured.",
      metadata: {},
    };
  }

  await postLog(run.id, "verification", `$ ${run.verification_command}`);

  const result = await sandbox.exec(run.verification_command, {
    onLine: (line) => {
      void postLog(run.id, "verification", line).catch((error) => {
        log(`Failed to stream verification log: ${error.message}`);
      });
    },
  });

  return verificationResult(run.verification_command, result);
}

async function runHostVerification(run) {
  if (!run.verification_command) {
    await postLog(run.id, "verification", "No verification command configured.");
    return {
      status: "skipped",
      summary: "Dry-run completed. No verification command was configured.",
      metadata: {},
    };
  }

  await postLog(run.id, "verification", `$ ${run.verification_command}`);
  const result = await execLocal(run.verification_command, config.repo, (line) => {
    void postLog(run.id, "verification", line).catch((error) => {
      log(`Failed to stream verification log: ${error.message}`);
    });
  });

  return verificationResult(run.verification_command, result);
}

function verificationResult(command, result) {
  const passed = result.exitCode === 0;

  return {
    status: passed ? "passed" : "failed",
    summary: passed
      ? `Verification passed: ${command}`
      : `Verification failed with exit ${result.exitCode}: ${command}`,
    metadata: {
      command,
      exit_code: result.exitCode,
      stdout_tail: tail(result.stdout),
      stderr_tail: tail(result.stderr),
    },
  };
}

function buildSummary(result, verification) {
  const commitCount = result.commits.length;
  const commitText = commitCount === 1 ? "1 commit" : `${commitCount} commits`;
  return `Sandcastle run completed with ${commitText}. ${verification.summary}`;
}

function dockerOptions() {
  const options = {};

  if (config.sandboxImage) {
    options.imageName = config.sandboxImage;
  }

  if (config.dockerNetwork) {
    options.network = config.dockerNetwork;
  }

  return options;
}

function selectedMode(run) {
  if (config.mode === "dry-run" || run.profile.runner_kind === "dry_run") {
    return "dry-run";
  }

  return "sandcastle";
}

function startRunHeartbeat(runId) {
  const timer = setInterval(() => {
    void api(`/factory/runner/runs/${runId}/heartbeat`, {
      method: "POST",
      body: { metadata: runnerMetadata() },
    }).catch((error) => {
      log(`Heartbeat failed: ${error.message}`);
    });
  }, config.heartbeatIntervalMs);

  return () => clearInterval(timer);
}

async function completeRun(runId, body) {
  await api(`/factory/runner/runs/${runId}/completion`, {
    method: "POST",
    body,
  });
}

async function failRun(runId, failureReason, metadata = {}) {
  await api(`/factory/runner/runs/${runId}/failure`, {
    method: "POST",
    body: { failure_reason: failureReason, metadata },
  });
}

async function blockRun(runId, blockReason, metadata = {}) {
  await api(`/factory/runner/runs/${runId}/block`, {
    method: "POST",
    body: { block_reason: blockReason, metadata },
  });
}

async function postLog(runId, stream, content) {
  if (!content) return;

  await api(`/factory/runner/runs/${runId}/logs`, {
    method: "POST",
    body: { stream, content },
  });
}

async function api(pathname, options = {}) {
  const headers = {
    Accept: "application/json",
    Authorization: `Bearer ${config.token}`,
  };

  if (options.body) {
    headers["Content-Type"] = "application/json";
  }

  const response = await fetch(`${config.baseUrl}${pathname}`, {
    method: options.method || "GET",
    headers,
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  if (response.status === 204) {
    return null;
  }

  const text = await response.text();
  const payload = text ? JSON.parse(text) : null;

  if (!response.ok) {
    throw new Error(payload?.error || `${response.status} ${response.statusText}`);
  }

  return payload;
}

function execLocal(command, cwd, onLine) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, {
      cwd,
      shell: true,
      env: process.env,
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      const text = chunk.toString();
      stdout += text;
      streamLines(text, onLine);
    });

    child.stderr.on("data", (chunk) => {
      const text = chunk.toString();
      stderr += text;
      streamLines(text, onLine);
    });

    child.on("error", reject);
    child.on("close", (exitCode) => {
      resolve({ exitCode: exitCode ?? 1, stdout, stderr });
    });
  });
}

function streamLines(text, onLine) {
  text.split(/\r?\n/).forEach((line) => {
    if (line.trim()) onLine(line);
  });
}

function formatAgentEvent(event) {
  if (event.type === "text") return event.message;
  if (event.type === "toolCall") return `${event.name} ${event.formattedArgs}`;
  return event.line;
}

function sanitizeBranchName(branchName) {
  return branchName.replace(/[^A-Za-z0-9._/-]/g, "-").replace(/^\/+/, "");
}

function runnerMetadata() {
  return {
    mode: config.mode,
    repo: config.repo,
    node: process.version,
    pid: process.pid,
    hostname: process.env.HOSTNAME,
  };
}

function tail(text, length = 4000) {
  if (!text) return "";
  return text.length > length ? text.slice(text.length - length) : text;
}

function numberEnv(name, fallback) {
  const value = process.env[name];
  if (!value) return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function requiredEnv(name) {
  const value = process.env[name];

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function log(message) {
  process.stdout.write(`[fizzy-runner] ${message}\n`);
}
