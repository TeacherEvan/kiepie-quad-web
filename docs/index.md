# Kiepie Quad — Documentation Index

Navigation hub for every doc in this repository. Start here.

## Core docs

| Doc | What it covers |
| --- | --- |
| [README.md](../README.md) | Player-facing overview: modes, controls, combat, mobile, rebuild commands, QA verdict, trademarks |
| [AGENTS.md](../AGENTS.md) | Agent/engineer invariants: pipeline boundaries, gate suite, deploy gotchas, model rules, Godot conventions |
| [SOURCE.md](../SOURCE.md) | Original Blender source/QA documentation for the Kiepie Bike model |
| [project-plan.md](project-plan.md) | **Canonical project plan** — current state, architecture pointers, canonical constants table, roadmap |
| [task-status.md](task-status.md) | **Done-vs-pending ledger** — audit remediation per finding (with commit evidence), blocked items, deferred work |

## Audits & plans

| Doc | What it covers |
| --- | --- |
| [audits/10 Principal Engineer.txt](audits/10%20Principal%20Engineer.txt) | External 10-principal-engineer audit, 2026-11-18 (81 files, score 78/100). Remediation status: [task-status.md](task-status.md) |
| [audits/kiepie-quad-surgical-audit-2026-11-18.md](audits/kiepie-quad-surgical-audit-2026-11-18.md) | Surgical audit 2026-11-18; its defects are locked by `godot/tools/verify_audit_regressions.gd` |
| [plans/audit/opencode/inkling 2 small/kiepie-quad-surgical-audit-2026-11-17.md](plans/audit/opencode/inkling%202%20small/kiepie-quad-surgical-audit-2026-11-17.md) | Earlier surgical audit pass (2026-11-17, historical) |

Scratch remediation notes (`docs/.scratch-audit/`) are git-ignored run artifacts;
their durable content is distilled into [task-status.md](task-status.md).

## Cross-reference map

- Plan ↔ ledger: [project-plan.md](project-plan.md) roadmap items carry the same
  TS-xxx IDs as [task-status.md](task-status.md#pending-and-blocked).
- Ledger ↔ evidence: every fixed finding cites its commit (`1494b0d`, `60a8b82`,
  `f09c80e`) and file; every gate claim names the gate script in `godot/tools/`.
- Constants: the single canonical table lives in
  [project-plan.md](project-plan.md#canonical-constants-table); README/AGENTS
  mention values by reference and must be swept together when a value changes.
- Requirements ↔ gates: gameplay contracts are locked by the 25-gate suite
  (`godot/tools/run_gates.sh`); AGENTS.md "Verification quirks" lists what each gate locks.

## Maintenance checklist

Every change that affects behavior, dependencies, or plans (per the
documentation-maintenance discipline):

1. **Plan sync** — update [project-plan.md](project-plan.md).
2. **Content docs** — update affected README/AGENTS/SOURCE sections and source comments.
3. **Legal check** — LICENSE/NOTICE/dependency notes (this repo has no LICENSE/NOTICE
   file; the trademark constraint lives in README "Trademarks / licence" and AGENTS.md).
4. **Scaffolding** — this index, README links, TOC intact.
5. **Cross-ref** — docs ↔ plan ↔ ledger ↔ gates connected, nothing orphaned.
6. **Verify** — links resolve, constants consistent, gates green where code changed.