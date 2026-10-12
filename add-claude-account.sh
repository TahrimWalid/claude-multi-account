#!/usr/bin/env bash
#
# add-claude-account.sh
# Add another Claude Code account on the same Linux machine, as its own command
# (e.g. `claude2`), with its own login, sessions and history.
#
# How it works: Claude Code reads its config from CLAUDE_CONFIG_DIR. Each extra
# account gets its own folder (e.g. ~/.claude2) and a shell alias that points
# `claude` at it. Your personal setup (CLAUDE.md, settings, skills, custom
# commands/agents) can be copied over; the login and history never are.
#
# Usage:
#   ./add-claude-account.sh                 # interactive, creates `claude2`
#   ./add-claude-account.sh work            # creates `work` -> ~/.work
#   ./add-claude-account.sh claude3 --yes   # no prompts, accept defaults
#   ./add-claude-account.sh claude2 --remove
#
# Options:
#   --dir PATH      Config folder for the new account (default: ~/.<name>)
#   --source PATH   Config folder to copy setup from (default: $CLAUDE_CONFIG_DIR or ~/.claude)
#   --no-copy       Don't copy CLAUDE.md / settings / skills etc.
#   --force         Overwrite items that already exist in the new folder
#   --rc FILE       Shell startup file to add the alias to (auto-detected otherwise)
#   --login         Start the new account right after setup so you can log in
#   --yes, -y       Answer yes to prompts (non-interactive)
#   --dry-run       Show what would happen, change nothing
#   --remove        Remove the alias for <name> (asks before deleting its folder)
#   -h, --help      Show this help

set -uo pipefail

# ---------- output helpers ----------
if [[ -t 1 ]]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YLW=$'\e[33m'; C_BLU=$'\e[34m'; C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
  C_RED=; C_GRN=; C_YLW=; C_BLU=; C_DIM=; C_RST=
fi
info() { printf '%s\n' "${C_BLU}==>${C_RST} $*"; }
ok()   { printf '%s\n' "  ${C_GRN}✓${C_RST} $*"; }
skip() { printf '%s\n' "  ${C_DIM}-${C_RST} $*"; }
warn() { printf '%s\n' "  ${C_YLW}!${C_RST} $*" >&2; }
err()  { printf '%s\n' "${C_RED}error:${C_RST} $*" >&2; }
die()  { err "$*"; exit 1; }

usage() { sed -n '2,/^$/{s/^# \{0,1\}//;p}' "$0"; exit 0; }

# ---------- argument parsing ----------
NAME=""
TARGET_DIR=""
SOURCE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DO_COPY=1
FORCE=0
RC_FILE=""
DO_LOGIN=0
ASSUME_YES=0
DRY_RUN=0
REMOVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)     [[ $# -ge 2 ]] || die "--dir needs a path"; TARGET_DIR="$2"; shift 2 ;;
    --source)  [[ $# -ge 2 ]] || die "--source needs a path"; SOURCE_DIR="$2"; shift 2 ;;
    --rc)      [[ $# -ge 2 ]] || die "--rc needs a file"; RC_FILE="$2"; shift 2 ;;
    --no-copy) DO_COPY=0; shift ;;
    --force)   FORCE=1; shift ;;
    --login)   DO_LOGIN=1; shift ;;
    -y|--yes)  ASSUME_YES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --remove)  REMOVE=1; shift ;;
    -h|--help) usage ;;
    -*)        die "unknown option: $1 (see --help)" ;;
    *)         [[ -z "$NAME" ]] || die "only one account name allowed (got '$NAME' and '$1')"
               NAME="$1"; shift ;;
  esac
done

NAME="${NAME:-claude2}"

# Prompts: default answer when not interactive or --yes
ask() {  # ask "question" default(y/n)
  local q="$1" def="${2:-n}" reply
  if [[ $ASSUME_YES -eq 1 ]]; then return 0; fi
  if [[ ! -t 0 ]]; then [[ "$def" == y ]]; return; fi
  local hint="[y/N]"; [[ "$def" == y ]] && hint="[Y/n]"
  read -r -p "  ? $q $hint " reply
  reply="${reply:-$def}"
  [[ "$reply" =~ ^[Yy] ]]
}

run() {  # run a command, or print it in dry-run mode
  if [[ $DRY_RUN -eq 1 ]]; then printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_RST" "$*"; return 0; fi
  "$@"
}

expand_path() {  # expand a leading ~ and make absolute
  local p="$1"
  [[ "$p" == "~" ]] && p="$HOME"
  [[ "$p" == "~/"* ]] && p="$HOME/${p#\~/}"
  [[ "$p" != /* ]] && p="$PWD/$p"
  printf '%s' "${p%/}"
}

# ---------- sanity checks ----------
[[ -n "${HOME:-}" && -d "$HOME" ]] || die "\$HOME is not set or doesn't exist."

# Running under sudo would put everything in root's home, not yours.
if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
  die "don't run this with sudo — it would set up the account for root, not '$SUDO_USER'. Run it as your normal user."
fi
if [[ $EUID -eq 0 ]]; then
  warn "running as root: the new account will belong to root's home ($HOME)."
  ask "Continue as root?" n || exit 1
fi

[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] \
  || die "account name '$NAME' must be letters, digits, '-' or '_' (it becomes a command name)."
[[ "$NAME" != "claude" ]] \
  || die "'claude' is your existing account's command. Pick another name, e.g. claude2."

TARGET_DIR="$(expand_path "${TARGET_DIR:-$HOME/.$NAME}")"
SOURCE_DIR="$(expand_path "$SOURCE_DIR")"

# ---------- pick the shell startup file ----------
SHELL_NAME="$(basename "${SHELL:-bash}")"
if [[ -z "$RC_FILE" ]]; then
  case "$SHELL_NAME" in
    zsh)  RC_FILE="${ZDOTDIR:-$HOME}/.zshrc" ;;
    fish) RC_FILE="$HOME/.config/fish/config.fish" ;;
    bash) RC_FILE="$HOME/.bashrc" ;;
    *)    RC_FILE="$HOME/.bashrc"; warn "unrecognised shell '$SHELL_NAME'; using ~/.bashrc (override with --rc)." ;;
  esac
else
  RC_FILE="$(expand_path "$RC_FILE")"
  [[ "$RC_FILE" == *.fish ]] && SHELL_NAME=fish
fi

MARK_BEGIN="# >>> claude-multi-account: $NAME >>>"
MARK_END="# <<< claude-multi-account: $NAME <<<"

remove_alias_block() {  # delete our marked block for $NAME from $RC_FILE
  [[ -f "$RC_FILE" ]] || return 0
  grep -qF "$MARK_BEGIN" "$RC_FILE" || return 0
  if [[ $DRY_RUN -eq 1 ]]; then skip "[dry-run] would remove the '$NAME' block from $RC_FILE"; return 0; fi
  cp -p "$RC_FILE" "$RC_FILE.bak.$(date +%Y%m%d%H%M%S)" || die "couldn't back up $RC_FILE"
  local tmp; tmp="$(mktemp)" || die "mktemp failed"
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '
    $0 == b {skip=1; next}
    $0 == e {skip=0; next}
    !skip' "$RC_FILE" > "$tmp" && cat "$tmp" > "$RC_FILE"   # cat keeps the file's owner/permissions
  rm -f "$tmp"
}

# ---------- --remove mode ----------
if [[ $REMOVE -eq 1 ]]; then
  info "Removing account command '$NAME'"
  if [[ -f "$RC_FILE" ]] && grep -qF "$MARK_BEGIN" "$RC_FILE"; then
    remove_alias_block && ok "removed alias from $RC_FILE (backup saved next to it)"
  else
    skip "no alias for '$NAME' found in $RC_FILE"
  fi
  if [[ -d "$TARGET_DIR" ]]; then
    warn "$TARGET_DIR holds this account's login, sessions and history."
    if ask "Delete $TARGET_DIR too? This can't be undone." n; then
      run rm -rf -- "$TARGET_DIR" && ok "deleted $TARGET_DIR"
    else
      skip "kept $TARGET_DIR"
    fi
  fi
  echo; info "Done. Open a new terminal (or run: source $RC_FILE) for the change to apply."
  exit 0
fi

# ---------- Claude Code installed? ----------
info "Checking Claude Code"
CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
if [[ -z "$CLAUDE_BIN" && -x "$HOME/.local/bin/claude" ]]; then
  CLAUDE_BIN="$HOME/.local/bin/claude"
  warn "claude is installed at ~/.local/bin but that folder isn't on your PATH in this shell."
  warn "Add it to $RC_FILE:  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
if [[ -z "$CLAUDE_BIN" ]]; then
  warn "Claude Code ('claude') is not installed or not on PATH."
  if ask "Install it now with Anthropic's official installer (curl -fsSL https://claude.ai/install.sh | bash)?" n; then
    command -v curl >/dev/null || die "curl is required to install Claude Code."
    if [[ $DRY_RUN -eq 1 ]]; then
      skip "[dry-run] would run the installer"
    else
      curl -fsSL https://claude.ai/install.sh | bash || die "installer failed — see the output above."
      hash -r
      CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
      [[ -z "$CLAUDE_BIN" && -x "$HOME/.local/bin/claude" ]] && CLAUDE_BIN="$HOME/.local/bin/claude"
      [[ -n "$CLAUDE_BIN" ]] || die "installed, but 'claude' still isn't on PATH. Open a new terminal and re-run this script."
    fi
  else
    die "install Claude Code first, then re-run this script."
  fi
fi
[[ -n "$CLAUDE_BIN" ]] && ok "found: $CLAUDE_BIN"

# ---------- name clashes ----------
info "Checking the name '$NAME'"
EXISTING_BLOCK=0
if [[ -f "$RC_FILE" ]] && grep -qF "$MARK_BEGIN" "$RC_FILE"; then
  EXISTING_BLOCK=1
  warn "this script already set up '$NAME' in $RC_FILE."
  ask "Replace that alias (pointing it at $TARGET_DIR)?" y || die "stopped; nothing changed."
elif [[ -f "$RC_FILE" ]] && grep -Eq "^[[:space:]]*alias[[:space:]]+$NAME([=[:space:]])" "$RC_FILE"; then
  HAND_LINE="$(grep -E "^[[:space:]]*alias[[:space:]]+$NAME([=[:space:]])" "$RC_FILE" | tail -1)"
  if [[ "$HAND_LINE" == *CLAUDE_CONFIG_DIR* ]]; then
    ok "'$NAME' is already set up by hand in $RC_FILE:"
    skip "$HAND_LINE"
    skip "Nothing to do. To let this script manage it, delete that line and re-run."
    exit 0
  fi
  die "$RC_FILE already has an alias '$NAME' for something else. Remove it or pick another name."
elif type -P "$NAME" >/dev/null 2>&1; then
  die "'$NAME' is already a program on this system ($(type -P "$NAME")). Pick another name."
fi
[[ $EXISTING_BLOCK -eq 1 ]] && ok "will update the existing '$NAME' alias" || ok "'$NAME' is free to use"

# ---------- folders ----------
info "Preparing $TARGET_DIR"
[[ "$TARGET_DIR" != "$SOURCE_DIR" ]] || die "new folder and source folder are the same ($TARGET_DIR)."
[[ "$TARGET_DIR" != "$HOME" ]]       || die "refusing to use your home folder itself as the config folder."
[[ ! -e "$TARGET_DIR" || -d "$TARGET_DIR" ]] || die "$TARGET_DIR exists and is not a folder."

if [[ -f "$TARGET_DIR/.credentials.json" ]]; then
  warn "$TARGET_DIR already has a login in it — this account was set up before."
  warn "Existing login, sessions and history will be kept."
  [[ $FORCE -eq 1 ]] || warn "Existing copied files won't be overwritten (use --force to overwrite)."
elif [[ -d "$TARGET_DIR" && -n "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]]; then
  warn "$TARGET_DIR already exists and isn't empty; existing files are kept."
fi
if [[ ! -d "$TARGET_DIR" ]]; then
  run mkdir -p -- "$TARGET_DIR" || die "couldn't create $TARGET_DIR"
  run chmod 700 "$TARGET_DIR"
  ok "created $TARGET_DIR"
else
  ok "using existing $TARGET_DIR"
fi
[[ $DRY_RUN -eq 1 || -w "$TARGET_DIR" ]] || die "$TARGET_DIR is not writable."

# ---------- copy personal setup ----------
# Only portable setup is copied. Never copied: .credentials.json (the login),
# projects/, sessions/, history.jsonl, cache/, plugins/ etc. (account-specific).
FILES_TO_COPY=(CLAUDE.md settings.json)
DIRS_TO_COPY=(skills commands agents output-styles hooks)
COPIED=0; FAILED=0

copy_item() {  # copy_item name kind(file|dir)
  local name="$1" kind="$2" src="$SOURCE_DIR/$1" dst="$TARGET_DIR/$1" note=""
  if [[ ! -e "$src" ]]; then
    case "$name" in
      commands) note=" (normal if you never created custom slash commands)" ;;
      agents)   note=" (normal if you never created custom subagents)" ;;
      CLAUDE.md) note=" (normal if you have no global CLAUDE.md)" ;;
    esac
    skip "$name: not in source — nothing to copy$note"; return 0
  fi
  if [[ "$kind" == file && ! -f "$src" ]]; then warn "$name: exists but isn't a file — skipped"; return 0; fi
  if [[ "$kind" == dir  && ! -d "$src" ]]; then warn "$name: exists but isn't a folder — skipped"; return 0; fi
  if [[ ! -r "$src" ]]; then warn "$name: not readable — skipped"; FAILED=$((FAILED+1)); return 0; fi
  if [[ -e "$dst" && $FORCE -eq 0 ]]; then skip "$name: already in $TARGET_DIR — kept (use --force to overwrite)"; return 0; fi
  if [[ -e "$dst" && $FORCE -eq 1 ]]; then run rm -rf -- "$dst" || { warn "$name: couldn't remove old copy"; FAILED=$((FAILED+1)); return 0; }; fi

  local out
  if [[ $DRY_RUN -eq 1 ]]; then
    skip "[dry-run] would copy $name"; return 0
  fi
  # Errors are captured and shown, never hidden.
  if out="$(cp -a -- "$src" "$dst" 2>&1)"; then
    ok "$name: copied"; COPIED=$((COPIED+1))
  else
    warn "$name: copy failed: $out"; FAILED=$((FAILED+1))
  fi
}

if [[ $DO_COPY -eq 1 ]]; then
  info "Copying your setup from $SOURCE_DIR"
  if [[ ! -d "$SOURCE_DIR" ]]; then
    warn "$SOURCE_DIR doesn't exist — nothing to copy. The new account starts with a clean setup."
    warn "(If your main account uses a different folder, re-run with --source PATH.)"
  else
    for f in "${FILES_TO_COPY[@]}"; do copy_item "$f" file; done
    for d in "${DIRS_TO_COPY[@]}";  do copy_item "$d" dir;  done

    # settings.json may contain paths that point into the old folder (e.g. hook scripts).
    if [[ -f "$TARGET_DIR/settings.json" ]] && grep -qF "$SOURCE_DIR" "$TARGET_DIR/settings.json" 2>/dev/null; then
      warn "settings.json mentions $SOURCE_DIR (e.g. hook script paths)."
      warn "Those still point at the first account's folder. Edit $TARGET_DIR/settings.json if they should point at $TARGET_DIR."
    fi
    if [[ -d "$SOURCE_DIR/plugins" ]]; then
      skip "plugins: not copied on purpose — install paths are tied to the first account."
      skip "         run /plugin inside '$NAME' to add the same marketplaces/plugins."
    fi
    [[ $FAILED -gt 0 ]] && warn "$FAILED item(s) failed to copy — see messages above. Setup continues."
  fi
else
  skip "skipping setup copy (--no-copy)"
fi

# ---------- write the alias ----------
info "Adding the '$NAME' command to $RC_FILE"
if [[ "$SHELL_NAME" == fish ]]; then
  ALIAS_LINE="alias $NAME 'env CLAUDE_CONFIG_DIR=\"$TARGET_DIR\" claude'"
else
  ALIAS_LINE="alias $NAME='CLAUDE_CONFIG_DIR=\"$TARGET_DIR\" claude'"
fi

if [[ $DRY_RUN -eq 1 ]]; then
  skip "[dry-run] would add: $ALIAS_LINE"
else
  mkdir -p "$(dirname "$RC_FILE")" || die "couldn't create $(dirname "$RC_FILE")"
  touch "$RC_FILE" || die "couldn't write $RC_FILE"
  [[ $EXISTING_BLOCK -eq 1 ]] && remove_alias_block
  # make sure we start on a new line
  [[ -s "$RC_FILE" && -n "$(tail -c1 "$RC_FILE")" ]] && printf '\n' >> "$RC_FILE"
  printf '%s\n%s\n%s\n' "$MARK_BEGIN" "$ALIAS_LINE" "$MARK_END" >> "$RC_FILE" || die "couldn't write $RC_FILE"
  ok "added: $ALIAS_LINE"
fi

# ---------- make SSH logins load the alias ----------
# SSH starts a login shell. Bash then reads only the FIRST of ~/.bash_profile,
# ~/.bash_login, ~/.profile — and if that file doesn't source ~/.bashrc, the
# alias is missing after every fresh login ("command not found").
# We append to whichever file bash actually reads; creating ~/.bash_profile
# next to an existing ~/.profile would stop ~/.profile being read at all.
if [[ "$SHELL_NAME" == bash && "$RC_FILE" == "$HOME/.bashrc" ]]; then
  info "Checking that SSH logins load ~/.bashrc"
  LOGIN_FILE=""
  for f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
    [[ -f "$f" ]] && { LOGIN_FILE="$f"; break; }
  done
  LOGIN_FILE="${LOGIN_FILE:-$HOME/.profile}"   # none exist: create ~/.profile
  SOURCE_LINE='[ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"'

  if [[ -f "$LOGIN_FILE" ]] && grep -q 'bashrc' "$LOGIN_FILE"; then
    ok "$LOGIN_FILE already loads ~/.bashrc"
  elif [[ $DRY_RUN -eq 1 ]]; then
    skip "[dry-run] would add to $LOGIN_FILE: $SOURCE_LINE"
  elif ask "$LOGIN_FILE doesn't load ~/.bashrc, so '$NAME' would vanish after each SSH login. Fix it?" y; then
    [[ -f "$LOGIN_FILE" ]] && cp -p "$LOGIN_FILE" "$LOGIN_FILE.bak.$(date +%Y%m%d%H%M%S)"
    [[ -s "$LOGIN_FILE" && -n "$(tail -c1 "$LOGIN_FILE")" ]] && printf '\n' >> "$LOGIN_FILE"
    printf '# load ~/.bashrc in login shells (added by add-claude-account.sh)\n%s\n' "$SOURCE_LINE" >> "$LOGIN_FILE" \
      && ok "added to $LOGIN_FILE (backup saved next to it)" \
      || warn "couldn't write $LOGIN_FILE — add this line yourself: $SOURCE_LINE"
  else
    warn "left as is. Add this line to $LOGIN_FILE yourself: $SOURCE_LINE"
  fi
fi

# ---------- verify in a fresh login shell ----------
# Same check as logging out and SSHing back in.
if [[ $DRY_RUN -eq 0 && ( "$SHELL_NAME" == bash || "$SHELL_NAME" == zsh ) ]] && command -v "$SHELL_NAME" >/dev/null; then
  info "Verifying '$NAME' in a fresh login shell"
  CHECK_CMD=("$SHELL_NAME" -lic "type $NAME")
  command -v timeout >/dev/null && CHECK_CMD=(timeout 15 "${CHECK_CMD[@]}")
  if "${CHECK_CMD[@]}" </dev/null 2>/dev/null | grep -q "$NAME is .*alias"; then
    ok "'$NAME' will be available after every login"
  else
    warn "couldn't confirm '$NAME' in a fresh login shell."
    warn "Log out, SSH back in and type '$NAME'. If it's missing, run: $SHELL_NAME -lic 'type $NAME'"
  fi
fi

# ---------- finish ----------
echo
info "${C_GRN}Done.${C_RST} '$NAME' uses $TARGET_DIR; your existing 'claude' is unchanged."
cat <<EOF

  Next steps:
    1. Load the alias in this terminal:   source $RC_FILE
       (new terminals pick it up automatically)
    2. Start the new account:             $NAME
       Then type /login. On a server without a browser, it prints a URL —
       open it on any device, sign in with the OTHER account, paste the code back.
    3. Check each command uses the right account: run /status in 'claude' and in '$NAME'.

  Notes:
    • Each account has its own sessions: /resume in '$NAME' only shows '$NAME' sessions.
    • Both accounts can work in the same project folder and edit the same files.
      Take turns on the same file (e.g. commit, then review) to avoid clashes.
    • Each account needs its own paid plan (Pro/Max/Team/Enterprise) or API key.
    • Undo later with: $0 $NAME --remove

EOF

if [[ $DO_LOGIN -eq 1 && $DRY_RUN -eq 0 ]]; then
  info "Starting '$NAME' so you can log in..."
  CLAUDE_CONFIG_DIR="$TARGET_DIR" exec "$CLAUDE_BIN"
fi
