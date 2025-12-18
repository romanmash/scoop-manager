# Memory Bank – How-To for AI Agent

You are an AI coding agent working in this repository.  
This file explains:

1. How to create and maintain the project Memory Bank in `memory-bank/`.
2. How to use it as long-term project memory across sessions.

The Memory Bank is project-local and lives in this repo. Treat it as the single
source of truth about:

- What this project is.
- How it works.
- What is currently being worked on.

---

## 1. Directory layout

All memory files live in a top-level folder:

```text
project-root/
  memory-bank/
    how-to-memory-bank.md   # this file (instructions for you)
    projectbrief.md
    productContext.md
    systemPatterns.md
    techContext.md
    activeContext.md
    progress.md
    decisionLog.md
```

If any of the core files are missing, you should create them following the spec
below.

---

## 2. Core files and their purpose

### 2.1 `projectbrief.md` – project overview

Purpose: high-level description of the project.

It should answer:

- What is this project?
- Why does it exist?
- What are the main goals and success criteria?
- What is in scope vs explicitly out of scope?
- Who are the target users (at a high level)?
- Any major constraints (platforms, performance, security, etc.).

Update this file only when the fundamental direction of the project changes.

---

### 2.2 `productContext.md` – product and user behavior

Purpose: describe the system from a product / user point of view.

It should cover:

- User types, roles, or personas.
- Main use cases and user flows.
- Business rules and validation rules.
- Important edge cases and “gotchas”.
- UX expectations and quality bar.

This file is about what the system should do, not how it is implemented.

---

### 2.3 `systemPatterns.md` – architecture and design

Purpose: capture the shape of the system.

It should include:

- Main modules, services, layers, and their responsibilities.
- How modules depend on each other (control flow and data flow).
- Key domain concepts and how they are modeled.
- Architectural patterns (e.g., layered, event-driven).
- Structural conventions:
  - directory layout
  - naming conventions
  - error-handling patterns
  - API design conventions

Update this file whenever architecture or structure changes in a meaningful way.

---

### 2.4 `techContext.md` – tech stack and environment

Purpose: document the technical environment.

It should include:

- Languages and frameworks (with versions if known).
- Important libraries and why they are used.
- How to build, run, and test the project (commands, scripts).
- External services (APIs, databases, queues).
- Tooling (linters, formatters, test frameworks, CI/CD, deployment).
- Technical constraints (supported platforms, performance targets).

Update this when tools, versions, or key dependencies change.

---

### 2.5 `activeContext.md` – current focus

Purpose: track what is happening right now.

Contents:

- Current focus / feature / bug / refactor.
- Relevant files, modules, or scripts for this work.
- Current assumptions or temporary constraints.
- Open questions.
- Short list of immediate next steps (small, concrete tasks).

Keep this file short enough to read in under a minute.

---

### 2.6 `progress.md` – progress log

Purpose: maintain a concise history of meaningful work.

For each entry include:

- Date (e.g. `2025-12-17`).
- Short description of what changed.
- How it was validated (tests, manual checks).
- Any follow-ups or remaining work.

Example:

```markdown
## 2025-12-17

- Implemented startup policy diagnostics script `12_Check-StartupPolicy.ps1`.
- Updated README and menu to include the new script.
- Validation: ran the script locally; confirmed it prints execution policy and language mode.
- Follow-up: extend diagnostics if new corporate blockers are discovered.
```

Use this file to reconstruct recent work after a context reset.

---

### 2.7 `decisionLog.md` – important decisions and rationale

Purpose: record why important choices were made.

Each entry should include:

- Date.
- Decision title (short summary).
- Context / problem being solved.
- Options considered.
- Reasoning and trade-offs.
- Impact (where in the system this matters).

Use this for decisions that will affect future work or be expensive to reverse.

---

## 3. Initialization rules

If you detect that the Memory Bank is missing or incomplete:

1. Ensure the directory `memory-bank/` exists.
2. For each core file above, if it does not exist:
   - Create it.
   - Add a `#` heading with the file name’s concept.
   - Add a short sentence describing what the file is for.
3. Populate initial content using:
   - The project README and other docs.
   - The codebase (directory structure, frameworks, scripts).
   - Any instructions from the user.

You may start with brief bullet points and refine over time.

---

## 4. How you must use the Memory Bank

### 4.1 Before any non-trivial task

For any significant work (new feature, non-trivial bug, refactor):

1. Re-read this file to remind yourself of the rules.
2. Read:
   - `projectbrief.md`
   - `productContext.md`
   - `systemPatterns.md`
   - `techContext.md`
   - `activeContext.md`
   - `progress.md`
   - `decisionLog.md`
3. Build a mental summary of:
   - What this project is.
   - What users need.
   - How the system is structured.
   - What technologies and constraints apply.
   - What is currently being worked on.
   - What has been done recently.
   - Which decisions are relevant.

Use that summary to guide all edits and suggestions.

---

### 4.2 When to update each file

You must update:

- `activeContext.md` when:
  - The current focus or task changes.
  - You finish tasks and start new ones.
- `progress.md` when:
  - You complete a meaningful unit of work (feature, refactor, bugfix).
- `systemPatterns.md` when:
  - Architecture or major structure changes.
- `techContext.md` when:
  - You add, remove, or significantly change tools, frameworks, or services.
- `productContext.md` when:
  - Product behavior, use cases, or business rules change.
- `decisionLog.md` when:
  - A new important decision is made that will affect future work.

You do not need to update every file for every task; only touch what is actually
affected.

---

### 4.3 Editing rules and safety

- Do not invent history or decisions.
  - Only record what actually happened in this repo or what the user clearly states.
- Prefer concise, high-signal content.
  - Use headings, bullet points, and short paragraphs.
- Avoid unnecessary duplication between files.
  - If something belongs in multiple places, choose the best one and optionally link.
- Respect human edits.
  - If the user writes content in these files, preserve their intent and wording.
- Avoid noisy rewrites.
  - Do not reformat entire files for trivial code changes.

---

## 5. Optional extensions

You may add extra documentation files inside `memory-bank/` when helpful, for example:

- `testingStrategy.md` – how tests are organized, coverage goals, conventions.
- `apiContracts.md` – descriptions of key public / external APIs.
- `deployment.md` – deployment and release process.

Rules for optional files:

- They must complement, not replace, the core files.
- If information overlaps, link or refer instead of duplicating long sections.

---

## 6. Goal

The goal of the Memory Bank is:

> After a complete context reset, you (or any future AI agent) can read
> `memory-bank/*.md` and quickly continue the project with minimal extra
> explanation from the user.

Keep these files accurate, concise, and useful so that future work is faster,
safer, and more consistent.

