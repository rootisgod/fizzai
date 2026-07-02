# Fizzy Factory Runner

This is the first local runner for Fizzy's software-factory draft.

Rails is the control plane: it owns profiles, skills, cards, runs, runner tokens, retries, logs, and status. This package is the worker: it polls the runner API, claims one ready run, executes it locally, streams logs back to Fizzy, and completes/fails/blocks the run.

## Setup

```bash
cd factory_runner
npm install
```

Register a runner in Fizzy at `/factory/runners/new`, then export:

```bash
export FIZZY_BASE_URL=http://app.fizzy.localhost:3006/897362094
export FIZZY_RUNNER_TOKEN=runner-token-from-fizzy
export FIZZY_RUNNER_REPO=/absolute/path/to/target/repo
```

For a quick control-plane test without Sandcastle:

```bash
export FIZZY_RUNNER_MODE=dry-run
npm run once
```

For Sandcastle/Codex execution:

```bash
codex login status
export FIZZY_RUNNER_MODE=sandcastle
export FIZZY_SANDBOX_IMAGE=sandcastle-your-repo-image
npm run poll
```

Sandcastle expects a Docker image that can run your project and has the `agent` user UID/GID matching the host. The verification command comes from the selected Fizzy profile and runs inside the Sandcastle sandbox after the agent iteration.

## Demo Target

`demo/simple-api` is a tiny Node HTTP API. Use it as `FIZZY_RUNNER_REPO` with a profile verification command of `npm test`.
