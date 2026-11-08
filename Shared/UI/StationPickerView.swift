import SwiftUI
import UniformTypeIdentifiers

/// A separate page leaves the player's fixed transport and Program gestures intact.
struct StationPickerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppReduceMotion private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var stationTextScale: CGFloat = 15
    @State private var reordering = false
    @State private var draggedID: String?
    @State private var lastReorderedTargetID: String?

    private var grid: Bool { model.stationPreferences.displayMode == .grid }
    private var map: Bool { model.stationPreferences.displayMode == .map }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            VStack(spacing: 0) {
                pageHeader(landscape: landscape)
                if !landscape {
                    HStack {
                        displayControls
                        Spacer()
                        if !map { reorderButton }
                    }.padding(.horizontal, 16).padding(.bottom, 8)
                }
                Rectangle().fill(Color.philharmonicSeparator).frame(height: 0.5)
                if reordering && !(landscape && dynamicTypeSize.isAccessibilitySize) {
                    Text("Drag a station, or use the arrows to move it earlier or later.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                GeometryReader { viewport in
                    if map {
                        StationMapView(stations: model.orderedStations, selectedStation: model.selectedStation,
                                       mapStyle: model.settings.stationMapStyle) { station in
                            model.selectStation(station.id)
                        }
                    } else if landscape {
                        landscapeStations(size: viewport.size)
                    } else {
                        portraitStations
                    }
                }
            }
        }
        .foregroundStyle(Color.philharmonicInk)
        .background(Color.philharmonicBackground.ignoresSafeArea())
        .tint(.philharmonicRed)
        .onAppear { PlayerOrientation.setProgrammeVisible(false); PlayerOrientation.refresh() }
        .onChange(of: model.stationPreferences.displayMode) { mode in
            if mode == .map { reordering = false }
        }
    }

    private func pageHeader(landscape: Bool) -> some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44).philharmonicControlSurface(Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Back to player")
            Text("Stations").font(.title2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if landscape { displayControls; if !map { reorderButton } }
        }.padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var displayControls: some View {
        Picker("Station display", selection: Binding(get: { model.stationPreferences.displayMode },
                                                     set: { mode in
            if mode != .map, !map {
                withAnimation(reduceMotion ? nil : .default) { model.setStationDisplayMode(mode) }
            } else { model.setStationDisplayMode(mode) }
        })) {
            displayOption(.grid, symbol: "square.grid.2x2", title: "Grid view")
            displayOption(.list, symbol: "list.bullet", title: "List view")
            displayOption(.map, symbol: "globe", title: "Map view")
        }
        .pickerStyle(.segmented).frame(width: 180, height: 44)
        .accessibilityIdentifier("stations-display")
    }

    private func displayOption(_ mode: StationDisplayMode, symbol: String, title: String) -> some View {
        Image(systemName: symbol).tag(mode).accessibilityLabel(title)
            .accessibilityIdentifier("stations-mode-\(mode.rawValue)")
    }

    private var reorderButton: some View {
        Button { withAnimation(reduceMotion ? nil : .default) { reordering.toggle() } } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: reordering ? "checkmark" : "arrow.up.arrow.down")
                        .font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
                } else {
                    Label(reordering ? "Done" : "Reorder", systemImage: reordering ? "checkmark" : "arrow.up.arrow.down")
                        .font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 44)
                }
            }.philharmonicControlSurface(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reordering ? "Done reordering" : "Reorder stations")
        .accessibilityIdentifier("stations-reorder")
    }

    private var portraitStations: some View {
        ScrollView(.vertical) {
            // One stable native grid preserves each card's identity while its
            // columns and internal AnyLayout interpolate between grid and list.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: grid ? 2 : 1),
                      spacing: grid ? 14 : 12) {
                ForEach(model.orderedStations) { station in stationCard(station, grid: grid, compact: false) }
            }.padding(16)
        }.accessibilityIdentifier("stations-vertical-scroll")
    }

    private func landscapeStations(size: CGSize) -> some View {
        let entriesPerPage = grid ? 2 : 1
        let stations = model.orderedStations
        let pageCount = (stations.count + entriesPerPage - 1) / entriesPerPage
        // At accessibility sizes, let each row extend horizontally instead of
        // forcing large names into a short landscape viewport. The same row
        // still contains two grid entries or one list entry, all reachable by
        // horizontal scrolling; text and the reorder footer stay untruncated.
        let expandedCardWidth = 360 * max(1, stationTextScale / 15)
        let pageWidth = dynamicTypeSize.isAccessibilitySize
            ? max(size.width, expandedCardWidth * CGFloat(entriesPerPage) + (grid ? 16 : 0) + 32)
            : size.width
        return ScrollView(.horizontal) {
            LazyHStack(alignment: .center, spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { page in
                    HStack(spacing: 16) {
                        ForEach(Array(stations.dropFirst(page * entriesPerPage).prefix(entriesPerPage))) { station in
                            stationCard(station, grid: grid, compact: true)
                                .frame(maxWidth: .infinity)
                        }
                        if grid && page == pageCount - 1 && stations.count % 2 != 0 {
                            Color.clear.frame(maxWidth: .infinity).accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(width: pageWidth, height: size.height)
                }
            }
        }.accessibilityIdentifier("stations-horizontal-scroll")
    }

    private func stationCard(_ station: RadioStation, grid: Bool, compact: Bool) -> some View {
        let selected = station.id == model.selectedStation.id
        let index = model.orderedStations.firstIndex(where: { $0.id == station.id }) ?? 0
        return VStack(spacing: 0) {
            Button { model.selectStation(station.id) } label: {
                stationLabel(station, selected: selected, grid: grid, compact: compact)
                    .padding(14).frame(maxWidth: .infinity, minHeight: compact ? 82 : (grid ? 188 : 88))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(station.name)
            .accessibilityValue(selected ? "Selected, position \(index + 1)" : "Position \(index + 1)")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier("station-\(station.id)")
            .accessibilityAction(named: Text("Move earlier")) { moveStation(station.id, by: -1) }
            .accessibilityAction(named: Text("Move later")) { moveStation(station.id, by: 1) }
            .onDrag {
                draggedID = station.id
                lastReorderedTargetID = nil
                return NSItemProvider(object: ("philharmonic-station:" + station.id) as NSString)
            }
            if reordering {
                Rectangle().fill(Color.philharmonicSeparator).frame(height: 0.5)
                HStack(spacing: 0) {
                    moveButton(station, earlier: true, enabled: index > 0)
                    Rectangle().fill(Color.philharmonicSeparator).frame(width: 0.5, height: 24)
                    moveButton(station, earlier: false, enabled: index < model.orderedStations.count - 1)
                }
            }
        }
        .background(Color.philharmonicSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Color.philharmonicRed : Color.philharmonicSeparator,
                                                                lineWidth: selected ? 1.5 : 0.75))
        .onDrop(of: [UTType.plainText], delegate: StationReorderDrop(targetID: station.id, draggedID: $draggedID,
                                                                 lastTargetID: $lastReorderedTargetID) { id, target in
            let order = model.orderedStations
            guard let source = order.firstIndex(where: { $0.id == id }),
                  let destination = order.firstIndex(where: { $0.id == target }) else { return }
            moveStation(id, by: destination - source)
        })
    }

    private func stationLabel(_ station: RadioStation, selected: Bool, grid: Bool, compact: Bool) -> some View {
        let vertical = grid && !compact
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            StationLogo(station: station).frame(width: vertical ? 76 : (compact ? 52 : 62), height: vertical ? 64 : 52)
            stationText(station, grid: grid)
                .multilineTextAlignment(vertical ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: vertical ? .center : .leading)
            selectionMark(selected)
        }.frame(maxWidth: .infinity)
    }

    private func stationText(_ station: RadioStation, grid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(station: station).font(grid ? .subheadline.weight(.semibold) : .body)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = station.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func selectionMark(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 19)).foregroundStyle(selected ? Color.philharmonicRed : Color.philharmonicSeparator)
            .modifier(NativeSymbolReplacement(value: selected))
            .accessibilityHidden(true)
    }

    private func moveButton(_ station: RadioStation, earlier: Bool, enabled: Bool) -> some View {
        Button { moveStation(station.id, by: earlier ? -1 : 1) } label: {
            Image(systemName: earlier ? "arrow.left" : "arrow.right")
                .font(.system(size: 16, weight: .medium)).frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.3)
        .accessibilityLabel("Move \(station.name) \(earlier ? "earlier" : "later")")
        .accessibilityIdentifier("station-move-\(earlier ? "earlier" : "later")-\(station.id)")
    }

    private func moveStation(_ id: String, by offset: Int) {
        withAnimation(reduceMotion ? nil : .default) { model.moveStation(id, by: offset) }
    }
}

private struct StationReorderDrop: DropDelegate {
    let targetID: String
    @Binding var draggedID: String?
    @Binding var lastTargetID: String?
    let move: (String, String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedID != nil && info.hasItemsConforming(to: [UTType.plainText.identifier])
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != targetID, lastTargetID != targetID else { return }
        lastTargetID = targetID
        move(draggedID, targetID)
    }
    func performDrop(info: DropInfo) -> Bool {
        let source = draggedID
        let reorderedOnEntry = lastTargetID != nil
        draggedID = nil; lastTargetID = nil
        guard let source else { return false }
        // A final drop still works if the native interaction omitted hover
        // entry. Once hover already reordered, a second move would swap back.
        if !reorderedOnEntry && source != targetID { move(source, targetID) }
        return true
    }
}
