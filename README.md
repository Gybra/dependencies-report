# dependencies-report

Weekly snapshot of what is installed on a Mac, published to a **secret GitHub gist** so it
survives a dead disk.

Every Monday morning it answers two questions:

1. **What is installed?** Homebrew taps, formulae and casks, plus a ready-to-run `Brewfile`.
2. **Where do my own scripts come from?** Every personal shell script in the bin dirs, matched
   back to the gist or git repo it came from. Anything with no remote copy is flagged
   `⚠️ local only, no remote backup`, which is the whole point: you find out *before* the disk dies.

The gist is always the same one, updated in place, so the URL never changes and you keep the
revision history GitHub gives you for free.

## Requirements

- macOS (uses `launchd` and `sw_vers`)
- [Homebrew](https://brew.sh)
- [GitHub CLI](https://cli.github.com) authenticated with the `gist` scope:
  ```bash
  gh auth login
  gh auth refresh -h github.com -s gist   # if the token predates this
  ```

## Install

```bash
git clone https://github.com/Gybra/dependencies-report.git
cd dependencies-report
./install.sh
```

That copies the script to `~/.local/bin/` and loads a `launchd` agent that runs it every
**Monday at 09:00**. If the Mac is asleep or off at that time, `launchd` runs it on the next wake.

Different schedule:

```bash
WEEKDAY=5 HOUR=18 ./install.sh   # 0 = Sunday, 1 = Monday … 6 = Saturday
```

> The script is **copied** out of the repo instead of being symlinked. A `launchd` agent gets no
> TCC permission to read `~/Documents`, `~/Desktop` or `~/Downloads`, so running it straight from a
> checkout in one of those folders dies with `Operation not permitted`.
> **Re-run `./install.sh` after editing the script.**

## Usage

```bash
dependencies-report.sh --dry-run    # build the report, print its path, upload nothing
dependencies-report.sh              # build it and push it to the gist

launchctl kickstart -p gui/$(id -u)/com.dependencies-report   # force a scheduled run now
tail ~/.local/state/dependencies-report/last-run.log          # what the last run did
```

First run creates the secret gist and stores its id. Every run after that edits that same gist.

## What the report contains

| Section | Content |
|---|---|
| Quick restore | Homebrew install one-liner + `brew bundle install` |
| Taps | `brew tap` |
| Explicitly installed formulae | `brew leaves`, with each package description |
| All formulae / Casks | full list with versions |
| Personal scripts | script, path, description, **origin** |
| My gists | every gist on the account: description, file count, visibility, last update |
| Brewfile | full `brew bundle dump`, ready to paste into a `Brewfile` |
| Not covered | what this report deliberately ignores |

### How a script is found

A file is treated as a personal script when it is a **regular file** (not a symlink), executable,
and its first line is a `bash`/`zsh`/`sh` shebang. That filters out Homebrew symlinks and binaries
without keeping a hardcoded list. Its description is the first comment line of the header.

### How the origin is resolved

1. An `# origin: <url>` line in the first 20 lines of the script wins over everything else. Add it
   to any script whose source lives somewhere the next two steps cannot see.
2. Otherwise, if the script sits inside a git working tree → `git remote get-url origin`.
3. Otherwise its filename is matched against the filenames of every gist on the account
   (`foo` also matches a gist file named `foo.sh`).
4. No match → flagged as local only.

## Configuration

Both live at the top of `dependencies-report.sh`:

- `SCAN_DIRS` — directories scanned for personal scripts. Defaults to `/usr/local/bin`,
  `~/bin`, `~/.local/bin`, `~/Documents/side-projects/scripts`.
- `GIST_DESC` — description of the gist.

## Where things live

| Path | What |
|---|---|
| `~/.local/bin/dependencies-report.sh` | installed script (what `launchd` actually runs) |
| `~/Library/LaunchAgents/com.dependencies-report.plist` | the weekly schedule |
| `~/.local/state/dependencies-report/gist_id` | id of the gist to update |
| `~/.local/state/dependencies-report/dependencies.md` | last generated report |
| `~/.local/state/dependencies-report/last-run.log` | stdout/stderr of the last scheduled run |

Delete `gist_id` to start over with a brand new gist.

## Uninstall

```bash
./install.sh --uninstall
```

Unloads the agent and removes the installed copies. State and gist are left alone.

## Known limits

- **Not covered by the report:** `~/.zshrc` aliases and functions, global npm/pnpm/bun packages,
  pyenv, gem, cargo, and apps installed by hand outside Homebrew Cask.
- `gh` reads its token from the macOS Keychain. The agent runs in your logged-in GUI session, so
  the Keychain is unlocked and this works. If you ever see an auth error in `last-run.log`, run
  `gh auth login` again.
- The gist is **secret**, not private: anyone with the URL can read it. It contains a package list
  and script paths, no secrets, but keep the link to yourself.

## License

MIT
