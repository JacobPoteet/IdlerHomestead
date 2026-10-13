# Patch notes

Every release gets a hand-written file `docs/patch-notes/<tag>.md` (for example `0.3.0.md`), committed **before** the tag is pushed. The release workflow (`.github/workflows/build.yml`, step "Compose release notes") puts that file at the top of the GitHub release page and appends the build info and the auto-generated list of closed issues in a collapsed section. If the file is missing the release still builds, with a "no hand-written patch notes" line. Tags starting with `0.` are published as pre-releases.

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
1. `lovec tests` shows 0 failed on main.
2. Write `docs/patch-notes/<tag>.md` from the template and commit it.
3. Push main, then tag (`git tag -s <tag> -m <tag>`; `git push origin <tag>`).
4. After the workflow finishes, check the release page and that the build artifacts are attached.
