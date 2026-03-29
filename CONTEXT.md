# Arcmark CLI (`arcmark`) Context

The `arcmark` CLI manages Arcmark bookmarks from the command line. It reads and writes the same `data.json` as the Arcmark GUI app.

## Rules of Engagement

- **Schema first:** Run `arcmark schema <command>` to inspect parameters before executing. Run `arcmark schema --all` for the complete command catalog.
- **Dry-run before mutating:** Always use `--dry-run` for create, rename, delete, move, and other write operations to validate before execution.
- **Field masks:** Use `--fields` on list commands to limit response size and protect context windows. Example: `--fields id,name,url`
- **Confirm destructive operations:** Always dry-run `workspace delete`, `folder delete`, `dedupe --delete`, and `import` before executing without `--dry-run`.
- **Workspace scoping:** Most node operations require `--workspace` to target a specific workspace. If omitted, the first workspace is used.
- **References:** Workspace and node references accept UUID (exact) or name (case-insensitive match). Use UUIDs when names are ambiguous.

## Core Syntax

```bash
arcmark <resource> <action> [arguments] [flags]
```

## Resources

- `workspace`: list, create, rename, delete, color, reorder, select, browser-profile
- `link`: list, add, rename, edit-url, delete, move, icon, pin, unpin
- `folder`: list, add, rename, delete, move, expand, collapse
- `search`: cross-workspace title+URL search
- `import`: arc, chrome, txt formats
- `export`: json, markdown formats
- `dedupe`: duplicate URL detection and removal
- `group`: group nodes into a new folder
- `move`: bulk cross-workspace move
- `schema`: command introspection for agent discovery

## Key Flags

- `--json`: Force JSON output (auto-detected when piped)
- `--format json|table`: Explicit output format
- `--dry-run`: Validate without persisting
- `--data-dir <path>`: Override data directory
- `--fields <list>`: Limit output fields (context window protection)
- `--limit <n>`: Cap result count
- `--workspace <ref>`: Target workspace (UUID or name)

## Output Behavior

- **TTY (interactive):** Table/text output by default
- **Piped (agent):** JSON output by default
- **Errors:** Structured JSON with `error`, `entity`, `reference`, `suggestions`, `hint` fields
- **Mutations:** Return entity data in JSON envelope: `{"status": "ok", "message": "...", "entity": {...}}`
- **Dry-run:** Returns `{"action": "...", "description": "...", "valid": true, "warnings": [...]}`
