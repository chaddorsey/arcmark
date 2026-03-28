import XCTest
@testable import ArcmarkCLI
@testable import ArcmarkData

@MainActor
final class ReferenceResolverTests: XCTestCase {

    private func makeState(workspaces: [Workspace]) -> AppState {
        AppState(schemaVersion: 1, workspaces: workspaces, selectedWorkspaceId: workspaces.first?.id, isSettingsSelected: false)
    }

    private func makeWorkspace(name: String, id: UUID = UUID()) -> Workspace {
        Workspace(id: id, name: name, colorId: .ember, items: [])
    }

    // MARK: - Workspace Resolution

    func testResolveWorkspaceByUUID() throws {
        let ws = makeWorkspace(name: "Work")
        let state = makeState(workspaces: [ws])

        let resolved = try ReferenceResolver.resolveWorkspace(ws.id.uuidString, in: state)
        XCTAssertEqual(resolved.id, ws.id)
    }

    func testResolveWorkspaceByExactName() throws {
        let ws = makeWorkspace(name: "Work")
        let state = makeState(workspaces: [ws])

        let resolved = try ReferenceResolver.resolveWorkspace("Work", in: state)
        XCTAssertEqual(resolved.id, ws.id)
    }

    func testResolveWorkspaceCaseInsensitive() throws {
        let ws = makeWorkspace(name: "Work")
        let state = makeState(workspaces: [ws])

        let resolved = try ReferenceResolver.resolveWorkspace("work", in: state)
        XCTAssertEqual(resolved.id, ws.id)
    }

    func testResolveWorkspaceNotFoundThrows() {
        let state = makeState(workspaces: [makeWorkspace(name: "Work")])

        XCTAssertThrowsError(try ReferenceResolver.resolveWorkspace("Missing", in: state)) { error in
            guard case CLIError.notFound(let entity, let ref, _) = error else {
                XCTFail("Expected notFound, got \(error)"); return
            }
            XCTAssertEqual(entity, "workspace")
            XCTAssertEqual(ref, "Missing")
        }
    }

    func testResolveWorkspaceNotFoundIncludesSuggestions() {
        let state = makeState(workspaces: [makeWorkspace(name: "Workshop"), makeWorkspace(name: "Personal")])

        XCTAssertThrowsError(try ReferenceResolver.resolveWorkspace("work", in: state)) { error in
            guard case CLIError.notFound(_, _, let suggestions) = error else {
                XCTFail("Expected notFound"); return
            }
            XCTAssertTrue(suggestions.contains("Workshop"))
        }
    }

    func testResolveWorkspaceAmbiguousThrowsWithUUIDs() {
        let ws1 = makeWorkspace(name: "Work")
        let ws2 = makeWorkspace(name: "Work")
        let state = makeState(workspaces: [ws1, ws2])

        XCTAssertThrowsError(try ReferenceResolver.resolveWorkspace("Work", in: state)) { error in
            guard case CLIError.ambiguousReference(let entity, _, let candidates) = error else {
                XCTFail("Expected ambiguousReference, got \(error)"); return
            }
            XCTAssertEqual(entity, "workspace")
            XCTAssertEqual(candidates.count, 2)
            // Candidates should include UUID prefixes for disambiguation
            XCTAssertTrue(candidates[0].contains("..."))
            XCTAssertTrue(candidates[1].contains("..."))
        }
    }

    func testResolveWorkspaceByUUIDWhenNameIsAmbiguous() throws {
        let ws1 = makeWorkspace(name: "Work")
        let ws2 = makeWorkspace(name: "Work")
        let state = makeState(workspaces: [ws1, ws2])

        // UUID resolution should bypass name ambiguity
        let resolved = try ReferenceResolver.resolveWorkspace(ws2.id.uuidString, in: state)
        XCTAssertEqual(resolved.id, ws2.id)
    }

    // MARK: - Node Resolution

    func testResolveNodeByUUIDInItems() throws {
        let link = Link(id: UUID(), title: "Example", url: "https://example.com")
        let ws = Workspace(id: UUID(), name: "Work", colorId: .ember, items: [.link(link)])

        let result = try ReferenceResolver.resolveNode(link.id.uuidString, in: ws)
        XCTAssertEqual(result.node.id, link.id)
        XCTAssertFalse(result.isPinned)
    }

    func testResolveNodeByUUIDInPinnedLinks() throws {
        let link = Link(id: UUID(), title: "Pinned", url: "https://pinned.com")
        let ws = Workspace(id: UUID(), name: "Work", colorId: .ember, items: [], pinnedLinks: [link])

        let result = try ReferenceResolver.resolveNode(link.id.uuidString, in: ws)
        XCTAssertEqual(result.node.id, link.id)
        XCTAssertTrue(result.isPinned)
    }

    func testResolveNodeByName() throws {
        let link = Link(id: UUID(), title: "Example", url: "https://example.com")
        let ws = Workspace(id: UUID(), name: "Work", colorId: .ember, items: [.link(link)])

        let result = try ReferenceResolver.resolveNode("Example", in: ws)
        XCTAssertEqual(result.node.id, link.id)
    }

    func testResolveNodeNotFoundThrows() {
        let ws = Workspace(id: UUID(), name: "Work", colorId: .ember, items: [])

        XCTAssertThrowsError(try ReferenceResolver.resolveNode("Missing", in: ws)) { error in
            guard case CLIError.notFound = error else {
                XCTFail("Expected notFound"); return
            }
        }
    }

    // MARK: - Folder Path Resolution

    func testResolveFolderSingleSegment() throws {
        let folder = Folder(id: UUID(), name: "APIs", children: [], isExpanded: true)
        let ws = Workspace(id: UUID(), name: "Work", colorId: .ember, items: [.folder(folder)])

        let result = try ReferenceResolver.resolveFolder(path: "APIs", in: ws)
        XCTAssertEqual(result.id, folder.id)
    }

    func testResolveFolderMultiSegment() throws {
        let inner = Folder(id: UUID(), name: "Internal", children: [], isExpanded: true)
        let outer = Folder(id: UUID(), name: "APIs", children: [.folder(inner)], isExpanded: true)
        let ws = Workspace(id: UUID(), name: "Work", colorId: .ember, items: [.folder(outer)])

        let result = try ReferenceResolver.resolveFolder(path: "APIs/Internal", in: ws)
        XCTAssertEqual(result.id, inner.id)
    }

    func testResolveFolderNotFoundThrows() {
        let ws = Workspace(id: UUID(), name: "Work", colorId: .ember, items: [])

        XCTAssertThrowsError(try ReferenceResolver.resolveFolder(path: "Missing", in: ws)) { error in
            guard case CLIError.notFound = error else {
                XCTFail("Expected notFound"); return
            }
        }
    }
}
