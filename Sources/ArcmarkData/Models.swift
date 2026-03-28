import Foundation

public struct AppState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var workspaces: [Workspace]
    public var selectedWorkspaceId: UUID?
    public var isSettingsSelected: Bool

    public init(schemaVersion: Int, workspaces: [Workspace], selectedWorkspaceId: UUID?, isSettingsSelected: Bool) {
        self.schemaVersion = schemaVersion
        self.workspaces = workspaces
        self.selectedWorkspaceId = selectedWorkspaceId
        self.isSettingsSelected = isSettingsSelected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        workspaces = try container.decode([Workspace].self, forKey: .workspaces)
        selectedWorkspaceId = try container.decodeIfPresent(UUID.self, forKey: .selectedWorkspaceId)
        isSettingsSelected = try container.decodeIfPresent(Bool.self, forKey: .isSettingsSelected) ?? false
    }
}

public struct Workspace: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var colorId: WorkspaceColorId
    public var items: [Node]
    public var pinnedLinks: [Link]
    public var browserProfiles: [String: String]

    /// Maximum pinned links per workspace. Must match ThemeConstants.Sizing.pinnedTileColumns (4) * pinnedTileMaxRows (3).
    public static let maxPinnedLinks = 12

    public init(id: UUID, name: String, colorId: WorkspaceColorId, items: [Node], pinnedLinks: [Link] = [], browserProfiles: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.colorId = colorId
        self.items = items
        self.pinnedLinks = pinnedLinks
        self.browserProfiles = browserProfiles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorId = try container.decode(WorkspaceColorId.self, forKey: .colorId)
        items = try container.decode([Node].self, forKey: .items)
        pinnedLinks = try container.decodeIfPresent([Link].self, forKey: .pinnedLinks) ?? []

        // Support new format (browserProfiles dictionary) and migrate old format
        if let profiles = try container.decodeIfPresent([String: String].self, forKey: .browserProfiles) {
            browserProfiles = profiles
        } else if let profile = try container.decodeIfPresent(String.self, forKey: .browserProfile),
                  let bundleId = try container.decodeIfPresent(String.self, forKey: .browserProfileBundleId) {
            browserProfiles = [bundleId: profile]
        } else {
            browserProfiles = [:]
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, colorId, items, pinnedLinks, browserProfiles
        // Legacy keys for backward compatibility decoding
        case browserProfile, browserProfileBundleId
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(colorId, forKey: .colorId)
        try container.encode(items, forKey: .items)
        try container.encode(pinnedLinks, forKey: .pinnedLinks)
        try container.encode(browserProfiles, forKey: .browserProfiles)
    }
}

public enum CustomIcon: Codable, Equatable, Sendable {
    case emoji(String)
    case sfSymbol(String)
    case cachedFavicon(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum IconType: String, Codable {
        case emoji
        case sfSymbol
        case cachedFavicon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(IconType.self, forKey: .type)
        let value = try container.decode(String.self, forKey: .value)
        switch type {
        case .emoji:
            self = .emoji(value)
        case .sfSymbol:
            self = .sfSymbol(value)
        case .cachedFavicon:
            self = .cachedFavicon(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .emoji(let value):
            try container.encode(IconType.emoji, forKey: .type)
            try container.encode(value, forKey: .value)
        case .sfSymbol(let value):
            try container.encode(IconType.sfSymbol, forKey: .type)
            try container.encode(value, forKey: .value)
        case .cachedFavicon(let value):
            try container.encode(IconType.cachedFavicon, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

public struct Link: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var url: String
    public var faviconPath: String?
    public var customIcon: CustomIcon?

    public init(id: UUID, title: String, url: String, faviconPath: String? = nil, customIcon: CustomIcon? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.faviconPath = faviconPath
        self.customIcon = customIcon
    }
}

public struct Folder: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var children: [Node]
    public var isExpanded: Bool

    public init(id: UUID, name: String, children: [Node], isExpanded: Bool) {
        self.id = id
        self.name = name
        self.children = children
        self.isExpanded = isExpanded
    }
}

public enum Node: Codable, Identifiable, Equatable, Hashable, Sendable {
    case folder(Folder)
    case link(Link)

    public enum CodingKeys: String, CodingKey {
        case type
        case folder
        case link
    }

    public enum NodeType: String, Codable, Sendable {
        case folder
        case link
    }

    public var id: UUID {
        switch self {
        case .folder(let folder):
            return folder.id
        case .link(let link):
            return link.id
        }
    }

    public var displayName: String {
        switch self {
        case .folder(let folder):
            return folder.name
        case .link(let link):
            return link.title
        }
    }

    public static func == (lhs: Node, rhs: Node) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(NodeType.self, forKey: .type)
        switch type {
        case .folder:
            let folder = try container.decode(Folder.self, forKey: .folder)
            self = .folder(folder)
        case .link:
            let link = try container.decode(Link.self, forKey: .link)
            self = .link(link)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .folder(let folder):
            try container.encode(NodeType.folder, forKey: .type)
            try container.encode(folder, forKey: .folder)
        case .link(let link):
            try container.encode(NodeType.link, forKey: .type)
            try container.encode(link, forKey: .link)
        }
    }
}

public struct NodeLocation: Equatable, Sendable {
    public var parentId: UUID?
    public var index: Int

    public init(parentId: UUID?, index: Int) {
        self.parentId = parentId
        self.index = index
    }
}

public enum WorkspaceMoveDirection: Sendable {
    case left
    case right
}
