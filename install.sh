#!/usr/bin/env bash
# Install this toolkit for Codex. It copies the skills in skills/ to the user skills folder Codex reads
# ($HOME/.agents/skills) and adds the short working rules in config/AGENTS.md, between two marker lines, to the
# global instructions file Codex reads (AGENTS.md in the Codex home, or AGENTS.override.md when that one is in
# use). It never touches config.toml or anything else in the Codex home, and never writes inside a git
# repository. Running it again refreshes the earlier install.
#
#   ./install.sh                 install, or refresh an earlier install
#   ./install.sh --dry-run       show every step and change nothing (works with --uninstall too)
#   ./install.sh --uninstall     remove what this script added and put back what it replaced
#
# Options:
#   --skills-dir DIR    install the skills here instead of $HOME/.agents/skills
#   --codex-home DIR    the Codex home with the global instructions (default: $CODEX_HOME, else $HOME/.codex)
#   --no-rules          install the skills only and leave the global instructions alone
#
# Exit codes: 0 done, 1 bad usage, 3 refused because a target is inside a git repository, 4 a target folder
# is not writable (nothing was changed).
set -euo pipefail

VERSION=0.1.0
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.agents/skills"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
MODE=install
DRY=0
DRY_REFRESH=0
RULES=1

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --uninstall) MODE=uninstall ;;
    --no-rules) RULES=0 ;;
    --skills-dir) SKILLS_DIR="${2:?--skills-dir needs a folder}"; shift ;;
    --codex-home) CODEX_DIR="${2:?--codex-home needs a folder}"; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'Unknown option: %s (see --help)\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

absolute() {  # an absolute path, without requiring it to exist
  case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$(pwd)" "$1" ;; esac
}
SKILLS_DIR="$(absolute "${SKILLS_DIR%/}")"
CODEX_DIR="$(absolute "${CODEX_DIR%/}")"
# The manifest and the backups sit next to the skills folder, outside the folders Codex scans for skills
STATE="$(dirname "$SKILLS_DIR")/.e3-coding-toolkit"
MANIFEST="$STATE/manifest"
BACKUP="$STATE/backup"
BEGIN_MARK="<!-- e3-coding-toolkit:begin -->"
END_MARK="<!-- e3-coding-toolkit:end -->"

say() { printf '%s\n' "$*"; }
die() { printf 'install.sh: %s\n' "$1" >&2; exit "${2:-1}"; }
run() { if [ "$DRY" = 1 ]; then say "  [dry run] $*"; else "$@"; fi; }
record() { if [ "$DRY" = 0 ]; then printf '%s\n' "$*" >> "$MANIFEST"; fi; }

existing_ancestor() {  # the nearest folder at or above a path that exists
  local p="$1"
  while [ ! -d "$p" ]; do p="$(dirname "$p")"; done
  printf '%s\n' "$p"
}

work_tree_of() {  # the top of the git work tree containing a path, or nothing
  command -v git >/dev/null 2>&1 || return 0
  git -C "$(existing_ancestor "$1")" rev-parse --show-toplevel 2>/dev/null || true
}

can_write() {  # a file can be created in the folder, or in its nearest existing parent when it is missing
  local probe
  probe="$(existing_ancestor "$1")/.e3-coding-toolkit-probe.$$"
  if (: > "$probe") 2>/dev/null; then rm -f "$probe"; return 0; fi
  return 1
}

has_text() { [ -f "$1" ] && grep -q '[^[:space:]]' "$1"; }

skill_names() {  # every folder in skills/ that holds a SKILL.md
  local dir
  for dir in "$SRC"/skills/*/; do
    if [ -f "$dir/SKILL.md" ]; then basename "$dir"; fi
  done
}

rules_file() {  # the global instructions file Codex reads: AGENTS.override.md wins when it has content
  if has_text "$CODEX_DIR/AGENTS.override.md"; then say "AGENTS.override.md"; else say "AGENTS.md"; fi
}

strip_block() {  # strip_block <file> <added_separator 0|1> <added_newline 0|1>: take the block out, exactly
  local file="$1" sep="$2" nl="$3" tmp
  grep -qxF "$BEGIN_MARK" "$file" || return 0
  tmp="$(mktemp "${TMPDIR:-/tmp}/e3-coding-toolkit.XXXXXX")"
  awk -v begin="$BEGIN_MARK" -v end="$END_MARK" -v sep="$sep" '
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) if (b == 0 && line[i] == begin) b = i
      for (i = b; i <= NR; i++) if (e == 0 && line[i] == end) e = i
      if (e == 0) e = NR
      first = b
      if (sep == 1 && b > 1 && line[b - 1] == "") first = b - 1
      for (i = 1; i <= NR; i++) if (i < first || i > e) print line[i]
    }' "$file" > "$tmp"
  # cat into the file keeps its inode, so a symlinked AGENTS.md stays a symlink
  if [ "$nl" = 1 ]; then printf '%s' "$(cat "$tmp")" > "$file"; else cat "$tmp" > "$file"; fi
  rm -f "$tmp"
}

uninstall() {  # uninstall <quiet 0|1>
  local quiet="$1" kind name a b c target dirs=""
  if [ ! -f "$MANIFEST" ]; then
    [ "$quiet" = 1 ] || say "Nothing to uninstall: no install found at $MANIFEST"
    return 0
  fi
  [ "$quiet" = 1 ] || say "Removing e3-coding-toolkit$([ "$DRY" = 1 ] && echo ' (dry run, nothing changes)')"
  # Newest entry first, so everything comes off in the reverse order it went on
  while read -r kind name a b c; do
    case "$kind" in
      skill)
        case "$name" in ""|*/*|.*) die "bad manifest line: skill '$name'" ;; esac
        target="$SKILLS_DIR/$name"
        run rm -rf "$target"
        if [ -e "$BACKUP/skills/$name" ]; then
          run mv "$BACKUP/skills/$name" "$target"
          [ "$quiet" = 1 ] || say "  put back your own skill $name"
        fi
        [ "$quiet" = 1 ] || say "  removed skill $name" ;;
      rules)
        case "$name" in AGENTS.md|AGENTS.override.md) ;; *) die "bad manifest line: rules '$name'" ;; esac
        target="$CODEX_DIR/$name"
        if [ -f "$target" ]; then
          if [ "$DRY" = 1 ]; then say "  [dry run] take the toolkit block out of $target"; else strip_block "$target" "$b" "$c"; fi
          # a file the install created, and that holds nothing else now, goes away
          if [ "$a" = 0 ] && [ "$DRY" = 0 ] && [ ! -s "$target" ]; then rm -f "$target"; fi
        fi
        [ "$quiet" = 1 ] || say "  removed the working rules from $target" ;;
      dir) dirs="$name
$dirs" ;;
    esac
  done < <(awk '{ lines[NR] = $0 } END { for (i = NR; i > 0; i--) print lines[i] }' "$MANIFEST")
  run rm -rf "$STATE"
  # Folders the install created, deepest first, only when nothing else lives in them now
  local dir
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    if [ "$DRY" = 1 ]; then say "  [dry run] rmdir $dir (if empty)"; else rmdir "$dir" 2>/dev/null || true; fi
  done < <(printf '%s' "$dirs" | awk 'NF' | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-)
  [ "$quiet" = 1 ] || say "Done$([ "$DRY" = 1 ] && echo ' (dry run, nothing was changed)')."
}

make_dir() {  # create a folder and its missing parents; remember each one this script created
  local dir="$1" missing="" p
  p="$dir"
  while [ ! -d "$p" ]; do missing="$p
$missing"; p="$(dirname "$p")"; done
  run mkdir -p "$dir"
  while IFS= read -r p; do if [ -n "$p" ]; then record "dir $p"; fi; done <<EOF
$missing
EOF
}

install() {
  local started name names target file existed sep nl top commit
  started="$(date +%s)"
  [ -d "$SRC/skills" ] || die "run this from a copy of the toolkit (no skills/ next to the script)"
  names="$(skill_names)"
  [ -n "$names" ] || die "no skills found in $SRC/skills"

  local targets=("$SKILLS_DIR")
  if [ "$RULES" = 1 ]; then targets+=("$CODEX_DIR"); fi

  # Never install into a repository: the files would show up in its working tree and its pull request
  top="$(work_tree_of "$(dirname "$SRC")")"
  [ -z "$top" ] || die "the toolkit is inside the git repository $top, so its files would show up there.
Remove $SRC and clone the toolkit outside any repository (for example /tmp/e3-coding-toolkit), then run install.sh again." 3
  for target in "${targets[@]}"; do
    top="$(work_tree_of "$target")"
    [ -z "$top" ] || die "$target is inside the git repository $top; installing there would add files to it.
Point --skills-dir or --codex-home at a folder outside the repository." 3
  done
  # Check every target before changing anything, so a sandbox or permission problem never leaves half an install
  for target in "${targets[@]}"; do
    can_write "$target" || die "cannot write to $target (the sandbox or file permissions block it). Nothing was changed.
Run install.sh with permission to write outside the workspace, or use the skills where they are: $SRC/skills/<name>/SKILL.md" 4
  done

  if [ -f "$MANIFEST" ]; then
    if [ "$DRY" = 1 ]; then
      say "Dry run: an earlier install exists; a real run removes it first, then installs again"
      DRY_REFRESH=1
    else
      say "Refreshing the earlier install"
      uninstall 1
    fi
  fi
  [ "$DRY" = 0 ] || say "Dry run: nothing changes"

  make_dir "$STATE"
  if [ "$DRY" = 0 ]; then
    # make_dir recorded the folders it created before the manifest existed; keep those lines
    local created=""
    [ -f "$MANIFEST" ] && created="$(cat "$MANIFEST")"
    printf 'version %s\n' "$VERSION" > "$MANIFEST"
    [ -z "$created" ] || printf '%s\n' "$created" >> "$MANIFEST"
  fi
  make_dir "$SKILLS_DIR"

  for name in $names; do
    target="$SKILLS_DIR/$name"
    if [ "$DRY_REFRESH" = 1 ] && grep -qx "skill $name" "$MANIFEST"; then
      say "  [dry run] replace skill $name with a fresh copy"
      continue
    fi
    if [ -e "$target" ] || [ -L "$target" ]; then
      [ ! -e "$BACKUP/skills/$name" ] || die "a backup of $name already exists in $BACKUP; move it back by hand first"
      run mkdir -p "$BACKUP/skills"
      run mv "$target" "$BACKUP/skills/$name"
      say "  your own skill $name was moved to $BACKUP/skills (put back by --uninstall)"
    fi
    # Recorded before the copy, so an interrupted copy is still removed by --uninstall
    record "skill $name"
    run cp -R "$SRC/skills/$name" "$target"
  done

  if [ "$RULES" = 1 ]; then
    make_dir "$CODEX_DIR"
    file="$(rules_file)"
    target="$CODEX_DIR/$file"
    existed=0; sep=0; nl=0
    if [ -f "$target" ]; then
      existed=1
      # a block left by an install whose manifest is gone is taken out first, so there is only ever one
      if [ "$DRY" = 0 ]; then strip_block "$target" 1 0; fi
      if [ -s "$target" ]; then
        sep=1
        [ "$(tail -c 1 "$target" | od -An -c | tr -d ' ')" = '\n' ] || nl=1
      fi
    fi
    record "rules $file $existed $sep $nl"
    if [ "$DRY" = 1 ]; then
      say "  [dry run] append the working rules between markers to $target"
    else
      {
        [ "$nl" = 0 ] || printf '\n'
        [ "$sep" = 0 ] || printf '\n'
        printf '%s\n' "$BEGIN_MARK"
        cat "$SRC/config/AGENTS.md"
        printf '%s\n' "$END_MARK"
      } >> "$target"
    fi
  fi

  if [ "$DRY" = 1 ]; then
    say "Would install e3-coding-toolkit $VERSION:"
  else
    commit="$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || true)"
    say "Installed e3-coding-toolkit $VERSION${commit:+ ($commit)} in $(( $(date +%s) - started ))s"
  fi
  say "  Skills: $SKILLS_DIR"
  say "    $(printf '%s ' $names | sed 's/ $//; s/ /, /g')"
  if [ "$RULES" = 1 ]; then
    say "  Rules:  $target (between marker lines; Codex reads it when a session starts)"
  fi
  say "  Not touched: config.toml and every other file in $CODEX_DIR"
  say "  Undo: $SRC/install.sh --uninstall"
  [ "$DRY" = 1 ] || say "This session: read $SKILLS_DIR/working-rules/SKILL.md now and follow it."
}

if [ "$MODE" = uninstall ]; then uninstall 0; else install; fi
