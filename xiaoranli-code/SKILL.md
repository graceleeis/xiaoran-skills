---
name: xiaoranli-code
description: Use when modifying a feature, bugfix, or refactor inside an existing backend service, especially C#, Rust, or similar service code, where the change must stay aligned with system boundaries, cross-service contracts, and shared policy.
---

# xiaoranli-code

## Overview

This skill is for service work that lives inside an existing building, not an empty lot. Before moving code, define the load-bearing walls: invariants, single source of truth, boundaries, and caller/callee contracts.

**Goal:** write code that makes its policy obvious, keeps the architecture coherent, and is hard to accidentally break later.

**REQUIRED SUB-SKILL:** Use superpowers:test-driven-development before writing implementation code.

## When to Use

Use this skill when:
- changing behavior in an existing service or service platform
- implementing a feature, bugfix, or refactor that interacts with upstream or downstream contracts
- touching policy-heavy code such as validation, retries, auth, routing, redaction, logging, or forwarding
- working in service code where local patches can create system-wide confusion, especially in C#, Rust, or similar backend code

Do not use this as the main skill for:
- greenfield prototypes with no established contracts yet
- isolated scripts with no service boundary or upstream/downstream dependencies

## Core Rule

Do not start from "what small patch can I add here?"

Start from:
1. what must always be true
2. where the rule is owned
3. where the boundary is
4. what the caller and callee already promise

If those are still fuzzy, implementation is premature.

## Base Clean Code Rules

These rules apply in all scenarios that use this skill:

- no hardcoded values or scattered env var decisions
- pack related logic together in one struct, class, or new file
- prefer smaller scope changes to existing code; if reasonable, add new functions in new files instead of spreading edits across old ones
- only refactor when explicitly asked
- if duplicated Python code must be extracted, move it into `utils.py`; create `utils.py` if it does not exist
- prefer fewer code changes over formatting cleanup; do not widen the diff for things like newline-only or line-length-only cleanup unless the code is becoming hard to read, for example complex `?:` usage
- prefer changing Python over C, C++, or CUDA when either option can solve the problem cleanly

Treat these as the house rules for the whole building. They are not a substitute for invariants and boundaries; they constrain how the change should be expressed once the design is clear.

## The Workflow

### 1. Write the invariant first

Before coding, write 1 to 3 sentences that answer:
- what must always hold
- what must never happen
- what success looks like from outside the function or service

If you cannot write that plainly, you do not understand the change yet.

### 2. Choose a single source of truth

Each rule gets one primary definition point.

Examples:
- header log safety is owned by one allowlist or one blocking policy, not half by each
- retry policy is owned by caller or callee, not partially duplicated in both

If a reviewer can ask "why is this checked again here?", the ownership is probably still unclear.

### 3. Mark the boundary explicitly

For every input or output, ask:
- is this raw input, normalized input, or trusted input
- does filtering happen at ingress, or does redaction happen only at output or logging

Unclear boundaries produce patchy "defend a little here, defend a little there" code.

### 4. Read the caller and callee before touching the middle

Check at least two levels:
- who calls this code, and what contract do they assume
- what this code calls next, and what contract it expects

Many service bugs are contract bugs, not line-by-line logic bugs.

### 5. List the files before editing

Write down the files you expect to change.

If a supposedly local fix needs 4 to 6 places, treat that as a design or policy signal first. The problem may be a missing shared rule, not a bad local implementation.

### 6. Write a failing flow test first

Prefer tests that exercise real data flow:
- input
- path
- observable output

Helper tests are allowed, but they do not replace a flow test.

For bugfixes, write one failing regression test first. If there was no red state, green proves very little.

### 7. Choose the simplest model, not the smallest patch

The smallest patch often leaves:
- extra branches
- duplicated checks
- local exceptions

Ask instead:
- can this collapse into one simpler rule
- can I remove a special case instead of adding another one

### 8. Name policy as policy

Names must explain what a rule does, not just what data it mentions.

Better:
- `BlockedForLoggingHeaders`
- `AllowedForwardHeaders`
- `ExcludedFromPayloadHeaders`

Worse:
- `UsePiiHeaders`

If the name is vague, reviewers must reverse-engineer intent from implementation.

### 9. Treat logging as part of the feature

Design logging for the worst case.

If data is not fully trusted and normalized, do not assume it is safe to log directly. Logging is not side code in service systems; it is part of the behavior and often part of the security model.

### 10. Run the reviewer-misread check

Before finishing, ask:
- will a reviewer think this is duplicate logic
- will a reviewer struggle to tell where the primary rule lives
- will a reviewer ask why this was not simplified into a cleaner model

If yes, the code may work but still communicate poorly.

### 11. Verify three things before claiming success

- Functional verification: the new behavior is correct
- Counterexample verification: the forbidden behavior still does not happen
- Regression verification: existing behavior was not accidentally changed

## The 7-Question Checklist

Use this shortest form when under pressure:

1. What is the invariant?
2. Where is the source of truth?
3. Where is the boundary?
4. What are the caller and callee contracts?
5. What is the failing test?
6. Is this the simplest model?
7. Will a reviewer misunderstand the intent?

## Service-Specific Red Flags

Stop and re-evaluate if:
- the same rule appears in multiple layers with slightly different wording
- filtering and redaction are mixed without a clear boundary
- a local fix requires touching many unrelated files
- the implementation adds a new exception instead of simplifying the rule
- names describe payload shape but not policy ownership
- logging decisions are made from convenience instead of trust level

## Why This Matters

In a service architecture, code is closer to renovating one room in an occupied building than assembling a toy on an empty table. The room must still line up with the structure, the pipes, and the people on the floors above and below it.
