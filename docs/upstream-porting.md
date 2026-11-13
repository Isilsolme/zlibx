# Keeping up with upstream

This repository (`Isilsolme/zlibx-MD3`) is an independent UI fork. The app
name remains **zlibx**; only the repository/product line is separate.

## Remotes

- `origin` — this repository (`Isilsolme/zlibx-MD3`)
- `upstream` — the original slim fork (`minglaiyo/zlibx`)

```bash
git fetch upstream
```

## What happened upstream

The zlibx maintainer merged the UI branch, then reverted it because the style
did not fit. The upstream repository now carries a rollback tag
(`rollback-20261113-pre-completion`) and continued its own feature work
(categories, full-text search, faster home feed, detail fixes, etc.).

Do **not** merge or cherry-pick the rollback commit/tag: it removes this UI.

## Porting policy

1. Work on a dedicated branch: `port/<topic>`.
2. Inspect only the relevant upstream commits:
   ```bash
   git log --oneline upstream/main -- <path>
   git show <commit>
   ```
3. Prefer cherry-pick / manual re-application of small fixes over a full
   `git merge upstream/main`. A full merge will conflict with the UI files and
   the rollback history.
4. Re-apply UI changes around upstream's new architecture rather than
   overwriting newer upstream features (the home/search splits are the main
   conflict points).
5. Run `flutter analyze` and `flutter test`; add/adjust tests for the ported
   behavior.
6. Update `docs/screenshots/` if a visible UI change occurs.

## Branch layout

- `main` — independent product baseline (UI + selected upstream fixes)
- `release/1.6.0` — the first published UI snapshot (historical)
- `upstream` — read-only mirror of the slim fork

## Update checker

`UpdateState.releaseApiUrl` points at
`https://api.github.com/repos/Isilsolme/zlibx-MD3/releases/latest`.
GitHub's "latest" endpoint ignores prereleases, so publish a normal release
(not a prerelease) for a version that clients should see.
