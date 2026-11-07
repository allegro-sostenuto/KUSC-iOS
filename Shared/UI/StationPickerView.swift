import SwiftUI
import UniformTypeIdentifiers

/// A separate page leaves the player's fixed transport and Program gestures intact.
struct StationPickerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var stationTextScale: CGFloat = 15
    @State private var reordering = false
    @State private var draggedID: String?
    @State private var lastReorderedTargetID: String?

    private var grid: Bool { model.stationPreferences.displayMode == .grid }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            VStack(spacing: 0) {
                pageHeader(landscape: landscape)
                if !landscape {
                    HStack {
                        displayControls
                        Spacer()
                        reorderButton
                    }.padding(.horizontal, 20).padding(.bottom, 12)
                }
                Rectangle().fill(Color.philharmonicSeparator).frame(height: 0.5)
                if reordering && !(landscape && dynamicTypeSize.isAccessibilitySize) {
                    Text("Drag a station, or use the arrows to move it earlier or later.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.vertical, 8)
                }
                GeometryReader { viewport in
                    if landscape {
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
            if landscape { displayControls; reorderButton }
        }.padding(.horizontal, 20).padding(.vertical, 8)
    }

    private var displayControls: some View {
        HStack(spacing: 0) {
            displayButton(.grid, symbol: "square.grid.2x2", title: "Grid view")
            displayButton(.list, symbol: "list.bullet", title: "List view")
        }
        .philharmonicControlSurface(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Station display")
    }

    private func displayButton(_ mode: StationDisplayMode, symbol: String, title: String) -> some View {
        Button { model.setStationDisplayMode(mode) } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                .frame(width: 52, height: 44)
                .foregroundStyle(model.stationPreferences.displayMode == mode ? Color.philharmonicRed : Color.philharmonicInk)
                .overlay(alignment: .bottom) {
                    if model.stationPreferences.displayMode == mode {
                        Capsule().fill(Color.philharmonicRed).frame(width: 20, height: 2).padding(.bottom, 5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(model.stationPreferences.displayMode == mode ? [.isSelected] : [])
        .accessibilityIdentifier(mode == .grid ? "stations-mode-grid" : "stations-mode-list")
    }

    private var reorderButton: some View {
        Button { reordering.toggle() } label: {
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
            if grid {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(model.orderedStations) { station in stationCard(station, grid: true, compact: false) }
                }.padding(20)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(model.orderedStations) { station in stationCard(station, grid: false, compact: false) }
                }.padding(20)
            }
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
            ? max(size.width, expandedCardWidth * CGFloat(entriesPerPage) + (grid ? 16 : 0) + 40)
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
                    .padding(.horizontal, 20).padding(.vertical, 12)
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
            .accessibilityAction(named: Text("Move earlier")) { model.moveStation(station.id, by: -1) }
            .accessibilityAction(named: Text("Move later")) { model.moveStation(station.id, by: 1) }
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
        .background(Color.philharmonicSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Color.philharmonicRed : Color.philharmonicSeparator,
                                                                lineWidth: selected ? 1.5 : 0.75))
        .onDrop(of: [UTType.plainText], delegate: StationReorderDrop(targetID: station.id, draggedID: $draggedID,
                                                                 lastTargetID: $lastReorderedTargetID) { id, target in
            let order = model.orderedStations
            guard let source = order.firstIndex(where: { $0.id == id }),
                  let destination = order.firstIndex(where: { $0.id == target }) else { return }
            model.moveStation(id, by: destination - source)
        })
    }

    @ViewBuilder
    private func stationLabel(_ station: RadioStation, selected: Bool, grid: Bool, compact: Bool) -> some View {
        if grid && !compact {
            VStack(spacing: 10) {
                StationLogo(station: station).frame(width: 76, height: 64)
                stationText(station).multilineTextAlignment(.center)
                selectionMark(selected)
            }.frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 12) {
                StationLogo(station: station).frame(width: compact ? 52 : 62, height: 52)
                stationText(station).frame(maxWidth: .infinity, alignment: .leading)
                selectionMark(selected)
            }
        }
    }

    private func stationText(_ station: RadioStation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(station: station).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if let subtitle = station.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func selectionMark(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 19)).foregroundStyle(selected ? Color.philharmonicRed : Color.philharmonicSeparator)
            .accessibilityHidden(true)
    }

    private func moveButton(_ station: RadioStation, earlier: Bool, enabled: Bool) -> some View {
        Button { model.moveStation(station.id, by: earlier ? -1 : 1) } label: {
            Image(systemName: earlier ? "arrow.left" : "arrow.right")
                .font(.system(size: 16, weight: .medium)).frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.3)
        .accessibilityLabel("Move \(station.name) \(earlier ? "earlier" : "later")")
        .accessibilityIdentifier("station-move-\(earlier ? "earlier" : "later")-\(station.id)")
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
