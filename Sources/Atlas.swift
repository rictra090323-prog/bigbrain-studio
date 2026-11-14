import AppKit
import SwiftUI
import simd

struct AtlasNode: Decodable, Equatable, Identifiable, Sendable {
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
        case "source": atlasIce
        case "skill": atlasLilac
        default: atlasGold
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

struct AtlasEdge: Decodable, Equatable, Identifiable, Sendable {
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

private let atlasInk = Color(red: 0.018, green: 0.022, blue: 0.035)
private let atlasIce = Color(red: 0.38, green: 0.91, blue: 0.86)
private let atlasLilac = Color(red: 0.78, green: 0.66, blue: 1)
private let atlasGold = Color(red: 1, green: 0.76, blue: 0.42)

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
}

private struct OrbitCamera {
    static let homeDistance = 3.65
    static let near = 0.12
    static let zoomRange = 0.6...17.0

    var yaw: Double = -0.81
    var tilt: Double = 0.35
    var zoom: Double = 1
    var focus = SIMD3<Double>.zero

    var distance: Double { Self.homeDistance / zoom }

    var rotation: simd_double3x3 {
        let (c, s) = (cos(yaw), sin(yaw))
        let (p, q) = (cos(tilt), sin(tilt))
        return simd_double3x3(columns: (
            SIMD3(c, q * s, -p * s),
            SIMD3(0, p, q),
            SIMD3(s, -q * c, p * c)
        ))
    }

    func moving(toward end: Self, fraction: Double) -> Self {
        Self(yaw: yaw + (end.yaw - yaw) * fraction,
             tilt: tilt + (end.tilt - tilt) * fraction,
             zoom: zoom * pow(end.zoom / zoom, fraction),
             focus: focus + (end.focus - focus) * fraction)
    }

    struct Projection {
        let size: CGSize
        let rotation: simd_double3x3
        let distance: Double
        let focus: SIMD3<Double>
        let focalLength: Double

        init(camera: OrbitCamera, size: CGSize) {
            self.size = size
            rotation = camera.rotation
            distance = camera.distance
            focus = camera.focus
            focalLength = min(size.width * 0.46, size.height * 0.47) * OrbitCamera.homeDistance
        }

        func viewSpace(_ world: SIMD3<Double>) -> SIMD3<Double> {
            let rotated = rotation * (world - focus)
            return SIMD3(rotated.x, rotated.y, distance - rotated.z)
        }

        func point(_ view: SIMD3<Double>) -> CGPoint? {
            guard view.z >= OrbitCamera.near else { return nil }
            let scale = focalLength / view.z
            return CGPoint(x: size.width / 2 + view.x * scale, y: size.height / 2 - view.y * scale)
        }

        func segment(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> (CGPoint, CGPoint)? {
            let near = OrbitCamera.near
            guard a.z >= near || b.z >= near else { return nil }
            var start = a
            var end = b
            if a.z < near || b.z < near {
                let intersection = a + (b - a) * ((near - a.z) / (b.z - a.z))
                let clipped = SIMD3(intersection.x, intersection.y, near)
                if a.z < near { start = clipped } else { end = clipped }
            }
            guard let start = point(start), let end = point(end) else { return nil }
            return (start, end)
        }
    }
}

private struct AtlasBrainSurface {
    let vertices: [SIMD3<Double>]
    let directions: [SIMD3<Double>]

    static let bundled: Self? = {
        guard let url = Bundle.main.url(forResource: "AtlasBrain", withExtension: "mesh"),
              let data = try? Data(contentsOf: url), data.count >= 12,
              data.prefix(4) == Data("BBM1".utf8) else { return nil }
        return data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let count = Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 4, as: UInt32.self)))
            guard (1..<65536).contains(count), 12 + count * 12 <= bytes.count else { return nil }
            let vertices = (0..<count).map { index in
                let offset = 12 + index * 12
                func value(_ component: Int) -> Double {
                    Double(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset + component * 2, as: Int16.self))) / 32767
                }
                return SIMD3(value(0), value(1), value(2)) - SIMD3(0, 0.12, 0)
            }.filter { simd_length_squared($0) > 0.02 }
            guard !vertices.isEmpty else { return nil }
            return Self(vertices: vertices, directions: vertices.map { simd_normalize($0) })
        }
    }()

    func position(for point: SIMD3<Double>) -> SIMD3<Double> {
        let radius = simd_length(point)
        guard radius > 0.0001 else { return .zero }
        let direction = point / radius
        let index = directions.indices.max {
            simd_dot(directions[$0], direction) < simd_dot(directions[$1], direction)
        } ?? 0
        return vertices[index] * min(1, radius * 1.12)
    }
}

private struct AtlasCloud {
    struct Mote {
        let offset: SIMD3<Double>
        let radius: Double
        let brightness: Double
    }

    struct Entry {
        let node: AtlasNode
        let sphere: SIMD3<Double>
        let brain: SIMD3<Double>
        let motes: [Mote]

        func position(blend: Double) -> SIMD3<Double> {
            sphere + (brain - sphere) * blend
        }
    }

    let entries: [Entry]

    init(nodes: [AtlasNode]) {
        let moteCount = min(40, max(5, 1250 / max(1, nodes.count)))
        entries = nodes.map { node in
            let point = SIMD3(node.x, node.y, node.z)
            let brain = AtlasBrainSurface.bundled?.position(for: point) ?? point
            // The surrounding points are decoration. Each bright anchor represents a real document.
            var seed = node.id.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
            func sample() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 40) / 16777216
            }
            let motes = (0..<moteCount).map { _ in
                let height = sample() * 2 - 1
                let angle = sample() * 2 * .pi
                let ring = sqrt(1 - height * height)
                let distance = 0.22 * pow(sample(), 0.68)
                return Mote(offset: SIMD3(ring * cos(angle), height, ring * sin(angle)) * distance,
                            radius: 0.40 + 0.61 * sample(), brightness: (0.32 + 0.68 * sample()) * (1 - distance * 1.1))
            }
            return Entry(node: node, sphere: point, brain: brain, motes: motes)
        }
    }
}

private func atlasProgress(_ elapsed: TimeInterval, duration: Double) -> Double {
    min(1, max(0, elapsed / duration))
}

private struct OrbitMotion {
    let start: OrbitCamera
    let target: OrbitCamera
    let started: Date
    let duration: Double

    func camera(at date: Date) -> OrbitCamera {
        let t = atlasProgress(date.timeIntervalSince(started), duration: duration)
        return start.moving(toward: target, fraction: 1 - pow(1 - t, 3))
    }
}

private enum AtlasHaptics {
    static func step() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

private struct AtlasOrbit: View {
    let atlas: AtlasSnapshot?
    let selected: String?
    let shape: AtlasShape
    let onlyConnections: Bool
    let focusRequest: Int
    let acceptsScroll: Bool
    let choose: (AtlasNode?) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("atlasHaptics") private var haptics = true
    @LocalState private var camera = OrbitCamera()
    @LocalState private var motion: OrbitMotion?
    @LocalState private var dragOrigin: OrbitCamera?
    @LocalState private var lastTick = -Double.infinity
    @LocalState private var accentTask: Task<Void, Never>?
    @LocalState private var lastDetent = SIMD2<Double>.zero
    @LocalState private var rotationSteps = 0
    @LocalState private var pinchTravel = 0.0
    @GestureState private var pinching = false
    @LocalState private var cloud = AtlasCloud(nodes: [])
    @LocalState private var edges: [AtlasEdge] = []
    @LocalState private var nodeArrivals: [String: Date] = [:]
    @LocalState private var edgeArrivals: [String: Date] = [:]
    @LocalState private var selectionStart = Date.distantPast
    @LocalState private var lightPulses: [String: Date] = [:]
    @LocalState private var morphStart = Date.distantPast
    @LocalState private var morphOrigin = 0.0
    @LocalState private var morphTarget = 0.0
    @LocalState private var animationUntil = Date.distantPast
    @LocalState private var animating = false
    @LocalState private var hovered: String?
    @LocalState private var lastPinch = 1.0

    private var nodes: [AtlasNode] { atlas?.nodes ?? [] }
    private var visibleEdges: [AtlasEdge] { atlas?.edges ?? [] }

    private var pulseRoutes: [String] {
        guard !reduceMotion else { return [] }
        return visibleEdges.filter { edge in
            edge.kind != "suggested" && (selected == nil || edge.a == selected || edge.b == selected)
        }.map(\.id).sorted()
    }

    private var connectedIDs: Set<String> {
        guard let selected else { return [] }
        var ids: Set<String> = [selected]
        for edge in edges {
            if edge.a == selected { ids.insert(edge.b) }
            if edge.b == selected { ids.insert(edge.a) }
        }
        return ids
    }

    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear)
                .overlay {
                    let live = !reduceMotion && (animating || !lightPulses.isEmpty)
                    TimelineView(.animation(minimumInterval: animating ? 1.0 / 60 : 1.0 / 30, paused: !live)) { timeline in
                        let date = live ? timeline.date : Date.now
                        Canvas { context, size in drawGraph(context, size: size, at: date) }
                    }
                    .allowsHitTesting(false)
                }
                .background {
                    AtlasScrollInput(enabled: acceptsScroll) { delta in
                        zoom(by: exp(delta * 0.012), animated: false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4).onChanged(rotate).onEnded(finishRotation))
                .simultaneousGesture(MagnifyGesture()
                    .updating($pinching) { _, active, _ in active = true }
                    .onChanged { value in
                        let scale = Double(value.magnification)
                        zoom(by: scale / lastPinch, animated: false, pinch: true)
                        lastPinch = scale
                    })
                .simultaneousGesture(SpatialTapGesture().onEnded { value in
                    let tapped = hit(at: value.location, size: geometry.size)?.node
                    choose(tapped?.id == selected ? nil : tapped)
                })
                .onContinuousHover { phase in
                    if case .active(let point) = phase, dragOrigin == nil, motion == nil {
                        hovered = hit(at: point, size: geometry.size)?.node.id
                    } else {
                        hovered = nil
                    }
                }
                .accessibilityHidden(true)
        }
        .onChange(of: pinching) { _, active in
            if !active {
                lastPinch = 1
                pinchTravel = 0
            }
        }
        .onChange(of: haptics) { _, enabled in
            if !enabled { accentTask?.cancel() }
        }
        .onDisappear { accentTask?.cancel() }
        .onChange(of: nodes, initial: true) { _, new in
            let now = Date.now
            let known = Set(cloud.entries.map { $0.node.id })
            let arriving = new.filter { !known.contains($0.id) }
            nodeArrivals = nodeArrivals.filter { now.timeIntervalSince($0.value) < 0.65 }
            for (index, entry) in arriving.enumerated() {
                nodeArrivals[entry.id] = now.addingTimeInterval(0.33 * Double(index) / Double(max(1, arriving.count - 1)))
            }
            cloud = AtlasCloud(nodes: new)
            if !arriving.isEmpty { animate(for: 1.0) }
        }
        .onChange(of: visibleEdges, initial: true) { _, new in
            let now = Date.now
            let known = Set(edges.map(\.id))
            let arriving = new.filter { !known.contains($0.id) }
            edgeArrivals = edgeArrivals.filter { now.timeIntervalSince($0.value) < 0.54 }
            for (index, edge) in arriving.enumerated() {
                edgeArrivals[edge.id] = now.addingTimeInterval(0.17 + 0.40 * Double(index) / Double(max(1, arriving.count - 1)))
            }
            edges = new
            if !arriving.isEmpty { animate(for: 1.18) }
        }
        .onChange(of: shape, initial: true) { old, new in
            let now = Date.now
            let target = new == .brain ? 1.0 : 0.0
            morphOrigin = old == new ? target : blend(at: now)
            morphTarget = target
            morphStart = now
            if old != new {
                var targetCamera = currentCamera()
                targetCamera.focus = .zero
                move(to: targetCamera, duration: 0.68)
            }
        }
        .onChange(of: selected) { _, _ in
            selectionStart = .now
            hovered = nil
            animate(for: 0.70)
        }
        .onChange(of: focusRequest) { _, _ in
            guard let entry = cloud.entries.first(where: { $0.node.id == selected }) else { return }
            var target = currentCamera()
            target.focus = entry.position(blend: morphTarget)
            target.zoom = 4.4
            move(to: target, duration: 0.66)
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                motion = nil
                morphOrigin = morphTarget
                animationUntil = .distantPast
                animating = false
            }
        }
        .task(id: pulseRoutes) {
            let routes = pulseRoutes
            lightPulses = [:]
            guard !routes.isEmpty else { return }
            do {
                try await Task.sleep(for: .milliseconds(selected == nil ? 1200 : 220))
                var cursor = Int.random(in: routes.indices)
                while !Task.isCancelled {
                    let count = min(selected == nil ? 3 : 5, routes.count)
                    let start = Date.now
                    lightPulses = Dictionary(uniqueKeysWithValues: (0..<count).map { index in
                        (routes[(cursor + index) % routes.count], start.addingTimeInterval(Double(index) * 0.19))
                    })
                    cursor = (cursor + count) % routes.count
                    try await Task.sleep(for: .seconds(1.8))
                    lightPulses = [:]
                    try await Task.sleep(for: .seconds(selected == nil ? 2.3 : 1.35))
                }
            } catch { return }
        }
        .task(id: animationUntil) {
            let remaining = animationUntil.timeIntervalSinceNow
            if remaining > 0 {
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            motion = nil
            animating = false
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 2) {
                orbitButton("minus", "Zooma ut", enabled: camera.zoom > OrbitCamera.zoomRange.lowerBound) {
                    zoom(by: 1 / 1.55, animated: true)
                }
                orbitButton("plus", "Zooma in", enabled: camera.zoom < OrbitCamera.zoomRange.upperBound) {
                    zoom(by: 1.55, animated: true)
                }
                Divider().frame(height: 14).padding(.horizontal, 3)
                orbitButton("arrow.counterclockwise", "Återställ perspektivet") {
                    var home = OrbitCamera()
                    let yaw = currentCamera().yaw
                    home.yaw += ((yaw - home.yaw) / (2 * .pi)).rounded() * 2 * .pi
                    move(to: home, duration: 0.58)
                }
            }
            .padding(4)
            .brainGlass(Capsule())
            .padding(16)
        }
    }

    private func animate(for duration: Double) {
        guard !reduceMotion else { return }
        animationUntil = max(animationUntil, Date.now.addingTimeInterval(duration))
        animating = true
    }

    private func blend(at date: Date) -> Double {
        if reduceMotion { return morphTarget }
        let t = atlasProgress(date.timeIntervalSince(morphStart), duration: 0.68)
        return morphOrigin + (morphTarget - morphOrigin) * (t * t * (3 - 2 * t))
    }

    private func currentCamera(at date: Date = .now) -> OrbitCamera {
        reduceMotion ? camera : motion?.camera(at: date) ?? camera
    }

    private func move(to target: OrbitCamera, duration: Double) {
        motion = reduceMotion ? nil : OrbitMotion(start: currentCamera(), target: target, started: .now, duration: duration)
        camera = target
        hovered = nil
        animate(for: duration + 0.05)
    }

    private func zoom(by factor: Double, animated: Bool, pinch: Bool = false) {
        var target = animated ? camera : currentCamera()
        let prior = target.zoom
        let range = OrbitCamera.zoomRange
        target.zoom = min(range.upperBound, max(range.lowerBound, prior * factor))
        guard target.zoom != prior else { return }
        if animated {
            move(to: target, duration: 0.32)
        } else {
            let boundary = OrbitCamera.homeDistance / 0.80
            let entersCloud = (prior < boundary) != (target.zoom < boundary)
            if pinch {
                pinchTravel += log(target.zoom / prior)
                let step = log(1.13)
                let crossed = (pinchTravel / step).rounded(.towardZero)
                let limit = target.zoom == range.lowerBound || target.zoom == range.upperBound
                if crossed != 0 || entersCloud || limit {
                    if tick(accent: entersCloud || limit) {
                        pinchTravel = limit ? 0 : pinchTravel - crossed * step
                    }
                }
            } else if entersCloud {
                tick()
            }
            camera = target
            motion = nil
            hovered = nil
            // A simultaneous drag should keep the new zoom on its next update.
            dragOrigin?.zoom = target.zoom
        }
    }

    @discardableResult
    private func tick(accent: Bool = false) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard haptics, now - lastTick >= 0.065 else { return false }
        lastTick = now
        AtlasHaptics.step()
        if accent {
            accentTask?.cancel()
            accentTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(34)) } catch { return }
                guard !Task.isCancelled else { return }
                AtlasHaptics.step()
            }
        }
        return true
    }

    private func rotate(_ value: DragGesture.Value) {
        if dragOrigin == nil {
            dragOrigin = currentCamera()
            motion = nil
            lastDetent = .zero
            rotationSteps = 0
            hovered = nil
        }
        guard let origin = dragOrigin else { return }
        var target = origin
        target.yaw += Double(value.translation.width) * 0.0075
        target.tilt = min(1.52, max(-1.52, origin.tilt + Double(value.translation.height) * 0.0075))
        camera = target
        let position = SIMD2(target.yaw - origin.yaw, target.tilt - origin.tilt)
        let step = 0.13
        let travel = (position - lastDetent) / step
        let crossed = SIMD2(travel.x.rounded(.towardZero), travel.y.rounded(.towardZero))
        guard crossed != .zero else { return }
        let nextStep = rotationSteps + 1
        if tick(accent: nextStep.isMultiple(of: 4)) {
            lastDetent += crossed * step
            rotationSteps = nextStep
        }
    }

    private func finishRotation(_ value: DragGesture.Value) {
        dragOrigin = nil
        guard !reduceMotion else { return }
        let dx = value.predictedEndTranslation.width - value.translation.width
        let dy = value.predictedEndTranslation.height - value.translation.height
        var target = camera
        target.yaw += min(0.82, max(-0.82, Double(dx) * 0.0041))
        target.tilt = min(1.52, max(-1.52, target.tilt + Double(dy) * 0.003))
        if abs(target.yaw - camera.yaw) + abs(target.tilt - camera.tilt) > 0.03 {
            move(to: target, duration: 0.62)
        }
    }

    private func hit(at point: CGPoint, size: CGSize) -> AtlasCloud.Entry? {
        let now = Date.now
        let projection = OrbitCamera.Projection(camera: currentCamera(at: now), size: size)
        let blend = blend(at: now)
        let ids = connectedIDs
        return cloud.entries.compactMap { entry -> (AtlasCloud.Entry, Double, Double)? in
            guard !onlyConnections || ids.contains(entry.node.id) else { return nil }
            let world = projection.viewSpace(entry.position(blend: blend))
            let visibility = reveal(nodeArrivals[entry.node.id], at: now, duration: 0.55) * depthFade(world.z)
            guard visibility > 0.15, let p = projection.point(world) else { return nil }
            let distance = hypot(p.x - point.x, p.y - point.y)
            return distance < 16 ? (entry, distance, world.z) : nil
        }.min { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 < $1.1 }?.0
    }

    private func reveal(_ start: Date?, at date: Date, duration: Double) -> Double {
        guard !reduceMotion, let start else { return 1 }
        return atlasProgress(date.timeIntervalSince(start), duration: duration)
    }

    private func depthFade(_ distance: Double) -> Double {
        atlasProgress(distance - OrbitCamera.near, duration: 0.48)
    }

    private func drawGraph(_ context: GraphicsContext, size: CGSize, at date: Date) {
        let projection = OrbitCamera.Projection(camera: currentCamera(at: date), size: size)
        let blend = blend(at: date)
        let neighbors = connectedIDs
        let entries = onlyConnections ? cloud.entries.filter { neighbors.contains($0.node.id) } : cloud.entries
        let world = entries.map { $0.position(blend: blend) }
        let view = world.map(projection.viewSpace)
        let indexes = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.node.id, $0.offset) })
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -8, dy: -8)
        var dust: [String: [Path]] = [:]
        var colors: [String: Color] = [:]
        for (index, entry) in entries.enumerated() {
            let visibility = reveal(nodeArrivals[entry.node.id], at: date, duration: 0.55)
            guard visibility > 0 else { continue }
            let group = entry.node.layer + (selected == nil || neighbors.contains(entry.node.id) ? "/full" : "/dim")
            colors[group] = entry.node.tint
            var bands = dust.removeValue(forKey: group) ?? Array(repeating: Path(), count: 6)
            for mote in entry.motes {
                let offset = mote.offset * (0.80 + 0.20 * visibility)
                let v = projection.viewSpace(world[index] + offset)
                guard let p = projection.point(v), bounds.contains(p) else { continue }
                let intensity = mote.brightness * depthFade(v.z) * visibility
                let band = min(5, Int(intensity * 7))
                guard band > 0 else { continue }
                let radius = min(1.7, mote.radius * pow(OrbitCamera.homeDistance / v.z, 0.36))
                bands[band].addEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
            }
            dust[group] = bands
        }
        for (group, bands) in dust {
            guard let color = colors[group] else { continue }
            let emphasis = group.hasSuffix("/dim") ? 0.52 : 1.0
            for (band, path) in bands.enumerated() where !path.isEmpty {
                context.fill(path, with: .color(color.opacity(Double(band) * 0.075 * emphasis)))
            }
        }

        let density = min(1, 200.0 / Double(max(1, edges.count)))
        for edge in edges {
            guard let a = indexes[edge.a], let b = indexes[edge.b] else { continue }
            let active = selected == edge.a || selected == edge.b
            let amount = reveal(edgeArrivals[edge.id], at: date, duration: 0.53)
            guard amount > 0 else { continue }
            let start = view[a]
            let end = start + (view[b] - start) * amount
            guard let (from, to) = projection.segment(start, end) else { continue }
            let learned = edge.kind == "learned"
            let suggested = edge.kind == "suggested"
            let tint = suggested ? Color.white : learned ? atlasLilac : entries[a].node.tint
            let overviewOpacity = suggested ? 0.24 : 0.27 * density
            let opacity = (active ? 0.78 : selected == nil ? overviewOpacity : 0.10 * density)
                * depthFade(max(start.z, end.z))
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            context.stroke(path, with: .color(tint.opacity(opacity)),
                           style: StrokeStyle(lineWidth: active ? 1.35 : 0.65, lineCap: .round,
                                              dash: suggested ? [1, 4] : learned ? [3, 4] : []))
            if !reduceMotion, amount >= 1, let launch = lightPulses[edge.id] {
                let leading = edge.b == selected ? end : start
                let destination = edge.b == selected ? start : end
                drawPulse(context, projection: projection, from: leading, to: destination,
                          elapsed: date.timeIntervalSince(launch), tint: tint)
            }
        }

        let ordered = entries.indices.sorted { view[$0].z > view[$1].z }
        var label: (AtlasNode, CGPoint, Double)?
        for index in ordered {
            let node = entries[index].node
            let depth = view[index].z
            guard let p = projection.point(view[index]), bounds.contains(p) else { continue }
            let visibility = reveal(nodeArrivals[node.id], at: date, duration: 0.55) * depthFade(depth)
            guard visibility > 0.03 else { continue }
            let active = selected == node.id || hovered == node.id
            let emphasized = selected == nil || neighbors.contains(node.id) || active
            let radius = min(6, (active ? 3.6 : 1.6 + node.signal * 1.2) * pow(OrbitCamera.homeDistance / depth, 0.38))
            let rect = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)
            if emphasized {
                context.fill(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(node.tint.opacity(0.15 * visibility)))
            }
            context.fill(Path(ellipseIn: rect), with: .color(node.tint.opacity((emphasized ? 0.96 : 0.41) * visibility)))
            if active {
                let ring = rect.insetBy(dx: -4, dy: -4)
                context.stroke(Path(ellipseIn: ring), with: .color(node.tint.opacity(0.82 * visibility)), lineWidth: 0.9)
                if selected == node.id && !reduceMotion {
                    let pulse = atlasProgress(date.timeIntervalSince(selectionStart), duration: 0.65)
                    if pulse < 1 {
                        context.stroke(Path(ellipseIn: ring.insetBy(dx: -pulse * 21, dy: -pulse * 21)),
                                       with: .color(node.tint.opacity((1 - pulse) * 0.63 * visibility)), lineWidth: 0.9)
                    }
                }
                if node.id == (hovered ?? selected) { label = (node, p, visibility) }
            }
        }
        if let (node, point, opacity) = label, size.width > 140 {
            let title = node.title.count > 35 ? String(node.title.prefix(34)) + "…" : node.title
            let text = context.resolve(Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white))
            let maxWidth = min(size.width - 32, 225)
            let width = min(maxWidth, text.measure(in: CGSize(width: maxWidth, height: 20)).width) + 16
            let x = min(size.width - width - 8, max(8, point.x + 13))
            let y = min(size.height - 53, max(44, point.y - 12))
            let bubble = CGRect(x: x, y: y, width: width, height: 24)
            var overlay = context
            overlay.opacity = opacity
            overlay.fill(Path(roundedRect: bubble, cornerRadius: 8), with: .color(atlasInk.opacity(0.96)))
            overlay.stroke(Path(roundedRect: bubble, cornerRadius: 8), with: .color(node.tint.opacity(0.33)))
            overlay.draw(text, in: bubble.insetBy(dx: 8, dy: 4))
        }
    }

    private func drawPulse(_ context: GraphicsContext, projection: OrbitCamera.Projection,
                           from start: SIMD3<Double>, to end: SIMD3<Double>, elapsed: Double, tint: Color) {
        let progress = elapsed / 0.92
        guard progress > 0, progress < 1 else { return }
        let head = start + (end - start) * progress
        let fade = min(1, progress * 12, (1 - progress) * 10) * depthFade(head.z)
        guard fade > 0, let point = projection.point(head) else { return }
        var tail = Path()
        let trailing = start + (end - start) * max(0, progress - 0.19)
        if let (from, to) = projection.segment(trailing, head) {
            tail.move(to: from)
            tail.addLine(to: to)
            context.stroke(tail, with: .linearGradient(
                Gradient(colors: [.clear, tint.opacity(0.85 * fade)]), startPoint: from, endPoint: to),
                style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
        }
        let halo = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: halo), with: .radialGradient(
            Gradient(colors: [tint.opacity(0.62 * fade), .clear]), center: point, startRadius: 0, endRadius: 5))
        context.fill(Path(ellipseIn: halo.insetBy(dx: 3.8, dy: 3.8)), with: .color(.white.opacity(fade)))
    }

    private func orbitButton(_ icon: String, _ label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button {
            action()
            tick()
        } label: {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).frame(width: 31, height: 31)
                .contentShape(Circle())
        }
        .buttonStyle(AtlasResultStyle(capsule: true))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct AtlasScrollInput: NSViewRepresentable {
    let enabled: Bool
    let zoom: (Double) -> Void

    func makeNSView(context: Context) -> ScrollProbe { ScrollProbe() }

    func updateNSView(_ view: ScrollProbe, context: Context) {
        view.zoom = enabled ? zoom : nil
    }

    final class ScrollProbe: NSView {
        var zoom: ((Double) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window, event.window === window, let zoom,
                      !isHiddenOrHasHiddenAncestor, visibleRect.contains(convert(event.locationInWindow, from: nil)),
                      abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
                if event.momentumPhase.isEmpty {
                    zoom(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8))
                }
                return nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

struct AtlasView: View {
    @ObservedObject var model: BrainModel
    @AppStorage("atlasShape") private var shape = AtlasShape.sphere
    @AppStorage("atlasHaptics") private var haptics = true
    @LocalState private var onlyConnections = false
    @LocalState private var inspectorVisible = true
    @LocalState private var showAllNodes = false
    @LocalState private var focusRequest = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @LocalState private var searchPresented = false
    private let searchRowHeight: CGFloat = 36
    private let searchPanelPadding: CGFloat = 7

    private var graph: AtlasSnapshot? { model.atlas }
    private var node: AtlasNode? { graph?.nodes.first { $0.id == model.selected?.id } }
    private var links: [AtlasEdge] {
        guard let id = node?.id else { return [] }
        return (graph?.edges ?? []).filter { $0.a == id || $0.b == id }.sorted {
            if ($0.kind == "suggested") != ($1.kind == "suggested") { return $1.kind == "suggested" }
            return $0.weight > $1.weight
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                HStack(spacing: 12) {
                    starfield
                    if inspectorVisible {
                        inspector.transition(.opacity)
                    }
                }
                .padding(.top, 13)
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: inspectorVisible)
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
            if searchPresented {
                dismissSearch()
            } else if model.selected != nil {
                model.closeAtlasDetail()
            } else {
                return .ignored
            }
            return .handled
        }
        .onChange(of: model.selected?.id) { _, selection in
            if selection == nil { onlyConnections = false }
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
            HStack(spacing: 12) {
                Text("Atlas").font(.system(size: 36, weight: .medium)).tracking(-1.8)
                    .accessibilityAddTraits(.isHeader)
                    .onTapGesture { dismissSearch() }
                Spacer()
                WorkspaceActions(model: model)
            }
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
                    select(hit)
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
        let frame = RoundedRectangle(cornerRadius: 24)
        return ZStack {
            frame.fill(atlasInk)
            AtlasOrbit(atlas: graph, selected: model.selected?.id,
                       shape: AtlasBrainSurface.bundled == nil ? .sphere : shape,
                       onlyConnections: onlyConnections && node != nil,
                       focusRequest: focusRequest, acceptsScroll: visibleSearchState == nil) { item in
                if let item {
                    select(item.hit)
                } else if model.selected != nil {
                    model.closeAtlasDetail()
                }
            }
            if graph?.nodes.isEmpty == true && !model.atlasBusy {
                ContentUnavailableView("Atlas är tomt", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text("Skapa eller importera en anteckning för att börja."))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 11) {
                legend("Anteckningar", atlasGold)
                legend("Källor", atlasIce)
                if !Distribution.store { legend("Skills", atlasLilac) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .brainGlass(Capsule())
            .padding(16)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                if AtlasBrainSurface.bundled != nil {
                    GlassSegmentedControl(selection: $shape, options: AtlasShape.allCases,
                                          label: "Form i Atlas", segmentWidth: 58, title: { $0.title }) {
                        if haptics { BrainHaptics.selection() }
                    }
                }
                Button {
                    inspectorVisible.toggle()
                    if haptics { BrainHaptics.selection() }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(inspectorVisible ? Color.white : Color.secondary)
                        .frame(width: 31, height: 31)
                }
                .buttonStyle(AtlasResultStyle(capsule: true))
                .accessibilityLabel(inspectorVisible ? "Dölj sidopanel" : "Visa sidopanel")
                .help(inspectorVisible ? "Dölj sidopanel" : "Visa sidopanel")
                .padding(4)
                .brainGlass(Capsule())
            }
            .padding(16)
        }
        .overlay(alignment: .bottomLeading) {
            Menu {
                Toggle("Haptisk återkoppling", isOn: $haptics)
                Button("Testa haptik", action: AtlasHaptics.step)
                .disabled(!haptics)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 31, height: 31)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(4)
            .brainGlass(Capsule())
            .padding(16)
            .accessibilityLabel("Inställningar för Atlas")
            .help("Dra för att rotera. Nyp eller rulla för att zooma in bland noderna.")
        }
        .clipShape(frame)
        .overlay { frame.strokeBorder(.white.opacity(0.09)).allowsHitTesting(false) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5).accessibilityHidden(true)
            Text(text).font(.system(size: 10, weight: .medium))
        }
    }

    private func select(_ item: Hit) {
        if model.selected?.id != item.id && haptics { BrainHaptics.selection() }
        if model.selected?.id != item.id { model.select(item) }
        inspectorVisible = true
    }

    private var inspector: some View {
        let frame = RoundedRectangle(cornerRadius: 24)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let item = model.selected {
                    Button("Avmarkera", systemImage: "xmark", action: model.closeAtlasDetail)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if item.kind == "note" && !item.path.hasPrefix("Codex Skills/") {
                        let pinned = model.pinnedNotes.contains(item.id)
                        Button(pinned ? "Lossa anteckningen" : "Fäst anteckningen", systemImage: pinned ? "pin.fill" : "pin") {
                            model.togglePin(item)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(pinned ? "Lossa anteckningen" : "Fäst anteckningen")
                    }
                } else {
                    Text("Utforska").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if graph?.nodes.isEmpty == false {
                        Toggle("Alla synliga noder", systemImage: "list.bullet", isOn: $showAllNodes)
                            .toggleStyle(.button)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help(showAllNodes ? "Visa senaste och fästa" : "Visa alla synliga noder")
                    }
                }
            }
            .frame(height: 26)
            ScrollView {
                Group {
                    if let item = model.selected { detail(item) }
                    else { overview }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(model.selected?.id)
                .transition(.opacity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: model.selected?.id)
        }
        .padding(16)
        .frame(width: 248)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(inset, in: frame)
        .overlay { frame.strokeBorder(.white.opacity(0.09)).allowsHitTesting(false) }
    }

    private var overview: some View {
        let nodes = graph?.nodes.map(\.hit) ?? []
        let recent = graph?.recent ?? []
        let pinned = nodes.filter { model.pinnedNotes.contains($0.id) }
        let pinnedIDs = Set(pinned.map(\.id))
        return VStack(alignment: .leading, spacing: 5) {
            if showAllNodes {
                ForEach(nodes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { row($0) }
            } else if !nodes.isEmpty {
                if !pinned.isEmpty {
                    Text("Fästa i vyn").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(pinned) { row($0) }
                }
                let remaining = recent.filter { !pinnedIDs.contains($0.id) }
                let items = recent.isEmpty && pinned.isEmpty ? Array(nodes.prefix(10)) : remaining
                if !items.isEmpty {
                    Text(recent.isEmpty ? "I Atlas" : "Senast öppnade")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, pinned.isEmpty ? 0 : 7)
                    ForEach(items) { row($0) }
                }
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

            if node != nil {
                HStack(spacing: 6) {
                    Button("Zooma till", systemImage: "viewfinder") {
                        focusRequest &+= 1
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Zooma till anteckningen")
                    if onlyConnections || !links.isEmpty {
                        Toggle("Visa bara kopplade noder", systemImage: "point.3.connected.trianglepath.dotted",
                               isOn: $onlyConnections)
                            .toggleStyle(.button)
                            .labelStyle(.iconOnly)
                            .help("Visa bara kopplade noder")
                    }
                }
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
                        row(neighbor.hit, subtitle: edge.kind == "suggested" ? "Föreslagen koppling"
                            : edge.kind == "learned" ? "Inlärt samband" : "Dokumentlänk")
                    }
                }
            }
        }
    }

    private func row(_ item: Hit, subtitle: String? = nil) -> some View {
        Button {
            select(item)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.kind == "inbox" ? "tray" : item.kind == "skill" ? "square.stack.3d.up" : "doc.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(graph?.nodes.first(where: { $0.id == item.id })?.tint ?? atlasIce)
                    .frame(width: 25, height: 25)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
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
            .padding(.vertical, 4).padding(.horizontal, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AtlasResultStyle())
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
            if graph?.edges.contains(where: { $0.kind == "suggested" }) == true {
                Label("Punktlinjer visar förslag", systemImage: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Förslagen bygger på gemensamma titelord eller en gemensam undermapp.")
            }
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

struct GlassSegmentedControl<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let label: String
    let segmentWidth: CGFloat
    let title: (Option) -> String
    var onChange: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    private let segmentHeight: CGFloat = 31

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(atlasInk.opacity(0.36))
                .overlay { Capsule().strokeBorder(.white.opacity(0.15)) }

            if let index = options.firstIndex(of: selection) {
                Color.clear
                    .frame(width: segmentWidth, height: segmentHeight)
                    .brainGlass(Capsule(), tint: .white.opacity(0.22))
                    .overlay { Capsule().strokeBorder(.white.opacity(0.16)) }
                    .offset(x: 3 + CGFloat(index) * segmentWidth)
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78), value: selection)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    Button {
                        guard selection != option else { return }
                        selection = option
                        onChange()
                    } label: {
                        Text(title(option))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(selection == option ? 1 : 0.72))
                            .frame(width: segmentWidth, height: segmentHeight)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(AtlasResultStyle(capsule: true))
                    .accessibilityAddTraits(selection == option ? [.isSelected] : [])
                }
            }
            .padding(3)
        }
        .fixedSize()
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

private struct AtlasResultStyle: ButtonStyle {
    var capsule = false

    func makeBody(configuration: Configuration) -> some View {
        AtlasResultRow(label: configuration.label, pressed: configuration.isPressed, capsule: capsule)
    }

    private struct AtlasResultRow<Label: View>: View {
        let label: Label
        let pressed: Bool
        let capsule: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @LocalState private var hovering = false

        var body: some View {
            label
                .background(Color.accentColor.opacity(pressed ? 0.64 : hovering ? 0.30 : 0),
                            in: RoundedRectangle(cornerRadius: capsule ? 100 : 10))
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
        }
    }
}
