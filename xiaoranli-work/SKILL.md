---
name: xiaoranli-work
description: Use after receiving review comments on a PR. If a review comment points out a genuine mistake or gap in your knowledge, update the repo's selfknowledge.md to capture the lesson honestly.
---

# xiaoranli-work

## Overview
Each repo under `~/repo/` may contain a `selfknowledge.md` file (can be at repo root or inside a sub-repo, e.g. `nimbus/selfknowledge.md`). This file is a living record of what Claude has learned - and gotten wrong - while working in that repo. It keeps Claude honest by documenting corrections from code reviews.

## When to trigger
After processing review comments on a PR (inline comments, review threads, or explicit feedback from the user about review results), evaluate each comment:

1. **Was the reviewer correct?** - If the comment points out something Claude did wrong or didn't know, proceed to step 2. If the comment is stylistic preference, a matter of opinion, or the reviewer is mistaken, skip it.
2. **Was it a knowledge gap or repeated mistake?** - Only record things that represent a genuine misunderstanding, a wrong assumption about the codebase/domain, or a pattern Claude should avoid in the future. Do not record trivial typos or one-off slips.
3. **Update selfknowledge.md** - Add a new dated section capturing:
   - What Claude got wrong or didn't know.
   - What the correct understanding is.
   - Which files/concepts are involved.

## selfknowledge.md format

The file uses this structure (refer to `nimbus/selfknowledge.md` as a living example):

```markdown
# Self Knowledge (Codex)

This file captures what I currently understand about <repo/area> ...

## <Topic or source heading>

### <Sub-topic>
- Bullet points of factual knowledge.

### Corrections to earlier assumptions
- What was wrong and why.

## Session additions (<date UTC>, <context>)

### <What was learned>
- Factual bullets.
- File paths and concrete values where relevant.
```

## Rules

1. **Honesty over completeness.** Only write what you actually got wrong or learned. Do not pad the file with things you already knew.
2. **Be specific.** Include file paths, variable names with values (e.g. `timeout(=30s)`), API endpoints, and concrete details - not vague summaries.
3. **Preserve existing content.** Append new sections; never delete or rewrite earlier entries unless they are factually superseded (in which case, note the correction inline).
4. **Date every addition.** Use the format `Session additions (<YYYY-MM-DD> UTC, <brief context>)`.
5. **Keep it repo-scoped.** Each selfknowledge.md is about its own repo. Do not mix knowledge across repos.
6. **No defensive language.** Do not write "I might have been wrong" or "this could be incorrect". State the correction plainly: "Earlier assumed X. Correct behavior is Y."
7. **Skip if nothing was learned.** If all review comments are acknowledged but none reveal a genuine knowledge gap, do not add an entry. Updating selfknowledge.md is not mandatory on every review - only when something was genuinely learned.

## Workflow

```
1. User shares review comments (or asks Claude to process them).
2. Claude reads the comments and evaluates each one.
3. For comments that reveal a real mistake or gap:
   a. Locate the repo's selfknowledge.md (or create one if it doesn't exist).
   b. Read the existing content to avoid duplicating known entries.
   c. Append a new dated section with the correction/learning.
4. Summarize to the user what was added to selfknowledge.md and why.
```

## Creating a new selfknowledge.md

If the repo does not yet have a `selfknowledge.md`, create one at the repo root with this template:

```markdown
# Self Knowledge (Codex)

This file captures what I currently understand about <repo name> and corrections from code reviews.

## Session additions (<YYYY-MM-DD> UTC, <context>)

### <What was learned>
- Details here.
```
