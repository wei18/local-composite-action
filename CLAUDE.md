# Project conventions

## What this is

A composite GitHub Action (single `action.yml`, pure bash) that lets composite
actions in other repositories reference sibling actions via local paths
(`uses: ./../org/repo/path/to/action`). It locates the calling action's repository
checkout under the runner's `_actions` directory and symlinks it to
`$(dirname $GITHUB_WORKSPACE)/org/repo`, plus an all-lowercase alias.

Step flow in `action.yml`: skip if the action path is already local (contains
`./../`) → find the repo directory (walk up parents from `action_path`; fall back
to scanning `_actions/*/*/*/`) → create the symlink and lowercase alias.

## GitHub Actions semantics this design depends on

These are runner behaviors that shaped the design and are not obvious from the
code alone:

- Expressions in a called action's `inputs` evaluate in the **called** action's
  context, not the caller's. This action cannot read the caller's
  `github.action_repository` itself — that's why callers must pass
  `GITHUB_ACTION_REPOSITORY` explicitly (and `GITHUB_ACTION_PATH` as
  `action_path` when the composite action lives in another repository).
- The on-disk casing under `_actions/` follows the caller's `uses:` line, not the
  canonical repo name. Hence all org/repo comparisons are case-insensitive and
  the lowercase alias is always created.
- This repo's own CI calls the action from the same repo, which cannot reproduce
  third-party-caller layouts. `tests/run-tests.sh` simulates those layouts
  instead — a green CI alone does not validate caller-facing changes.

## README sync (bilingual)

`README.md` (English) and `README.zh-TW.md` (Traditional Chinese) are translations
of each other. Any content change to one MUST be mirrored in the other in the same
commit — same sections, same badges, same code examples; only prose is translated.

## Testing

All action logic lives in `action.yml` bash steps. Before committing changes to it,
run `tests/run-tests.sh` (extracts the real step scripts and runs them against
simulated runner layouts). CI runs it on every push and pull request.

## Constraints

- Pure bash, zero dependencies, no network access — keep it that way.
- `uses: ./../org/repo/...` references must work in all-lowercase: the lowercase
  symlink alias is part of the public contract.

## Releases

- Version tags have no `v` prefix (e.g. `1.2.0`); the floating `v1` tag must be
  force-moved to each new release.
- Marketplace listing updates automatically from the latest release.

## Adoption status

As of 2026-06-11 no external public repository uses this action — both
`gh search code "Wei18/local-composite-action"` and the dependents page
(`github.com/Wei18/local-composite-action/network/dependents`) show only this
repo itself. Private usage is invisible to both, and GitHub provides no
download/usage counts for actions. Re-run the search (filtering out this repo)
before assuming breaking changes are safe.
