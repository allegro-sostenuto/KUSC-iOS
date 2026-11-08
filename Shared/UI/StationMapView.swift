import SwiftUI
import MapKit

struct StationMapView: View {
    let stations: [RadioStation]
    let selectedStation: RadioStation
    let select: (RadioStation) -> Void
    @State private var zoom: StationMapZoom = .globe
    @State private var focusedCity: StationCity
    @State private var cameraRequest = UUID()
    @State private var presentedCity: StationCityGroup?
    @State private var pendingStation: RadioStation?

    init(stations: [RadioStation], selectedStation: RadioStation, select: @escaping (RadioStation) -> Void) {
        self.stations = stations
        self.selectedStation = selectedStation
        self.select = select
        _focusedCity = State(initialValue: StationGeography.city(for: selectedStation) ?? StationGeography.cities[0])
    }

    private var cities: [StationCityGroup] { StationGeography.groups(stations: stations) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Map zoom", selection: $zoom) {
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
                             zoom: zoom, focusedCity: focusedCity, cameraRequest: cameraRequest,
                             choose: choose, focus: { focusedCity = $0 }, expandCluster: { city in
                focusedCity = city
                if zoom == .globe { zoom = .continent }
                else if zoom == .continent { zoom = .country }
                cameraRequest = UUID()
            })
            .accessibilityIdentifier("stations-map")

            HStack(spacing: 8) {
                Text(zoom == .globe ? "Tap a city to choose a station" : (zoom == .continent ? focusedCity.continent.name : focusedCity.countryName))
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
        .onChange(of: zoom) { _ in cameraRequest = UUID() }
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
    let focusedCity: StationCity
    let cameraRequest: UUID
    let choose: (StationCityGroup) -> Void
    let focus: (StationCity) -> Void
    let expandCluster: (StationCity) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isZoomEnabled = false // The three named controls are the three zoom levels.
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
        guard coordinator.lastCameraRequest != cameraRequest else { return }
        let first = coordinator.lastCameraRequest == nil
        coordinator.lastCameraRequest = cameraRequest
        if zoom == .globe {
            map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        } else {
            let configuration = MKStandardMapConfiguration(elevationStyle: .realistic)
            configuration.pointOfInterestFilter = .excludingAll
            map.preferredConfiguration = configuration
        }
        let camera = zoom.camera(focusing: focusedCity)
        let centre = CLLocationCoordinate2D(latitude: camera.latitude, longitude: camera.longitude)
        if let span = zoom.span(focusing: focusedCity) {
            let region = MKCoordinateRegion(center: centre,
                span: .init(latitudeDelta: span.latitude, longitudeDelta: span.longitude))
            map.setRegion(map.regionThatFits(region), animated: !first)
        } else {
            map.setCamera(MKMapCamera(lookingAtCenter: centre, fromDistance: camera.distance,
                                      pitch: 0, heading: 0), animated: !first)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeStationMap
        var lastCameraRequest: UUID?
        private var userMovedCamera = false
        init(_ parent: NativeStationMap) { self.parent = parent }

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
            userMovedCamera = hasActiveGesture(mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard userMovedCamera else { return }
            userMovedCamera = false
            let centre = mapView.centerCoordinate
            let city = StationGeography.nearestCity(latitude: centre.latitude, longitude: centre.longitude)
            // Publish after the MapKit callback to avoid mutating SwiftUI state during an update.
            DispatchQueue.main.async { [weak self] in self?.parent.focus(city) }
        }
    }
}
