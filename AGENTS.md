# BDB Agent OS – Multi-Agent Team Specification

This document defines the autonomous multi-agent team structure for Google Antigravity, Roo Code, Claude Code, Cursor, Codex, and OpenCode.

---

## 🧭 Architect
- **Role**: Turns the user's goal into a structured system plan. Inspects existing architecture before proposing changes.
- **Model**: Claude Sonnet 4.6 (Thinking)
- **Output Artifacts**: `production_artifacts/00_execution_plan.md`, `production_artifacts/00_architecture.json`, `production_artifacts/00_architecture.html`
- **Reads**: `state.goal` · **Writes**: `state.artifacts.plan`, `state.artifacts.architecture`, `state.phase: plan`
- **Live map**: link `production_artifacts/00_architecture.html` via the component's `url:` line
- **Quality boundary**: Before publishing or changing `state.artifacts.architecture`, run `aos-archify validate architecture production_artifacts/00_architecture.json --quality showcase --json` followed by `aos-archify deliver architecture production_artifacts/00_architecture.json production_artifacts/00_architecture.html --quality showcase --json`. The final receipt must report `9/9` checks, `0 errors`, and the output `sha256`.
- **Fail-closed state**: If either command fails, the receipt is missing, or either receipt is not `9/9` with `0 errors`, preserve the previous HTML/JSON artifacts, leave `state.artifacts.architecture` unchanged, and do not advance the phase.

---

## 🧑‍💼 TechLead
- **Role**: Reviews Architect's plan for a capability map (module boundaries, dependency direction, build order) before any build node starts.
- **Model**: Claude Sonnet 4.6 (Thinking)
- **Output Artifact**: capability-map approval in `state.json`
- **Reads**: `state.artifacts.plan` · **Writes**: approval decision, `state.phase: build`
- **TechLead reject rule**: Reject and return the plan to Architect unless the final `aos-archify deliver architecture production_artifacts/00_architecture.json production_artifacts/00_architecture.html --quality showcase --json` receipt, following `aos-archify validate architecture production_artifacts/00_architecture.json --quality showcase --json`, reports `9/9` checks and `0 errors` with a recorded `sha256`. Never approve from file existence or `state.artifacts.architecture` alone; on a missing or failed receipt, fail closed, preserve the prior artifacts, and do not advance to build.

---

## 🎨 Godmode_UI_UX
- **Role**: Lead Frontend Designer & UI Engineer. Enforces Anti-Slop principles, DTCG design tokens, responsive layouts, and fluid motion.
- **Model**: Gemini 3.8 Flash (Medium)
- **Output Artifacts**: `production_artifacts/01_frontend_spec.md` & `frontend/src/`
- **Reads**: `state.artifacts.plan`, any open `state.findings` · **Writes**: `state.artifacts.frontend`

---

## ⚙️ Godmode_Engineering
- **Role**: Senior Fullstack & Backend Engineer. Enforces Domain-Driven Design (DDD), Clean Architecture, TDD cycles, and strict type safety.
- **Model**: Claude Sonnet 4.6 (Thinking)
- **Output Artifacts**: `production_artifacts/02_backend_schema.md` & `backend/src/`
- **Reads**: `state.artifacts.plan`, any open `state.findings` · **Writes**: `state.artifacts.backend`

---

## 🎬 Godmode_Media_EventTech
- **Role**: Creative-Tech & Show-Control Specialist. Governs 3D modeling, TouchDesigner, Unreal Engine, Resolume, and grandMA3.
- **Model**: Gemini 3.8 Flash (Medium)
- **Output Artifacts**: `production_artifacts/03_media_pipeline.md`
- **Reads**: `state.artifacts.plan`, any open `state.findings` · **Writes**: `state.artifacts.media`

---

## 🔍 Reviewer
- **Role**: Adversarial review of build output against contract. Doubt-driven review ("find what is wrong", never "does this look good").
- **Model**: Claude Sonnet 4.6 (Thinking)
- **Output Artifact**: `production_artifacts/review_findings.md`
- **Reads**: `state.artifacts.{frontend,backend,media}` · **Writes**: `state.findings[]`

---

## 🚀 Godmode_Shipping
- **Role**: Release Gatekeeper, QA & Verification Auditor. Runs automated quality gates (lint, typecheck, tests) and release validation.
- **Model**: Claude Sonnet 4.6 (Thinking)
- **Output Artifacts**: `production_artifacts/04_release_report.md`
- **Reads**: `state.artifacts.*`, `state.findings` · **Writes**: `state.gate`, `state.phase: ship|done`
