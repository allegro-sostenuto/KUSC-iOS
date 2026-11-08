import SwiftUI
import MapKit

struct StationMapView: View {
    let stations: [RadioStation]
    let selectedStation: RadioStation
    let mapStyle: StationMapStyle
    let select: (RadioStation) -> Void
    @State private var zoom: StationMapZoom = .globe
    @State private var focusedCity: StationCity
    @State private var cameraRequest = UUID()
    @State private var presentedCity: StationCityGroup?
    @State private var pendingStation: RadioStation?

    init(stations: [RadioStation], selectedStation: RadioStation, mapStyle: StationMapStyle,
         select: @escaping (RadioStation) -> Void) {
        self.stations = stations
        self.selectedStation = selectedStation
        self.mapStyle = mapStyle
        self.select = select
        _focusedCity = State(initialValue: StationGeography.city(for: selectedStation) ?? StationGeography.cities[0])
    }

    private var cities: [StationCityGroup] { StationGeography.groups(stations: stations) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Map zoom", selection: Binding(get: { zoom }, set: { level in
                    zoom = level
                    cameraRequest = UUID()
                })) {
                    ForEach(StationMapZoom.allCases) { level in
                        Text(level.title).tag(level).accessibilityIdentifier("map-zoom-\(level.rawValue)")
                    }
                }.pickerStyle(.segmented).accessibilityIdentifier("map-zoom")
                Menu {
                    ForEach(cities) { group in
                        Button { choose(group) } label: {
                            Text("\(group.city.name) · \(group.stations.count)")
                        }.accessibilityIdentifier("map-city-list-\(group.id)")
                    }
                } label: {
                    Image(systemName: "list.bullet").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Cities").accessibilityIdentifier("map-cities")
            }.padding(.horizontal, 16).padding(.vertical, 6)

            NativeStationMap(cities: cities, selectedCityID: StationGeography.city(for: selectedStation)?.id,
                             zoom: zoom, mapStyle: mapStyle, focusedCity: focusedCity, cameraRequest: cameraRequest,
                             choose: choose, cameraChanged: { city, level in
                focusedCity = city
                zoom = level // Following a gesture never issues a camera request.
            }, expandCluster: { city in
                focusedCity = city
                if zoom == .globe { zoom = .continent }
                else if zoom == .continent { zoom = .country }
                cameraRequest = UUID()
            })
            .accessibilityIdentifier("stations-map")

            HStack(spacing: 8) {
                Text(zoom == .globe ? "Pinch to zoom · Tap a city to choose a station" : (zoom == .continent ? focusedCity.continent.name : focusedCity.countryName))
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    focusedCity = StationGeography.city(for: selectedStation) ?? focusedCity
                    cameraRequest = UUID()
                } label: {
                    Image(systemName: "scope").frame(width: 44, height: 44)
                }.accessibilityLabel("Centre on selected station").accessibilityIdentifier("map-recentre")
            }.padding(.leading, 16).padding(.trailing, 4)
        }
        .sheet(item: $presentedCity, onDismiss: {
            if let station = pendingStation {
                pendingStation = nil
                select(station)
            }
        }) { group in
            NavigationStack {
                List(group.stations) { station in
                    Button {
                        pendingStation = station
                        presentedCity = nil
                    } label: {
                        HStack(spacing: 12) {
                            StationLogo(station: station).frame(width: 40, height: 40)
                            Text(station: station).foregroundStyle(Color.philharmonicInk)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if selectedStation.id == station.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.philharmonicRed)
                            }
                        }.frame(minHeight: 44)
                    }
                    .listRowBackground(Color.philharmonicSurface)
                    .accessibilityIdentifier("map-station-\(station.id)")
                }
                .scrollContentBackground(.hidden)
                .background(Color.philharmonicBackground)
                .navigationTitle(group.city.name).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { presentedCity = nil }
                    }
                }
            }
            .tint(.philharmonicRed)
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
    }

    private func choose(_ group: StationCityGroup) {
        if group.stations.count == 1, let station = group.stations.first { select(station) }
        else { presentedCity = group }
    }
}

private final class CityAnnotation: NSObject, MKAnnotation {
    let group: StationCityGroup
    var coordinate: CLLocationCoordinate2D { .init(latitude: group.city.latitude, longitude: group.city.longitude) }
    var title: String? { group.city.name }
    init(_ group: StationCityGroup) { self.group = group }
}

private struct NativeStationMap: UIViewRepresentable {
    let cities: [StationCityGroup]
    let selectedCityID: String?
    let zoom: StationMapZoom
    let mapStyle: StationMapStyle
    let focusedCity: StationCity
    let cameraRequest: UUID
    let choose: (StationCityGroup) -> Void
    let cameraChanged: (StationCity, StationMapZoom) -> Void
    let expandCluster: (StationCity) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isZoomEnabled = true
        map.isPitchEnabled = false
        map.showsUserLocation = false
        map.showsScale = false
        map.showsCompass = true
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "station-city")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        map.addAnnotations(cities.map(CityAnnotation.init))
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // Both imagery configurations use the same native globe. Only the
        // borders/labels change at the continent threshold; camera stays put.
        let presentation = mapStyle == .political ? "political"
            : "satellite-\(zoom == .globe ? "globe" : "detail")"
        if coordinator.lastPresentation != presentation {
            coordinator.lastPresentation = presentation
            switch mapStyle {
            case .political:
                let configuration = MKStandardMapConfiguration(elevationStyle: .realistic)
                configuration.pointOfInterestFilter = .excludingAll
                map.preferredConfiguration = configuration
            case .satellite where zoom == .globe:
                map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
            case .satellite:
                let configuration = MKHybridMapConfiguration(elevationStyle: .realistic)
                configuration.pointOfInterestFilter = .excludingAll
                map.preferredConfiguration = configuration
            }
        }
        guard coordinator.lastCameraRequest != cameraRequest else { return }
        let first = coordinator.lastCameraRequest == nil
        coordinator.lastCameraRequest = cameraRequest
        coordinator.movingToShortcut = true
        coordinator.observedZoom = zoom
        map.setCamera(Self.camera(for: zoom, city: focusedCity, map: map), animated: !first)
    }

    private static func camera(for zoom: StationMapZoom, city: StationCity, map: MKMapView) -> MKMapCamera {
        let target = zoom.camera(focusing: city)
        let centre = CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude)
        guard let span = zoom.span(focusing: city) else {
            return MKMapCamera(lookingAtCenter: centre, fromDistance: target.distance, pitch: 0, heading: 0)
        }
        let northWest = MKMapPoint(CLLocationCoordinate2D(latitude: min(85, target.latitude + span.latitude / 2),
                                                          longitude: target.longitude - span.longitude / 2))
        let southEast = MKMapPoint(CLLocationCoordinate2D(latitude: max(-85, target.latitude - span.latitude / 2),
                                                          longitude: target.longitude + span.longitude / 2))
        let rect = MKMapRect(x: northWest.x, y: northWest.y,
                             width: southEast.x - northWest.x, height: southEast.y - northWest.y)
        let fitted = map.cameraThatFits(rect, edgePadding: UIEdgeInsets(top: 32, left: 24, bottom: 32, right: 24))
        // Large/high-latitude regions must remain closer than the outer globe.
        let maximumDistance = zoom == .continent ? 25_000_000
            : camera(for: .continent, city: city, map: map).centerCoordinateDistance * 0.8
        fitted.centerCoordinateDistance = min(fitted.centerCoordinateDistance, maximumDistance)
        fitted.pitch = 0
        fitted.heading = 0
        return fitted
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeStationMap
        var lastCameraRequest: UUID?
        var lastPresentation: String?
        var movingToShortcut = false
        var observedZoom: StationMapZoom
        private var lastPublishedCityID: String?
        private var referenceKey = ""
        private var referenceDistances: (continent: Double, country: Double) = (15_000_000, 7_000_000)
        init(_ parent: NativeStationMap) { self.parent = parent; observedZoom = parent.zoom }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let clustered = annotation is MKClusterAnnotation
            guard clustered || annotation is CityAnnotation else { return nil }
            let reuseID = clustered ? MKMapViewDefaultClusterAnnotationViewReuseIdentifier : "station-city"
            let marker = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID, for: annotation) as! MKMarkerAnnotationView
            marker.canShowCallout = false
            marker.markerTintColor = UIColor(Color.philharmonicRed)
            marker.displayPriority = .defaultHigh
            marker.titleVisibility = .visible
            marker.isAccessibilityElement = true
            marker.accessibilityTraits = .button
            if let city = annotation as? CityAnnotation {
                marker.clusteringIdentifier = "station-cities"
                marker.glyphText = city.group.stations.count > 1 ? String(city.group.stations.count) : nil
                marker.glyphImage = city.group.stations.count == 1 ? UIImage(systemName: city.group.id == parent.selectedCityID ? "checkmark" : "radio") : nil
                marker.accessibilityLabel = "\(city.group.city.name), \(city.group.stations.count) \(city.group.stations.count == 1 ? "station" : "stations")"
                marker.accessibilityIdentifier = "map-city-\(city.group.id)"
                marker.accessibilityHint = city.group.stations.count == 1 ? "Select station" : "Choose a station"
            } else if let cluster = annotation as? MKClusterAnnotation {
                marker.clusteringIdentifier = nil
                marker.glyphImage = nil
                marker.glyphText = String(cluster.memberAnnotations.count)
                marker.accessibilityLabel = "\(cluster.memberAnnotations.count) cities"
                marker.accessibilityHint = "Show cities at a closer zoom level"
            }
            return marker
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            mapView.deselectAnnotation(annotation, animated: false)
            if let city = annotation as? CityAnnotation { parent.choose(city.group) }
            else if let cluster = annotation as? MKClusterAnnotation {
                let city = StationGeography.nearestCity(latitude: cluster.coordinate.latitude, longitude: cluster.coordinate.longitude)
                parent.expandCluster(city)
            }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            func hasActiveGesture(_ view: UIView) -> Bool {
                (view.gestureRecognizers ?? []).contains { $0.state == .began || $0.state == .changed }
                    || view.subviews.contains(where: hasActiveGesture)
            }
            if hasActiveGesture(mapView) { movingToShortcut = false }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            guard !movingToShortcut else { return }
            publishCamera(mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if movingToShortcut {
                movingToShortcut = false
                return
            }
            publishCamera(mapView)
        }

        private func publishCamera(_ mapView: MKMapView) {
            let centre = mapView.centerCoordinate
            let city = StationGeography.nearestCity(latitude: centre.latitude, longitude: centre.longitude)
            let key = "\(city.id)-\(mapView.bounds.size)-\(parent.mapStyle.rawValue)"
            if referenceKey != key {
                referenceKey = key
                referenceDistances = (NativeStationMap.camera(for: .continent, city: city, map: mapView).centerCoordinateDistance,
                                      NativeStationMap.camera(for: .country, city: city, map: mapView).centerCoordinateDistance)
            }
            let level = observedZoom.following(distance: mapView.camera.centerCoordinateDistance,
                                               continentDistance: referenceDistances.continent,
                                               countryDistance: referenceDistances.country)
            guard level != observedZoom || city.id != lastPublishedCityID else { return }
            observedZoom = level
            lastPublishedCityID = city.id
            let request = lastCameraRequest
            // Publish after the MapKit callback to avoid mutating SwiftUI state during an update.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lastCameraRequest == request, !self.movingToShortcut else { return }
                self.parent.cameraChanged(city, level)
            }
        }
    }
}
