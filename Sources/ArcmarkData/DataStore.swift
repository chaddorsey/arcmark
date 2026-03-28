import Foundation

public final class DataStore {
    private let fileManager = FileManager.default
    public let baseDirectory: URL
    private let dataURL: URL

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = appSupport.appendingPathComponent("Arcmark", isDirectory: true)
        }
        self.dataURL = self.baseDirectory.appendingPathComponent("data.json")
    }

    public func load() -> AppState {
        ensureDirectories()
        guard fileManager.fileExists(atPath: dataURL.path) else {
            let defaultState = Self.defaultState()
            save(defaultState)
            return defaultState
        }

        do {
            let data = try Data(contentsOf: dataURL)
            let decoder = JSONDecoder()
            let state = try decoder.decode(AppState.self, from: data)
            return state
        } catch {
            let fallback = Self.defaultState()
            save(fallback)
            return fallback
        }
    }

    public func save(_ state: AppState) {
        ensureDirectories()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: dataURL, options: [.atomic])
        } catch {
            // Failing silently to avoid crashing; this can be surfaced later in a UI.
        }
    }

    // MARK: - Throwing Variants (CLI)

    /// Load state, propagating errors instead of silently falling back to defaults.
    /// Use this in CLI contexts where silent data loss is unacceptable.
    public func tryLoad() throws -> AppState {
        ensureDirectories()
        guard fileManager.fileExists(atPath: dataURL.path) else {
            let defaultState = Self.defaultState()
            try trySave(defaultState)
            return defaultState
        }

        let data = try Data(contentsOf: dataURL)
        let decoder = JSONDecoder()
        return try decoder.decode(AppState.self, from: data)
    }

    /// Save state, propagating errors instead of silently swallowing them.
    /// Use this in CLI contexts where failed writes must produce non-zero exit codes.
    public func trySave(_ state: AppState) throws {
        ensureDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: dataURL, options: [.atomic])
    }

    // MARK: - Icons

    public func iconsDirectory() -> URL {
        let iconsURL = baseDirectory.appendingPathComponent("Icons", isDirectory: true)
        if !fileManager.fileExists(atPath: iconsURL.path) {
            try? fileManager.createDirectory(at: iconsURL, withIntermediateDirectories: true)
        }
        return iconsURL
    }

    private func ensureDirectories() {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    public static func defaultState() -> AppState {
        let workspace = Workspace(
            id: UUID(),
            name: "Inbox",
            colorId: .defaultColor(),
            items: []
        )
        return AppState(schemaVersion: 1, workspaces: [workspace], selectedWorkspaceId: workspace.id, isSettingsSelected: false)
    }
}
