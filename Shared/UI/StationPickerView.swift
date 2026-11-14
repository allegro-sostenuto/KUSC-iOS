import SwiftUI
import UIKit

/// A separate page leaves the player's fixed transport and Program gestures intact.
struct StationPickerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppReduceMotion private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var stationTextScale: CGFloat = 15
    @State private var reordering = false

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
                        if reordering && !map { doneButton }
                    }.padding(.horizontal, 16).padding(.bottom, 8)
                }
                Rectangle().fill(Color.philharmonicSeparator).frame(height: 0.5)
                if reordering && !(landscape && dynamicTypeSize.isAccessibilitySize) {
                    Text(grid ? "Drag stations to reorder." : "Drag a reorder handle to move a station.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                if map {
                    StationMapView(stations: model.orderedStations, selectedStation: model.selectedStation,
                                   mapStyle: model.settings.stationMapStyle) { station in
                        model.selectStation(station.id)
                    }
                } else {
                    NativeStationCollection(stations: model.orderedStations, selectedID: model.selectedStation.id,
                                            grid: grid, landscape: landscape, reordering: reordering,
                                            reduceMotion: reduceMotion, dynamicTypeSize: dynamicTypeSize,
                                            stationTextScale: stationTextScale,
                                            select: { model.selectStation($0) },
                                            beginReordering: { setReordering(true) },
                                            move: { model.moveStation($0, by: $1) })
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
            if landscape {
                displayControls
                if reordering && !map { doneButton }
            }
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

    private var doneButton: some View {
        Button { setReordering(false) } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
                } else {
                    Label("Done", systemImage: "checkmark")
                        .font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(minHeight: 44)
                }
            }.philharmonicControlSurface(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done reordering")
        .accessibilityIdentifier("stations-reorder-done")
    }

    private func setReordering(_ enabled: Bool) {
        withAnimation(reduceMotion ? nil : .default) { reordering = enabled }
    }
}

private struct NativeStationCollection: UIViewControllerRepresentable {
    let stations: [RadioStation]
    let selectedID: String
    let grid: Bool
    let landscape: Bool
    let reordering: Bool
    let reduceMotion: Bool
    let dynamicTypeSize: DynamicTypeSize
    let stationTextScale: CGFloat
    let select: (String) -> Void
    let beginReordering: () -> Void
    let move: (String, Int) -> Void

    func makeUIViewController(context: Context) -> Controller { Controller(self) }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(self)
    }

    final class Controller: UICollectionViewController {
        private var configuration: NativeStationCollection
        private var stations: [RadioStation]
        private let reuseIdentifier = "station"

        init(_ configuration: NativeStationCollection) {
            self.configuration = configuration
            self.stations = configuration.stations
            super.init(collectionViewLayout: Self.layout(for: configuration))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Use init(_:) for station collections") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = UIColor(Color.philharmonicBackground)
            collectionView.backgroundColor = UIColor(Color.philharmonicBackground)
            collectionView.contentInsetAdjustmentBehavior = .never
            collectionView.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: reuseIdentifier)
            collectionView.dragInteractionEnabled = false
            updateEditing()
            applyScrollingDirection()
        }

        func update(_ next: NativeStationCollection) {
            let previous = configuration
            configuration = next
            guard isViewLoaded else { stations = next.stations; return }
            let layoutChanged = previous.grid != next.grid || previous.landscape != next.landscape ||
                previous.stationTextScale != next.stationTextScale || previous.dynamicTypeSize != next.dynamicTypeSize
            let orderChanged = stations.map(\.id) != next.stations.map(\.id)
            let editingChanged = previous.reordering != next.reordering
            if layoutChanged || editingChanged || orderChanged { collectionView.cancelInteractiveMovement() }
            if editingChanged { updateEditing() }
            if orderChanged {
                stations = next.stations
                collectionView.reloadData()
            }
            if layoutChanged {
                collectionView.setCollectionViewLayout(Self.layout(for: next), animated: !next.reduceMotion && !editingChanged)
                applyScrollingDirection()
            }
            if layoutChanged || editingChanged || previous.selectedID != next.selectedID { refreshVisibleCells() }
        }

        private func updateEditing() {
            installsStandardGestureForInteractiveMovement = configuration.reordering
            collectionView.isEditing = configuration.reordering
        }

        private func applyScrollingDirection() {
            collectionView.alwaysBounceHorizontal = configuration.landscape
            collectionView.alwaysBounceVertical = !configuration.landscape
            collectionView.accessibilityIdentifier = configuration.landscape
                ? "stations-horizontal-scroll" : "stations-vertical-scroll"
        }

        private static func layout(for configuration: NativeStationCollection) -> UICollectionViewLayout {
            let settings = UICollectionViewCompositionalLayoutConfiguration()
            settings.scrollDirection = configuration.landscape ? .horizontal : .vertical
            return UICollectionViewCompositionalLayout(sectionProvider: { _, environment in
                let columns = configuration.grid ? 2 : 1
                let spacing: CGFloat = configuration.landscape ? 16 : (configuration.grid ? 14 : 12)
                let estimatedHeight: CGFloat = configuration.grid ? 188 : 88
                let height: NSCollectionLayoutDimension = configuration.landscape
                    ? .fractionalHeight(1) : .estimated(estimatedHeight)
                let width = environment.container.effectiveContentSize.width
                let accessibleCardWidth = 360 * max(1, configuration.stationTextScale / 15)
                let pageWidth = configuration.dynamicTypeSize.isAccessibilitySize
                    ? max(width, accessibleCardWidth * CGFloat(columns) + spacing * CGFloat(columns - 1) + 32)
                    : width
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1 / CGFloat(columns)),
                                                                    heightDimension: height))
                let group = NSCollectionLayoutGroup.horizontal(
                    layoutSize: .init(widthDimension: configuration.landscape ? .absolute(max(1, pageWidth - 32)) : .fractionalWidth(1),
                                      heightDimension: height),
                    repeatingSubitem: item, count: columns)
                group.interItemSpacing = .fixed(spacing)
                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = configuration.landscape ? 32 : spacing
                section.contentInsets = .init(top: configuration.landscape ? 12 : 16, leading: 16,
                                              bottom: configuration.landscape ? 12 : 16, trailing: 16)
                return section
            }, configuration: settings)
        }

        override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            stations.count
        }

        override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! UICollectionViewListCell
            configure(cell, at: indexPath.item)
            return cell
        }

        private func configure(_ cell: UICollectionViewListCell, at index: Int) {
            let station = stations[index]
            let selected = station.id == configuration.selectedID
            var background = UIBackgroundConfiguration.clear()
            background.backgroundColor = UIColor(Color.philharmonicSurface)
            background.cornerRadius = 16
            background.strokeColor = UIColor(selected ? Color.philharmonicRed : Color.philharmonicSeparator)
            background.strokeWidth = selected ? 1.5 : 0.75
            cell.backgroundConfiguration = background
            cell.contentConfiguration = UIHostingConfiguration {
                StationCardContents(station: station, selected: selected, grid: configuration.grid,
                                    compact: configuration.landscape)
                    .foregroundStyle(Color.philharmonicInk)
                    .environment(\.dynamicTypeSize, configuration.dynamicTypeSize)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }.margins(.all, 0)
                .minSize(width: 0, height: configuration.landscape ? 82 : (configuration.grid ? 188 : 88))
            cell.accessories = configuration.reordering && !configuration.grid ? [.reorder(displayed: .always)] : []
            cell.contentView.accessibilityElementsHidden = true
            cell.isAccessibilityElement = true
            cell.accessibilityIdentifier = "station-\(station.id)"
            cell.accessibilityLabel = station.name
            cell.accessibilityValue = selected ? "Selected, position \(index + 1)" : "Position \(index + 1)"
            cell.accessibilityTraits = selected ? [.button, .selected] : [.button]
            if configuration.reordering {
                var actions: [UIAccessibilityCustomAction] = []
                if index > 0 { actions.append(accessibleMove(station.id, by: -1, name: "Move earlier")) }
                if index + 1 < stations.count { actions.append(accessibleMove(station.id, by: 1, name: "Move later")) }
                cell.accessibilityCustomActions = actions
            } else {
                cell.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Reorder Stations") { [weak self] _ in
                    self?.configuration.beginReordering()
                    return self != nil
                }]
            }
        }

        private func refreshVisibleCells() {
            for path in collectionView.indexPathsForVisibleItems where stations.indices.contains(path.item) {
                if let cell = collectionView.cellForItem(at: path) as? UICollectionViewListCell {
                    configure(cell, at: path.item)
                }
            }
        }

        private func accessibleMove(_ id: String, by offset: Int, name: String) -> UIAccessibilityCustomAction {
            UIAccessibilityCustomAction(name: name) { [weak self] _ in
                guard let self, self.configuration.reordering,
                      let source = self.stations.firstIndex(where: { $0.id == id }),
                      self.stations.indices.contains(source + offset) else { return false }
                let from = IndexPath(item: source, section: 0)
                let to = IndexPath(item: source + offset, section: 0)
                let move = {
                    self.collectionView.performBatchUpdates({
                        self.moveStation(from: from, to: to)
                        self.collectionView.moveItem(at: from, to: to)
                    }, completion: nil)
                }
                if self.configuration.reduceMotion { UIView.performWithoutAnimation(move) }
                else { move() }
                return true
            }
        }

        override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: false)
            guard !configuration.reordering, stations.indices.contains(indexPath.item) else { return }
            configuration.select(stations[indexPath.item].id)
        }

        override func collectionView(_ collectionView: UICollectionView,
                                     contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
            guard !configuration.reordering, indexPaths.count == 1 else { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                let reorder = UIAction(title: "Reorder Stations", image: UIImage(systemName: "arrow.up.arrow.down")) { _ in
                    self?.configuration.beginReordering()
                }
                return UIMenu(children: [reorder])
            }
        }

        override func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
            configuration.reordering
        }

        override func collectionView(_ collectionView: UICollectionView, moveItemAt source: IndexPath, to destination: IndexPath) {
            moveStation(from: source, to: destination)
        }

        private func moveStation(from source: IndexPath, to destination: IndexPath) {
            guard configuration.reordering, source != destination,
                  stations.indices.contains(source.item), stations.indices.contains(destination.item) else { return }
            let station = stations.remove(at: source.item)
            stations.insert(station, at: destination.item)
            configuration.move(station.id, destination.item - source.item)
            DispatchQueue.main.async { [weak self] in self?.refreshVisibleCells() }
        }
    }
}

private struct StationCardContents: View {
    let station: RadioStation
    let selected: Bool
    let grid: Bool
    let compact: Bool

    var body: some View {
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
}
