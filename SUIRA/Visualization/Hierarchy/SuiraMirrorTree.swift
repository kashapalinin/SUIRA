import CoreGraphics
import Foundation

/// Узел дерева, построенного через `Mirror` (поля и вложенные объекты, не граф SwiftUI).
public struct SuiraMirrorTreeNode: Identifiable {
    public let id: String
    public let title: String
    public let typeName: String
    public let valueSummary: String
    public var children: [SuiraMirrorTreeNode]

    public init(id: String, title: String, typeName: String, valueSummary: String, children: [SuiraMirrorTreeNode]) {
        self.id = id
        self.title = title
        self.typeName = typeName
        self.valueSummary = valueSummary
        self.children = children
    }

    public var tag: String {
        SuiraDebugTag.make(from: id)
    }
}

public struct SuiraViewNodeSnapshot: Identifiable, Sendable {
    public let key: String
    public let screenLabel: String
    public let path: String
    public let tag: String
    public let title: String
    public let typeName: String
    public let displayName: String
    public let signature: String

    public var id: String { key }

    public init(
        key: String,
        screenLabel: String,
        path: String,
        tag: String,
        title: String,
        typeName: String,
        displayName: String,
        signature: String
    ) {
        self.key = key
        self.screenLabel = screenLabel
        self.path = path
        self.tag = tag
        self.title = title
        self.typeName = typeName
        self.displayName = displayName
        self.signature = signature
    }
}

enum SuiraDebugTag {
    static func make(from raw: String, prefix: String = "V") -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in raw.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        let short = String(format: "%04X", Int(hash & 0xFFFF))
        return "\(prefix)-\(short)"
    }
}

public enum SuiraMirrorTreeBuilder {
    public static let maxDepth = 6
    public static let maxChildrenPerNode = 48

    /// Дерево полей и вложенных значений для одного корня (модель, struct, enum и т.д.).
    public static func buildRoot(label: String, value: Any) -> SuiraMirrorTreeNode {
        var seenAlongPath = Set<ObjectIdentifier>()
        return buildNode(
            name: label,
            value: value,
            path: label,
            depth: 0,
            seenAlongPath: &seenAlongPath
        )
    }

    private static func buildNode(
        name: String,
        value: Any,
        path: String,
        depth: Int,
        seenAlongPath: inout Set<ObjectIdentifier>
    ) -> SuiraMirrorTreeNode {
        guard depth < maxDepth else {
            return SuiraMirrorTreeNode(
                id: path,
                title: name,
                typeName: typeName(of: value),
                valueSummary: "…",
                children: []
            )
        }

        let raw = unwrapIfOptional(value) ?? value
        let mirror = Mirror(reflecting: raw)

        if mirror.displayStyle == .collection {
            let kids = mirror.children.prefix(maxChildrenPerNode).enumerated().map { idx, child in
                buildNode(
                    name: "[\(idx)]",
                    value: child.value,
                    path: "\(path)[\(idx)]",
                    depth: depth + 1,
                    seenAlongPath: &seenAlongPath
                )
            }
            return SuiraMirrorTreeNode(
                id: path,
                title: name,
                typeName: typeName(of: raw),
                valueSummary: "\(mirror.children.count) элементов",
                children: Array(kids)
            )
        }

        if mirror.displayStyle == .dictionary {
            var kids: [SuiraMirrorTreeNode] = []
            for (idx, child) in mirror.children.enumerated() {
                guard idx < maxChildrenPerNode else { break }
                let tupleChildren = Array(Mirror(reflecting: child.value).children)
                if tupleChildren.count >= 2 {
                    let k = tupleChildren[0].value
                    let v = tupleChildren[1].value
                    kids.append(
                        buildNode(
                            name: String(describing: k),
                            value: v,
                            path: "\(path).\(idx)",
                            depth: depth + 1,
                            seenAlongPath: &seenAlongPath
                        )
                    )
                }
            }
            return SuiraMirrorTreeNode(
                id: path,
                title: name,
                typeName: "Dictionary",
                valueSummary: "\(mirror.children.count) пар",
                children: kids
            )
        }

        if mirror.displayStyle == .class {
            let obj = raw as AnyObject
            let oid = ObjectIdentifier(obj)
            if seenAlongPath.contains(oid) {
                return SuiraMirrorTreeNode(
                    id: path,
                    title: name,
                    typeName: typeName(of: raw),
                    valueSummary: "(уже в пути — цикл)",
                    children: []
                )
            }
            seenAlongPath.insert(oid)
            defer { seenAlongPath.remove(oid) }
            let kids = buildMirrorChildren(
                mirror: mirror,
                path: path,
                depth: depth,
                seenAlongPath: &seenAlongPath
            )
            return SuiraMirrorTreeNode(
                id: path,
                title: name,
                typeName: typeName(of: raw),
                valueSummary: summarizeLeaf(raw),
                children: kids
            )
        }

        let kids = buildMirrorChildren(
            mirror: mirror,
            path: path,
            depth: depth,
            seenAlongPath: &seenAlongPath
        )
        return SuiraMirrorTreeNode(
            id: path,
            title: name,
            typeName: typeName(of: raw),
            valueSummary: summarizeLeaf(raw),
            children: kids
        )
    }

    private static func buildMirrorChildren(
        mirror: Mirror,
        path: String,
        depth: Int,
        seenAlongPath: inout Set<ObjectIdentifier>
    ) -> [SuiraMirrorTreeNode] {
        guard depth + 1 < maxDepth else { return [] }
        var kids: [SuiraMirrorTreeNode] = []
        for (idx, child) in mirror.children.enumerated() {
            guard idx < maxChildrenPerNode else { break }
            let cname = child.label ?? "(\(idx))"
            let cpath = "\(path).\(cname)"
            kids.append(
                buildNode(
                    name: cname,
                    value: child.value,
                    path: cpath,
                    depth: depth + 1,
                    seenAlongPath: &seenAlongPath
                )
            )
        }
        return kids
    }

    private static func unwrapIfOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return nil }
        for child in mirror.children where child.label == "some" {
            return child.value
        }
        return nil
    }

    private static func typeName(of value: Any) -> String {
        String(describing: Swift.type(of: value))
    }

    private static func summarizeLeaf(_ value: Any) -> String {
        if let v = unwrapIfOptional(value) {
            return summarizeLeaf(v)
        }
        if let v = value as? String {
            let t = v.count > 80 ? String(v.prefix(80)) + "…" : v
            return "\"\(t)\""
        }
        if value is any BinaryInteger { return String(describing: value) }
        if value is Bool { return String(describing: value) }
        if value is Double || value is Float { return String(describing: value) }
        if let v = value as? CGFloat { return String(format: "%g", Double(v)) }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .enum, let c = mirror.children.first, let lab = c.label {
            return ".\(lab)"
        }

        let s = String(describing: value)
        if s.count > 100 { return String(s.prefix(100)) + "…" }
        return s
    }
}

public enum SuiraSwiftUIViewTreeBuilder {
    public static let maxDepth = 50
    public static let maxChildrenPerNode = 64

    public static func buildRoot(label: String, view: Any) -> SuiraMirrorTreeNode {
        var seen = Set<String>()
        return buildNode(
            title: label,
            value: view,
            path: label,
            depth: 0,
            seenPaths: &seen,
            forceDisplayTypeName: typeName(of: view)
        )
    }

    public static func captureNodeSnapshots(label: String, view: Any) -> [SuiraViewNodeSnapshot] {
        let root = buildRoot(label: label, view: view)
        return flattenNodeSnapshots(screenLabel: label, root: root)
    }

    public static func flattenNodeSnapshots(screenLabel: String, root: SuiraMirrorTreeNode) -> [SuiraViewNodeSnapshot] {
        var result: [SuiraViewNodeSnapshot] = []
        collectNodeSnapshots(screenLabel: screenLabel, node: root, into: &result, isRoot: true)
        return result
    }

    private static func buildNode(
        title: String,
        value: Any,
        path: String,
        depth: Int,
        seenPaths: inout Set<String>,
        forceDisplayTypeName: String? = nil
    ) -> SuiraMirrorTreeNode {
        let raw = unwrapIfOptional(value) ?? value
        let currentTypeName = forceDisplayTypeName ?? typeName(of: raw)

        guard depth < maxDepth else {
            return SuiraMirrorTreeNode(
                id: path,
                title: title,
                typeName: simplifyViewTypeName(currentTypeName),
                valueSummary: "…",
                children: []
            )
        }

        if seenPaths.contains(path) {
            return SuiraMirrorTreeNode(
                id: path,
                title: title,
                typeName: simplifyViewTypeName(currentTypeName),
                valueSummary: "(цикл)",
                children: []
            )
        }
        seenPaths.insert(path)
        defer { seenPaths.remove(path) }

        let mirror = Mirror(reflecting: raw)
        let childValues = extractViewChildren(from: raw, mirror: mirror).prefix(maxChildrenPerNode)
        let children = childValues.enumerated().map { index, child in
            buildNode(
                title: child.title ?? defaultChildTitle(for: child.value, index: index),
                value: child.value,
                path: "\(path).\(index)",
                depth: depth + 1,
                seenPaths: &seenPaths
            )
        }

        return SuiraMirrorTreeNode(
            id: path,
            title: title,
            typeName: simplifyViewTypeName(currentTypeName),
            valueSummary: children.isEmpty ? summarizeViewLeaf(raw) : "\(children.count) дочерних view",
            children: children
        )
    }

    private static func extractViewChildren(from value: Any, mirror: Mirror) -> [(title: String?, value: Any)] {
        let type = typeName(of: value)

        if type.contains("TupleView") {
            if let tuple = mirror.children.first?.value {
                return Array(Mirror(reflecting: tuple).children).enumerated().map { index, child in
                    (child.label ?? "[\(index)]", child.value)
                }
            }
        }

        if type.contains("_ConditionalContent") {
            return mirror.children.map { child in
                (child.label, child.value)
            }
        }

        if type.contains("ModifiedContent") {
            if let content = mirror.descendant("content") {
                return [("content", content)]
            }
        }

        if let flattened = flattenWrapperChildren(from: value, mirror: mirror), !flattened.isEmpty {
            return flattened
        }

        var candidates: [(String?, Any)] = []
        for (index, child) in mirror.children.enumerated() {
            let label = child.label ?? "[\(index)]"
            if shouldSkipViewField(label: label, value: child.value) {
                continue
            }

            if let expanded = expandWrapperField(label: label, value: child.value), !expanded.isEmpty {
                candidates.append(contentsOf: expanded)
                continue
            }

            let childType = typeName(of: child.value)
            if isViewLike(childType) {
                candidates.append((label, child.value))
                continue
            }

            let discovered = discoverEmbeddedViews(
                in: child.value,
                preferredTitle: label,
                depth: 0
            )
            if !discovered.isEmpty {
                candidates.append(contentsOf: discovered)
                continue
            }

            candidates.append((label, child.value))
        }

        return candidates
    }

    private static func shouldSkipViewField(label: String, value: Any) -> Bool {
        let childType = typeName(of: value)
        if label == "modifier" { return true }
        if childType.contains("Environment") { return true }
        if childType.contains("State") { return true }
        if childType.contains("Binding") { return true }
        if childType.contains("GestureState") { return true }
        if childType.contains("Namespace") { return true }
        return false
    }

    private static func flattenWrapperChildren(from value: Any, mirror: Mirror) -> [(title: String?, value: Any)]? {
        let type = typeName(of: value)
        if !looksLikeWrapperContainer(typeName: type) { return nil }

        var flattened: [(title: String?, value: Any)] = []
        for (index, child) in mirror.children.enumerated() {
            let label = child.label ?? "[\(index)]"
            if shouldSkipViewField(label: label, value: child.value) {
                continue
            }
            if let expanded = expandWrapperField(label: label, value: child.value), !expanded.isEmpty {
                flattened.append(contentsOf: expanded)
            } else if isViewLike(typeName(of: child.value)) {
                flattened.append((label, child.value))
            }
        }

        return flattened.isEmpty ? nil : flattened
    }

    private static func discoverEmbeddedViews(
        in value: Any,
        preferredTitle: String?,
        depth: Int
    ) -> [(title: String?, value: Any)] {
        guard depth < 5 else { return [] }

        let raw = unwrapIfOptional(value) ?? value
        let rawType = typeName(of: raw)
        if isViewLike(rawType) {
            return [(preferredTitle, raw)]
        }

        let mirror = Mirror(reflecting: raw)
        guard !mirror.children.isEmpty else { return [] }

        var result: [(title: String?, value: Any)] = []
        for (index, child) in mirror.children.enumerated() {
            let label = child.label ?? "[\(index)]"
            if shouldSkipViewField(label: label, value: child.value) {
                continue
            }

            if let expanded = expandWrapperField(label: label, value: child.value), !expanded.isEmpty {
                result.append(contentsOf: expanded)
                continue
            }

            let childType = typeName(of: child.value)
            if isViewLike(childType) {
                result.append((sanitizeDiscoveredTitle(label, fallback: preferredTitle), child.value))
                continue
            }

            let nested = discoverEmbeddedViews(
                in: child.value,
                preferredTitle: sanitizeDiscoveredTitle(label, fallback: preferredTitle),
                depth: depth + 1
            )
            if !nested.isEmpty {
                result.append(contentsOf: nested)
            }
        }

        return result.prefix(maxChildrenPerNode).map { $0 }
    }

    private static func sanitizeDiscoveredTitle(_ label: String, fallback: String?) -> String? {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return fallback }
        if ["storage", "content", "value", "root", "list", "tree", "_tree", "some"].contains(normalized.lowercased()) {
            return fallback
        }
        return normalized
    }

    private static func expandWrapperField(label: String, value: Any) -> [(title: String?, value: Any)]? {
        guard shouldExpandWrapperField(label: label, value: value) else { return nil }
        let raw = unwrapIfOptional(value) ?? value
        let innerMirror = Mirror(reflecting: raw)
        return extractViewChildren(from: raw, mirror: innerMirror)
    }

    private static func shouldExpandWrapperField(label: String, value: Any) -> Bool {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["storage", "content", "value", "root", "list", "tree", "_tree", "some"].contains(normalized) {
            return true
        }

        let type = typeName(of: value)
        if looksLikeWrapperContainer(typeName: type) { return true }
        if normalized.hasPrefix("_") && !isViewLike(type) { return true }
        return false
    }

    private static func defaultChildTitle(for value: Any, index: Int) -> String {
        let type = simplifyViewTypeName(typeName(of: value))
        return type.isEmpty ? "[\(index)]" : type
    }

    private static func summarizeViewLeaf(_ value: Any) -> String {
        let text = String(describing: value)
        if text.isEmpty || text == typeName(of: value) {
            return "leaf view"
        }
        if text.count > 80 { return String(text.prefix(80)) + "…" }
        return text
    }

    private static func simplifyViewTypeName(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "SwiftUI.", with: "")
            .replacingOccurrences(of: "(unknown context at $", with: "")
    }

    private static func collectNodeSnapshots(
        screenLabel: String,
        node: SuiraMirrorTreeNode,
        into result: inout [SuiraViewNodeSnapshot],
        isRoot: Bool
    ) {
        let signature = subtreeSignature(for: node)
        if !isRoot, shouldIncludeInAnalysis(node: node) {
            result.append(
                SuiraViewNodeSnapshot(
                    key: "\(screenLabel)|\(node.id)",
                    screenLabel: screenLabel,
                    path: node.id,
                    tag: node.tag,
                    title: node.title,
                    typeName: node.typeName,
                    displayName: displayName(for: node),
                    signature: signature
                )
            )
        }

        for child in node.children {
            collectNodeSnapshots(screenLabel: screenLabel, node: child, into: &result, isRoot: false)
        }
    }

    private static func subtreeSignature(for node: SuiraMirrorTreeNode) -> String {
        let childSignatures = node.children.map(subtreeSignature(for:)).joined(separator: "|")
        return "\(node.typeName)#\(node.title)#\(node.valueSummary)#\(childSignatures)"
    }

    private static func displayName(for node: SuiraMirrorTreeNode) -> String {
        let type = baseTypeName(from: node.typeName)
        let title = node.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if isGenericNodeTitle(title) || title == type {
            return type
        }

        return "\(type) · \(title)"
    }

    private static func baseTypeName(from raw: String) -> String {
        let simplified = simplifyViewTypeName(raw)
        let prefix = simplified.split(separator: "<", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? simplified
        return prefix.split(separator: ".", omittingEmptySubsequences: true).last.map(String.init) ?? prefix
    }

    private static func isGenericNodeTitle(_ title: String) -> Bool {
        if title.isEmpty { return true }
        if title == "content" { return true }
        if title == "RootView" { return true }
        if title.hasPrefix("[") { return true }
        if Int(title) != nil { return true }
        return false
    }

    private static func shouldIncludeInAnalysis(node: SuiraMirrorTreeNode) -> Bool {
        let type = node.typeName.lowercased()
        let title = node.title.lowercased()

        if !isViewLike(node.typeName) { return false }
        if type.contains("storage") || title.contains("storage") { return false }
        if type.contains("state") || type.contains("binding") || type.contains("environment") { return false }
        if type.contains("attribute") || type.contains("transaction") || type.contains("publisher") { return false }
        if type.contains("propertylist") || type.contains("trait") || type.contains("namespace") { return false }
        if title == "content" && node.children.count == 1 { return false }

        return true
    }

    private static func isViewLike(_ typeName: String) -> Bool {
        let type = typeName.lowercased()
        if type.contains("swiftui") { return true }
        if type.contains("view") { return true }
        if type.contains("text") { return true }
        if type.contains("button") { return true }
        if type.contains("toggle") { return true }
        if type.contains("textfield") { return true }
        if type.contains("securefield") { return true }
        if type.contains("texteditor") { return true }
        if type.contains("image") { return true }
        if type.contains("list") { return true }
        if type.contains("section") { return true }
        if type.contains("navigation") { return true }
        if type.contains("picker") { return true }
        if type.contains("slider") { return true }
        if type.contains("stepper") { return true }
        if type.contains("scroll") { return true }
        if type.contains("stack") { return true }
        return false
    }

    private static func looksLikeWrapperContainer(typeName: String) -> Bool {
        let type = typeName.lowercased()
        if type.contains("wrapper") { return true }
        if type.contains("container") { return true }
        if type.contains("traitwritingmodifier") { return true }
        if type.contains("environmentkeywritingmodifier") { return true }
        if type.contains("modifiedcontent") { return true }
        if type.contains("listcore") { return true }
        if type.contains("tableviewlistcore") { return true }
        if type.contains("tupleview") { return true }
        return false
    }

    private static func unwrapIfOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return nil }
        return mirror.children.first?.value
    }

    private static func typeName(of value: Any) -> String {
        String(describing: Swift.type(of: value))
    }
}

public struct SuiraValueSnapshot: Sendable {
    public let label: String
    public let fields: [String: String]

    public init(label: String, fields: [String: String]) {
        self.label = label
        self.fields = fields
    }
}

public enum SuiraValueSnapshotBuilder {
    public static let maxDepth = 8
    public static let maxChildrenPerNode = 40

    public static func capture(label: String, value: Any) -> SuiraValueSnapshot {
        var fields: [String: String] = [:]
        var seenObjects = Set<ObjectIdentifier>()
        collect(
            value: value,
            path: [],
            depth: 0,
            fields: &fields,
            seenObjects: &seenObjects
        )
        return SuiraValueSnapshot(label: label, fields: fields)
    }

    public static func diff(
        previous: SuiraValueSnapshot?,
        current: SuiraValueSnapshot,
        limit: Int = 20
    ) -> [(path: String, oldValue: String?, newValue: String?)] {
        let oldFields = previous?.fields ?? [:]
        let newFields = current.fields
        let keys = Set(oldFields.keys).union(newFields.keys).sorted()

        return keys.compactMap { key in
            let oldValue = oldFields[key]
            let newValue = newFields[key]
            guard oldValue != newValue else { return nil }
            return (key, oldValue, newValue)
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func collect(
        value: Any,
        path: [String],
        depth: Int,
        fields: inout [String: String],
        seenObjects: inout Set<ObjectIdentifier>
    ) {
        guard depth < maxDepth else { return }

        let raw = unwrapIfOptional(value) ?? value
        let typeName = String(describing: Swift.type(of: raw))
        let mirror = Mirror(reflecting: raw)

        if let leaf = summarizeLeaf(raw) {
            if !path.isEmpty {
                fields[path.joined(separator: ".")] = leaf
            }
            return
        }

        if mirror.displayStyle == .class {
            let object = raw as AnyObject
            let oid = ObjectIdentifier(object)
            guard !seenObjects.contains(oid) else { return }
            seenObjects.insert(oid)
        }

        if mirror.children.isEmpty {
            if !path.isEmpty {
                fields[path.joined(separator: ".")] = trimmedDescription(of: raw)
            }
            return
        }

        if mirror.displayStyle == .collection {
            for (index, child) in mirror.children.enumerated() where index < maxChildrenPerNode {
                collect(
                    value: child.value,
                    path: path + ["[\(index)]"],
                    depth: depth + 1,
                    fields: &fields,
                    seenObjects: &seenObjects
                )
            }
            return
        }

        if mirror.displayStyle == .dictionary {
            for (index, child) in mirror.children.enumerated() where index < maxChildrenPerNode {
                let tupleChildren = Array(Mirror(reflecting: child.value).children)
                guard tupleChildren.count >= 2 else { continue }
                let key = sanitizePathComponent(String(describing: tupleChildren[0].value))
                collect(
                    value: tupleChildren[1].value,
                    path: path + [key.isEmpty ? "[\(index)]" : key],
                    depth: depth + 1,
                    fields: &fields,
                    seenObjects: &seenObjects
                )
            }
            return
        }

        if typeName.contains("TupleView"), let tupleValue = mirror.children.first?.value {
            let tupleChildren = Array(Mirror(reflecting: tupleValue).children)
            for (index, child) in tupleChildren.enumerated() where index < maxChildrenPerNode {
                collect(
                    value: child.value,
                    path: path + ["[\(index)]"],
                    depth: depth + 1,
                    fields: &fields,
                    seenObjects: &seenObjects
                )
            }
            return
        }

        for (index, child) in mirror.children.enumerated() where index < maxChildrenPerNode {
            let label = sanitizePathComponent(child.label ?? "field\(index)")
            if shouldSkipSnapshotField(label: label, value: child.value) {
                continue
            }
            collect(
                value: child.value,
                path: path + [label.isEmpty ? "field\(index)" : label],
                depth: depth + 1,
                fields: &fields,
                seenObjects: &seenObjects
            )
        }

        if mirror.displayStyle == .class {
            let object = raw as AnyObject
            seenObjects.remove(ObjectIdentifier(object))
        }
    }

    private static func shouldSkipSnapshotField(label: String, value: Any) -> Bool {
        let type = String(describing: Swift.type(of: value))
        if label == "modifier" { return true }
        if label == "content", type.contains("ModifiedContent") { return false }
        if type.contains("Environment") { return true }
        if type.contains("Transaction") { return true }
        if type.contains("GestureState") { return true }
        if type.contains("Namespace") { return true }
        return false
    }

    private static func sanitizePathComponent(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "some", with: "value")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func unwrapIfOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return nil }
        return mirror.children.first?.value
    }

    private static func summarizeLeaf(_ value: Any) -> String? {
        if let string = value as? String {
            return "\"\(string.count > 80 ? String(string.prefix(80)) + "…" : string)\""
        }
        if value is Bool || value is any BinaryInteger || value is Double || value is Float || value is CGFloat {
            return String(describing: value)
        }
        if value is Date {
            return String(describing: value)
        }

        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .enum {
            if mirror.children.isEmpty { return String(describing: value) }
            if let child = mirror.children.first, let label = child.label {
                return ".\(label)"
            }
        }

        return nil
    }

    private static func trimmedDescription(of value: Any) -> String {
        let description = String(describing: value)
        if description.count > 80 {
            return String(description.prefix(80)) + "…"
        }
        return description
    }
}
