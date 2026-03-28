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
}
