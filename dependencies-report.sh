#!/usr/bin/env bash
#
# origin: https://github.com/Gybra/dependencies-report
#
# dependencies-report.sh — weekly inventory of this Mac:
#   - Homebrew taps / formulae / casks (+ a ready-to-run Brewfile for restore)
#   - personal shell scripts found in the bin dirs, with their origin (gist / git repo)
#   - uploads the report to a SECRET gist, always the same one (updated in place)
#
# Usage:
#   dependencies-report.sh            generate and upload to the gist
#   dependencies-report.sh --dry-run  generate only, print the path of the .md
#
# Weekly scheduling: see install.sh (launchd agent, Mondays at 09:00).
#
# State (gist id + last report + log): ~/.local/state/dependencies-report/

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1

# Directories scanned for personal scripts. Add your own here.
SCAN_DIRS=(/usr/local/bin "$HOME/bin" "$HOME/.local/bin" "$HOME/Documents/side-projects/scripts")

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dependencies-report"
OUT="$STATE_DIR/dependencies.md"
GIST_ID_FILE="$STATE_DIR/gist_id"
GIST_DESC="Machine inventory (brew + personal scripts) — updated automatically"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

mkdir -p "$STATE_DIR"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

command -v brew >/dev/null || { echo "brew not found"; exit 1; }
if [ "$DRY_RUN" -eq 0 ]; then
  command -v gh >/dev/null || { echo "gh not found"; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh not authenticated (run: gh auth login)"; exit 1; }
fi

# --- gist lookup tables (fetched once) ---------------------------------------
: > "$TMP/gists.tsv"
: > "$TMP/gists_summary.tsv"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  # filename -> gist, used to resolve where a local script came from
  gh api /gists --paginate \
    --jq '.[] | .html_url as $url | .public as $pub | .files | keys[] | [., $url, (if $pub then "public" else "secret" end)] | @tsv' \
    > "$TMP/gists.tsv" 2>/dev/null || true
  # one row per gist, for the human-readable list
  gh api /gists --paginate \
    --jq '.[] | . as $g | [(if (($g.description // "") | length) == 0 then ($g.files|keys|.[0]) else ($g.description | gsub("[\r\n|]"; " ")) end), ($g.files|length|tostring), (if $g.public then "public" else "secret" end), $g.html_url, $g.updated_at[0:10]] | @tsv' \
    > "$TMP/gists_summary.tsv" 2>/dev/null || true
fi

gist_for() { # $1 = script basename
  awk -F'\t' -v n="$1" '$1==n || $1==n".sh" { printf "[%s gist](%s)", $3, $2; exit }' "$TMP/gists.tsv"
}

# --- report ------------------------------------------------------------------
{
  echo "# Machine inventory — $(hostname -s)"
  echo
  echo "Generated: $(date '+%Y-%m-%d %H:%M %Z') · macOS $(sw_vers -productVersion) · $(uname -m)"
  echo
  echo '> Regenerated every week by `dependencies-report.sh`. Do not edit by hand, changes get overwritten.'
  echo

  echo "## Quick restore"
  echo
  echo 'Full Homebrew state (formulae + casks + taps) from the Brewfile at the bottom of this document:'
  echo
  echo '```bash'
  echo '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  echo '# save the Brewfile block below as ./Brewfile, then:'
  echo 'brew bundle install --file=./Brewfile'
  echo '```'
  echo
  echo 'Personal scripts have to be fetched one by one from their origin (table below).'
  echo

  echo "## Homebrew"
  echo
  echo "Version: \`$(brew --version | head -1)\` · prefix \`$(brew --prefix)\`"
  echo
  echo "### Taps"
  echo
  taps=$(brew tap)
  if [ -n "$taps" ]; then printf '%s\n' "$taps" | sed 's/^/- `/;s/$/`/'; else echo "_no taps beyond the defaults._"; fi
  echo
  echo "### Explicitly installed formulae (leaves)"
  echo
  echo "These are the ones actually asked for, everything else is a dependency pulled in automatically."
  echo
  brew desc --formula $(brew leaves) 2>/dev/null | sed 's/^\([^:]*\): /- `\1` — /'
  echo
  echo "### All formulae ($(brew list --formula | wc -l | tr -d ' '))"
  echo
  echo '```'
  brew list --formula --versions
  echo '```'
  echo
  echo "### Casks ($(brew list --cask | wc -l | tr -d ' '))"
  echo
  echo '```'
  brew list --cask --versions
  echo '```'
  echo

  echo "## Personal scripts"
  echo
  echo "Non-symlink executables with a shell shebang, found in: $(printf '`%s` ' "${SCAN_DIRS[@]}")"
  echo
  echo "| Script | Path | Description | Origin |"
  echo "|---|---|---|---|"

  found=0
  for d in "${SCAN_DIRS[@]}"; do
    [ -d "$d" ] || continue
    while IFS= read -r f; do
      # real shell scripts only (sh/bash/zsh shebang), no binaries
      head -1 "$f" | grep -qE '^#!.*(bash|zsh|/sh)' || continue
      found=1
      base=$(basename "$f")
      desc=$(awk 'NR>1 && NR<12 && /^#/ && !/^#[[:space:]]*origin:/ { sub(/^#[[:space:]]*/,""); if (length($0)) { gsub(/\|/,"\\|"); print; exit } }' "$f")
      [ -n "$desc" ] || desc="_(no description in the header)_"

      # a script can declare where it comes from with an "# origin: <url>" header line
      origin=$(awk 'NR<20 && /^#[[:space:]]*origin:/ { sub(/^#[[:space:]]*origin:[[:space:]]*/,""); print; exit }' "$f")
      repo=$(git -C "$(dirname "$(readlink -f "$f" 2>/dev/null || echo "$f")")" remote get-url origin 2>/dev/null || true)
      [ -n "$origin" ] && repo=""
      [ -n "$repo" ] && origin="repo \`$repo\`"
      [ -z "$origin" ] && origin=$(gist_for "$base")
      [ -n "$origin" ] || origin="⚠️ **local only, no remote backup**"

      echo "| \`$base\` | \`$f\` | $desc | $origin |"
    done < <(find "$d" -maxdepth 1 -type f -perm +111 2>/dev/null | sort)
  done
  [ "$found" -eq 1 ] || echo "| _none_ | | | |"
  echo

  echo "## My gists"
  echo
  if [ -s "$TMP/gists_summary.tsv" ]; then
    echo "| Description | Files | Visibility | Updated | Link |"
    echo "|---|---|---|---|---|"
    awk -F'\t' '{ printf "| %s | %s | %s | %s | %s |\n", $1, $2, $3, $5, $4 }' "$TMP/gists_summary.tsv"
  else
    echo "_not fetched (gh not authenticated)._"
  fi
  echo

  echo "## Brewfile"
  echo
  echo '```ruby'
  brew bundle dump --file=- 2>/dev/null
  echo '```'
  echo

  echo "## Not covered by this report"
  echo
  echo "- \`~/.zshrc\` aliases and functions (backed up separately: $(git -C "$HOME" rev-parse --is-inside-work-tree >/dev/null 2>&1 && echo 'home is a git repo' || echo '**nowhere, dotfiles are not versioned**'))"
  echo "- global npm/pnpm/bun packages, pyenv, gem, cargo"
  echo "- apps installed by hand outside Homebrew Cask"
} > "$OUT"

echo "Report: $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"

if [ "$DRY_RUN" -eq 1 ]; then
  exit 0
fi

# --- upload: same gist every time --------------------------------------------
gist_id=""
[ -f "$GIST_ID_FILE" ] && gist_id=$(cat "$GIST_ID_FILE")

if [ -n "$gist_id" ] && gh gist view "$gist_id" --files >/dev/null 2>&1; then
  gh gist edit "$gist_id" --filename dependencies.md "$OUT"
  echo "Gist updated: https://gist.github.com/$gist_id"
else
  url=$(gh gist create "$OUT" --desc "$GIST_DESC")
  echo "${url##*/}" > "$GIST_ID_FILE"
  echo "Gist created: $url"
fi
