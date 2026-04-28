---
name: xiaoranli-publishengdef
description: Use when publishing or updating a Nimbus or MPSS engine definition from adm-engine-configs, especially for SGLang or finetune engines, image swaps, server command changes, or retrying assetstore publish failures. Trigger whenever the user wants to publish an engine definition and the workflow should gather required publish inputs before executing.
---

# xiaoranli-publishengdef

## Overview

Publish engine definitions from `adm-engine-configs` through the MPSS V2 onboarding API by default.

Prefer this skill over the legacy direct Nimbus `engineDefinitions` POST flow when the target engine definition shape matches the modern `config.modelName`, `publisherName`, `hostingConfig`, and `assets` schema.

Keep the workflow pragmatic:
- infer as much as possible from the nearest existing config,
- ask the user only for the missing deltas,
- write generated artifacts under `AI-gen/`,
- and execute the publish rather than stopping at a draft.

## Required User Inputs

Before writing the request, make sure the user has provided these inputs:

1. `base image docker`
   Use the full docker reference, including tag or digest.

2. `server command`
   This is the exact command that starts the inference server.
   Convert shell-style commands into a JSON string array when the request format needs an argv list.

3. `ft sidecar docker image`
   Required only when the engine is a finetune (`ft`) engine.

If the repo cannot already infer them, collect these next:
- `model name`
- `publisher name`
- `model weights directory`
- `model snapshot asset id` or a previously onboarded snapshot to reuse
- `allowed instance type`
- `gpu count`
- `ports`
- `environment variable deltas`
- `whether CMP is needed`

Do not ask for everything up front. First mine the repo for the closest working example, then ask only for the missing fields.

## Context Gathering

Follow this order:

1. Read the repo `AGENTS.md`.
2. Search `configs/<publisher>/` for the closest runtime match:
   - same model family first,
   - same server runtime second (`sglang`, `vllm`, etc.),
   - same finetune shape third (`ft` sidecar, CMP, ingress).
3. Read `docs/Automated ED Onboarding V2.md` to confirm the current request schema.
4. Check any prior `AI-gen/*publish-result*.json` and `AI-gen/*assets-tracking*.json` files if the user is retrying.
5. If a recent publish failed with `Customer Managed CosmosDB Firewall settings were not properly set up`, treat that as a likely platform-side incident until proven otherwise.

## Build Rules

### Default path

Use MPSS V2 unless the user explicitly asks for the legacy path.

Write the request to:

```text
AI-gen/<model-name>-mpss-request.json
```

Use or update a helper script like:

```text
AI-gen/publish_engine_definition_onboarding_v2.py
```

### Request shape

Build the request under a top-level `config` object.

Core fields:
- `modelName`
- `publisherName`
- `description`
- `capabilities`
- `hostingConfig`
- `assets`

For a single-engine publish, use one template asset named `default` unless there is a clear reason to split templates.

### Server command handling

If the server command is needed in the request:
- preserve the exact order of arguments,
- keep quoting-safe tokens intact,
- prefer a JSON array over a shell string when the schema supports `command`.

If the entrypoint is already baked into the image and no override is needed, do not invent one.

### Finetune handling

For `ft` engines:
- require `ft sidecar docker image`,
- colocate the inference container and ft sidecar in the same deployment,
- preserve the sidecar port wiring and finetune cache environment variables from the closest working example,
- add `cmp` only if the existing pattern or user request needs it.

If the engine is not `ft`, do not add a finetune sidecar.

### Minimalism

Do not refactor checked-in configs just to publish.
Default to generating request bodies and results under `AI-gen/`.
Only patch repo configs when the user explicitly asks to persist the changes in `configs/`.

## Publish Flow

1. Build the request JSON in `AI-gen/`.
2. Validate the JSON syntax before any network call.
3. Run the publish helper and poll the operation to a terminal state when feasible.
4. Save:
   - request JSON,
   - latest status JSON,
   - assets tracking JSON.

Use filenames like:

```text
AI-gen/<model-name>-publish-result.json
AI-gen/<model-name>-assets-tracking.json
```

## Failure Handling

### Platform-side failure pattern

If publish fails in `assetstore` with messages like:
- `Customer Managed CosmosDB Firewall settings were not properly set up`
- registry publish `403`
- environment asset registration failure during `EngineImage`

then:

1. classify it as a likely external platform or registry issue,
2. retry once with the same request,
3. capture both operation IDs,
4. save the retry result and tracking files,
5. avoid rewriting the request body unless the failure evidence points to schema or payload issues.

### Payload-side failure pattern

If the API rejects the request before asset creation begins, inspect:
- missing schema fields,
- invalid container layout,
- wrong probe shapes,
- missing sidecar image for `ft`,
- malformed command arrays.

Fix only the specific payload defect and retry.

## Output to the User

Always close with:
- final status,
- `operationId`,
- concise diagnosis,
- clickable links to the request, result, and tracking files,
- exact rerun command if the operation is still running or failed.

If there was a retry, include both operation IDs and explain whether the second attempt changed behavior.

## Quick Reference

Common prompts this skill should handle:
- "publish this engine definition"
- "switch the base image and republish"
- "make this sglang engine publishable"
- "retry the failed engine publish"
- "turn this ft engine into a publish request"

Common decisions:
- modern Nimbus shape present -> MPSS V2
- `ft` mentioned -> require `ft sidecar docker image`
- same platform 403 seen elsewhere -> retry once before changing config

