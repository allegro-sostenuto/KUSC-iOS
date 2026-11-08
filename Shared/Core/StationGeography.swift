import Foundation

enum StationContinent: String {
    case europe, northAmerica
    var name: String { self == .europe ? "Europe" : "North America" }
}

struct StationCity: Identifiable, Equatable {
    let id: String
    let name: String
    let countryCode: String
    let continent: StationContinent
    let latitude: Double
    let longitude: Double
    var countryName: String { Locale.current.localizedString(forRegionCode: countryCode.uppercased()) ?? countryCode.uppercased() }
}

struct StationCityGroup: Identifiable {
    let city: StationCity
    let stations: [RadioStation]
    var id: String { city.id }
}

/// Broadcaster base cities, using approximate city centres, not transmitter locations.
/// Official contact/address sources are recorded in docs/ios_v2_4_0.md.
enum StationGeography {
    static let cities: [StationCity] = [
        .init(id: "los-angeles", name: "Los Angeles", countryCode: "us", continent: .northAmerica, latitude: 34.0522, longitude: -118.2437),
        .init(id: "basel", name: "Basel", countryCode: "ch", continent: .europe, latitude: 47.5596, longitude: 7.5886),
        .init(id: "stockholm", name: "Stockholm", countryCode: "se", continent: .europe, latitude: 59.3293, longitude: 18.0686),
        .init(id: "paris", name: "Paris", countryCode: "fr", continent: .europe, latitude: 48.8566, longitude: 2.3522),
        .init(id: "cologne", name: "Cologne", countryCode: "de", continent: .europe, latitude: 50.9375, longitude: 6.9603),
        .init(id: "warsaw", name: "Warsaw", countryCode: "pl", continent: .europe, latitude: 52.2297, longitude: 21.0122),
        .init(id: "moscow", name: "Moscow", countryCode: "ru", continent: .europe, latitude: 55.7558, longitude: 37.6173),
        .init(id: "zagreb", name: "Zagreb", countryCode: "hr", continent: .europe, latitude: 45.8150, longitude: 15.9819),
        .init(id: "helsinki", name: "Helsinki", countryCode: "fi", continent: .europe, latitude: 60.1699, longitude: 24.9384),
        .init(id: "prato", name: "Prato", countryCode: "it", continent: .europe, latitude: 43.8777, longitude: 11.1022),
        .init(id: "chicago", name: "Chicago", countryCode: "us", continent: .northAmerica, latitude: 41.8781, longitude: -87.6298),
        .init(id: "bucharest", name: "Bucharest", countryCode: "ro", continent: .europe, latitude: 44.4268, longitude: 26.1025),
        .init(id: "lisbon", name: "Lisbon", countryCode: "pt", continent: .europe, latitude: 38.7223, longitude: -9.1393),
        .init(id: "utrecht", name: "Utrecht", countryCode: "nl", continent: .europe, latitude: 52.0907, longitude: 5.1214)
    ]

    private static let cityIDs = [
        "kusc": "los-angeles", "radio-swiss-classic": "basel", "sr-p2": "stockholm",
        "france-musique-classique-easy": "paris", "france-musique-la-baroque": "paris",
        "wdr3": "cologne", "radio-chopin": "warsaw", "orpheus-large-scale": "moscow",
        "orpheus-russian-classical": "moscow", "orpheus-camerata": "moscow", "hr-klasik": "zagreb",
        "yle-klassinen": "helsinki", "rete-toscana-classica": "prato", "wfmt": "chicago",
        "romania-muzical": "bucharest", "rtp-opera": "lisbon", "concertzender-oude-muziek": "utrecht"
    ]

    static func city(for station: RadioStation) -> StationCity? {
        cities.first { $0.id == cityIDs[station.id] }
    }

    /// Keep both cities and the stations within each city in the user's saved order.
    static func groups(stations: [RadioStation]) -> [StationCityGroup] {
        var orderedCities: [StationCity] = []
        var grouped: [String: [RadioStation]] = [:]
        for station in stations {
            guard let city = city(for: station) else { continue }
            if grouped[city.id] == nil { orderedCities.append(city) }
            grouped[city.id, default: []].append(station)
        }
        return orderedCities.map { StationCityGroup(city: $0, stations: grouped[$0.id] ?? []) }
    }

    static func nearestCity(latitude: Double, longitude: Double) -> StationCity {
        // Spherical angular distance handles longitude wrap at the date line.
        func distance(_ city: StationCity) -> Double {
            let lat1 = latitude * .pi / 180, lat2 = city.latitude * .pi / 180
            let dLat = (city.latitude - latitude) * .pi / 180
            let dLon = (city.longitude - longitude) * .pi / 180
            return pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2)
        }
        return cities.min { distance($0) < distance($1) } ?? cities[0]
    }
}

enum StationMapZoom: String, CaseIterable, Identifiable {
    case globe, continent, country
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func span(focusing city: StationCity) -> (latitude: Double, longitude: Double)? {
        switch self {
        case .globe: return nil
        case .continent: return city.continent == .europe ? (60, 100) : (80, 138)
        case .country:
            // Native region fitting accommodates portrait and landscape aspect ratios.
            // US/Portugal frame the mainland; Russia frames the station's western region.
            let spans: [String: (Double, Double)] = ["us": (32, 64), "ch": (3.4, 5.2),
                "se": (18, 16), "fr": (11.6, 16), "de": (10, 14), "pl": (10, 14),
                "ru": (32, 64), "hr": (8, 10), "fi": (15, 16), "it": (17, 16),
                "ro": (9, 12), "pt": (10, 8), "nl": (5, 6)]
            return spans[city.countryCode] ?? (10, 14)
        }
    }

    func camera(focusing city: StationCity) -> StationMapCamera {
        switch self {
        case .globe:
            return .init(latitude: city.latitude, longitude: city.longitude, distance: 45_000_000)
        case .continent:
            return city.continent == .europe
                ? .init(latitude: 53, longitude: 17, distance: 11_000_000)
                : .init(latitude: 44, longitude: -100, distance: 15_000_000)
        case .country:
            // Country-scale framing around the station's part of the country.
            let distances: [String: Double] = ["us": 7_200_000, "ch": 720_000, "se": 2_500_000,
                "fr": 1_800_000, "de": 1_600_000, "pl": 1_500_000, "ru": 5_500_000,
                "hr": 1_000_000, "fi": 1_900_000, "it": 2_000_000, "ro": 1_300_000,
                "pt": 1_100_000, "nl": 650_000]
            let centres: [String: (Double, Double)] = ["us": (39.5, -98.35), "ch": (46.8, 8.2),
                "se": (62.8, 16.5), "fr": (46.6, 2.4), "de": (51.2, 10.4), "pl": (52, 19),
                "ru": (58, 55), "hr": (45.4, 16.3), "fi": (64.4, 26), "it": (42.8, 12.8),
                "ro": (45.9, 25), "pt": (39.6, -8), "nl": (52.2, 5.3)]
            let centre = centres[city.countryCode] ?? (city.latitude, city.longitude)
            return .init(latitude: centre.0, longitude: centre.1, distance: distances[city.countryCode] ?? 1_500_000)
        }
    }
}

struct StationMapCamera: Equatable {
    let latitude: Double
    let longitude: Double
    let distance: Double
}
