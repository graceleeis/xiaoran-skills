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
PodSnapshots
KubernetesEvents
```

Do not ask the user for cluster or database unless execution fails because `XIAORANLI_KUDA_CLUSTER_URL` or `XIAORANLI_KUDA_DATABASE` is missing. APIM tracing defaults to `https://cogsvc.kusto.windows.net` / `Platform`. Singularity tracing defaults to `https://aiscprodkusto.westus2.kusto.windows.net` / `logs`.

Important environment note discovered in practice:
- The installed `xiaoranli-kuda investigate` command still calls `load_connection_config()` even in `--apim-request-id` mode, so you usually must pass or set a main Vienna cluster/database explicitly.
- For East US MaaS AML log investigation, prefer `--cluster-url https://viennause.kusto.windows.net --database Vienna`.
- Do not use `https://aiscprodkusto.westus2.kusto.windows.net / logs` with `investigate --apim-request-id ...`; the generated `UnionOfAllLogs('Vienna', ...)` queries fail there.

## Required setup

1. Confirm the CLI exists: `xiaoranli-kuda --help`
2. Confirm Azure auth: `az login`
3. Confirm connection env vars exist if you want defaults:
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

For East US APIM tracing, prefer:

```bash
xiaoranli-kuda investigate \
  --apim-request-id <apim-request-id> \
  --cluster-url https://viennause.kusto.windows.net \
  --database Vienna
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
9. Include the returned `kustoLink`, and also `apimKustoLink` when APIM tracing was used, so the user can continue the query manually in Azure Data Explorer.

## LoRA / finetune debugging workflow

Use this exact order when the model error mentions LoRA, finetune, adapter loading, registry asset resolution, or `/scratch/mesh/finetunes/`.

1. Trace from APIM request id to the backend endpoint/deployment with `investigate`.
2. Record all three identifiers because they differ by layer:
   - customer deployment in the URL, e.g. `tc-tn-qwen-...`
   - backend endpoint, e.g. `qwen-3-32b-eus-ep-m365`
   - backend AML deployment, e.g. `dep-eus-qwen3-32b-...`
3. Run `list-containers` for the backend endpoint/deployment.
4. Pull broad logs first, then narrow to the likely failing container.
   - For qwen LoRA issues, `qwen-vllm-ft-sidecar` is often the first container to check.
   - `qwen-vllm` may show nothing if the sidecar fails before handing the request to the main server.
5. If `xiaoranli-kuda logs` is too noisy, switch to direct Kusto on `AMLManagedComputeLogs` instead of the generated `UnionOfAllLogs(...)` query. This avoids cross-cluster throttling and lets you narrow aggressively.
6. For LoRA failures, search for these patterns:
   - `Failed to prepare LoRA directory`
   - `failed to resolve registry asset`
   - `Failed to load LoRA`
   - the exact `rp-...` LoRA id
   - `/scratch/mesh/finetunes/`
7. Distinguish failure modes explicitly:
   - `failed to resolve registry asset` => asset/registry resolution failure
   - `Failed to prepare LoRA directory ... /scratch/mesh/finetunes/...` => local cache/directory preparation failure in the finetune sidecar
8. Check whether the failure is isolated or systemic by querying other `rp-*` LoRAs on the same backend endpoint.
9. Check Singularity pod state with `PodSnapshots` and `KubernetesEvents` if you need to rule out restart, mount, or node-level issues.

## Direct Kusto mode

When the CLI output is insufficient, use direct Kusto queries and always return a click-through Data Explorer link.

Preferred clusters/databases:
- APIM / TraceCallResult: `https://cogsvc.kusto.windows.net` / `Platform`
- East US Vienna / AMLManagedComputeLogs: `https://viennause.kusto.windows.net` / `Vienna`
- Singularity pod state / pod events: `https://aiscprodkusto.westus2.kusto.windows.net` / `nexus-logs`

Recommended East US LoRA query pattern:

```kusto
AMLManagedComputeLogs
| where PreciseTimeStamp between (datetime(<start>) .. datetime(<end>))
| where onlineEndpointName == '<endpoint>'
| where deploymentName == '<backend-aml-deployment>'
| where Container == 'qwen-vllm-ft-sidecar'
| where log has '<rp-lora-id>' or log has 'Failed to prepare LoRA directory' or log has 'failed to resolve registry asset'
| project PreciseTimeStamp, Container, log
| order by PreciseTimeStamp asc
```

Recommended Singularity pod-state query pattern:

```kusto
PodSnapshots
| where PreciseTimeStamp between (datetime(<start>) .. datetime(<end>))
| where EndpointName == '<endpoint>'
| project PreciseTimeStamp, Tenant, Name, RoleInstance, Phase, Error, PodNotReadyError, PodNotInitializedError, MainContainerRestarts, EndpointName, ComponentName
| order by PreciseTimeStamp desc
```

Recommended Singularity Kubernetes events query pattern:

```kusto
KubernetesEvents
| where PreciseTimeStamp between (datetime(<start>) .. datetime(<end>))
| where InvolvedObjectName has '<deployment-id>' or PodName has '<deployment-id>'
| where message has_any ('mount','disk','space','permission','denied','read-only','filesystem','inode','scratch','evict','oom','kill','back-off','unhealthy','failed')
   or EventReason has_any ('FailedMount','BackOff','Unhealthy','Failed','Killing','Evicted')
| project PreciseTimeStamp, PodName, InvolvedObjectName, ContainerName, EventType, EventReason, message, RoleInstance, AISC_NodeInstanceId
| order by PreciseTimeStamp desc
```

## Clickable Data Explorer links

Always give the user a direct Azure Data Explorer link they can open and click Run on.

Base cluster links:
- APIM: `https://dataexplorer.azure.com/clusters/cogsvc/databases/Platform`
- East US Vienna: `https://dataexplorer.azure.com/clusters/viennause/databases/Vienna`
- Singularity pod state: `https://dataexplorer.azure.com/clusters/aiscprodkusto/databases/nexus-logs`

When using `xiaoranli-kuda`, return the tool's `kustoLink` and `apimKustoLink` verbatim.

When writing manual KQL, include:
1. the cluster/database link above
2. the exact KQL in a fenced block immediately below it

If the environment supports full encoded ADX links, prefer giving both:
- a plain cluster link
- and an encoded query link

But do not block on generating the encoded query URL. A clickable cluster/database link plus ready-to-run KQL is acceptable.

## Interpretation rules from recent incidents

- If `PodSnapshots` shows workers continuously `Running`, `MainContainerRestarts == 0`, and empty `Error` / `PodNotReadyError` / `PodNotInitializedError`, the issue is probably not a pod lifecycle or mount failure.
- If `KubernetesEvents` shows no `FailedMount`, `BackOff`, `Unhealthy`, `Evicted`, `disk`, `permission`, or `read-only` signals, a stable LoRA failure is more likely due to LoRA asset resolution or local finetune cache state than Kubernetes infrastructure.
- If multiple request ids over time fail with the same LoRA and the same error pattern, do not call it a transient race without stronger evidence. Treat it as a deterministic asset/cache issue first.

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
  --apim-request-id 11111111-2222-3333-4444-555555555555 \
  --cluster-url https://viennause.kusto.windows.net \
  --database Vienna
```
