import SwiftUI
import simd

struct AtlasNode: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let path: String
    let file: String
    let kind: String
    let layer: String
    let x: Double
    let y: Double
    let z: Double
    let signal: Double
    let degree: Int

    var hit: Hit { Hit(id: id, path: path, file: file, title: title, kind: kind, excerpt: "", match: "text") }
    var tint: Color {
        switch layer {
        case "source": Color(red: 0.32, green: 0.93, blue: 0.94)
        case "skill": Color(red: 0.83, green: 0.65, blue: 1)
        default: Color(red: 0.75, green: 0.84, blue: 1)
        }
    }
    var label: String {
        switch layer {
        case "source": "Källa"
        case "skill": "Skill"
        default: "Anteckning"
        }
    }
}

struct AtlasEdge: Decodable, Identifiable, Sendable {
    let a: String, b: String, kind: String
    let weight: Double
    let count: Int
    var id: String { a + "\u{1f}" + b + "\u{1f}" + kind }
}

struct AtlasSnapshot: Decodable, Sendable {
    let nodes: [AtlasNode]
    let recent: [Hit]
    let edges: [AtlasEdge]
    let total: Int
    let linked: Int
    let learned: Int
}

private let atlasInk = Color(red: 0.024, green: 0.038, blue: 0.094)
private let atlasBlue = Color(red: 0.23, green: 0.45, blue: 0.88)
private let atlasIce = Color(red: 0.53, green: 0.95, blue: 1)
private let atlasLilac = Color(red: 0.81, green: 0.64, blue: 1)

extension View {
    @ViewBuilder
    func brainGlass<S: Shape>(_ shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorderIfPossible() }
        }
    }
}

private extension Shape {
    func strokeBorderIfPossible() -> some View { stroke(.white.opacity(0.13), lineWidth: 1) }
}

private enum AtlasShape: String, CaseIterable {
    case sphere, brain

    var title: String {
        switch self {
        case .sphere: "Sfär"
        case .brain: "Hjärna"
        }
    }

    var icon: String {
        switch self {
        case .sphere: "globe"
        case .brain: "brain.head.profile"
        }
    }
}

private struct OrbitCamera {
    typealias ProjectedPoint = (point: CGPoint, depth: Double, scale: Double)
    static let distance = 3.65
    var yaw: Double = -0.81
    var tilt: Double = 0.35
    var zoom: Double = 1

    func units(in size: CGSize) -> Double {
        min(size.width * 0.40, size.height * 0.41) * zoom
    }

    var rotation: simd_double3x3 {
        let (c, s) = (cos(yaw), sin(yaw))
        let (p, q) = (cos(tilt), sin(tilt))
        return simd_double3x3(columns: (
            SIMD3(c, q * s, -p * s),
            SIMD3(0, p, q),
            SIMD3(s, -q * c, p * c)
        ))
    }

    func projection(in size: CGSize) -> (SIMD3<Double>) -> ProjectedPoint {
        let rotation = rotation
        let unit = units(in: size)
        return { world in
            let rotated = rotation * world
            let scale = Self.distance / (Self.distance - rotated.z)
            return (CGPoint(x: size.width / 2 + rotated.x * unit * scale,
                            y: size.height / 2 - rotated.y * unit * scale), rotated.z, scale)
        }
    }
}

private struct AtlasBrainSurface: Sendable {
    struct Face: Sendable {
        let a, b, c: Int
        let normal: SIMD3<Double>
    }

    struct Ridge: Sendable {
        let a, b: Int
        let normal: SIMD3<Double>
        let contrast: Double
    }

    let vertices: [SIMD3<Double>]
    let faces: [Face]
    let neighbors: [[Int]]
    let ridges: [Ridge]

    static let bundled: Self? = {
        guard let url = Bundle.main.url(forResource: "AtlasBrain", withExtension: "mesh"),
              let data = try? Data(contentsOf: url), data.count >= 12,
              data.prefix(4) == Data("BBM1".utf8) else { return nil }
        return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let vertexCount = Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 4, as: UInt32.self)))
            let indexCount = Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 8, as: UInt32.self)))
            guard (1..<65536).contains(vertexCount), indexCount > 0, indexCount % 3 == 0 else { return nil }
            let indexOffset = 12 + vertexCount * 12
            guard indexOffset + indexCount * 2 == bytes.count else { return nil }

            func vector(at offset: Int) -> SIMD3<Double> {
                func value(_ i: Int) -> Double {
                    Double(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset + i, as: Int16.self))) / 32767
                }
                return SIMD3(value(0), value(2), value(4))
            }

            let vertices = (0..<vertexCount).map { vector(at: 12 + $0 * 12) }
            let normals = (0..<vertexCount).map { vector(at: 18 + $0 * 12) }
            var neighbors = Array(repeating: Set<Int>(), count: vertexCount)
            var faces: [Face] = []
            faces.reserveCapacity(indexCount / 3)
            func index(at offset: Int) -> Int {
                Int(UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self)))
            }
            for offset in stride(from: indexOffset, to: bytes.count, by: 6) {
                let (a, b, c) = (index(at: offset), index(at: offset + 2), index(at: offset + 4))
                guard a < vertexCount, b < vertexCount, c < vertexCount else { return nil }
                let normal = normals[a] + normals[b] + normals[c]
                guard simd_length_squared(normal) > 0.00001 else { continue }
                faces.append(Face(a: a, b: b, c: c, normal: simd_normalize(normal)))
                neighbors[a].formUnion([b, c])
                neighbors[b].formUnion([a, c])
                neighbors[c].formUnion([a, b])
            }
            let adjacency = neighbors.map { $0.sorted() }
            var ridges: [Ridge] = []
            for a in vertices.indices {
                for b in adjacency[a] where b > a {
                    let contrast = 1 - simd_dot(normals[a], normals[b])
                    let normal = normals[a] + normals[b]
                    guard contrast > 0.058, simd_length_squared(normal) > 0.00001 else { continue }
                    ridges.append(Ridge(a: a, b: b, normal: simd_normalize(normal), contrast: min(1, contrast * 6)))
                }
            }
            return Self(vertices: vertices, faces: faces, neighbors: adjacency, ridges: ridges)
        }
    }()

    func anchor(for node: AtlasNode) -> Int {
        let side = node.x < 0 ? -1.0 : 1.0
        let direction = simd_normalize(SIMD3(0.24 + abs(node.x), node.y * 1.18, node.z * 1.18))
        let target = SIMD3(side * (0.33 + direction.x * 0.46), 0.12 + direction.y * 0.62, direction.z * 0.86)
        return vertices.indices.min { simd_distance_squared(vertices[$0], target) < simd_distance_squared(vertices[$1], target) } ?? 0
    }

    func routes(from start: Int, to targets: Set<Int>) -> [Int: [Int]] {
        var parents = Array(repeating: -1, count: vertices.count)
        parents[start] = start
        var queue = [start]
        var next = 0
        var pending = targets
        pending.remove(start)
        while next < queue.count && !pending.isEmpty {
            let vertex = queue[next]
            next += 1
            for neighbor in neighbors[vertex] where parents[neighbor] == -1 {
                parents[neighbor] = vertex
                queue.append(neighbor)
                pending.remove(neighbor)
            }
        }

        var paths: [Int: [Int]] = [:]
        for target in targets where parents[target] != -1 {
            var path = [target]
            while let last = path.last, last != start { path.append(parents[last]) }
            paths[target] = Array(path.reversed())
        }
        return paths
    }
}

private struct AtlasBrainNetwork: Sendable {
    struct LitFace: Sendable {
        let face: AtlasBrainSurface.Face
        let strength: Double
        let begins: Double
    }

    struct LitRidge: Sendable {
        let ridge: AtlasBrainSurface.Ridge
        let strength: Double
        let begins: Double
    }

    let anchors: [String: Int]
    let routes: [String: [Int]]
    let faces: [LitFace]
    let ridges: [LitRidge]

    init(atlas: AtlasSnapshot, surface: AtlasBrainSurface, starts: [String: Double]) {
        let anchors = Dictionary(uniqueKeysWithValues: atlas.nodes.map { ($0.id, surface.anchor(for: $0)) })
        self.anchors = anchors
        var routes: [String: [Int]] = [:]
        for (source, edges) in Dictionary(grouping: atlas.edges, by: \.a) {
            guard let start = anchors[source] else { continue }
            let paths = surface.routes(from: start, to: Set(edges.compactMap { anchors[$0.b] }))
            for edge in edges {
                guard let end = anchors[edge.b] else { continue }
                // Separate meshes, such as the two hemispheres, meet through a direct connection.
                routes[edge.id] = paths[end] ?? [start, end]
            }
        }
        self.routes = routes

        var onset = Array(repeating: Double.infinity, count: surface.vertices.count)
        var strength = Array(repeating: 0.0, count: surface.vertices.count)
        var wave: [Int] = []
        for edge in atlas.edges {
            guard let route = routes[edge.id] else { continue }
            let start = starts[edge.id] ?? -1
            for (index, vertex) in route.enumerated() {
                if strength[vertex] == 0 { wave.append(vertex) }
                strength[vertex] = 1
                onset[vertex] = min(onset[vertex], start + 0.27 * Double(index) / Double(max(1, route.count - 1)))
            }
        }
        // Light only the folds bordering a route. The rest of the surface stays invisible.
        for step in 1...5 {
            var next: [Int] = []
            for vertex in wave {
                for neighbor in surface.neighbors[vertex] {
                    if strength[neighbor] == 0 {
                        strength[neighbor] = 1 - Double(step) * 0.145
                        onset[neighbor] = onset[vertex] + 0.022
                        next.append(neighbor)
                    } else if abs(strength[neighbor] - (strength[vertex] - 0.145)) < 0.001 {
                        onset[neighbor] = min(onset[neighbor], onset[vertex] + 0.022)
                    }
                }
            }
            wave = next
        }
        faces = surface.faces.compactMap { face in
            let intensity = (strength[face.a] + strength[face.b] + strength[face.c]) / 3
            guard intensity > 0.12 else { return nil }
            return LitFace(face: face, strength: intensity, begins: min(onset[face.a], onset[face.b], onset[face.c]))
        }
        ridges = surface.ridges.compactMap { ridge in
            let intensity = min(strength[ridge.a], strength[ridge.b])
            guard intensity > 0 else { return nil }
            return LitRidge(ridge: ridge, strength: intensity, begins: max(onset[ridge.a], onset[ridge.b]))
        }
    }
}

private func edgeStart(_ rank: Int, count: Int) -> Double {
    0.58 * Double(rank) / Double(max(1, count - 1))
}

private struct AtlasOrbit: View {
    let atlas: AtlasSnapshot?
    let selected: String?
    let shape: AtlasShape
    let choose: (AtlasNode) -> Void

    private struct LayoutKey: Equatable {
        let shape: AtlasShape
        let nodes: [String]
        let edges: [String]
    }

    @LocalState private var camera = OrbitCamera()
    @LocalState private var dragOrigin: OrbitCamera?
    @LocalState private var brain: AtlasBrainNetwork?
    @LocalState private var displayedShape: AtlasShape?
    @LocalState private var displayedEdges: Set<String> = []
    @LocalState private var edgeStarts: [String: Double] = [:]
    @LocalState private var growthStart = Date.distantPast
    @LocalState private var growing = false
    @GestureState private var pinch: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let zoomLimits = 0.55...3.25

    private var layoutKey: LayoutKey {
        LayoutKey(shape: shape, nodes: atlas?.nodes.map(\.id).sorted() ?? [], edges: atlas?.edges.map(\.id) ?? [])
    }

    private var displayCamera: OrbitCamera {
        var display = camera
        display.zoom = boundedZoom(camera.zoom * pinch)
        return display
    }

    private func boundedZoom(_ value: Double) -> Double {
        min(zoomLimits.upperBound, max(zoomLimits.lowerBound, value))
    }

    private func worldPosition(_ node: AtlasNode) -> SIMD3<Double> {
        if shape == .brain, let anchor = brain?.anchors[node.id], let surface = AtlasBrainSurface.bundled {
            return surface.vertices[anchor]
        }
        return SIMD3(node.x, node.y, node.z)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Rectangle().fill(.clear)
                .overlay {
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !growing || reduceMotion)) { timeline in
                        let progress = growing && !reduceMotion
                            ? min(1, max(0, timeline.date.timeIntervalSince(growthStart) / 1.25)) : 1
                        Canvas { context, bounds in drawGraph(context, bounds: bounds, progress: progress) }
                    }
                    .allowsHitTesting(false)
                }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                let origin = dragOrigin ?? camera
                dragOrigin = origin
                camera.yaw = origin.yaw + Double(value.translation.width) * 0.009
                camera.tilt = min(1.5, max(-1.5, origin.tilt + Double(value.translation.height) * 0.009))
            }.onEnded { _ in dragOrigin = nil })
            .simultaneousGesture(MagnifyGesture()
                .updating($pinch) { value, scale, _ in scale = value.magnification }
                .onEnded { value in camera.zoom = boundedZoom(camera.zoom * value.magnification) })
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                guard shape == .sphere || brain != nil else { return }
                let project = displayCamera.projection(in: size)
                let candidates = (atlas?.nodes ?? []).map { node in
                    let p = project(worldPosition(node))
                    return (node: node, distance: hypot(p.point.x - value.location.x, p.point.y - value.location.y), depth: p.depth)
                }
                let nearest = candidates.min {
                    $0.distance == $1.distance ? $0.depth > $1.depth : $0.distance < $1.distance
                }
                if let nearest, nearest.distance < 19 { choose(nearest.node) }
            })
            .accessibilityHidden(true)
        }
        .task(id: layoutKey) {
            let visible = atlas?.edges.map(\.id) ?? []
            let newEdges = displayedShape == shape ? visible.filter { !displayedEdges.contains($0) } : visible
            let starts = Dictionary(uniqueKeysWithValues: newEdges.enumerated().map {
                ($0.element, edgeStart($0.offset, count: newEdges.count))
            })
            if shape == .brain, let atlas, let surface = AtlasBrainSurface.bundled {
                let work = Task.detached(priority: .userInitiated) {
                    AtlasBrainNetwork(atlas: atlas, surface: surface, starts: starts)
                }
                let network = await work.value
                guard !Task.isCancelled else { return }
                brain = network
            } else {
                brain = nil
            }
            displayedShape = shape
            displayedEdges = Set(visible)
            edgeStarts = starts
            guard !reduceMotion, !starts.isEmpty else {
                growing = false
                return
            }
            growthStart = .now
            growing = true
            do {
                try await Task.sleep(for: .milliseconds(1250))
                growing = false
            } catch {}
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 4) {
                orbitButton("minus", "Zooma ut", enabled: camera.zoom > zoomLimits.lowerBound) {
                    camera.zoom = boundedZoom(camera.zoom / 1.2)
                }
                orbitButton("plus", "Zooma in", enabled: camera.zoom < zoomLimits.upperBound) {
                    camera.zoom = boundedZoom(camera.zoom * 1.2)
                }
                orbitButton("arrow.counterclockwise", "Återställ perspektivet") { camera = OrbitCamera() }
            }
            .padding(5)
            .brainGlass(Capsule())
            .padding(15)
        }
    }

    private func drawGraph(_ context: GraphicsContext, bounds: CGSize, progress: Double) {
        guard let atlas, shape == .sphere || brain != nil else { return }
        let camera = displayCamera
        let project = camera.projection(in: bounds)
        let world = Dictionary(uniqueKeysWithValues: atlas.nodes.map { ($0.id, worldPosition($0)) })
        let points = world.mapValues(project)
        let surface = shape == .brain ? AtlasBrainSurface.bundled : nil
        let surfacePoints = surface?.vertices.map(project) ?? []
        if let brain, shape == .brain {
            drawFolds(brain, surfacePoints: surfacePoints, rotation: camera.rotation, progress: progress, context: context)
        }

        let density = min(1, 185.0 / Double(max(1, atlas.edges.count)))
        for edge in atlas.edges {
            guard let one = points[edge.a], let two = points[edge.b] else { continue }
            let active = selected == edge.a || selected == edge.b
            let growth = edgeStarts[edge.id].map { min(1, max(0, (progress - $0) / 0.42)) } ?? 1
            guard growth > 0 else { continue }
            let depth = min(1, max(0, (one.depth + two.depth + 2) / 4))
            var trace = Path()
            trace.move(to: one.point)
            if shape == .brain, let route = brain?.routes[edge.id], route.count > 2 {
                trace.addLines(route.map { surfacePoints[$0].point })
            } else if shape == .sphere, let start = world[edge.a], let end = world[edge.b] {
                let middle = (start + end) / 2
                let radialBend = min(0.16, simd_distance(start, end) * 0.16)
                let control = project(middle * (1 + radialBend)).point
                trace.addQuadCurve(to: two.point, control: control)
            } else {
                trace.addLine(to: two.point)
            }
            let learned = edge.kind == "learned"
            let color = learned ? atlasLilac : atlasIce
            let opacity = (0.13 + depth * 0.22 + edge.weight * 0.08) * density
                * (shape == .brain && (brain?.routes[edge.id]?.count ?? 0) < 3 ? 0.52 : 1)
            context.stroke(growth == 1 ? trace : trace.trimmedPath(from: 0, to: growth),
                           with: .color(color.opacity(active ? 0.93 : opacity)),
                           style: StrokeStyle(lineWidth: active ? 1.65 : 0.7, lineCap: .round, lineJoin: .round,
                                              dash: learned ? [4, 4] : []))
        }
        let ordered = atlas.nodes.sorted { (points[$0.id]?.depth ?? 0) < (points[$1.id]?.depth ?? 0) }
        for node in ordered {
            guard let p = points[node.id] else { continue }
            let chosen = selected == node.id
            let depth = min(1, max(0, (p.depth + 1) / 2))
            let radius = (chosen ? 6.5 : 2.1 + node.signal * 2.3 + min(Double(node.degree), 12) * 0.08) * p.scale
            let rect = CGRect(x: p.point.x - radius, y: p.point.y - radius, width: 2 * radius, height: 2 * radius)
            if chosen || node.signal > 0.35 {
                context.fill(Path(ellipseIn: rect.insetBy(dx: -5, dy: -5)), with: .color(node.tint.opacity(0.20)))
            }
            context.fill(Path(ellipseIn: rect), with: .color(node.tint.opacity(chosen ? 1 : 0.43 + depth * 0.54)))
            if chosen {
                context.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(node.tint), lineWidth: 0.9)
            }
        }
    }

    private func drawFolds(_ brain: AtlasBrainNetwork, surfacePoints: [OrbitCamera.ProjectedPoint],
                           rotation: simd_double3x3, progress: Double, context: GraphicsContext) {
        let light = simd_normalize(SIMD3(-0.38, 0.53, 0.68))
        // Batch facets by light level so the cortex stays responsive while rotating.
        let bands = 14
        var paths = Array(repeating: Path(), count: bands * 2)
        for part in brain.faces {
            let normal = rotation * part.face.normal
            let growth = min(1, max(0, (progress - part.begins) / 0.12))
            guard normal.z > -0.02, growth > 0 else { continue }
            let brightness = (0.12 + max(0, simd_dot(normal, light)) * 0.88) * part.strength * growth
            let band = min(bands - 1, Int(brightness * Double(bands)))
            guard band > 0 else { continue }
            let face = part.face
            let side = part.face.normal.x < 0 ? 0 : bands
            paths[side + band].move(to: surfacePoints[face.a].point)
            paths[side + band].addLine(to: surfacePoints[face.b].point)
            paths[side + band].addLine(to: surfacePoints[face.c].point)
            paths[side + band].closeSubpath()
        }
        for (index, path) in paths.enumerated() where !path.isEmpty {
            let strength = Double(index % bands) / Double(bands - 1)
            let tint = index < bands ? atlasIce : atlasLilac
            context.fill(path, with: .color(tint.opacity(0.024 + strength * 0.34)))
        }
        var contours = Array(repeating: Path(), count: 8)
        for part in brain.ridges {
            let ridge = part.ridge
            let normal = rotation * ridge.normal
            let growth = min(1, max(0, (progress - part.begins) / 0.12))
            guard normal.z > 0, growth > 0 else { continue }
            let signal = (0.24 + 0.76 * max(0, simd_dot(normal, light))) * ridge.contrast * part.strength * growth
            let band = min(contours.count - 1, Int(signal * Double(contours.count)))
            guard band > 0 else { continue }
            contours[band].move(to: surfacePoints[ridge.a].point)
            contours[band].addLine(to: surfacePoints[ridge.b].point)
        }
        for (index, contour) in contours.enumerated() where !contour.isEmpty {
            let opacity = 0.04 + 0.26 * Double(index) / Double(contours.count - 1)
            context.stroke(contour, with: .color(atlasIce.opacity(opacity)), lineWidth: 0.7)
        }
    }

    private func orbitButton(_ icon: String, _ label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button {
            action()
            BrainHaptics.selection()
        } label: {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).frame(width: 31, height: 31)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel(label).help(label)
    }
}

struct AtlasView: View {
    @ObservedObject var model: BrainModel
    @AppStorage("atlasShape") private var shape = AtlasShape.sphere
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @LocalState private var searchPresented = false
    private let searchRowHeight: CGFloat = 36
    private let searchPanelPadding: CGFloat = 7

    private var graph: AtlasSnapshot? { model.atlas }
    private var node: AtlasNode? { graph?.nodes.first { $0.id == model.selected?.id } }
    private var links: [AtlasEdge] {
        guard let id = node?.id else { return [] }
        return (graph?.edges ?? []).filter { $0.a == id || $0.b == id }.sorted { $0.weight > $1.weight }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                HStack(spacing: 12) {
                    starfield
                    inspector
                }
                .padding(.top, 13)
                .simultaneousGesture(TapGesture().onEnded { dismissSearch() })
                .overlay(alignment: .topLeading) { searchDropdown }
            }
            footer
                .simultaneousGesture(TapGesture().onEnded { dismissSearch() })
        }
        .padding(.horizontal, 21)
        .padding(.top, 14)
        .padding(.bottom, 19)
        .task(id: model.dashboard?.config.vault) {
            await model.loadAtlas()
        }
        .onKeyPress(.escape) {
            guard searchPresented else { return .ignored }
            dismissSearch()
            return .handled
        }
        .onDisappear(perform: dismissSearch)
    }

    private var visibleSearchState: AtlasSearchState? {
        guard searchPresented else { return nil }
        return model.atlasSearchState(for: model.atlasSearchTerm)
    }

    private var masthead: some View {
        let term = searchPresented ? model.atlasSearchTerm : ""
        return VStack(alignment: .leading, spacing: 11) {
            WorkspaceTitle("Atlas")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { dismissSearch() }
            QueryBox(query: $model.query, placeholder: "Sök med ord, begrepp eller en fråga…",
                     autofocus: false, prominent: true, focus: $searchFocused,
                     attachedResults: visibleSearchState != nil, action: model.searchFromAtlas)
                .simultaneousGesture(TapGesture().onEnded { searchPresented = true })
                .onChange(of: model.query) { _, _ in
                    if searchFocused { searchPresented = true }
                }
                .task(id: term) { await model.searchAtlasSuggestions(for: term) }
        }
    }

    private func dismissSearch() {
        guard searchPresented else { return }
        searchPresented = false
        searchFocused = false
        model.dismissAtlasSearch()
    }

    @ViewBuilder
    private var searchDropdown: some View {
        if let state = visibleSearchState {
            let rowCount: Int = {
                if case .results(let hits) = state { return min(8, max(2, hits.count)) }
                return 2
            }()
            Group {
                switch state {
                case .searching:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Söker…")
                    }
                    .padding(12)
                case .results(let hits) where hits.isEmpty:
                    Text("Inga träffar").padding(12)
                case .results(let hits):
                    ScrollView { searchRows(hits) }
                        .scrollBounceBehavior(.basedOnSize)
                        .defaultScrollAnchor(.top)
                        .id(model.atlasSearchTerm)
                case .failed:
                    Text("Kunde inte visa träffar. Tryck Retur för att söka i Biblioteket.")
                        .padding(12)
                }
            }
            .font(QueryBox.prominentFont)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: searchRowHeight * CGFloat(rowCount) + searchPanelPadding * 2, alignment: .topLeading)
            .background(inset.opacity(0.55), in: searchPanelShape)
            .brainGlass(searchPanelShape, tint: .indigo.opacity(0.18))
            .clipShape(searchPanelShape)
            .overlay {
                searchPanelShape.strokeBorder(QueryBox.focusBorder)
                    .mask { Rectangle().padding(.top, 1) }
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                Rectangle().fill(.white.opacity(0.11)).frame(height: 1)
                    .padding(.horizontal, 16).allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.30), radius: 13, y: 7)
            .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: rowCount)
            .accessibilityIdentifier("atlas-search-results")
        }
    }

    private var searchPanelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: QueryBox.prominentRadius,
                               bottomTrailingRadius: QueryBox.prominentRadius)
    }

    private func searchRows(_ hits: [Hit]) -> some View {
        VStack(spacing: 0) {
            ForEach(hits) { hit in
                Button {
                    dismissSearch()
                    if model.selected?.id != hit.id { BrainHaptics.selection() }
                    model.select(hit)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: hit.kind == "skill" ? "square.stack.3d.up" :
                                hit.kind == "inbox" ? "tray" : "doc.text")
                            .frame(width: 16).accessibilityHidden(true)
                        Text(hit.title).lineLimit(1).layoutPriority(1)
                        Text("·").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(hit.excerpt.isEmpty ? hit.path : hit.excerpt.replacingOccurrences(of: "\n", with: " "))
                            .foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(QueryBox.prominentFont)
                    .padding(.horizontal, 10)
                    .frame(height: searchRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(AtlasResultStyle())
                .help(hit.title)
            }
        }
        .padding(searchPanelPadding)
    }

    private var starfield: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(atlasInk)
            RadialGradient(colors: [atlasBlue.opacity(0.43), atlasInk.opacity(0.25), atlasInk.opacity(0)],
                           center: .center, startRadius: 0, endRadius: 360)
            LinearGradient(colors: [atlasLilac.opacity(0.12), .clear, atlasIce.opacity(0.09)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            AtlasOrbit(atlas: graph, selected: model.selected?.id,
                       shape: AtlasBrainSurface.bundled == nil ? .sphere : shape) { item in
                if model.selected?.id != item.id { BrainHaptics.selection() }
                model.select(item.hit)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Dra för att rotera. Nyp för att zooma.").font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.69))
                    .padding(.trailing, 154)
                Spacer()
                HStack(spacing: 11) {
                    legend("Källor", atlasIce)
                    legend("Anteckningar", Color(red: 0.75, green: 0.84, blue: 1))
                    if !Distribution.store { legend("Skills", atlasLilac) }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .brainGlass(Capsule(), tint: .indigo.opacity(0.25))
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if AtlasBrainSurface.bundled != nil {
                Picker("Form i Atlas", selection: $shape) {
                    ForEach(AtlasShape.allCases, id: \.self) { shape in
                        Label(shape.title, systemImage: shape.icon).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 147)
                .padding(4)
                .brainGlass(Capsule(), tint: .indigo.opacity(0.15))
                .padding(13)
                .onChange(of: shape) { _, _ in BrainHaptics.selection() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.15)) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 9, weight: .medium))
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.selected != nil {
                Button("Tillbaka till listan", systemImage: "chevron.left", action: model.closeAtlasDetail)
                    .buttonStyle(.bordered)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if let item = model.selected {
                        detail(item)
                    } else {
                        overview
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(model.selected?.id)
        }
        .padding(15)
        .frame(width: 282)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(atlasInk.opacity(0.88), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.14)) }
    }

    private var overview: some View {
        let recent = graph?.recent ?? []
        let items = recent.isEmpty ? (graph?.nodes ?? []).prefix(10).map(\.hit) : recent
        return VStack(alignment: .leading, spacing: 8) {
            if !items.isEmpty {
                Text(recent.isEmpty ? "I Atlas" : "Senast öppnade")
                    .font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 3)
                ForEach(items) { item in
                    row(item)
                }
            } else if graph != nil && !model.atlasBusy {
                Text("Dina anteckningar visas här.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func detail(_ item: Hit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title).font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader).textSelection(.enabled)
            if let node {
                Text(node.label + " · " + node.degree.formatted() + " kopplingar")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if item.kind == "note", !item.path.hasPrefix("Codex Skills/") {
                Button("Öppna i redigeraren", systemImage: "square.and.pencil") {
                    model.openEditor(for: item)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.note?.path != item.path)
            } else {
                Button("Visa i biblioteket", systemImage: "arrow.up.right") {
                    model.reply = nil
                    model.show(.search)
                    model.select(item, train: false)
                }.buttonStyle(.borderedProminent)
            }

            if let note = model.note {
                let plain = note.body.split(separator: "\n").filter { !$0.hasPrefix("#") }.joined(separator: " ")
                let excerpt = String(plain.prefix(320))
                if !excerpt.isEmpty {
                    let value = (try? AttributedString(markdown: excerpt,
                        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(excerpt)
                    Text(value).font(.callout).lineSpacing(3).textSelection(.enabled)
                }
            }

            if let node, !links.isEmpty {
                Divider().padding(.vertical, 3)
                Text("Kopplingar i vyn").font(.headline)
                ForEach(links.prefix(10)) { edge in
                    let neighborID = edge.a == node.id ? edge.b : edge.a
                    if let neighbor = graph?.nodes.first(where: { $0.id == neighborID }) {
                        row(neighbor.hit, subtitle: edge.kind == "learned" ? "Inlärt samband" : "Dokumentlänk")
                    }
                }
            }
        }
    }

    private func row(_ item: Hit, subtitle: String? = nil) -> some View {
        Button {
            model.select(item)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.kind == "inbox" ? "tray" : item.kind == "skill" ? "square.stack.3d.up" : "doc.text")
                    .font(.system(size: 13)).foregroundStyle(atlasIce)
                    .frame(width: 16).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 9))
        .help(item.title)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if let graph {
                Text("\(graph.nodes.count.formatted()) / \(graph.total.formatted()) noder")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.83))
                    .help("Antal noder i vyn och i hela biblioteket")
            }
            metric(graph?.linked ?? 0, "länkar")
            metric(graph?.learned ?? 0, "inlärda")
            Spacer()
            if model.atlasBusy { ProgressView().controlSize(.small) }
            if let pending = model.dashboard?.proposals.filter({ $0.status == "pending" }).count, pending > 0 {
                ActionButton(title: "\(pending) att granska", icon: "arrow.up.right") { model.show(.review) }
            }
        }
        .padding(.horizontal, 9)
    }

    private func metric(_ value: Int, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(value.formatted()).font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(label).foregroundStyle(.white.opacity(0.59)).font(.system(size: 11))
        }
    }
}

private struct AtlasResultStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AtlasResultRow(label: configuration.label, pressed: configuration.isPressed)
    }

    private struct AtlasResultRow<Label: View>: View {
        let label: Label
        let pressed: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @LocalState private var hovering = false

        var body: some View {
            label
                .background(Color.accentColor.opacity(pressed ? 0.64 : hovering ? 0.30 : 0),
                            in: RoundedRectangle(cornerRadius: 10))
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
        }
    }
}
