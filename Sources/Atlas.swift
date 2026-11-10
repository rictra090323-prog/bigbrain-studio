import SwiftUI

struct AtlasNode: Decodable, Identifiable {
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

struct AtlasEdge: Decodable, Identifiable {
    let a: String, b: String, kind: String
    let weight: Double
    let count: Int
    var id: String { a + "\u{1f}" + b + "\u{1f}" + kind }
}

struct AtlasSnapshot: Decodable {
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

private struct OrbitCamera {
    var yaw: Double = -0.43
    var tilt: Double = 0.47
    var zoom: Double = 1

    func project(x: Double, y: Double, z: Double, size: CGSize) -> (point: CGPoint, depth: Double, scale: Double) {
        let xx = x * cos(yaw) + z * sin(yaw)
        let zz = z * cos(yaw) - x * sin(yaw)
        let yy = y * cos(tilt) - zz * sin(tilt)
        let depth = y * sin(tilt) + zz * cos(tilt)
        let scale = 3.65 / (3.65 - depth)
        let unit = min(size.width * 0.40, size.height * 0.41) * zoom
        return (CGPoint(x: size.width / 2 + xx * unit * scale,
                        y: size.height * 0.55 - yy * unit * scale), depth, scale)
    }
}

struct AtlasOrbit: View {
    let atlas: AtlasSnapshot?
    let selected: String?
    let choose: (AtlasNode) -> Void

    @LocalState private var camera = OrbitCamera()
    @LocalState private var dragOrigin: OrbitCamera?

    private func position(_ node: AtlasNode, size: CGSize) -> (point: CGPoint, depth: Double, scale: Double) {
        camera.project(x: node.x, y: node.y, z: node.z, size: size)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Canvas { context, bounds in
                var grid = Path()
                for depth in [-0.81, 0, 0.81] {
                    for radius in [0.46, 0.91, 1.16] {
                        for step in 0...64 {
                            let a = Double(step) * 2 * .pi / 64
                            let point = camera.project(x: cos(a) * radius, y: sin(a) * radius, z: depth, size: bounds).point
                            if step == 0 { grid.move(to: point) } else { grid.addLine(to: point) }
                        }
                    }
                }
                context.stroke(grid, with: .color(atlasBlue.opacity(0.28)), style: StrokeStyle(lineWidth: 0.65, dash: [2, 5]))
                guard let atlas else { return }
                let points = Dictionary(uniqueKeysWithValues: atlas.nodes.map { ($0.id, position($0, size: bounds)) })
                for edge in atlas.edges {
                    guard let one = points[edge.a]?.point, let two = points[edge.b]?.point else { continue }
                    let active = selected == edge.a || selected == edge.b
                    var trace = Path()
                    trace.move(to: one)
                    trace.addLine(to: two)
                    let learned = edge.kind == "learned"
                    let color = learned ? atlasLilac : atlasIce
                    context.stroke(trace, with: .color(color.opacity(active ? 0.8 : 0.18 + edge.weight * 0.11)),
                                   style: StrokeStyle(lineWidth: active ? 1.55 : 0.65, dash: learned ? [4, 4] : []))
                }
                let ordered = atlas.nodes.sorted { (points[$0.id]?.depth ?? 0) < (points[$1.id]?.depth ?? 0) }
                for node in ordered {
                    guard let p = points[node.id] else { continue }
                    let chosen = selected == node.id
                    let radius = (chosen ? 6.7 : 2.5 + node.signal * 2.5 + min(Double(node.degree), 12) * 0.09) * p.scale
                    let rect = CGRect(x: p.point.x - radius, y: p.point.y - radius, width: 2 * radius, height: 2 * radius)
                    if chosen || node.signal > 0.35 {
                        context.fill(Path(ellipseIn: rect.insetBy(dx: -6, dy: -6)), with: .color(node.tint.opacity(0.16)))
                    }
                    context.fill(Path(ellipseIn: rect), with: .color(node.tint.opacity(chosen ? 1 : 0.86)))
                    if chosen {
                        context.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(node.tint), lineWidth: 0.9)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                let origin = dragOrigin ?? camera
                dragOrigin = origin
                camera.yaw = origin.yaw + Double(value.translation.width) * 0.009
                camera.tilt = min(1.35, max(-1.35, origin.tilt + Double(value.translation.height) * 0.009))
            }.onEnded { _ in dragOrigin = nil })
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                let candidates = (atlas?.nodes ?? []).map { node in
                    let p = position(node, size: size).point
                    return (node, hypot(p.x - value.location.x, p.y - value.location.y))
                }
                if let nearest = candidates.min(by: { $0.1 < $1.1 }), nearest.1 < 19 { choose(nearest.0) }
            })
            .accessibilityHidden(true)
        }
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 4) {
                orbitButton("minus", "Zooma ut") { camera.zoom = max(0.55, camera.zoom / 1.2) }
                orbitButton("plus", "Zooma in") { camera.zoom = min(2, camera.zoom * 1.2) }
                orbitButton("arrow.counterclockwise", "Återställ perspektivet") { camera = OrbitCamera() }
            }
            .padding(5)
            .brainGlass(Capsule())
            .padding(15)
        }
    }

    private func orbitButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).frame(width: 31, height: 31)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label).help(label)
    }
}

struct AtlasView: View {
    @ObservedObject var model: BrainModel

    private var graph: AtlasSnapshot? { model.atlas }
    private var node: AtlasNode? { graph?.nodes.first { $0.id == model.selected?.id } }
    private var links: [AtlasEdge] {
        guard let id = node?.id else { return [] }
        return (graph?.edges ?? []).filter { $0.a == id || $0.b == id }.sorted { $0.weight > $1.weight }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            masthead
            HStack(spacing: 12) {
                starfield
                inspector
            }
            footer
        }
        .padding(.horizontal, 21)
        .padding(.top, 14)
        .padding(.bottom, 19)
        .task(id: model.dashboard?.config.vault) {
            await model.loadAtlas()
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Atlas").font(.system(size: 48, weight: .medium))
                .tracking(-3.4).accessibilityAddTraits(.isHeader)
            QueryBox(query: $model.query, placeholder: "Sök med ord, begrepp eller en fråga…",
                     autofocus: false, prominent: true, action: model.searchFromAtlas)
        }
    }

    private var starfield: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24).fill(atlasInk)
            RadialGradient(colors: [atlasBlue.opacity(0.43), atlasInk.opacity(0.25), atlasInk.opacity(0)],
                           center: .center, startRadius: 0, endRadius: 360)
            LinearGradient(colors: [atlasLilac.opacity(0.12), .clear, atlasIce.opacity(0.09)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            AtlasOrbit(atlas: graph, selected: model.selected?.id) { item in
                model.select(item.hit)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Dra för att rotera. Välj en nod för att läsa.").font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.69))
                Spacer()
                HStack(spacing: 11) {
                    legend("Källor", atlasIce)
                    legend("Anteckningar", Color(red: 0.75, green: 0.84, blue: 1))
                    if !Distribution.store { legend("Skills", atlasLilac) }
                }
                .padding(7).background(atlasInk.opacity(0.80), in: Capsule())
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).allowsHitTesting(false)
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
            Button("Öppna anteckningen", systemImage: "arrow.up.right") {
                model.reply = nil
                model.show(.search)
                model.select(item, train: false)
            }.buttonStyle(.borderedProminent)

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
