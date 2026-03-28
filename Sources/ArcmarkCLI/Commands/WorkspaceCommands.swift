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

        @Option(name: .long, help: "Limit output to specific fields (comma-separated: id, name, colorId, colorName, itemCount, pinnedCount).")
        var fields: String?

        @Option(name: .long, help: "Maximum number of workspaces to return.")
        var limit: Int?

        mutating func run() async throws {
            if let limit, limit < 1 {
                throw CLIError.invalidInput(field: "limit", value: String(limit), reason: "must be a positive integer")
            }

            let model = try await globals.makeModel()
            let workspaces = await model.workspaces
            let format = globals.effectiveFormat

            let validFields: Set<String> = ["id", "name", "colorId", "colorName", "itemCount", "pinnedCount"]
            let ws = if let limit { Array(workspaces.prefix(limit)) } else { workspaces }

            var entries: [WorkspaceEntry] = []

            for workspace in ws {
                entries.append(WorkspaceEntry(
                    id: workspace.id.uuidString,
                    name: workspace.name,
                    colorId: workspace.colorId.rawValue,
                    colorName: workspace.colorId.name,
                    itemCount: countNodes(workspace.items),
                    pinnedCount: workspace.pinnedLinks.count
                ))
            }

            if let fields {
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
            try InputValidator.validateNoControlChars(name, field: "name")
            let colorId = try InputValidator.validateColor(color)
            let format = globals.effectiveFormat

            if globals.dryRun {
                let result = DryRunResult(
                    action: "workspace.create",
                    description: "Create workspace '\(name)' with color \(colorId.rawValue) (\(colorId.name))",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            let model = try await globals.makeModel()
            let id = await model.createWorkspace(name: name, colorId: colorId, selectAfterCreation: false)

            let output = SingleValueOutput(value: ["id": id.uuidString, "name": name, "colorId": colorId.rawValue])
            OutputFormatter.print(output, format: format)

            if !globals.quiet {
                OutputFormatter.printSuccess("Created workspace '\(name)' (\(id.uuidString.prefix(8))...)", format: format, quiet: false)
            }
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
            try InputValidator.validateNoControlChars(newName, field: "name")
            let format = globals.effectiveFormat
            let model = try await globals.makeModel()
            let ws = try ReferenceResolver.resolveWorkspace(ref, in: await model.state)

            if globals.dryRun {
                let result = DryRunResult(
                    action: "workspace.rename",
                    description: "Rename workspace '\(ws.name)' to '\(newName)'",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            await model.renameWorkspace(id: ws.id, newName: newName)
            OutputFormatter.printSuccess("Renamed '\(ws.name)' to '\(newName)'", format: format, quiet: globals.quiet)
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
            OutputFormatter.printSuccess("Deleted workspace '\(ws.name)'", format: format, quiet: globals.quiet)
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
            OutputFormatter.printSuccess("Changed '\(ws.name)' color to \(colorId.rawValue) (\(colorId.name))", format: format, quiet: globals.quiet)
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

            if globals.dryRun {
                let currentIndex = state.workspaces.firstIndex(where: { $0.id == ws.id }) ?? 0
                let result = DryRunResult(
                    action: "workspace.reorder",
                    description: "Move '\(ws.name)' from position \(currentIndex) to \(to)",
                    valid: true, warnings: []
                )
                OutputFormatter.print(result, format: format)
                return
            }

            await model.reorderWorkspace(id: ws.id, toIndex: to)
            OutputFormatter.printSuccess("Moved '\(ws.name)' to position \(to)", format: format, quiet: globals.quiet)
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
            let model = try await globals.makeModel()
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

            // selectWorkspace intentionally writes UserDefaults — it's the agent-to-GUI control command.
            // We need a model with defaults enabled for this specific command.
            let store = globals.makeStore()
            let selectModel = await AppModel(store: store, defaults: .standard)
            await selectModel.selectWorkspace(id: ws.id)
            OutputFormatter.printSuccess("Selected workspace '\(ws.name)'", format: format, quiet: globals.quiet)
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
            let action = profile != nil ? "Set" : "Cleared"
            OutputFormatter.printSuccess("\(action) browser profile for '\(ws.name)'", format: format, quiet: globals.quiet)
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
        var lines: [String] = []
        for entry in entries {
            let pinned = entry.pinnedCount > 0 ? ", \(entry.pinnedCount) pinned" : ""
            lines.append("  \(entry.name)  (\(entry.colorName), \(entry.itemCount) items\(pinned))")
        }
        return lines.joined(separator: "\n")
    }
}

/// Simple key-value output for single-entity responses (create, etc.)
struct SingleValueOutput: OutputFormattable {
    let value: [String: String]

    func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    func toText() -> String {
        value.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
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
