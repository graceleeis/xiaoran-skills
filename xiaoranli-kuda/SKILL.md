---
name: xiaoranli-kuda
description: Use immediately when the user says `kuda`, `xiaoranli-kuda`, `用kuda`, `用$xiaoranli-kuda 来debug`, or asks for MaaS Kusto incident debugging with APIM request tracing, FrontDoor or Singularity correlation, AML managed online endpoint logs, or partial identifiers such as `CorrelationId`, resource URIs, `No active target found`, `insufficient_parameters`, `model + region + time window`, `onlineEndpointName`, `deploymentName`, or `apim-request-id`.
compatibility: Requires the Miniconda installation at `/home/xiaoranli/miniconda3` that provides `xiaoranli-kuda` and `python`, plus Azure CLI login.
---

# xiaoranli-kuda

This skill is intentionally narrow.

It targets:

```kusto
TraceCallResult
UnionOfAllLogs('Vienna', 'requests')
AzureMLFrontdoorAccessLog
ContainerTraces_allEnvironments()
UnionOfAllLogs('Vienna', 'AMLManagedComputeLogs')
```

Do not ask the user for cluster or database unless execution fails because `XIAORANLI_KUDA_CLUSTER_URL` or `XIAORANLI_KUDA_DATABASE` is missing. Important implementation quirk: `xiaoranli-kuda investigate --apim-request-id ...` still calls `load_connection_config()` before APIM mode, so you must provide or set the backend Vienna cluster/database for the target region even when APIM tracing is the starting point. For East US backend tracing, use `--cluster-url https://viennause.kusto.windows.net --database Vienna`. APIM tracing itself still uses `https://cogsvc.kusto.windows.net` / `Platform` for the APIM half of the correlation. Singularity tracing defaults to `https://aiscprodkusto.westus2.kusto.windows.net` / `logs`. Also note that customer deployment names in the online URL often differ from backend AML `deploymentName`; correlate by APIM request id -> X-Request-ID -> backend endpoint -> AML deployment instead of assuming the names match.

## Machine-specific bootstrap

Always start with the known-good local environment for this machine. Do not trust bare `python` or bare `xiaoranli-kuda` until this path fails.

1. Export Azure CLI into `PATH` first:
   - `export PATH="/mnt/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin:$PATH"`
2. Prefer these exact binaries:
   - `export KUDA_BIN=/home/xiaoranli/miniconda3/bin/xiaoranli-kuda`
   - `export KUDA_PYTHON=/home/xiaoranli/miniconda3/bin/python`
3. Only use the pyenv shim path for drift diagnosis after the Miniconda path fails:
   - `/home/xiaoranli/.pyenv/shims/xiaoranli-kuda`
   - bare `python`
4. Treat the Miniconda and `xiaoranli-kuda` environment as one unit. If `KUDA_BIN` works, do not re-investigate shell Python resolution.

## Intake Before Query

1. Normalize identifiers before you run anything:
   - exact `apim-request-id` UUID => use it directly
   - `CorrelationId: resource://...:<uuid>` => treat the trailing UUID as the best APIM request id candidate, and keep the prefix only as context
   - explicit `endpoint` + `deployment` => use endpoint/deployment mode
   - model name + region + time window + symptom such as SLA drop, `503`, readiness, or engine suspicion => treat it as a blast-radius investigation, not an intake block
   - model name, region, alert title, or symptom only without a concrete time window => usually not enough for root-cause tracing
2. Try one derivation pass from the incident body, title, and extracted fields before declaring the input insufficient.
3. If the incident is a generic platform-health alert such as `Low pct of ready replicas`, or only provides model/region text without a request id or endpoint/deployment, do not pretend that `xiaoranli-kuda` has already done RCA. Classify it as blocked at intake and state the exact missing identifiers.
4. If several incidents share the same correlation id, model, region pattern, or identical error signature, cluster them as one blast-radius investigation first instead of repeating the same `kuda` run per incident.

## Required setup

1. Export Azure CLI into `PATH`: `export PATH="/mnt/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin:$PATH"`
2. Confirm the CLI exists with the fixed binary: `/home/xiaoranli/miniconda3/bin/xiaoranli-kuda --help`
3. Confirm Azure auth: `az login`
4. Confirm connection env vars exist:
   - `XIAORANLI_KUDA_CLUSTER_URL`
   - `XIAORANLI_KUDA_DATABASE`
5. Optional override env vars:
   - `XIAORANLI_KUDA_APIM_CLUSTER_URL`
   - `XIAORANLI_KUDA_APIM_DATABASE`
   - `XIAORANLI_KUDA_SINGULARITY_CLUSTER_URL`
   - `XIAORANLI_KUDA_SINGULARITY_DATABASE`
6. Run `/home/xiaoranli/miniconda3/bin/xiaoranli-kuda auth-check`
7. Only if step 2 or 6 fails, diagnose path drift with:
   - `which -a xiaoranli-kuda`
   - `/home/xiaoranli/miniconda3/bin/python -c "import kuda; print(kuda.__file__)"`

## Command mapping

Investigate one endpoint or deployment and summarize likely failures:

```bash
"$KUDA_BIN" investigate \
  --deployment <deployment>
```

Trace one APIM request ID across APIM, Nexus, FrontDoor, and container logs:

```bash
"$KUDA_BIN" investigate \
  --apim-request-id <apim-request-id>
```

List all containers for an endpoint and deployment:

```bash
"$KUDA_BIN" list-containers \
  --endpoint <endpoint> \
  --deployment <deployment>
```

Show logs for one container:

```bash
"$KUDA_BIN" logs \
  --endpoint <endpoint> \
  --deployment <deployment> \
  --container <container> \
  --lookback 2h
```

Show the generated KQL without executing it:

```bash
"$KUDA_BIN" logs \
  --endpoint <endpoint> \
  --deployment <deployment> \
  --container <container> \
  --print-query
```

## Workflow

1. Extract `apim-request-id`, or `endpoint`, `deployment`, optional `container`, and optional lookback window.
2. Normalize the input first:
   - if the only structured id is `resource://...:<uuid>`, use the trailing UUID as the APIM request id candidate
   - if the input contains `model + region + time window`, do not stop at intake; treat it as a blast-radius investigation and mine the impacted backend endpoint/deployment pair from `requests`, FrontDoor, and AML logs for that window
   - if the input contains neither a request id, nor endpoint/deployment, nor a usable `model + region + time window` incident window, stop and report an intake block instead of running a dummy `kuda` command
3. If the user gives an APIM request ID, run `investigate --apim-request-id ...` first. Default to `lookback(=7d)` if the user does not specify one.
4. If the user asks what is wrong, asks for DRI support, or gives only one endpoint/deployment identifier, run `investigate` first.
5. If the user asks to list containers, run `list-containers`.
6. If the user asks for logs and names a container, run `logs --container ...`.
7. If the user asks for logs without a container, run `logs` without the container filter.
8. Treat early failure outputs as first-class diagnostic categories:
   - `insufficient investigation parameters` or `insufficient_parameters` => the run never reached trace/log correlation; report exact missing identifiers and the next source to mine
   - `No active target found for <id>` => target resolution failed; treat this as control-plane, stale deployment, suspended endpoint, or no-longer-active-target territory until proven otherwise, and do not waste time on container logs until a real target is resolved
   - multiple installed copies or path drift => verify `which -a xiaoranli-kuda` and `/home/xiaoranli/miniconda3/bin/python -c "import kuda; print(kuda.__file__)"`, but only after the fixed Miniconda path fails
9. Summarize the result directly, leading with the investigation summary when `investigate` was used.
10. When APIM tracing is used, explain that the tool anchors the downstream search to the APIM timestamp and uses `anchor +/- 30m`.
11. If `investigate` succeeds but container rows are empty or you need the true engine-side root cause, query the regional Vienna `AMLManagedComputeLogs` table directly (not `UnionOfAllLogs`) for the correlated backend endpoint/deployment and container. This avoids cross-cluster throttling and is especially useful for `qwen-vllm-ft-sidecar` LoRA failures. Search around the exact request second for strings like the LoRA id, `/scratch/mesh/finetunes/`, `Failed to prepare LoRA directory`, `Deterministic finetune path found in cache`, and `Failed to process LoRA request`.
12. For `model + region + time window` SLA-drop investigations, use this fast path instead of rediscovering the workflow every time:
   - resolve the backend endpoint/deployment pair for the incident window first
   - check `AzureMLFrontdoorAccessLog` for `responseCodeDetails`, `responseCodeReason`, `modelResponseCodeReason`, `durationTotal`, and `durationUpstream`
   - check `AMLManagedComputeLogs` for `VLLM is not ready`, `/health/ready 503`, `/health/live 503`, `Exception in ASGI application`, `start_two.sh`, `streaming_worker_failed`, `/psm_`, and `context canceled`
   - if the user asks whether this is an engine/container issue, prioritize readiness, restart, and engine-side signals before APIM-level speculation
13. If request tracing shows scoring/data-plane symptoms, classify them before concluding:
   - `FrontDoor responseCodeDetails == no_healthy_upstream` or `UH`/`503` => the request likely never reached the model. Treat this as deployment/pod readiness or routing registration investigation, not a model bug.
   - `FrontDoor responseCodeDetails == via_upstream` => the request did reach the backend. Trace by `x-request-id` through downstream logs and then inspect the target container logs.
   - `Duration == 0` with no backend host/upstream evidence => instant rejection at the frontdoor/mesh layer.
   - `UpCluster`/upstream cluster identifiers often encode `{InstanceId}--{DeploymentName}`; preserve these in the summary because they are the best bridge into Singularity namespace/pod debugging.
14. If the trace points to pod health rather than model logic, pivot explicitly into Singularity-style checks instead of stopping at kuda output:
   - inspect deployment / pod readiness state,
   - look for recent sidecar-only restarts,
   - check Kubernetes events for scheduling, probe, image-pull, or crash-loop signals,
   - only then fall back to broad container log scraping.
15. Be careful with deployment naming: customer-facing deployment names in URLs or APIM may differ from backend AML `deploymentName`. Correlate by `apim-request-id -> X-Request-ID -> backend endpoint -> FrontDoor endpointName/deploymentName -> container logs`, not by name guessing.
16. In the final answer, always separate: symptom, deepest confirmed layer, likely root cause, and next manual query/link.
17. Prefer the tool's structured trace output when APIM mode is used. Recent versions return `analysis.structuredSummary` with:
   - `symptom`
   - `correlated_path`
   - `deepest_confirmed_layer`
   - `likely_root_cause`
   - `what_is_not_yet_proven`
   - `next_query_focus`
   Use these fields directly when available instead of re-inventing the summary format.
18. Treat those structured fields as ownership guidance, not just formatting. For your team, the key question is whether the deepest confirmed layer is still in request routing / hosting / LoRA handling, or whether the evidence only shows a downstream Singularity landing symptom.
19. When APIM mode points to readiness/routing health rather than model logic, also use the returned `podHealthQueries` bundle when present:
   - `applicationSnapshotsQuery`
   - `podSnapshotsQuery`
   - `kubernetesEventsQuery`
   These are downstream follow-up queries for `no_healthy_upstream`, instant rejection, and similar mesh-side failures. Use them to confirm or hand off, but do not let them overshadow team-owned hosting / LoRA investigation when direct evidence exists there.
20. In ownership-sensitive cases, prefer this framing in the final answer:
   - customer symptom
   - correlated request path
   - deepest confirmed layer
   - likely root cause
   - what is and is not in team ownership
   - next team-owned query
   - optional downstream Singularity query
21. For LoRA and container-hosting investigations, prioritize engine-side evidence before broad Singularity triage. If AML logs or container traces show adapter/materialization failures, cache-path issues, sidecar bootstrap failures, or request-specific LoRA preparation errors, lead with those findings; treat pod health as secondary confirmation unless the trace clearly stops before hosting.
22. For routine checks, do not create `AI-gen/` summary files or command-log files unless the user explicitly asks for artifacts on disk.
23. Prefer the returned query-opening links over the cluster landing links:
   - endpoint/deployment mode: `resolveQueryLink`, `queryLink`
   - APIM mode: `apimQueryLink`, `nexusQueryLink`, `tracesQueryLink`, `frontdoorQueryLink`, `containerQueryLink`
   These links open Azure Data Explorer with the KQL already filled in, so the user only needs to click and run.
24. Only fall back to `kustoLink` / `apimKustoLink` when a query-specific link is unavailable.
25. In the final answer, include direct clickable links for the next manual step, not just pasted KQL. Preferred pattern:
   - `Logs query: <queryLink>`
   - `Resolve query: <resolveQueryLink>`
   - `APIM trace: <apimQueryLink>`
   - `Backend AML logs: <containerQueryLink>` or `<queryLink>`
26. When the user asks whether an endpoint or deployment is busy, prefer `investigate` first to resolve the true endpoint/deployment pair, then present the exact ADX query link that reproduces the result.

## Debug heuristics to apply in summaries

- Do not jump from `424` straight to "model failure". First decide whether the request was rejected before reaching the backend (`no_healthy_upstream`) or returned by the backend (`via_upstream`).
- Prefer specific request tracing over aggregate trends when the user gives a concrete request id.
- Treat brief bursts carefully: pod readiness flaps and sidecar restarts can create short `424`/`503` windows that may not show up clearly in coarse snapshots.
- When logs are noisy, state the highest-confidence layer only; avoid over-claiming a root cause the trace does not prove.
- If the tool surfaces only APIM/Nexus evidence but the user needs engine-side cause, say so explicitly and continue with direct regional AML or Singularity queries rather than stopping.

## Maintenance notes for local development

- On this machine, the default shell often resolves `xiaoranli-kuda` through `/home/xiaoranli/.pyenv/shims/xiaoranli-kuda`, and that path may not import the correct `kuda` package. Start with `/home/xiaoranli/miniconda3/bin/xiaoranli-kuda` and `/home/xiaoranli/miniconda3/bin/python` first.
- Export `PATH="/mnt/c/Program Files/Microsoft SDKs/Azure/CLI2/wbin:$PATH"` before `auth-check` so the Miniconda environment can find the working Azure CLI.
- Do not assume the editable source is still at `/home/xiaoranli/env-setup/kuda.py`. Verify the active binary and import path only after the fixed Miniconda path fails, using `which -a xiaoranli-kuda` and `/home/xiaoranli/miniconda3/bin/python -c "import kuda; print(kuda.__file__)"`.
- When adding or changing request-trace heuristics, write focused regression tests under `/home/xiaoranli/env-setup/tests/` first. A good pattern is to call `analyze_request_trace(...)` directly with minimal synthetic APIM/Nexus/FrontDoor/container rows.
- In this environment, `pytest` without overrides may import a different installed `kuda` module from pyenv instead of the repo copy. For local tests against source, use `PYTHONPATH=/home/xiaoranli/env-setup pytest ...` or run `/home/xiaoranli/miniconda3/bin/pytest ...` after reinstalling editable.
- If you change the package source, refresh the Miniconda copy first with `/home/xiaoranli/miniconda3/bin/python -m pip install -e /home/xiaoranli/env-setup`.
- Only refresh the pyenv copy if you explicitly need the shim path too: `/home/xiaoranli/.pyenv/versions/3.12.9/bin/python -m pip install -e /home/xiaoranli/env-setup` and `/home/xiaoranli/.pyenv/bin/pyenv rehash`.
- Verify the active Miniconda environment is loading the expected source with `/home/xiaoranli/miniconda3/bin/python -c "import kuda; print(kuda.__file__)"` and `which -a xiaoranli-kuda`.
- For FrontDoor diagnostics, include `responseCodeDetails`, `durationTotal`, and `durationUpstream` in evidence formatting so instant rejections vs backend failures are distinguishable in one glance.

## Example

User:

```text
the incident only gives `CorrelationId: resource://vienna/nexusgithub/llama-3.3-70b-instruct_vienna:4959e241-e032-478b-9fd7-dd444a8ac714`
```

Run:

```bash
"$KUDA_BIN" investigate \
  --apim-request-id 4959e241-e032-478b-9fd7-dd444a8ac714 \
  --cluster-url https://viennause.kusto.windows.net \
  --database Vienna
```

User:

```text
use kuda for AMLManagedComputeLogs, endpoint is mistral-wus-3b-ep, deployment is dep-mistral-wus-3b-250927173559, list all containers
```

Run:

```bash
"$KUDA_BIN" list-containers \
  --endpoint mistral-wus-3b-ep \
  --deployment dep-mistral-wus-3b-250927173559
```

User:

```text
debug this customer request, apim request id is 11111111-2222-3333-4444-555555555555
```

Run:

```bash
"$KUDA_BIN" investigate \
  --apim-request-id 11111111-2222-3333-4444-555555555555
```
