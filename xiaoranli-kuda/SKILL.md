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

Do not ask the user for cluster or database unless execution fails because `XIAORANLI_KUDA_CLUSTER_URL` or `XIAORANLI_KUDA_DATABASE` is missing. APIM tracing defaults to `https://cogsvc.kusto.windows.net` / `Platform`. Singularity tracing defaults to `https://aiscprodkusto.westus2.kusto.windows.net` / `logs`.

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
9. Include the returned `kustoLink`, and also `apimKustoLink` when APIM tracing was used, so the user can continue the query manually in Azure Data Explorer.

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
