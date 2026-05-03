# AGENTS Guide

This file defines collaboration guardrails for AI coding assistants and human contributors.

## Rules

- Do not change runtime behavior unless explicitly requested.
- Preserve portability and stealth guarantees.
- Avoid destructive operations on user data unless the script is explicitly designed for that path.
- Keep documentation accurate and synchronized with script behavior.
- Read `memory-bank/*.md` before substantial changes to understand architecture, constraints, and prior decisions.
- When behavior, architecture, or workflow decisions change, update relevant `memory-bank/*.md` files in the same change set.
- Never commit machine-specific secrets or local environment artifacts.

## Documentation Standard

- `README.md` is the primary user-facing and operational document.
- Keep onboarding clear for first-time users while preserving technical depth.
- Do not remove existing operational context without replacing it in-place.
