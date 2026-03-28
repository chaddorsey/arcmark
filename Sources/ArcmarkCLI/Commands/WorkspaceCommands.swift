import ArgumentParser
import ArcmarkData
import Foundation

struct WorkspaceGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workspace",
        abstract: "Manage workspaces.",
        subcommands: [
            List.self,
            Create.self,
            Rename.self,
            Delete.self,
            Color.self,
            Reorder.self,
            Select.self,
            BrowserProfile.self,
        ]
    )

    // MARK: - workspace list

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all workspaces."
        )

        @OptionGroup var globals: GlobalOptions

        @Option(name: .long, help: "Limit output to specific fields (comma-separated: id, name, colorId, colorName, itemCount, pinnedCount, isSelected).")
        var fields: String?

        @Option(name: .long, help: "Maximum number of workspaces to return.")
        var limit: Int?

        mutating func run() async throws {
            if let limit, limit < 1 {
                throw CLIError.invalidInput(field: "limit", value: String(limit), reason: "must be a positive integer")
            }

            let model = try await globals.makeModel()
            let state = await model.state
            let workspaces = state.workspaces
            let format = globals.effectiveFormat

            let ws = if let limit { Array(workspaces.prefix(limit)) } else { workspaces }

            var entries: [WorkspaceEntry] = []
            for workspace in ws {
                entries.append(WorkspaceEntry.from(workspace, selectedId: state.selectedWorkspaceId))
            }

            if let fields {
                try WorkspaceEntry.validateFields(fields)
            }

            let output = WorkspaceListOutput(entries: entries, fields: fields)
            OutputFormatter.print(output, format: format)
        }
    }

    // MARK: - workspace create

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new workspace."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Name for the new workspace.")
        var name: String

        @Option(name: .long, help: "Workspace color: ember (Blush), ruby (Apricot), coral (Butter), tangerine (Leaf), moss (Mint), ocean (Sky), indigo (Periwinkle), graphite (Lavender).")
        var color: String = "ember"

        mutating func run() async throws {
            try InputValidator.validateNotEmpty(name, field: "name")
            try InputValidator.validateNoControlChars(name, field: "name")
            let colorId = try InputValidator.validateColor(color)
            let format = globals.effectiveFormat

            let model = try await globals.makeModel()
            let warnings = InputValidator.checkDuplicateWorkspaceName(name, in: await model.state)

            if globals.dryRun {
                let result = DryRunResult(
                    action: "workspace.create",
                    description: "Create workspace '\(name)' with color \(colorId.rawValue) (\(colorId.name))",
                    valid: true, warnings: warnings
                )
                OutputFormatter.print(result, format: format)
                return
            }

            let id = await model.createWorkspace(name: name, colorId: colorId, selectAfterCreation: false)
            let ws = await model.state.workspaces.first(where: { $0.id == id })!
            let entry = WorkspaceEntry.from(ws, selectedId: await model.state.selectedWorkspaceId)
            OutputFormatter.print(MutationOutput(entity: entry, message: "Created workspace '\(name)'"), format: format)
        }
    }

    // MARK: - workspace rename

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Rename a workspace."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Workspace to rename (UUID or name).")
        var ref: String

        @Argument(help: "New name for the workspace.")
        var newName: String

        mutating func run() async throws {
            try InputValidator.validateNotEmpty(newName, field: "name")
            try InputValidator.validateNoControlChars(newName, field: "name")
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let ws = try ReferenceResolver.resolveWorkspace(ref, in: await model.state)

            let warnings = InputValidator.checkDuplicateWorkspaceName(newName, in: await model.state)

            if globals.dryRun {
                let result = DryRunResult(
                    action: "workspace.rename",
                    description: "Rename workspace '\(ws.name)' to '\(newName)'",
                    valid: true, warnings: warnings
                )
                OutputFormatter.print(result, format: format)
                return
            }

            await model.renameWorkspace(id: ws.id, newName: newName)
            let updated = await model.state.workspaces.first(where: { $0.id == ws.id })!
            let entry = WorkspaceEntry.from(updated, selectedId: await model.state.selectedWorkspaceId)
            OutputFormatter.print(MutationOutput(entity: entry, message: "Renamed '\(ws.name)' to '\(newName)'"), format: format)
        }
    }

    // MARK: - workspace delete

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a workspace (cannot delete the last one)."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Workspace to delete (UUID or name).")
        var ref: String

        mutating func run() async throws {
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state
            let ws = try ReferenceResolver.resolveWorkspace(ref, in: state)

            if state.workspaces.count <= 1 {
                throw CLIError.validationFailed(message: "Cannot delete the last workspace.")
            }

            let itemCount = countNodes(ws.items) + ws.pinnedLinks.count

            if globals.dryRun {
                var warnings: [String] = []
                if itemCount > 0 {
                    warnings.append("Workspace contains \(itemCount) item(s) that will be permanently deleted.")
                }
                let result = DryRunResult(
                    action: "workspace.delete",
                    description: "Delete workspace '\(ws.name)' (\(ws.id.uuidString))",
                    valid: true, warnings: warnings
                )
                OutputFormatter.print(result, format: format)
                return
            }

            await model.deleteWorkspace(id: ws.id)
            OutputFormatter.print(
                MutationOutput(entity: ["id": ws.id.uuidString, "name": ws.name], message: "Deleted workspace '\(ws.name)'"),
                format: format
            )
        }
    }

    // MARK: - workspace color

    struct Color: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Change a workspace's color."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Workspace to change (UUID or name).")
        var ref: String

        @Argument(help: "New color: ember (Blush), ruby (Apricot), coral (Butter), tangerine (Leaf), moss (Mint), ocean (Sky), indigo (Periwinkle), graphite (Lavender).")
        var color: String

        mutating func run() async throws {
            let colorId = try InputValidator.validateColor(color)
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let ws = try ReferenceResolver.resolveWorkspace(ref, in: await model.state)

            if globals.dryRun {
                let result = DryRunResult(
                    action: "workspace.color",
                    description: "Change '\(ws.name)' color from \(ws.colorId.rawValue) (\(ws.colorId.name)) to \(colorId.rawValue) (\(colorId.name))",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            await model.updateWorkspaceColor(id: ws.id, colorId: colorId)
            let updated = await model.state.workspaces.first(where: { $0.id == ws.id })!
            let entry = WorkspaceEntry.from(updated, selectedId: await model.state.selectedWorkspaceId)
            OutputFormatter.print(MutationOutput(entity: entry, message: "Changed '\(ws.name)' color to \(colorId.rawValue) (\(colorId.name))"), format: format)
        }
    }

    // MARK: - workspace reorder

    struct Reorder: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Move a workspace to a specific position (0-based index)."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Workspace to move (UUID or name).")
        var ref: String

        @Option(name: .long, help: "Target position (0-based index).")
        var to: Int

        mutating func run() async throws {
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let state = await model.state
            let ws = try ReferenceResolver.resolveWorkspace(ref, in: state)

            if to < 0 || to >= state.workspaces.count {
                throw CLIError.invalidInput(
                    field: "to",
                    value: String(to),
                    reason: "must be between 0 and \(state.workspaces.count - 1)"
                )
            }

            let currentIndex = state.workspaces.firstIndex(where: { $0.id == ws.id }) ?? 0

            if globals.dryRun {
                let result = DryRunResult(
                    action: "workspace.reorder",
                    description: "Move '\(ws.name)' from position \(currentIndex) to \(to)",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            await model.reorderWorkspace(id: ws.id, toIndex: to)
            let entry = WorkspaceEntry.from(ws, selectedId: await model.state.selectedWorkspaceId)
            OutputFormatter.print(MutationOutput(entity: entry, message: "Moved '\(ws.name)' to position \(to)"), format: format)
        }
    }

    // MARK: - workspace select

    struct Select: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set the active workspace (changes which workspace the GUI shows)."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Workspace to select (UUID or name).")
        var ref: String

        mutating func run() async throws {
            let format = globals.effectiveFormat
            // Use a single model with UserDefaults enabled — selectWorkspace intentionally
            // writes UserDefaults as the agent-to-GUI control mechanism.
            let store = globals.makeStore()
            let model = try await AppModel(store: store, defaults: .standard, throwing: true)
            let ws = try ReferenceResolver.resolveWorkspace(ref, in: await model.state)

            if globals.dryRun {
                let result = DryRunResult(
                    action: "workspace.select",
                    description: "Set active workspace to '\(ws.name)' (GUI will switch on next launch)",
                    valid: true, warnings: ["This writes to UserDefaults to change the GUI's active workspace."]
                )
                OutputFormatter.print(result, format: format)
                return
            }

            await model.selectWorkspace(id: ws.id)
            let entry = WorkspaceEntry.from(ws, selectedId: ws.id)
            OutputFormatter.print(MutationOutput(entity: entry, message: "Selected workspace '\(ws.name)'"), format: format)
        }
    }

    // MARK: - workspace browser-profile

    struct BrowserProfile: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "browser-profile",
            abstract: "Set or clear the browser profile for a workspace."
        )

        @OptionGroup var globals: GlobalOptions

        @Argument(help: "Workspace to configure (UUID or name).")
        var ref: String

        @Option(name: .long, help: "Browser bundle ID (e.g., com.google.chrome).")
        var browser: String

        @Option(name: .long, help: "Profile name to set. Omit to clear the profile.")
        var profile: String?

        mutating func run() async throws {
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let ws = try ReferenceResolver.resolveWorkspace(ref, in: await model.state)

            if globals.dryRun {
                let action = profile != nil ? "Set" : "Clear"
                let desc = "\(action) browser profile for '\(ws.name)' (browser: \(browser), profile: \(profile ?? "none"))"
                let result = DryRunResult(action: "workspace.browser-profile", description: desc, valid: true, warnings: [])
                OutputFormatter.print(result, format: format)
                return
            }

            await model.updateWorkspaceBrowserProfile(id: ws.id, bundleId: browser, profile: profile)
            let updated = await model.state.workspaces.first(where: { $0.id == ws.id })!
            let entry = WorkspaceEntry.from(updated, selectedId: await model.state.selectedWorkspaceId)
            let action = profile != nil ? "Set" : "Cleared"
            OutputFormatter.print(MutationOutput(entity: entry, message: "\(action) browser profile for '\(ws.name)'"), format: format)
        }
    }
}

// MARK: - Output Types

struct WorkspaceEntry: Codable {
    let id: String
    let name: String
    let colorId: String
    let colorName: String
    let itemCount: Int
    let pinnedCount: Int
    let isSelected: Bool

    static let validFields: Set<String> = ["id", "name", "colorId", "colorName", "itemCount", "pinnedCount", "isSelected"]

    static func from(_ workspace: Workspace, selectedId: UUID?) -> WorkspaceEntry {
        WorkspaceEntry(
            id: workspace.id.uuidString,
            name: workspace.name,
            colorId: workspace.colorId.rawValue,
            colorName: workspace.colorId.name,
            itemCount: countNodes(workspace.items),
            pinnedCount: workspace.pinnedLinks.count,
            isSelected: workspace.id == selectedId
        )
    }

    static func validateFields(_ fields: String) throws {
        let requested = Set(fields.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
        let unknown = requested.subtracting(validFields)
        if !unknown.isEmpty {
            throw CLIError.invalidInput(
                field: "fields",
                value: unknown.sorted().joined(separator: ", "),
                reason: "unknown field(s). Valid fields: \(validFields.sorted().joined(separator: ", "))"
            )
        }
    }
}

struct WorkspaceListOutput: OutputFormattable {
    let entries: [WorkspaceEntry]
    let fields: String?

    func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let fields {
            let requested = Set(fields.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
            let fullData = try encoder.encode(entries)
            var dicts = try JSONSerialization.jsonObject(with: fullData) as? [[String: Any]] ?? []
            dicts = dicts.map { dict in dict.filter { requested.contains($0.key) } }
            return try JSONSerialization.data(withJSONObject: dicts, options: [.prettyPrinted, .sortedKeys])
        }

        return try encoder.encode(entries)
    }

    func toText() -> String {
        if entries.isEmpty { return "No workspaces." }

        let requested: Set<String>? = fields.map { f in
            Set(f.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
        }

        var lines: [String] = []
        for entry in entries {
            if let requested {
                // Field-filtered table output
                var parts: [String] = []
                if requested.contains("id") { parts.append(entry.id) }
                if requested.contains("name") { parts.append(entry.name) }
                if requested.contains("colorId") { parts.append(entry.colorId) }
                if requested.contains("colorName") { parts.append(entry.colorName) }
                if requested.contains("itemCount") { parts.append("\(entry.itemCount) items") }
                if requested.contains("pinnedCount") { parts.append("\(entry.pinnedCount) pinned") }
                if requested.contains("isSelected") { parts.append(entry.isSelected ? "selected" : "") }
                lines.append("  " + parts.filter { !$0.isEmpty }.joined(separator: "  "))
            } else {
                let pinned = entry.pinnedCount > 0 ? ", \(entry.pinnedCount) pinned" : ""
                let selected = entry.isSelected ? " *" : ""
                lines.append("  \(entry.name)  (\(entry.colorName), \(entry.itemCount) items\(pinned))\(selected)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Unified output for mutation commands — single JSON object with entity data + message.
struct MutationOutput<T: Codable>: OutputFormattable {
    let entity: T
    let message: String

    func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    func toText() -> String {
        message
    }
}

extension MutationOutput: Codable {
    enum CodingKeys: String, CodingKey {
        case entity, message, status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("ok", forKey: .status)
        try container.encode(message, forKey: .message)
        try container.encode(entity, forKey: .entity)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entity = try container.decode(T.self, forKey: .entity)
        message = try container.decode(String.self, forKey: .message)
    }
}

// MARK: - Shared Helpers

func countNodes(_ nodes: [Node]) -> Int {
    nodes.reduce(0) { count, node in
        switch node {
        case .link: return count + 1
        case .folder(let folder): return count + 1 + countNodes(folder.children)
        }
    }
}
