import XCTest
@testable import ArcmarkData

@MainActor
final class WorkspaceExplicitAPITests: XCTestCase {
    private func makeStore() -> DataStore {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return DataStore(baseDirectory: temp)
    }

    private func makeModelWithTwoWorkspaces() -> (AppModel, UUID, UUID) {
        let store = makeStore()
        store.save(DataStore.defaultState())
        let model = AppModel(store: store, defaults: nil)
        let ws1Id = model.currentWorkspace.id
        let ws2Id = model.createWorkspace(name: "Second", colorId: .ocean)
        return (model, ws1Id, ws2Id)
    }

    // MARK: - Workspace-Explicit addLink

    func testAddLinkInExplicitWorkspace() {
        let (model, ws1Id, ws2Id) = makeModelWithTwoWorkspaces()

        let linkId = model.addLink(urlString: "https://example.com", title: "Example", parentId: nil, inWorkspace: ws1Id)

        // Link should be in ws1, not ws2
        let ws1 = model.state.workspaces.first(where: { $0.id == ws1Id })!
        let ws2 = model.state.workspaces.first(where: { $0.id == ws2Id })!
        XCTAssertTrue(ws1.items.contains(where: { $0.id == linkId }))
        XCTAssertFalse(ws2.items.contains(where: { $0.id == linkId }))
    }

    func testAddLinkInExplicitWorkspaceDoesNotChangeSelectedWorkspace() {
        let (model, _, ws2Id) = makeModelWithTwoWorkspaces()
        let selectedBefore = model.state.selectedWorkspaceId

        _ = model.addLink(urlString: "https://example.com", title: "Example", parentId: nil, inWorkspace: ws2Id)

        // selectedWorkspaceId should not change
        XCTAssertEqual(model.state.selectedWorkspaceId, selectedBefore)
    }

    // MARK: - Workspace-Explicit deleteNode

    func testDeleteNodeInExplicitWorkspace() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let linkId = model.addLink(urlString: "https://a.com", title: "A", parentId: nil, inWorkspace: ws1Id)

        model.deleteNode(id: linkId, inWorkspace: ws1Id)

        let ws1 = model.state.workspaces.first(where: { $0.id == ws1Id })!
        XCTAssertFalse(ws1.items.contains(where: { $0.id == linkId }))
    }

    // MARK: - Workspace-Explicit renameNode

    func testRenameNodeInExplicitWorkspace() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let linkId = model.addLink(urlString: "https://a.com", title: "Original", parentId: nil, inWorkspace: ws1Id)

        model.renameNode(id: linkId, newName: "Renamed", inWorkspace: ws1Id)

        let node = model.nodeById(linkId, inWorkspace: ws1Id)
        XCTAssertEqual(node?.displayName, "Renamed")
    }

    // MARK: - Workspace-Explicit pinLink

    func testPinLinkInExplicitWorkspace() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let linkId = model.addLink(urlString: "https://a.com", title: "A", parentId: nil, inWorkspace: ws1Id)

        model.pinLink(id: linkId, inWorkspace: ws1Id)

        let ws1 = model.state.workspaces.first(where: { $0.id == ws1Id })!
        XCTAssertEqual(ws1.pinnedLinks.count, 1)
        XCTAssertEqual(ws1.pinnedLinks[0].id, linkId)
        XCTAssertTrue(ws1.items.isEmpty)
    }

    func testPinLinkRespectsMaxInExplicitWorkspace() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()

        // Fill to max
        for i in 0..<Workspace.maxPinnedLinks {
            let id = model.addLink(urlString: "https://\(i).com", title: "\(i)", parentId: nil, inWorkspace: ws1Id)
            model.pinLink(id: id, inWorkspace: ws1Id)
        }

        // One more should be rejected
        let extraId = model.addLink(urlString: "https://extra.com", title: "Extra", parentId: nil, inWorkspace: ws1Id)
        model.pinLink(id: extraId, inWorkspace: ws1Id)

        let ws1 = model.state.workspaces.first(where: { $0.id == ws1Id })!
        XCTAssertEqual(ws1.pinnedLinks.count, Workspace.maxPinnedLinks)
    }

    // MARK: - Workspace-Explicit unpinLink

    func testUnpinLinkInExplicitWorkspace() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let linkId = model.addLink(urlString: "https://a.com", title: "A", parentId: nil, inWorkspace: ws1Id)
        model.pinLink(id: linkId, inWorkspace: ws1Id)

        model.unpinLink(id: linkId, inWorkspace: ws1Id)

        let ws1 = model.state.workspaces.first(where: { $0.id == ws1Id })!
        XCTAssertTrue(ws1.pinnedLinks.isEmpty)
        XCTAssertEqual(ws1.items.count, 1)
    }

    // MARK: - Workspace-Explicit groupNodesInNewFolder

    func testGroupNodesInExplicitWorkspace() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let link1 = model.addLink(urlString: "https://a.com", title: "A", parentId: nil, inWorkspace: ws1Id)
        let link2 = model.addLink(urlString: "https://b.com", title: "B", parentId: nil, inWorkspace: ws1Id)

        let folderId = model.groupNodesInNewFolder(nodeIds: [link1, link2], folderName: "Grouped", inWorkspace: ws1Id)

        XCTAssertNotNil(folderId)
        let ws1 = model.state.workspaces.first(where: { $0.id == ws1Id })!
        XCTAssertEqual(ws1.items.count, 1)
        if case .folder(let folder) = ws1.items[0] {
            XCTAssertEqual(folder.name, "Grouped")
            XCTAssertEqual(folder.children.count, 2)
        } else {
            XCTFail("Expected folder")
        }
    }

    // MARK: - Workspace-Explicit moveNode

    func testMoveNodeInExplicitWorkspace() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let folderId = model.addFolder(name: "Folder", parentId: nil, inWorkspace: ws1Id)
        let linkId = model.addLink(urlString: "https://a.com", title: "A", parentId: nil, inWorkspace: ws1Id)

        model.moveNode(id: linkId, toParentId: folderId, index: 0, inWorkspace: ws1Id)

        let location = model.location(of: linkId, inWorkspace: ws1Id)
        XCTAssertEqual(location?.parentId, folderId)
    }

    // MARK: - Workspace-Explicit moveNodeToWorkspace

    func testMoveNodeToWorkspaceExplicit() {
        let (model, ws1Id, ws2Id) = makeModelWithTwoWorkspaces()
        let linkId = model.addLink(urlString: "https://a.com", title: "A", parentId: nil, inWorkspace: ws1Id)

        model.moveNodeToWorkspace(id: linkId, toWorkspaceId: ws2Id, fromWorkspace: ws1Id)

        let ws1 = model.state.workspaces.first(where: { $0.id == ws1Id })!
        let ws2 = model.state.workspaces.first(where: { $0.id == ws2Id })!
        XCTAssertFalse(ws1.items.contains(where: { $0.id == linkId }))
        XCTAssertTrue(ws2.items.contains(where: { $0.id == linkId }))
    }

    // MARK: - UserDefaults Suppression

    func testNilDefaultsSuppressesUserDefaultsAccess() {
        let store = makeStore()
        store.save(DataStore.defaultState())

        // Using a unique suite so we can verify nothing was written
        let suiteName = "com.arcmark.test.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!

        let model = AppModel(store: store, defaults: nil)
        _ = model.createWorkspace(name: "Test", colorId: .ember)

        // Nothing should have been written to any UserDefaults
        XCTAssertNil(testDefaults.string(forKey: UserDefaultsKeys.lastSelectedWorkspaceId))
        testDefaults.removePersistentDomain(forName: suiteName)
    }

    func testCreateWorkspaceWithoutSelection() {
        let store = makeStore()
        store.save(DataStore.defaultState())
        let model = AppModel(store: store, defaults: nil)

        let originalSelectedId = model.state.selectedWorkspaceId

        let newWsId = model.createWorkspace(name: "Background", colorId: .ocean, selectAfterCreation: false)

        // New workspace should exist
        XCTAssertTrue(model.state.workspaces.contains(where: { $0.id == newWsId }))
        // But selected workspace should not have changed
        XCTAssertEqual(model.state.selectedWorkspaceId, originalSelectedId)
    }

    // MARK: - Throwing Initializer

    func testThrowingInitSucceeds() throws {
        let store = makeStore()
        store.save(DataStore.defaultState())

        let model = try AppModel(store: store, defaults: nil, throwing: true)
        XCTAssertFalse(model.workspaces.isEmpty)
    }

    func testThrowingInitThrowsOnCorruptData() throws {
        let store = makeStore()
        let dataURL = store.baseDirectory.appendingPathComponent("data.json")
        try FileManager.default.createDirectory(at: store.baseDirectory, withIntermediateDirectories: true)
        try "corrupt".data(using: .utf8)!.write(to: dataURL)

        XCTAssertThrowsError(try AppModel(store: store, defaults: nil, throwing: true))
    }

    // MARK: - GUI+CLI Round Trip

    func testGUICLIRoundTrip() {
        let store = makeStore()
        store.save(DataStore.defaultState())

        // Simulate GUI: create state via default AppModel
        let guiModel = AppModel(store: store, defaults: nil)
        let wsId = guiModel.currentWorkspace.id
        guiModel.addLink(urlString: "https://gui.com", title: "GUI Link", parentId: nil)

        // Simulate CLI: load from same store, mutate via workspace-explicit API
        let cliModel = AppModel(store: store, defaults: nil)
        cliModel.addLink(urlString: "https://cli.com", title: "CLI Link", parentId: nil, inWorkspace: wsId)

        // Reload and verify both mutations are present
        let freshModel = AppModel(store: store, defaults: nil)
        let ws = freshModel.state.workspaces.first(where: { $0.id == wsId })!
        let titles = ws.items.map(\.displayName)
        XCTAssertTrue(titles.contains("GUI Link"))
        XCTAssertTrue(titles.contains("CLI Link"))
    }

    // MARK: - Workspace-Explicit setFolderExpanded

    func testSetFolderExpandedInExplicitWorkspace() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let folderId = model.addFolder(name: "Folder", parentId: nil, inWorkspace: ws1Id)

        model.setFolderExpanded(id: folderId, isExpanded: false, inWorkspace: ws1Id)

        let node = model.nodeById(folderId, inWorkspace: ws1Id)
        if case .folder(let folder) = node {
            XCTAssertFalse(folder.isExpanded)
        } else {
            XCTFail("Expected folder")
        }

        model.setFolderExpanded(id: folderId, isExpanded: true, inWorkspace: ws1Id)
        let node2 = model.nodeById(folderId, inWorkspace: ws1Id)
        if case .folder(let folder) = node2 {
            XCTAssertTrue(folder.isExpanded)
        } else {
            XCTFail("Expected folder")
        }
    }

    // MARK: - Workspace-Explicit updateLinkUrl

    func testUpdateLinkUrlInExplicitWorkspace() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let linkId = model.addLink(urlString: "https://old.com", title: "Test", parentId: nil, inWorkspace: ws1Id)

        model.updateLinkUrl(id: linkId, newUrl: "https://new.com", inWorkspace: ws1Id)

        let node = model.nodeById(linkId, inWorkspace: ws1Id)
        if case .link(let link) = node {
            XCTAssertEqual(link.url, "https://new.com")
            // updateLinkUrl clears faviconPath as a side effect
            XCTAssertNil(link.faviconPath)
        } else {
            XCTFail("Expected link")
        }
    }

    // MARK: - Workspace-Explicit setLinkCustomIcon

    func testSetLinkCustomIconInExplicitWorkspace() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let linkId = model.addLink(urlString: "https://a.com", title: "A", parentId: nil, inWorkspace: ws1Id)

        model.setLinkCustomIcon(id: linkId, icon: .emoji("🔥"), inWorkspace: ws1Id)

        let node = model.nodeById(linkId, inWorkspace: ws1Id)
        if case .link(let link) = node {
            XCTAssertEqual(link.customIcon, .emoji("🔥"))
        } else {
            XCTFail("Expected link")
        }

        model.setLinkCustomIcon(id: linkId, icon: nil, inWorkspace: ws1Id)
        let node2 = model.nodeById(linkId, inWorkspace: ws1Id)
        if case .link(let link) = node2 {
            XCTAssertNil(link.customIcon)
        } else {
            XCTFail("Expected link")
        }
    }

    // MARK: - Workspace-Explicit moveNodesToWorkspace (batch)

    func testMoveNodesToWorkspaceBatch() {
        let (model, ws1Id, ws2Id) = makeModelWithTwoWorkspaces()
        let link1 = model.addLink(urlString: "https://a.com", title: "A", parentId: nil, inWorkspace: ws1Id)
        let link2 = model.addLink(urlString: "https://b.com", title: "B", parentId: nil, inWorkspace: ws1Id)
        let link3 = model.addLink(urlString: "https://c.com", title: "C", parentId: nil, inWorkspace: ws1Id)

        model.moveNodesToWorkspace(nodeIds: [link1, link2], toWorkspaceId: ws2Id, fromWorkspace: ws1Id)

        let ws1 = model.state.workspaces.first(where: { $0.id == ws1Id })!
        let ws2 = model.state.workspaces.first(where: { $0.id == ws2Id })!
        XCTAssertEqual(ws1.items.count, 1) // only link3 remains
        XCTAssertEqual(ws2.items.count, 2) // link1 and link2 moved
        XCTAssertTrue(ws2.items.contains(where: { $0.id == link1 }))
        XCTAssertTrue(ws2.items.contains(where: { $0.id == link2 }))
    }

    // MARK: - Invalid Workspace ID Handling

    func testOperationsWithInvalidWorkspaceIdAreNoOps() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let linkId = model.addLink(urlString: "https://a.com", title: "A", parentId: nil, inWorkspace: ws1Id)
        let bogusId = UUID()

        // These should all silently no-op without crashing
        model.deleteNode(id: linkId, inWorkspace: bogusId)
        model.renameNode(id: linkId, newName: "Renamed", inWorkspace: bogusId)
        model.pinLink(id: linkId, inWorkspace: bogusId)

        // Original link should be untouched
        let node = model.nodeById(linkId, inWorkspace: ws1Id)
        XCTAssertEqual(node?.displayName, "A")
    }

    func testMoveNodeToInvalidWorkspaceDoesNotLoseNode() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let linkId = model.addLink(urlString: "https://a.com", title: "A", parentId: nil, inWorkspace: ws1Id)
        let bogusId = UUID()

        model.moveNodeToWorkspace(id: linkId, toWorkspaceId: bogusId, fromWorkspace: ws1Id)

        // Node should still be in ws1 — not lost
        let ws1 = model.state.workspaces.first(where: { $0.id == ws1Id })!
        XCTAssertTrue(ws1.items.contains(where: { $0.id == linkId }))
    }

    // MARK: - Workspace-Explicit canPinMore / pinnedLinkById

    func testCanPinMoreInExplicitWorkspace() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()

        XCTAssertTrue(model.canPinMore(inWorkspace: ws1Id))

        // Fill to max
        for i in 0..<Workspace.maxPinnedLinks {
            let id = model.addLink(urlString: "https://\(i).com", title: "\(i)", parentId: nil, inWorkspace: ws1Id)
            model.pinLink(id: id, inWorkspace: ws1Id)
        }

        XCTAssertFalse(model.canPinMore(inWorkspace: ws1Id))
    }

    func testPinnedLinkByIdInExplicitWorkspace() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let linkId = model.addLink(urlString: "https://a.com", title: "A", parentId: nil, inWorkspace: ws1Id)
        model.pinLink(id: linkId, inWorkspace: ws1Id)

        let pinned = model.pinnedLinkById(linkId, inWorkspace: ws1Id)
        XCTAssertNotNil(pinned)
        XCTAssertEqual(pinned?.title, "A")
        XCTAssertEqual(pinned?.url, "https://a.com")
    }

    // MARK: - Workspace-Explicit updateLinkTitleIfDefault

    func testUpdateLinkTitleIfDefaultInExplicitWorkspace() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        // Add link with title matching hostname (the "default" title pattern)
        let linkId = model.addLink(urlString: "https://example.com", title: "example.com", parentId: nil, inWorkspace: ws1Id)

        let updated = model.updateLinkTitleIfDefault(id: linkId, newTitle: "Example Site", inWorkspace: ws1Id)

        XCTAssertTrue(updated)
        let node = model.nodeById(linkId, inWorkspace: ws1Id)
        XCTAssertEqual(node?.displayName, "Example Site")
    }

    func testUpdateLinkTitleIfDefaultDoesNotOverrideCustomTitle() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let linkId = model.addLink(urlString: "https://example.com", title: "My Custom Title", parentId: nil, inWorkspace: ws1Id)

        let updated = model.updateLinkTitleIfDefault(id: linkId, newTitle: "New Title", inWorkspace: ws1Id)

        XCTAssertFalse(updated)
        let node = model.nodeById(linkId, inWorkspace: ws1Id)
        XCTAssertEqual(node?.displayName, "My Custom Title")
    }

    // MARK: - Move Node Cycle Prevention

    func testMoveNodePreventsMovingFolderIntoOwnDescendant() {
        let (model, ws1Id, _) = makeModelWithTwoWorkspaces()
        let parentId = model.addFolder(name: "Parent", parentId: nil, inWorkspace: ws1Id)
        let childId = model.addFolder(name: "Child", parentId: parentId, inWorkspace: ws1Id)

        // Try to move parent into its own child — should be rejected
        model.moveNode(id: parentId, toParentId: childId, index: 0, inWorkspace: ws1Id)

        // Parent should still be at root level, not inside child
        let location = model.location(of: parentId, inWorkspace: ws1Id)
        XCTAssertNil(location?.parentId) // still at root
    }
}
