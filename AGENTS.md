# AGENTS.md

Sections of this file adapt the Mojaloop community's top-level
AI-assistance guidelines to this repository's actual scope and workflow.
All content must be reviewed and validated by a human contributor before
it governs any AI-assisted work here.

## Purpose and scope

This file provides instructions for AI-assisted work in the Mojaloop
Performance Testing Workstream — a Terraform + Ansible + Helm + k6 lab that
provisions infrastructure, deploys Mojoloop and DFSP simulators, and
benchmarks the switch under different security postures and message
formats. It applies to any AI tool used here, not just one vendor's.

This is **not** a Mojaloop product/service repository. It contains no
application code that processes a live transaction, publishes no package,
and has no npm/Docker/CI pipeline of its own to gate. Where Mojaloop's
top-level community AI-assistance guidance addresses product-code
contribution specifically (dependency supply-chain review, JS/TS lint and
coverage thresholds, container base-image pinning, semantic versioning,
issue-linked pull requests), that guidance does not apply here as written —
this file adapts what *does* apply: accountability, correctness,
confidentiality, and traceability.

A human contributor directs the work, reviews and understands every change,
and makes every decision about what actually ships or gets applied to live
infrastructure. Nothing in this file authorizes an AI agent to commit, push,
open a pull request, or apply infrastructure changes autonomously.

## Instruction precedence

1. The human's instructions in the current conversation.
2. `.claude/CLAUDE.md` (or the equivalent instruction file for whichever AI
   tool is in use) for tool-specific behavior.
3. This file, for repository-wide principles.
4. Mojaloop's community-wide contribution and AI-assistance standards, where
   this repository's own conventions are silent.

Never use this precedence to justify skipping a confidentiality, safety, or
review requirement. When instructions genuinely conflict, stop and ask
rather than guessing which one wins.

## Mandatory operating principles

- A human remains accountable for correctness, security, and the
  consequences of every change — including changes to live AWS
  infrastructure, not just source code.
- Do not fabricate configuration values, test results, benchmark numbers,
  or claims about what a file or a live cluster contains. Verify against
  the actual override file, chart template, or cluster state before
  documenting it — this repository has shipped stale and outright
  fabricated claims (a copy-pasted dashboard screenshot presented as a
  real capture; a config claim that didn't match the committed file) that
  were only caught by direct verification, not by trusting the last
  session's account of things.
- Do not expose AWS credentials, account IDs, private keys, or other
  environment-identifying material in anything committed to the repository
  — code, docs, comments, or commit messages. This data routinely appears
  in ad-hoc diagnostic tool output while investigating something live;
  that's expected and fine, but it must never be copied into a file that
  gets committed.
- Do not take a destructive or hard-to-reverse action — `terraform destroy`
  or `apply`, force-push, deleting live pods mid-test, `git reset --hard`
  — without the human's explicit go-ahead for that specific action.
- Do not claim work is "ready to merge," "verified," or "tested" unless
  that's actually true of what was done in this session, not of what the
  documentation says should be true.
- Preserve traceability: when a benchmark result changes or a scenario's
  configuration is edited, the reasoning should be visible in the
  conversation and, where it belongs, in the config's own rationale — not
  asserted without a basis a reader could check.

## How work actually happens here

This repository does not run a GitHub-issue-per-change workflow. Work is
directed live, in conversation, against real (often live, shared) AWS
infrastructure and Kubernetes clusters. That changes what "process" means
here relative to a typical product repo:

- There is no ticket to read before starting — the human's request in the
  conversation *is* the work item. If it's ambiguous or its scope is
  unclear, ask, rather than guessing and expanding scope silently.
- Changes to live infrastructure (terraform, cluster config, running pods)
  are inherently higher-stakes than changes to a file — treat an
  infrastructure action with at least the caution a destructive git
  operation would get, even if the underlying command looks routine.
- "Done" for a benchmark result means: measured against the steady-state
  methodology (see `.claude/CLAUDE.md`), not just that a command exited
  zero.

## Documentation

- Write documentation in Markdown, matching the existing style in
  `README.md`, `benchmarks/README.md`, and each scenario's own report —
  see `.claude/CLAUDE.md`'s "Documentation style" section for the specific,
  hard-learned conventions (no history narration, no cross-scenario
  references, validate before documenting).
- Explain rationale and operational impact, not just syntax — a reader
  should understand *why* a value is set the way it is, not just that it
  is.
- AI assistance is disclosed at the pull request level (a checkbox on the
  PR), not with an inline banner on individual files — do not add
  per-document AI-disclosure banners to READMEs or other repository
  content.

## Confidentiality

Do not place AWS credentials, access keys, account IDs, private key
material, cluster-internal hostnames/IPs tied to a specific live account,
or other environment-identifying secrets into any file, log, commit
message, or document that becomes part of the repository. Ad-hoc
inspection of live infrastructure during a session is expected and will
surface this kind of data in tool output — the rule is about what gets
written into the repo, not about avoiding the investigation itself.

## Stop and escalate

Stop and ask the human before proceeding when:

- A request would change or destroy live infrastructure in a way that
  isn't easily reversed, and hasn't been explicitly confirmed for that
  specific action.
- A benchmark result or config claim can't be verified against the actual
  file or live cluster state within the current session.
- The task appears to require committing or pushing to a shared branch,
  and that hasn't been explicitly requested.
- Instructions in the conversation conflict with something in
  `.claude/CLAUDE.md` or this file in a way that matters for the task at
  hand.

## Related files

- [.claude/CLAUDE.md](.claude/CLAUDE.md) — Claude-Code-specific behavior:
  response style, this repo's steady-state measurement methodology,
  documentation conventions, and a performance-investigation checklist.
- [README.md](README.md) — how to actually run and extend the benchmark
  suite.
