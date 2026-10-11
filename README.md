# claude-multi-account

Run more than one Claude Code account on the same Linux machine, side by side, each as its own command (`claude2`, `work`, whatever you like).

Each account gets its own login, settings and session history. Your existing `claude` command stays exactly as it is.

## How it works

Claude Code keeps everything about an account in `~/.claude`. The `CLAUDE_CONFIG_DIR` environment variable points it at a different folder. This script creates that folder, copies your portable setup into it, and adds a shell alias:

```bash
alias claude2='CLAUDE_CONFIG_DIR="$HOME/.claude2" claude'
```

## Usage

```bash
curl -fsSLO https://raw.githubusercontent.com/TahrimWalid/claude-multi-account/main/add-claude-account.sh
less add-claude-account.sh        # read it first
chmod +x add-claude-account.sh
./add-claude-account.sh           # creates claude2
```

Then:

```bash
source ~/.bashrc    # or open a new terminal
claude2             # type /login
```

On a server without a browser, `/login` prints a URL. Open it on any device, sign in with the other account and paste the code back. Run `/status` in `claude` and `claude2` to confirm each shows a different email.

### Options

| Flag | What it does |
| --- | --- |
| `<name>` | Command name for the new account (default `claude2`) |
| `--dir PATH` | Config folder (default `~/.<name>`) |
| `--source PATH` | Folder to copy setup from (default `~/.claude`) |
| `--no-copy` | Start with a clean setup |
| `--force` | Overwrite files already copied to the new folder |
| `--rc FILE` | Shell startup file to edit (auto-detected) |
| `--login` | Start the new account right away so you can log in |
| `--dry-run` | Show what would happen, change nothing |
| `--remove` | Remove the alias, and optionally the folder |
| `--yes` | Accept defaults, no prompts |

## What gets copied

| Copied | Not copied |
| --- | --- |
| `CLAUDE.md`, `settings.json` | `.credentials.json` (the login) |
| `skills/`, `commands/`, `agents/` | `projects/`, `sessions/`, `history.jsonl`, `cache/` |
| `output-styles/`, `hooks/` | `plugins/` (add them again with `/plugin`) |

Items that don't exist are reported as "nothing to copy". Copy errors are always shown.

## Edge cases handled

- Re-running updates its own alias instead of adding a duplicate, and keeps an existing login.
- An alias you already wrote by hand is detected and left alone.
- Rejects `claude` as a name, names with spaces, and names that are already programs.
- Refuses to run under `sudo` (it would set up the account for root).
- Offers to install Claude Code if it's missing.
- Detects bash, zsh and fish; warns if SSH logins won't load `~/.bashrc`.
- Backs up your shell startup file before every change.
- Warns if `settings.json` contains paths pointing into the old folder.

## Notes

- Don't run two accounts on the same project folder at the same time. Use separate folders, branches or git worktrees.
- Each account needs its own paid plan (Pro, Max, Team or Enterprise) or an API key.
- This is for keeping separate accounts apart, such as work and personal. Check Anthropic's terms for your plans.

## Uninstall

```bash
./add-claude-account.sh claude2 --remove
```

## License

MIT
