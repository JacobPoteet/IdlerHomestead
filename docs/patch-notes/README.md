# Patch notes

Every release gets a hand-written file `docs/patch-notes/<tag>.md` (for example `v0.5.0.md`; tags before v0.5.0 had no `v`, so `0.3.0.md`), committed **before** the tag is pushed. The release workflow (`.github/workflows/build.yml`, step "Compose release notes") puts that file at the top of the GitHub release page and appends the build info and the auto-generated list of closed issues in a collapsed section. If the file is missing the release still builds, with a "no hand-written patch notes" line. Tags starting with `v0.` (or the old `0.`) are published as pre-releases.

Start from [TEMPLATE.md](TEMPLATE.md). Write for players: say what changed in the game, not which files changed. Only list what is in the tagged commit (`git log <previous tag>..HEAD`).

## Rules
- One title line: `# Idler Homestead <tag> (pre-release)`, then a one-paragraph summary.
- A save-compatibility warning at the top whenever `Save.SAVE_COMPAT` changed since the last release.
- Sections in this order, dropping empty ones: Highlights, New features (grouped by area), Improvements, Visual and atmosphere, Audio, Bug fixes, Under the hood, Known issues.
- Highlights are 3 to 6 one-line bullets with a bold lead-in.
- Bug fixes are one short line each, written as the symptom that is gone.
- Known issues are honest: unmeasured performance, unfinished edges, issue numbers where one exists.
- Keep GDD decision numbers (D-numbers) out of the player-facing sections; mention the range once under "Under the hood".

## Release checklist
`/release` runs these steps. Tags are `vX.Y.Z`.
1. `lovec tests` shows 0 failed on main.
2. On a `release/<tag>` branch, write `docs/patch-notes/<tag>.md` from the template, open a PR and squash-merge it.
3. Run the wiki pass (see `CLAUDE.md`).
4. Tag the squash commit (`git tag -s <tag> -m <tag>`; `git push origin <tag>`).
5. After the workflow finishes, check the release page and that the build artifacts are attached.
