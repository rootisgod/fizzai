import { spawn } from "node:child_process";

const port = 4199;
const server = spawn(process.execPath, [ "server.mjs" ], {
  env: { ...process.env, PORT: String(port) },
  stdio: [ "ignore", "pipe", "inherit" ],
});

try {
  await waitForServer(server);

  const health = await fetchJson(`http://127.0.0.1:${port}/health`);
  const message = await fetchJson(`http://127.0.0.1:${port}/message`);

  if (!health.ok) {
    throw new Error("health endpoint did not return ok");
  }

  if (message.message !== "hello from fizzy factory") {
    throw new Error("message endpoint returned unexpected payload");
  }

  process.stdout.write("demo-api test passed\n");
} finally {
  server.kill("SIGTERM");
}

async function waitForServer(child) {
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("server did not start")), 5000);

    child.stdout.on("data", (chunk) => {
      if (chunk.toString().includes("demo-api listening")) {
        clearTimeout(timeout);
        resolve();
      }
    });

    child.on("exit", (code) => {
      clearTimeout(timeout);
      reject(new Error(`server exited before ready with ${code}`));
    });
  });
}

async function fetchJson(url) {
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`${url} returned ${response.status}`);
  }

  return response.json();
}
