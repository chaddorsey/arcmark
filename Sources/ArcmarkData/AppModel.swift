import Foundation
import os

@MainActor
public final class AppModel {
    private let store: DataStore
    public private(set) var state: AppState
    public var onChange: (@MainActor () -> Void)?
    private let logger = Logger(subsystem: "com.arcmark.app", category: "model")
    private let defaults: UserDefaults?

    public init(store: DataStore = DataStore(), defaults: UserDefaults? = .standard) {
        self.store = store
        self.defaults = defaults
        self.state = store.load()

        if !state.isSettingsSelected {
            if let savedId = defaults?.string(forKey: UserDefaultsKeys.lastSelectedWorkspaceId),
               let uuid = UUID(uuidString: savedId),
               state.workspaces.contains(where: { $0.id == uuid }) {
                state.selectedWorkspaceId = uuid
            }
            if state.selectedWorkspaceId == nil {
                state.selectedWorkspaceId = state.workspaces.first?.id
            }
        }
    }

    public var workspaces: [Workspace] {
        state.workspaces
    }

    public var currentWorkspace: Workspace {
        if let selected = state.selectedWorkspaceId,
           let workspace = state.workspaces.first(where: { $0.id == selected }) {
            return workspace
        }
        if let first = state.workspaces.first {
            return first
        }
        let fallback = Workspace(id: UUID(), name: "Inbox", colorId: .defaultColor(), items: [], pinnedLinks: [])
        state.workspaces = [fallback]
        state.selectedWorkspaceId = fallback.id
        persist()
        return fallback
    }

    // MARK: - Workspace Operations

    public func selectWorkspace(id: UUID) {
        guard state.workspaces.contains(where: { $0.id == id }) else { return }
        state.selectedWorkspaceId = id
        state.isSettingsSelected = false
        // selectWorkspace always writes UserDefaults — it's the agent-to-GUI control command
        defaults?.set(id.uuidString, forKey: UserDefaultsKeys.lastSelectedWorkspaceId)
        persist()
    }

    public func selectSettings() {
        state.isSettingsSelected = true
        state.selectedWorkspaceId = nil
        persist()
    }

    @discardableResult
    public func createWorkspace(name: String, colorId: WorkspaceColorId) -> UUID {
        let workspace = Workspace(id: UUID(), name: name, colorId: colorId, items: [])
        state.workspaces.append(workspace)
        state.selectedWorkspaceId = workspace.id
        defaults?.set(workspace.id.uuidString, forKey: UserDefaultsKeys.lastSelectedWorkspaceId)
        persist()
        return workspace.id
    }

    public func renameWorkspace(id: UUID, newName: String) {
        updateWorkspace(id: id) { workspace in
            workspace.name = newName
        }
    }

    public func updateWorkspaceColor(id: UUID, colorId: WorkspaceColorId) {
        updateWorkspace(id: id) { workspace in
            workspace.colorId = colorId
        }
    }

    public func updateWorkspaceBrowserProfile(id: UUID, bundleId: String, profile: String?) {
        let trimmed = profile?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        updateWorkspace(id: id) { workspace in
            if let value {
                workspace.browserProfiles[bundleId] = value
            } else {
                workspace.browserProfiles.removeValue(forKey: bundleId)
            }
        }
    }

    public func deleteWorkspace(id: UUID) {
        guard state.workspaces.count > 1 else { return }
        state.workspaces.removeAll { $0.id == id }
        if state.selectedWorkspaceId == id {
            state.selectedWorkspaceId = state.workspaces.first?.id
            if let newId = state.selectedWorkspaceId {
                defaults?.set(newId.uuidString, forKey: UserDefaultsKeys.lastSelectedWorkspaceId)
            }
        }
        persist()
    }

    public func moveWorkspace(id: UUID, direction: WorkspaceMoveDirection) {
        guard let currentIndex = state.workspaces.firstIndex(where: { $0.id == id }) else { return }

        let newIndex: Int
        switch direction {
        case .left:
            guard currentIndex > 0 else { return }
            newIndex = currentIndex - 1
        case .right:
            guard currentIndex < state.workspaces.count - 1 else { return }
            newIndex = currentIndex + 1
        }

        let workspace = state.workspaces.remove(at: currentIndex)
        state.workspaces.insert(workspace, at: newIndex)
        persist()
    }

    public func reorderWorkspace(id: UUID, toIndex: Int) {
        guard let currentIndex = state.workspaces.firstIndex(where: { $0.id == id }) else { return }
        guard toIndex >= 0 && toIndex < state.workspaces.count else { return }
        guard currentIndex != toIndex else { return }

        let workspace = state.workspaces.remove(at: currentIndex)
        state.workspaces.insert(workspace, at: toIndex)
        persist()
    }

    // MARK: - Node Operations (GUI — uses currentWorkspace)

    @discardableResult
    public func addFolder(name: String, parentId: UUID?, isExpanded: Bool = true) -> UUID {
        addFolder(name: name, parentId: parentId, isExpanded: isExpanded, inWorkspace: currentWorkspace.id)
    }

    @discardableResult
    public func addLink(urlString: String, title: String, parentId: UUID?) -> UUID {
        addLink(urlString: urlString, title: title, parentId: parentId, inWorkspace: currentWorkspace.id)
    }

    public func renameNode(id: UUID, newName: String) {
        renameNode(id: id, newName: newName, inWorkspace: currentWorkspace.id)
    }

    public func deleteNode(id: UUID) {
        deleteNode(id: id, inWorkspace: currentWorkspace.id)
    }

    public func moveNode(id: UUID, toParentId: UUID?, index: Int) {
        moveNode(id: id, toParentId: toParentId, index: index, inWorkspace: currentWorkspace.id)
    }

    public func moveNodeToWorkspace(id: UUID, workspaceId: UUID) {
        moveNodeToWorkspace(id: id, toWorkspaceId: workspaceId, fromWorkspace: currentWorkspace.id)
    }

    public func setFolderExpanded(id: UUID, isExpanded: Bool) {
        setFolderExpanded(id: id, isExpanded: isExpanded, inWorkspace: currentWorkspace.id)
    }

    public func updateLinkFaviconPath(id: UUID, path: String?) {
        updateLinkFaviconPath(id: id, path: path, inWorkspace: currentWorkspace.id)
    }

    public func updateLinkUrl(id: UUID, newUrl: String) {
        updateLinkUrl(id: id, newUrl: newUrl, inWorkspace: currentWorkspace.id)
    }

    public func updateLinkTitleIfDefault(id: UUID, newTitle: String) -> Bool {
        updateLinkTitleIfDefault(id: id, newTitle: newTitle, inWorkspace: currentWorkspace.id)
    }

    public func setLinkCustomIcon(id: UUID, icon: CustomIcon?) {
        setLinkCustomIcon(id: id, icon: icon, inWorkspace: currentWorkspace.id)
    }

    // MARK: - Pinned Links (GUI — uses currentWorkspace)

    public var canPinMore: Bool {
        currentWorkspace.pinnedLinks.count < Workspace.maxPinnedLinks
    }

    public func pinnedLinkById(_ id: UUID) -> Link? {
        currentWorkspace.pinnedLinks.first(where: { $0.id == id })
    }

    public func pinLink(id: UUID) {
        pinLink(id: id, inWorkspace: currentWorkspace.id)
    }

    public func unpinLink(id: UUID) {
        unpinLink(id: id, inWorkspace: currentWorkspace.id)
    }

    public func updatePinnedLinkFaviconPath(id: UUID, path: String?) {
        updatePinnedLinkFaviconPath(id: id, path: path, inWorkspace: currentWorkspace.id)
    }

    public func setPinnedLinkCustomIcon(id: UUID, icon: CustomIcon?) {
        setPinnedLinkCustomIcon(id: id, icon: icon, inWorkspace: currentWorkspace.id)
    }

    public func moveNodesToWorkspace(nodeIds: [UUID], toWorkspaceId: UUID) {
        moveNodesToWorkspace(nodeIds: nodeIds, toWorkspaceId: toWorkspaceId, fromWorkspace: currentWorkspace.id)
    }

    @discardableResult
    public func groupNodesInNewFolder(nodeIds: [UUID], folderName: String) -> UUID? {
        groupNodesInNewFolder(nodeIds: nodeIds, folderName: folderName, inWorkspace: currentWorkspace.id)
    }

    // MARK: - Node Lookup (GUI — uses currentWorkspace)

    public func location(of nodeId: UUID) -> NodeLocation? {
        findNodeLocation(id: nodeId, nodes: currentWorkspace.items)
    }

    public func nodeById(_ id: UUID) -> Node? {
        nodeById(id, nodes: currentWorkspace.items)
    }

    public func findNode(id: UUID, in nodes: [Node]) -> Node? {
        for node in nodes {
            if node.id == id {
                return node
            }
            if case .folder(let folder) = node,
               let found = findNode(id: id, in: folder.children) {
                return found
            }
        }
        return nil
    }

    // MARK: - Workspace-Explicit Node Operations (CLI)

    @discardableResult
    public func addFolder(name: String, parentId: UUID?, isExpanded: Bool = true, inWorkspace workspaceId: UUID) -> UUID {
        let folder = Folder(id: UUID(), name: name, children: [], isExpanded: isExpanded)
        let node = Node.folder(folder)
        insertNodeInWorkspace(node, parentId: parentId, inWorkspace: workspaceId)
        return folder.id
    }

    @discardableResult
    public func addLink(urlString: String, title: String, parentId: UUID?, inWorkspace workspaceId: UUID) -> UUID {
        let link = Link(id: UUID(), title: title, url: urlString, faviconPath: nil)
        let node = Node.link(link)
        insertNodeInWorkspace(node, parentId: parentId, inWorkspace: workspaceId)
        logger.debug("Added link \(title, privacy: .public) -> \(urlString, privacy: .public)")
        return link.id
    }

    public func renameNode(id: UUID, newName: String, inWorkspace workspaceId: UUID) {
        updateNodeInWorkspace(id: id, inWorkspace: workspaceId) { node in
            switch node {
            case .folder(var folder):
                folder.name = newName
                node = .folder(folder)
            case .link(var link):
                link.title = newName
                node = .link(link)
            }
        }
    }

    public func deleteNode(id: UUID, inWorkspace workspaceId: UUID) {
        updateWorkspace(id: workspaceId) { workspace in
            _ = self.removeNode(id: id, nodes: &workspace.items)
        }
    }

    public func moveNode(id: UUID, toParentId: UUID?, index: Int, inWorkspace workspaceId: UUID) {
        guard let ws = state.workspaces.first(where: { $0.id == workspaceId }) else { return }
        guard let location = findNodeLocation(id: id, nodes: ws.items) else { return }
        if let toParentId, isDescendant(nodeId: toParentId, in: id, nodes: ws.items) { return }

        updateWorkspace(id: workspaceId) { workspace in
            guard let removedNode = self.removeNode(id: id, nodes: &workspace.items) else { return }

            var targetIndex = max(0, index)
            if location.parentId == toParentId, location.index < targetIndex {
                targetIndex -= 1
            }

            self.insertNode(removedNode, parentId: toParentId, index: targetIndex, nodes: &workspace.items)
        }
    }

    public func moveNodeToWorkspace(id: UUID, toWorkspaceId: UUID, fromWorkspace sourceWorkspaceId: UUID) {
        guard toWorkspaceId != sourceWorkspaceId else { return }
        guard state.workspaces.contains(where: { $0.id == toWorkspaceId }) else { return }
        var removedNode: Node?
        updateWorkspace(id: sourceWorkspaceId, notify: false) { workspace in
            removedNode = self.removeNode(id: id, nodes: &workspace.items)
        }
        guard let node = removedNode else { return }

        updateWorkspace(id: toWorkspaceId) { workspace in
            workspace.items.append(node)
        }
    }

    public func setFolderExpanded(id: UUID, isExpanded: Bool, inWorkspace workspaceId: UUID) {
        updateNodeInWorkspace(id: id, inWorkspace: workspaceId) { node in
            switch node {
            case .folder(var folder):
                folder.isExpanded = isExpanded
                node = .folder(folder)
            case .link:
                break
            }
        }
    }

    public func updateLinkFaviconPath(id: UUID, path: String?, inWorkspace workspaceId: UUID) {
        if let node = nodeById(id, inWorkspace: workspaceId), case .link(let link) = node, link.faviconPath == path {
            return
        }
        updateNodeInWorkspace(id: id, inWorkspace: workspaceId) { node in
            switch node {
            case .link(var link):
                link.faviconPath = path
                node = .link(link)
            case .folder:
                break
            }
        }
    }

    public func updateLinkUrl(id: UUID, newUrl: String, inWorkspace workspaceId: UUID) {
        updateNodeInWorkspace(id: id, inWorkspace: workspaceId) { node in
            switch node {
            case .link(var link):
                link.url = newUrl
                link.faviconPath = nil
                node = .link(link)
            case .folder:
                break
            }
        }
    }

    public func setLinkCustomIcon(id: UUID, icon: CustomIcon?, inWorkspace workspaceId: UUID) {
        updateNodeInWorkspace(id: id, inWorkspace: workspaceId) { node in
            switch node {
            case .link(var link):
                link.customIcon = icon
                node = .link(link)
            case .folder:
                break
            }
        }
    }

    @discardableResult
    public func updateLinkTitleIfDefault(id: UUID, newTitle: String, inWorkspace workspaceId: UUID) -> Bool {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard let node = nodeById(id, inWorkspace: workspaceId), case .link(let link) = node else { return false }
        let defaultTitle = URL(string: link.url)?.host ?? link.url
        guard link.title == defaultTitle else { return false }
        guard link.title != trimmed else { return false }

        updateNodeInWorkspace(id: id, inWorkspace: workspaceId) { node in
            switch node {
            case .link(var link):
                link.title = trimmed
                node = .link(link)
            case .folder:
                break
            }
        }
        logger.debug("Updated title for \(link.url, privacy: .public) -> \(trimmed, privacy: .public)")
        return true
    }

    public func pinLink(id: UUID, inWorkspace workspaceId: UUID) {
        guard let ws = state.workspaces.first(where: { $0.id == workspaceId }) else { return }
        guard ws.pinnedLinks.count < Workspace.maxPinnedLinks else { return }
        guard let node = nodeById(id, nodes: ws.items), case .link(let link) = node else { return }
        guard !ws.pinnedLinks.contains(where: { $0.id == id }) else { return }

        updateWorkspace(id: workspaceId) { workspace in
            _ = self.removeNode(id: id, nodes: &workspace.items)
            workspace.pinnedLinks.append(link)
        }
    }

    public func unpinLink(id: UUID, inWorkspace workspaceId: UUID) {
        updateWorkspace(id: workspaceId) { workspace in
            guard let index = workspace.pinnedLinks.firstIndex(where: { $0.id == id }) else { return }
            let link = workspace.pinnedLinks.remove(at: index)
            workspace.items.append(.link(link))
        }
    }

    public func updatePinnedLinkFaviconPath(id: UUID, path: String?, inWorkspace workspaceId: UUID) {
        updateWorkspace(id: workspaceId) { workspace in
            guard let index = workspace.pinnedLinks.firstIndex(where: { $0.id == id }) else { return }
            workspace.pinnedLinks[index].faviconPath = path
        }
    }

    public func setPinnedLinkCustomIcon(id: UUID, icon: CustomIcon?, inWorkspace workspaceId: UUID) {
        updateWorkspace(id: workspaceId) { workspace in
            guard let index = workspace.pinnedLinks.firstIndex(where: { $0.id == id }) else { return }
            workspace.pinnedLinks[index].customIcon = icon
        }
    }

    public func moveNodesToWorkspace(nodeIds: [UUID], toWorkspaceId: UUID, fromWorkspace sourceWorkspaceId: UUID) {
        guard toWorkspaceId != sourceWorkspaceId else { return }
        guard !nodeIds.isEmpty else { return }
        guard state.workspaces.contains(where: { $0.id == toWorkspaceId }) else { return }

        var nodesToMove: [Node] = []

        updateWorkspace(id: sourceWorkspaceId, notify: false) { workspace in
            for nodeId in nodeIds {
                if let removed = self.removeNode(id: nodeId, nodes: &workspace.items) {
                    nodesToMove.append(removed)
                }
            }
        }

        updateWorkspace(id: toWorkspaceId) { workspace in
            workspace.items.append(contentsOf: nodesToMove)
        }
    }

    @discardableResult
    public func groupNodesInNewFolder(nodeIds: [UUID], folderName: String, inWorkspace workspaceId: UUID) -> UUID? {
        guard !nodeIds.isEmpty else { return nil }

        guard let ws = state.workspaces.first(where: { $0.id == workspaceId }) else { return nil }

        // Find locations BEFORE removal to determine correct insertion point
        let locations = nodeIds.compactMap { findNodeLocation(id: $0, nodes: ws.items) }

        // Determine common parent — if all selected nodes share the same parent, use it
        let parentIds = Set(locations.map { $0.parentId })
        let commonParentId: UUID? = parentIds.count == 1 ? parentIds.first! : nil

        // Insertion index: earliest position among selected nodes in the common parent
        let insertionIndex: Int? = parentIds.count == 1 ? locations.map { $0.index }.min() : nil

        var nodesToGroup: [Node] = []

        updateWorkspace(id: workspaceId, notify: false) { workspace in
            for nodeId in nodeIds {
                if let removed = self.removeNode(id: nodeId, nodes: &workspace.items) {
                    nodesToGroup.append(removed)
                }
            }
        }

        guard !nodesToGroup.isEmpty else { return nil }

        let folder = Folder(id: UUID(), name: folderName, children: nodesToGroup, isExpanded: true)

        updateWorkspace(id: workspaceId) { workspace in
            self.insertNode(.folder(folder), parentId: commonParentId, index: insertionIndex, nodes: &workspace.items)
        }

        return folder.id
    }

    // MARK: - Workspace-Explicit Node Lookup (CLI)

    public func nodeById(_ id: UUID, inWorkspace workspaceId: UUID) -> Node? {
        guard let ws = state.workspaces.first(where: { $0.id == workspaceId }) else { return nil }
        return nodeById(id, nodes: ws.items)
    }

    public func location(of nodeId: UUID, inWorkspace workspaceId: UUID) -> NodeLocation? {
        guard let ws = state.workspaces.first(where: { $0.id == workspaceId }) else { return nil }
        return findNodeLocation(id: nodeId, nodes: ws.items)
    }

    public func canPinMore(inWorkspace workspaceId: UUID) -> Bool {
        guard let ws = state.workspaces.first(where: { $0.id == workspaceId }) else { return false }
        return ws.pinnedLinks.count < Workspace.maxPinnedLinks
    }

    public func pinnedLinkById(_ id: UUID, inWorkspace workspaceId: UUID) -> Link? {
        guard let ws = state.workspaces.first(where: { $0.id == workspaceId }) else { return nil }
        return ws.pinnedLinks.first(where: { $0.id == id })
    }

    // MARK: - Private Helpers

    private func insertNodeInWorkspace(_ node: Node, parentId: UUID?, inWorkspace workspaceId: UUID) {
        updateWorkspace(id: workspaceId) { workspace in
            self.insertNode(node, parentId: parentId, index: nil, nodes: &workspace.items)
        }
    }

    private func updateNodeInWorkspace(id: UUID, inWorkspace workspaceId: UUID, notify: Bool = true, _ mutate: (inout Node) -> Void) {
        updateWorkspace(id: workspaceId, notify: notify) { workspace in
            _ = self.updateNode(id: id, nodes: &workspace.items, mutate)
        }
    }

    private func updateWorkspace(id: UUID, notify: Bool = true, _ mutate: (inout Workspace) -> Void) {
        guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return }
        mutate(&state.workspaces[index])
        persist(notify: notify)
    }

    private func persist(notify: Bool = true) {
        store.save(state)
        if notify {
            onChange?()
        }
    }

    private func insertNode(_ node: Node, parentId: UUID?, index: Int?, nodes: inout [Node]) {
        if let parentId {
            for i in nodes.indices {
                switch nodes[i] {
                case .folder(var folder):
                    if folder.id == parentId {
                        if let index {
                            let idx = max(0, min(index, folder.children.count))
                            folder.children.insert(node, at: idx)
                        } else {
                            folder.children.append(node)
                        }
                        nodes[i] = .folder(folder)
                        return
                    }
                    insertNode(node, parentId: parentId, index: index, nodes: &folder.children)
                    nodes[i] = .folder(folder)
                case .link:
                    continue
                }
            }
        } else {
            if let index {
                let idx = max(0, min(index, nodes.count))
                nodes.insert(node, at: idx)
            } else {
                nodes.append(node)
            }
        }
    }

    private func updateNode(id: UUID, nodes: inout [Node], _ mutate: (inout Node) -> Void) -> Bool {
        for index in nodes.indices {
            switch nodes[index] {
            case .link(let link):
                if link.id == id {
                    var node = nodes[index]
                    mutate(&node)
                    nodes[index] = node
                    return true
                }
            case .folder(var folder):
                if folder.id == id {
                    var node = nodes[index]
                    mutate(&node)
                    nodes[index] = node
                    return true
                }
                if updateNode(id: id, nodes: &folder.children, mutate) {
                    nodes[index] = .folder(folder)
                    return true
                }
            }
        }
        return false
    }

    private func removeNode(id: UUID, nodes: inout [Node]) -> Node? {
        for index in nodes.indices {
            switch nodes[index] {
            case .link(let link):
                if link.id == id {
                    return nodes.remove(at: index)
                }
            case .folder(var folder):
                if folder.id == id {
                    return nodes.remove(at: index)
                }
                if let removed = removeNode(id: id, nodes: &folder.children) {
                    nodes[index] = .folder(folder)
                    return removed
                }
            }
        }
        return nil
    }

    private func findNodeLocation(id: UUID, nodes: [Node], parentId: UUID? = nil) -> NodeLocation? {
        for (index, node) in nodes.enumerated() {
            switch node {
            case .link(let link):
                if link.id == id {
                    return NodeLocation(parentId: parentId, index: index)
                }
            case .folder(let folder):
                if folder.id == id {
                    return NodeLocation(parentId: parentId, index: index)
                }
                if let location = findNodeLocation(id: id, nodes: folder.children, parentId: folder.id) {
                    return location
                }
            }
        }
        return nil
    }

    private func isDescendant(nodeId: UUID, in potentialAncestorId: UUID, nodes: [Node]) -> Bool {
        guard let ancestor = nodeById(potentialAncestorId, nodes: nodes) else { return false }
        return containsNode(nodeId, within: ancestor)
    }

    private func nodeById(_ id: UUID, nodes: [Node]) -> Node? {
        for node in nodes {
            switch node {
            case .link(let link):
                if link.id == id { return node }
            case .folder(let folder):
                if folder.id == id { return node }
                if let found = nodeById(id, nodes: folder.children) {
                    return found
                }
            }
        }
        return nil
    }

    private func containsNode(_ id: UUID, within node: Node) -> Bool {
        switch node {
        case .link(let link):
            return link.id == id
        case .folder(let folder):
            if folder.id == id { return true }
            return folder.children.contains(where: { containsNode(id, within: $0) })
        }
    }
}
