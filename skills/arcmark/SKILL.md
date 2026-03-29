---
name: arcmark
description: "Arcmark: Manage bookmarks, folders, and workspaces from the CLI."
metadata:
  version: 0.1.9
  openclaw:
    category: "productivity"
    requires:
      bins:
        - arcmark
    cliHelp: "arcmark --help"
---

# Arcmark CLI

Prerequisite: Read [../../CONTEXT.md](../../CONTEXT.md) for rules of engagement.

## Discovery

```bash
arcmark schema --all           # Complete command catalog (JSON)
arcmark schema workspace       # List all workspace commands
arcmark schema workspace.create # Full schema for a specific command
```

## Workspace Operations

| Command | Description |
|---------|-------------|
| `arcmark workspace list [--fields ...] [--limit N]` | List all workspaces |
| `arcmark workspace create <name> [--color <c>]` | Create workspace |
| `arcmark workspace rename <ref> <new-name>` | Rename workspace |
| `arcmark workspace delete <ref>` | Delete workspace |
| `arcmark workspace color <ref> <color>` | Change color |
| `arcmark workspace reorder <ref> --to <index>` | Reorder position |
| `arcmark workspace select <ref>` | Set GUI active workspace |
| `arcmark workspace browser-profile <ref> --browser <id> [--profile <p>]` | Set browser profile |

Colors: `ember` (Blush), `ruby` (Apricot), `coral` (Butter), `tangerine` (Leaf), `moss` (Mint), `ocean` (Sky), `indigo` (Periwinkle), `graphite` (Lavender).

## Link Operations

| Command | Description |
|---------|-------------|
| `arcmark link list [--workspace <ws>] [--depth N] [--urls-only]` | List links |
| `arcmark link add <url> [--workspace <ws>] [--folder <path>] [--title <t>]` | Add link |
| `arcmark link rename <ref> <new-title> [--workspace <ws>]` | Rename link |
| `arcmark link edit-url <ref> <new-url> [--workspace <ws>]` | Change URL |
| `arcmark link delete <ref> [--workspace <ws>]` | Delete link |
| `arcmark link move <ref> [--workspace <ws>] [--folder <path>] [--at N]` | Move link |
| `arcmark link icon <ref> --emoji <e> \| --symbol <s> \| --clear` | Set icon |
| `arcmark link pin <ref> [--workspace <ws>]` | Pin link |
| `arcmark link unpin <ref> [--workspace <ws>]` | Unpin link |

## Folder Operations

| Command | Description |
|---------|-------------|
| `arcmark folder list [--workspace <ws>] [--depth N]` | List hierarchy |
| `arcmark folder add <name> [--workspace <ws>] [--parent <path>]` | Create folder |
| `arcmark folder rename <ref> <new-name> [--workspace <ws>]` | Rename folder |
| `arcmark folder delete <ref> [--workspace <ws>]` | Delete folder+contents |
| `arcmark folder move <ref> [--workspace <ws>] [--parent <path>]` | Move folder |
| `arcmark folder expand <ref> [--workspace <ws>]` | Expand (GUI state) |
| `arcmark folder collapse <ref> [--workspace <ws>]` | Collapse (GUI state) |

## Utility Commands

| Command | Description |
|---------|-------------|
| `arcmark search <query> [--workspace <ws>] [--limit N] [--urls-only]` | Search titles+URLs |
| `arcmark import <file> [--format arc\|chrome\|txt] [--workspace <ws>]` | Import bookmarks |
| `arcmark export [--workspace <ws>] [--export-format json\|md] [--output <path>]` | Export data |
| `arcmark dedupe [--workspace <ws>] [--delete] [--limit N]` | Find duplicates |
| `arcmark group <refs...> --name <name> [--workspace <ws>]` | Group into folder |
| `arcmark move <refs...> --workspace <ws> [--from <ws>]` | Bulk cross-workspace move |

## Common Workflows

### Add a bookmark from terminal
```bash
arcmark link add "https://example.com" --workspace Research
```

### Search and open
```bash
arcmark search "react" --urls-only | head -1 | xargs open
```

### Import Chrome bookmarks
```bash
arcmark import bookmarks.html --format chrome --workspace Imported --dry-run
arcmark import bookmarks.html --format chrome --workspace Imported
```

### Export workspace as Markdown
```bash
arcmark export --workspace Research --export-format md --output research.md
```

### Find and clean duplicates
```bash
arcmark dedupe --dry-run
arcmark dedupe --delete
```

### Create workspace without affecting GUI
```bash
arcmark workspace create "CLI Project" --color ocean --dry-run
arcmark workspace create "CLI Project" --color ocean
```
