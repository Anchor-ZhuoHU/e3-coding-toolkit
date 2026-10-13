#!/usr/bin/env bash
# Tests for install.sh. Everything happens in a throwaway folder with its own HOME and CODEX_HOME. The Codex
# home starts with a config.toml (with an MCP server entry) and an AGENTS.md, standing in for a hosted
# environment's own setup, and the install runs from inside a small git repository, the way a coding agent
# runs it from the repository it is working on.
#
#   scripts/test-install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/toolkit-install-test.XXXXXX")"
trap 'chmod -R u+w "$WORK" 2>/dev/null || true; rm -rf "$WORK"' EXIT
REPO="$WORK/repo"
export HOME="$WORK/home" CODEX_HOME="$WORK/home/.codex"
INSTALL="$ROOT/install.sh"
SKILLS="$(cd "$ROOT/skills" && for d in */; do if [ -f "$d/SKILL.md" ]; then printf '%s ' "${d%/}"; fi; done)"

hash_of() { if command -v shasum >/dev/null 2>&1; then shasum "$1" | cut -d' ' -f1; else sha1sum "$1" | cut -d' ' -f1; fi; }

tree_state() {  # every file and folder under HOME with a content hash, so two moments compare exactly
  (cd "$WORK" && find home -print | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then echo "$p -> $(readlink "$p")"
    elif [ -f "$p" ]; then echo "$p $(hash_of "$p")"
    else echo "$p/"; fi
  done)
}

fresh_home() {  # a home whose Codex folder already has its own config.toml and AGENTS.md
  chmod -R u+w "$HOME" 2>/dev/null || true
  rm -rf "$HOME"
  mkdir -p "$CODEX_HOME"
  printf '%s\n' 'model = "example-model"' '' '[mcp_servers.assessment_tools]' 'command = "assessment-tools"' \
    'args = ["serve"]' > "$CODEX_HOME/config.toml"
  printf '%s\n' '# Workspace instructions' '' '- Submit through the assessment tools.' > "$CODEX_HOME/AGENTS.md"
  cp "$CODEX_HOME/config.toml" "$WORK/config.toml.orig"
  cp "$CODEX_HOME/AGENTS.md" "$WORK/AGENTS.md.orig"
}

FAILS=0
check() {  # check "<what>" <command...>
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "PASS  $what"; else echo "FAIL  $what"; FAILS=$((FAILS + 1)); fi
}
repo_clean() { [ -z "$(git -C "$REPO" status --porcelain --untracked-files=all)" ]; }
markers_once() { [ "$(grep -c '^<!-- e3-coding-toolkit:begin -->$' "$1")" = 1 ] && [ "$(grep -c '^<!-- e3-coding-toolkit:end -->$' "$1")" = 1 ]; }
is_prefix() { head -c "$(wc -c < "$1" | tr -d ' ')" "$2" | cmp -s - "$1"; }  # file $1 is the start of file $2

# A small repository; every install below runs from inside it
mkdir -p "$REPO"
git -C "$REPO" init -q
printf 'print("hello")\n' > "$REPO/agent.py"
git -C "$REPO" add agent.py
git -C "$REPO" -c user.name=test -c user.email=test@example.com commit -q -m init
cd "$REPO"

# 0. Every skill has the front matter Codex needs
for s in $SKILLS; do
  check "skill $s: front matter with its own name and a description" \
    bash -c "head -1 '$ROOT/skills/$s/SKILL.md' | grep -qx -- '---' && grep -qx 'name: $s' '$ROOT/skills/$s/SKILL.md' && grep -q '^description: .\{40,\}' '$ROOT/skills/$s/SKILL.md'"
done

# 1. A dry run changes nothing and names what it would do
fresh_home
tree_state > "$WORK/before.txt"
"$INSTALL" --dry-run > "$WORK/dry.txt"
check "dry run changes nothing" cmp -s "$WORK/before.txt" <(tree_state)
for s in $SKILLS; do check "dry run names skill $s" grep -q "$s" "$WORK/dry.txt"; done
check "dry run names the rules file" grep -q "$CODEX_HOME/AGENTS.md" "$WORK/dry.txt"

# 2. Install
start="$(date +%s)"
"$INSTALL" > "$WORK/install.txt"
check "install finishes within 5 seconds" test "$(( $(date +%s) - start ))" -le 5
for s in $SKILLS; do check "skill $s installed, same as the source" diff -r "$ROOT/skills/$s" "$HOME/.agents/skills/$s"; done
check "config.toml untouched" cmp -s "$WORK/config.toml.orig" "$CODEX_HOME/config.toml"
check "AGENTS.md keeps every byte it had, at the start" is_prefix "$WORK/AGENTS.md.orig" "$CODEX_HOME/AGENTS.md"
check "AGENTS.md has the rules block once" markers_once "$CODEX_HOME/AGENTS.md"
check "the rules block carries config/AGENTS.md" grep -qF "$(head -1 "$ROOT/config/AGENTS.md")" "$CODEX_HOME/AGENTS.md"
check "no new file in the repository, untracked included" repo_clean
check "output says config.toml was not touched" grep -q "Not touched: config.toml" "$WORK/install.txt"
check "output points at the working-rules skill" grep -q "working-rules/SKILL.md" "$WORK/install.txt"

# 3. Running it again gives the same result
tree_state > "$WORK/installed.txt"
"$INSTALL" > "$WORK/install2.txt"
check "second run leaves exactly the same files" cmp -s "$WORK/installed.txt" <(tree_state)
check "second run says it refreshed" grep -q "Refreshing" "$WORK/install2.txt"
check "still one rules block" markers_once "$CODEX_HOME/AGENTS.md"
check "repository still clean" repo_clean
"$INSTALL" --dry-run > /dev/null
check "a dry run over an install changes nothing" cmp -s "$WORK/installed.txt" <(tree_state)

# 4. Uninstall puts everything back, byte for byte
"$INSTALL" --uninstall --dry-run > /dev/null
check "uninstall dry run changes nothing" cmp -s "$WORK/installed.txt" <(tree_state)
"$INSTALL" --uninstall > "$WORK/uninstall.txt"
check "uninstall leaves the home exactly as before" cmp -s "$WORK/before.txt" <(tree_state)
check "a second uninstall finds nothing to do" bash -c "'$INSTALL' --uninstall | grep -q 'Nothing to uninstall'"

# 5. An AGENTS.md without a final newline comes back exact
fresh_home
printf '# Instructions\n\n- No newline at the end' > "$CODEX_HOME/AGENTS.md"
cp "$CODEX_HOME/AGENTS.md" "$WORK/nonl.orig"
tree_state > "$WORK/before5.txt"
"$INSTALL" > /dev/null
check "no final newline: original bytes kept at the start" is_prefix "$WORK/nonl.orig" "$CODEX_HOME/AGENTS.md"
"$INSTALL" > /dev/null
"$INSTALL" --uninstall > /dev/null
check "no final newline: exact after install, reinstall, uninstall" cmp -s "$WORK/before5.txt" <(tree_state)

# 6. No AGENTS.md at all: the install creates one and the uninstall removes it
fresh_home
rm "$CODEX_HOME/AGENTS.md"
tree_state > "$WORK/before6.txt"
"$INSTALL" > /dev/null
check "no AGENTS.md: one is created with the block" markers_once "$CODEX_HOME/AGENTS.md"
"$INSTALL" --uninstall > /dev/null
check "no AGENTS.md: removed again, home as before" cmp -s "$WORK/before6.txt" <(tree_state)

# 7. AGENTS.override.md in use: the block goes there, since Codex then ignores AGENTS.md
fresh_home
printf '# Override\n' > "$CODEX_HOME/AGENTS.override.md"
tree_state > "$WORK/before7.txt"
"$INSTALL" > "$WORK/install7.txt"
check "override in use: block goes into AGENTS.override.md" markers_once "$CODEX_HOME/AGENTS.override.md"
check "override in use: AGENTS.md untouched" cmp -s "$WORK/AGENTS.md.orig" "$CODEX_HOME/AGENTS.md"
check "override in use: output names AGENTS.override.md" grep -q "AGENTS.override.md" "$WORK/install7.txt"
"$INSTALL" --uninstall > /dev/null
check "override in use: home as before after uninstall" cmp -s "$WORK/before7.txt" <(tree_state)

# 8. A skill of the same name that is not ours is kept aside and put back
fresh_home
first="${SKILLS%% *}"
mkdir -p "$HOME/.agents/skills/$first"
printf 'someone else s skill\n' > "$HOME/.agents/skills/$first/SKILL.md"
tree_state > "$WORK/before8.txt"
"$INSTALL" > /dev/null
check "same-name skill replaced by ours" diff -r "$ROOT/skills/$first" "$HOME/.agents/skills/$first"
"$INSTALL" > /dev/null
"$INSTALL" --uninstall > /dev/null
check "same-name skill back after reinstall and uninstall" cmp -s "$WORK/before8.txt" <(tree_state)

# 9. --no-rules leaves the global instructions alone
fresh_home
"$INSTALL" --no-rules > /dev/null
check "--no-rules: AGENTS.md untouched" cmp -s "$WORK/AGENTS.md.orig" "$CODEX_HOME/AGENTS.md"
check "--no-rules: skills installed" test -f "$HOME/.agents/skills/$first/SKILL.md"
"$INSTALL" --uninstall > /dev/null

# 10. Never into a repository: a home inside a repository, or the toolkit copied into one, is refused
fresh_home
git -C "$HOME" init -q
tree_state > "$WORK/before10.txt"
set +e; "$INSTALL" > /dev/null 2> "$WORK/err10.txt"; code=$?; set -e
check "home inside a repository: refused with exit code 3" test "$code" = 3
check "home inside a repository: nothing changed" cmp -s "$WORK/before10.txt" <(tree_state)
rm -rf "$HOME/.git"
mkdir -p "$REPO/vendor"
cp -R "$ROOT" "$REPO/vendor/toolkit"
set +e; "$REPO/vendor/toolkit/install.sh" > /dev/null 2> "$WORK/err11.txt"; code=$?; set -e
check "toolkit inside a repository: refused with exit code 3" test "$code" = 3
check "toolkit inside a repository: the message says where to clone instead" grep -q "outside any repository" "$WORK/err11.txt"
rm -rf "$REPO/vendor"

# 11. A folder it cannot write to: a clear error and nothing changed (file permissions stand in for a sandbox)
if [ "$(id -u)" != 0 ]; then
  fresh_home
  chmod a-w "$HOME"
  tree_state > "$WORK/before11.txt"
  set +e; "$INSTALL" > /dev/null 2> "$WORK/err12.txt"; code=$?; set -e
  chmod u+w "$HOME"
  check "unwritable home: exit code 4" test "$code" = 4
  check "unwritable home: the message names the folder" grep -q "cannot write to $HOME/.agents/skills" "$WORK/err12.txt"
  check "unwritable home: nothing changed" cmp -s "$WORK/before11.txt" <(tree_state)
else
  echo "SKIP  unwritable home (running as root, file permissions do not stop root)"
fi

# 12. A manifest line pointing outside the skills folder is refused before anything is removed
fresh_home
"$INSTALL" > /dev/null
printf 'skill ../.codex\n' >> "$HOME/.agents/.e3-coding-toolkit/manifest"
check "a manifest line leaving the skills folder is refused" bash -c "! '$INSTALL' --uninstall"
check "the folder it named is untouched" test -f "$CODEX_HOME/config.toml"

check "the repository is still clean at the end" repo_clean
if [ "$FAILS" -gt 0 ]; then echo "$FAILS check(s) failed"; exit 1; fi
echo "all checks passed"
