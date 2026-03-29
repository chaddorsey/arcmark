import Foundation
import ArcmarkData

/// Collects schemas from all commands for `arcmark schema` introspection.
enum SchemaRegistry {

    static let allSchemas: [String: CommandSchema] = {
        var schemas: [String: CommandSchema] = [:]
        for schema in allCommandSchemas {
            schemas[schema.command] = schema
        }
        return schemas
    }()

    static let allCommandSchemas: [CommandSchema] = [
        // Workspace
        workspaceList, workspaceCreate, workspaceRename, workspaceDelete,
        workspaceColor, workspaceReorder, workspaceSelect, workspaceBrowserProfile,
        // Link
        linkList, linkAdd, linkRename, linkEditURL, linkDelete,
        linkMove, linkIcon, linkPin, linkUnpin,
        // Folder
        folderList, folderAdd, folderRename, folderDelete,
        folderMove, folderExpand, folderCollapse,
        // Top-level
        search, importCmd, export, dedupe, group, bulkMove,
    ]

    /// Get schemas for a resource group (e.g., "workspace" returns all workspace.* commands).
    static func schemasForResource(_ resource: String) -> [CommandSchema] {
        allCommandSchemas.filter { $0.command.hasPrefix(resource + ".") }
    }

    // MARK: - Global flags (included in every command's schema)

    static let globalFlags: [CommandSchema.FlagSchema] = [
        .init(name: "--json", help: "Output as JSON regardless of terminal type."),
        .init(name: "--format", help: "Output format: json, table."),
        .init(name: "--data-dir", help: "Override the data directory."),
        .init(name: "--quiet", help: "Suppress informational messages."),
        .init(name: "--dry-run", help: "Validate and show what would change without persisting."),
    ]

    // MARK: - Workspace Schemas

    static let workspaceList = CommandSchema(
        command: "workspace.list", description: "List all workspaces.", mutates: false,
        parameters: [
            .init(name: "fields", type: "string", required: false, help: "Comma-separated fields: id, name, colorId, colorName, itemCount, pinnedCount, isSelected.", values: nil, defaultValue: nil),
            .init(name: "limit", type: "int", required: false, help: "Maximum number of workspaces to return.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let workspaceCreate = CommandSchema(
        command: "workspace.create", description: "Create a new workspace.", mutates: true,
        parameters: [
            .init(name: "name", type: "string", required: true, help: "Name for the new workspace.", values: nil, defaultValue: nil),
            .init(name: "color", type: "enum", required: false, help: "Workspace color.", values: WorkspaceColorId.allCases.map(\.rawValue), defaultValue: "ember"),
        ],
        flags: globalFlags
    )

    static let workspaceRename = CommandSchema(
        command: "workspace.rename", description: "Rename a workspace.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Workspace to rename (UUID or name).", values: nil, defaultValue: nil),
            .init(name: "new-name", type: "string", required: true, help: "New name.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let workspaceDelete = CommandSchema(
        command: "workspace.delete", description: "Delete a workspace (cannot delete the last one).", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Workspace to delete (UUID or name).", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let workspaceColor = CommandSchema(
        command: "workspace.color", description: "Change a workspace's color.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Workspace to change (UUID or name).", values: nil, defaultValue: nil),
            .init(name: "color", type: "enum", required: true, help: "New color.", values: WorkspaceColorId.allCases.map(\.rawValue), defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let workspaceReorder = CommandSchema(
        command: "workspace.reorder", description: "Move a workspace to a specific position.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Workspace to move (UUID or name).", values: nil, defaultValue: nil),
            .init(name: "to", type: "int", required: true, help: "Target position (0-based index).", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let workspaceSelect = CommandSchema(
        command: "workspace.select", description: "Set the active workspace (changes GUI display).", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Workspace to select (UUID or name).", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let workspaceBrowserProfile = CommandSchema(
        command: "workspace.browser-profile", description: "Set or clear browser profile for a workspace.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Workspace to configure (UUID or name).", values: nil, defaultValue: nil),
            .init(name: "browser", type: "string", required: true, help: "Browser bundle ID.", values: nil, defaultValue: nil),
            .init(name: "profile", type: "string", required: false, help: "Profile name. Omit to clear.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    // MARK: - Link Schemas

    static let linkList = CommandSchema(
        command: "link.list", description: "List links in a workspace.", mutates: false,
        parameters: [
            .init(name: "workspace", type: "string", required: false, help: "Workspace to list from (UUID or name). All if omitted.", values: nil, defaultValue: nil),
            .init(name: "fields", type: "string", required: false, help: "Comma-separated fields.", values: nil, defaultValue: nil),
            .init(name: "limit", type: "int", required: false, help: "Maximum results.", values: nil, defaultValue: nil),
            .init(name: "depth", type: "int", required: false, help: "Max folder depth.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags + [.init(name: "--urls-only", help: "Output only URLs, one per line.")]
    )

    static let linkAdd = CommandSchema(
        command: "link.add", description: "Add a link to a workspace.", mutates: true,
        parameters: [
            .init(name: "url", type: "string", required: true, help: "URL to add (http/https only).", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Target workspace.", values: nil, defaultValue: nil),
            .init(name: "folder", type: "string", required: false, help: "Folder path (e.g., 'APIs/Internal').", values: nil, defaultValue: nil),
            .init(name: "title", type: "string", required: false, help: "Custom title. Auto-fetched if omitted.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let linkRename = CommandSchema(
        command: "link.rename", description: "Rename a link.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Link to rename (UUID or title).", values: nil, defaultValue: nil),
            .init(name: "new-title", type: "string", required: true, help: "New title.", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Workspace containing the link.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let linkEditURL = CommandSchema(
        command: "link.edit-url", description: "Change a link's URL.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Link to edit (UUID or title).", values: nil, defaultValue: nil),
            .init(name: "new-url", type: "string", required: true, help: "New URL (http/https only).", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Workspace containing the link.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let linkDelete = CommandSchema(
        command: "link.delete", description: "Delete a link.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Link to delete (UUID or title).", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Workspace containing the link.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let linkMove = CommandSchema(
        command: "link.move", description: "Move a link to a different location.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Link to move (UUID or title).", values: nil, defaultValue: nil),
            .init(name: "from", type: "string", required: false, help: "Source workspace.", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Target workspace for cross-workspace move.", values: nil, defaultValue: nil),
            .init(name: "folder", type: "string", required: false, help: "Target folder path.", values: nil, defaultValue: nil),
            .init(name: "at", type: "int", required: false, help: "Position (0-based index).", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let linkIcon = CommandSchema(
        command: "link.icon", description: "Set or clear a link's custom icon.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Link to modify (UUID or title).", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Workspace containing the link.", values: nil, defaultValue: nil),
            .init(name: "emoji", type: "string", required: false, help: "Set an emoji icon.", values: nil, defaultValue: nil),
            .init(name: "symbol", type: "string", required: false, help: "Set an SF Symbol icon.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags + [.init(name: "--clear", help: "Clear the custom icon.")]
    )

    static let linkPin = CommandSchema(
        command: "link.pin", description: "Pin a link.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Link to pin (UUID or title).", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Workspace containing the link.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let linkUnpin = CommandSchema(
        command: "link.unpin", description: "Unpin a link.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Link to unpin (UUID or title).", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Workspace containing the link.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    // MARK: - Folder Schemas

    static let folderList = CommandSchema(
        command: "folder.list", description: "List folder hierarchy.", mutates: false,
        parameters: [
            .init(name: "workspace", type: "string", required: false, help: "Workspace to list from.", values: nil, defaultValue: nil),
            .init(name: "depth", type: "int", required: false, help: "Maximum depth to display.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let folderAdd = CommandSchema(
        command: "folder.add", description: "Create a new folder.", mutates: true,
        parameters: [
            .init(name: "name", type: "string", required: true, help: "Name for the new folder.", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Target workspace.", values: nil, defaultValue: nil),
            .init(name: "parent", type: "string", required: false, help: "Parent folder path.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let folderRename = CommandSchema(
        command: "folder.rename", description: "Rename a folder.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Folder to rename (UUID or name).", values: nil, defaultValue: nil),
            .init(name: "new-name", type: "string", required: true, help: "New name.", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Workspace containing the folder.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let folderDelete = CommandSchema(
        command: "folder.delete", description: "Delete a folder and all contents.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Folder to delete (UUID or name).", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Workspace containing the folder.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let folderMove = CommandSchema(
        command: "folder.move", description: "Move a folder.", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Folder to move (UUID or name).", values: nil, defaultValue: nil),
            .init(name: "from", type: "string", required: false, help: "Source workspace.", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Target workspace.", values: nil, defaultValue: nil),
            .init(name: "parent", type: "string", required: false, help: "Target parent folder path.", values: nil, defaultValue: nil),
            .init(name: "at", type: "int", required: false, help: "Position (0-based index).", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let folderExpand = CommandSchema(
        command: "folder.expand", description: "Set folder to expanded state (GUI).", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Folder to expand (UUID or name).", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Workspace containing the folder.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let folderCollapse = CommandSchema(
        command: "folder.collapse", description: "Set folder to collapsed state (GUI).", mutates: true,
        parameters: [
            .init(name: "ref", type: "string", required: true, help: "Folder to collapse (UUID or name).", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Workspace containing the folder.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    // MARK: - Top-Level Schemas

    static let search = CommandSchema(
        command: "search", description: "Search links by title or URL across all workspaces.", mutates: false,
        parameters: [
            .init(name: "query", type: "string", required: true, help: "Search query.", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Limit to a workspace.", values: nil, defaultValue: nil),
            .init(name: "limit", type: "int", required: false, help: "Maximum results.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags + [.init(name: "--urls-only", help: "Output only URLs.")]
    )

    static let importCmd = CommandSchema(
        command: "import", description: "Import bookmarks from a file.", mutates: true,
        parameters: [
            .init(name: "file", type: "string", required: true, help: "Path to bookmark file.", values: nil, defaultValue: nil),
            .init(name: "format", type: "enum", required: false, help: "Import format.", values: ["arc", "chrome", "txt"], defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Target workspace (chrome/txt only).", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let export = CommandSchema(
        command: "export", description: "Export workspaces to JSON or Markdown.", mutates: false,
        parameters: [
            .init(name: "workspace", type: "string", required: false, help: "Workspace to export. All if omitted.", values: nil, defaultValue: nil),
            .init(name: "export-format", type: "enum", required: false, help: "Export format.", values: ["json", "md"], defaultValue: "json"),
            .init(name: "output", type: "string", required: false, help: "Output file path. Stdout if omitted.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags + [.init(name: "--snapshot", help: "Write a timestamped backup.")]
    )

    static let dedupe = CommandSchema(
        command: "dedupe", description: "Find duplicate URLs across workspaces.", mutates: false,
        parameters: [
            .init(name: "workspace", type: "string", required: false, help: "Limit to a workspace.", values: nil, defaultValue: nil),
            .init(name: "limit", type: "int", required: false, help: "Max duplicate groups to show.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags + [.init(name: "--delete", help: "Delete duplicates, keeping first occurrence.")]
    )

    static let group = CommandSchema(
        command: "group", description: "Group nodes into a new folder.", mutates: true,
        parameters: [
            .init(name: "refs", type: "string[]", required: true, help: "Node references to group (2+ UUIDs or titles).", values: nil, defaultValue: nil),
            .init(name: "name", type: "string", required: true, help: "Name for the new folder.", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: false, help: "Workspace containing the nodes.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )

    static let bulkMove = CommandSchema(
        command: "move", description: "Move multiple nodes to a different workspace.", mutates: true,
        parameters: [
            .init(name: "refs", type: "string[]", required: true, help: "Node references to move.", values: nil, defaultValue: nil),
            .init(name: "workspace", type: "string", required: true, help: "Target workspace.", values: nil, defaultValue: nil),
            .init(name: "from", type: "string", required: false, help: "Source workspace.", values: nil, defaultValue: nil),
        ],
        flags: globalFlags
    )
}
