import XCTest
@testable import ArcmarkData

@MainActor
final class DataStoreErrorTests: XCTestCase {
    private func makeStore() -> DataStore {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return DataStore(baseDirectory: temp)
    }

    // MARK: - trySave

    func testTrySaveSucceeds() throws {
        let store = makeStore()
        let state = DataStore.defaultState()
        XCTAssertNoThrow(try store.trySave(state))
    }

    func testTrySaveThrowsOnReadOnlyDirectory() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        // Make directory read-only
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: temp.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.path)
            try? FileManager.default.removeItem(at: temp)
        }

        let store = DataStore(baseDirectory: temp)
        let state = DataStore.defaultState()

        XCTAssertThrowsError(try store.trySave(state))
    }

    // MARK: - tryLoad

    func testTryLoadSucceeds() throws {
        let store = makeStore()
        let state = DataStore.defaultState()
        try store.trySave(state)

        let loaded = try store.tryLoad()
        XCTAssertEqual(loaded.workspaces.count, state.workspaces.count)
        XCTAssertEqual(loaded.schemaVersion, state.schemaVersion)
    }

    func testTryLoadThrowsOnMalformedJSON() throws {
        let store = makeStore()
        let dataURL = store.baseDirectory.appendingPathComponent("data.json")

        // Write invalid JSON
        try FileManager.default.createDirectory(at: store.baseDirectory, withIntermediateDirectories: true)
        try "{ this is not valid json".data(using: .utf8)!.write(to: dataURL)

        XCTAssertThrowsError(try store.tryLoad())
    }

    func testTryLoadThrowsOnSchemaMismatch() throws {
        let store = makeStore()
        let dataURL = store.baseDirectory.appendingPathComponent("data.json")

        // Write valid JSON that doesn't match AppState schema
        try FileManager.default.createDirectory(at: store.baseDirectory, withIntermediateDirectories: true)
        let badSchema = """
        {"schemaVersion": "not_an_int", "workspaces": []}
        """
        try badSchema.data(using: .utf8)!.write(to: dataURL)

        XCTAssertThrowsError(try store.tryLoad())
    }

    func testTryLoadReturnsDefaultForMissingFile() throws {
        let store = makeStore()

        // No file exists yet — should create default and return it
        let loaded = try store.tryLoad()
        XCTAssertEqual(loaded.workspaces.count, 1)
        XCTAssertEqual(loaded.workspaces[0].name, "Inbox")
    }

    // MARK: - Non-throwing variants unchanged

    func testLoadSilentlyFallsBackOnCorruptData() {
        let store = makeStore()
        let dataURL = store.baseDirectory.appendingPathComponent("data.json")

        try? FileManager.default.createDirectory(at: store.baseDirectory, withIntermediateDirectories: true)
        try? "corrupt data".data(using: .utf8)!.write(to: dataURL)

        // Non-throwing load should return default state, not crash
        let loaded = store.load()
        XCTAssertEqual(loaded.workspaces.count, 1)
        XCTAssertEqual(loaded.workspaces[0].name, "Inbox")
    }
}
