# Project conventions

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
