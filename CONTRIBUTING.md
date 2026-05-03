# Contributing to Scoop Manager

## Project Principles

1. Preserve portability and stealth behavior (no persistent system mutation unless explicitly designed).
2. Keep script behavior predictable and transparent.
3. Prefer the smallest correct change over speculative refactors.
4. Documentation changes must not lose operational context.

## Commit Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```text
<type>(<scope>): <description>
```

Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`.

## Development Workflow

1. Read [README.md](README.md) fully before changing behavior or docs.
2. Implement the smallest scoped change.
3. Verify scripts/config/docs remain aligned.
4. Update [CHANGELOG.md](CHANGELOG.md) for user-facing changes.

## Pull Request Checklist

- [ ] No behavior regression in script flow
- [ ] Docs updated for any behavior/config changes
- [ ] No secrets committed
- [ ] Local-only files remain ignored
- [ ] Changelog updated (when applicable)
