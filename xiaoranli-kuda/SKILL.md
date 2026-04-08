---
name: xiaoranli-kuda
description: Use when the user wants MaaS Kusto help for APIM request tracing, regional FrontDoor lookups, direct Singularity container traces, or AML managed online endpoint logs. Trigger on prompts like "debug this APIM request id", "find the root cause for request id", "use kuda for AMLManagedComputeLogs", "list all containers", or requests about `onlineEndpointName`, `deploymentName`, `AMLManagedComputeLogs`, `ContainerTraces_allEnvironments`, `TraceCallResult`, or `apim-request-id`.
compatibility: Requires the `xiaoranli` package installation that provides `xiaoranli-kuda`, plus Azure CLI login.
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

## Required setup

1. Confirm the CLI exists: `xiaoranli-kuda --help`
2. Confirm Azure auth: `az login`
3. Confirm connection env vars exist:
   - `XIAORANLI_KUDA_CLUSTER_URL`
   - `XIAORANLI_KUDA_DATABASE`
4. Optional override env vars:
   - `XIAORANLI_KUDA_APIM_CLUSTER_URL`
   - `XIAORANLI_KUDA_APIM_DATABASE`
   - `XIAORANLI_KUDA_SINGULARITY_CLUSTER_URL`
   - `XIAORANLI_KUDA_SINGULARITY_DATABASE`
5. Run `xiaoranli-kuda auth-check`

## Command mapping

Investigate one endpoint or deployment and summarize likely failures:

```bash
xiaoranli-kuda investigate \
  --deployment <deployment>
```

Trace one APIM request ID across APIM, Nexus, FrontDoor, and container logs:

```bash
xiaoranli-kuda investigate \
  --apim-request-id <apim-request-id>
```

List all containers for an endpoint and deployment:

```bash
xiaoranli-kuda list-containers \
  --endpoint <endpoint> \
  --deployment <deployment>
```

Show logs for one container:

```bash
xiaoranli-kuda logs \
  --endpoint <endpoint> \
  --deployment <deployment> \
  --container <container> \
  --lookback 2h
```

Show the generated KQL without executing it:

```bash
xiaoranli-kuda logs \
  --endpoint <endpoint> \
  --deployment <deployment> \
  --container <container> \
  --print-query
```

## Workflow

1. Extract `apim-request-id`, or `endpoint`, `deployment`, optional `container`, and optional lookback window.
2. If the user gives an APIM request ID, run `investigate --apim-request-id ...` first. Default to `lookback(=7d)` if the user does not specify one.
3. If the user asks what is wrong, asks for DRI support, or gives only one endpoint/deployment identifier, run `investigate` first.
4. If the user asks to list containers, run `list-containers`.
5. If the user asks for logs and names a container, run `logs --container ...`.
6. If the user asks for logs without a container, run `logs` without the container filter.
7. Summarize the result directly, leading with the investigation summary when `investigate` was used.
8. When APIM tracing is used, explain that the tool anchors the downstream search to the APIM timestamp and uses `anchor +/- 30m`.
9. If `investigate` succeeds but container rows are empty or you need the true engine-side root cause, query the regional Vienna `AMLManagedComputeLogs` table directly (not `UnionOfAllLogs`) for the correlated backend endpoint/deployment and container. This avoids cross-cluster throttling and is especially useful for `qwen-vllm-ft-sidecar` LoRA failures. Search around the exact request second for strings like the LoRA id, `/scratch/mesh/finetunes/`, `Failed to prepare LoRA directory`, `Deterministic finetune path found in cache`, and `Failed to process LoRA request`.
10. If request tracing shows scoring/data-plane symptoms, classify them before concluding:
   - `FrontDoor responseCodeDetails == no_healthy_upstream` or `UH`/`503` => the request likely never reached the model. Treat this as deployment/pod readiness or routing registration investigation, not a model bug.
   - `FrontDoor responseCodeDetails == via_upstream` => the request did reach the backend. Trace by `x-request-id` through downstream logs and then inspect the target container logs.
   - `Duration == 0` with no backend host/upstream evidence => instant rejection at the frontdoor/mesh layer.
   - `UpCluster`/upstream cluster identifiers often encode `{InstanceId}--{DeploymentName}`; preserve these in the summary because they are the best bridge into Singularity namespace/pod debugging.
11. If the trace points to pod health rather than model logic, pivot explicitly into Singularity-style checks instead of stopping at kuda output:
   - inspect deployment / pod readiness state,
   - look for recent sidecar-only restarts,
   - check Kubernetes events for scheduling, probe, image-pull, or crash-loop signals,
   - only then fall back to broad container log scraping.
12. Be careful with deployment naming: customer-facing deployment names in URLs or APIM may differ from backend AML `deploymentName`. Correlate by `apim-request-id -> X-Request-ID -> backend endpoint -> FrontDoor endpointName/deploymentName -> container logs`, not by name guessing.
13. In the final answer, always separate: symptom, deepest confirmed layer, likely root cause, and next manual query/link.
14. Prefer the tool's structured trace output when APIM mode is used. Recent versions return `analysis.structuredSummary` with:
   - `symptom`
   - `correlated_path`
   - `deepest_confirmed_layer`
   - `likely_root_cause`
   - `what_is_not_yet_proven`
   - `next_query_focus`
   Use these fields directly when available instead of re-inventing the summary format.
15. Treat those structured fields as ownership guidance, not just formatting. For your team, the key question is whether the deepest confirmed layer is still in request routing / hosting / LoRA handling, or whether the evidence only shows a downstream Singularity landing symptom.
16. When APIM mode points to readiness/routing health rather than model logic, also use the returned `podHealthQueries` bundle when present:
   - `applicationSnapshotsQuery`
   - `podSnapshotsQuery`
   - `kubernetesEventsQuery`
   These are downstream follow-up queries for `no_healthy_upstream`, instant rejection, and similar mesh-side failures. Use them to confirm or hand off, but do not let them overshadow team-owned hosting / LoRA investigation when direct evidence exists there.
17. In ownership-sensitive cases, prefer this framing in the final answer:
   - customer symptom
   - correlated request path
   - deepest confirmed layer
   - likely root cause
   - what is and is not in team ownership
   - next team-owned query
   - optional downstream Singularity query
18. For LoRA and container-hosting investigations, prioritize engine-side evidence before broad Singularity triage. If AML logs or container traces show adapter/materialization failures, cache-path issues, sidecar bootstrap failures, or request-specific LoRA preparation errors, lead with those findings; treat pod health as secondary confirmation unless the trace clearly stops before hosting.
19. Include the returned `kustoLink`, and also `apimKustoLink` when APIM tracing was used, so the user can continue the query manually in Azure Data Explorer.

## Debug heuristics to apply in summaries

- Do not jump from `424` straight to "model failure". First decide whether the request was rejected before reaching the backend (`no_healthy_upstream`) or returned by the backend (`via_upstream`).
- Prefer specific request tracing over aggregate trends when the user gives a concrete request id.
- Treat brief bursts carefully: pod readiness flaps and sidecar restarts can create short `424`/`503` windows that may not show up clearly in coarse snapshots.
- When logs are noisy, state the highest-confidence layer only; avoid over-claiming a root cause the trace does not prove.
- If the tool surfaces only APIM/Nexus evidence but the user needs engine-side cause, say so explicitly and continue with direct regional AML or Singularity queries rather than stopping.

## Maintenance notes for local development

- The editable source for the CLI currently lives at `/home/xiaoranli/env-setup/kuda.py`.
- When adding or changing request-trace heuristics, write focused regression tests under `/home/xiaoranli/env-setup/tests/` first. A good pattern is to call `analyze_request_trace(...)` directly with minimal synthetic APIM/Nexus/FrontDoor/container rows.
- In this environment, `pytest` without overrides may import a different installed `kuda` module from pyenv instead of the repo copy. For local tests against source, use `PYTHONPATH=/home/xiaoranli/env-setup pytest ...` or run `/home/xiaoranli/miniconda3/bin/pytest ...` after reinstalling editable.
- After changing `kuda.py`, refresh the CLI with `/home/xiaoranli/miniconda3/bin/pip install -e /home/xiaoranli/env-setup` and verify using `/home/xiaoranli/miniconda3/bin/python -c "import kuda; print(kuda.__file__)"`.
- For FrontDoor diagnostics, include `responseCodeDetails`, `durationTotal`, and `durationUpstream` in evidence formatting so instant rejections vs backend failures are distinguishable in one glance.

## Example

User:

```text
use kuda for AMLManagedComputeLogs, endpoint is mistral-wus-3b-ep, deployment is dep-mistral-wus-3b-250927173559, list all containers
```

Run:

```bash
xiaoranli-kuda list-containers \
  --endpoint mistral-wus-3b-ep \
  --deployment dep-mistral-wus-3b-250927173559
```

User:

```text
debug this customer request, apim request id is 11111111-2222-3333-4444-555555555555
```

Run:

```bash
xiaoranli-kuda investigate \
  --apim-request-id 11111111-2222-3333-4444-555555555555
```
