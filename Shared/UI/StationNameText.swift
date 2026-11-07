import SwiftUI

extension Text {
    init(station: RadioStation) {
        self.init(stationID: station.id, name: station.name)
    }

    /// Inline artwork keeps the flag beside the name as text wraps or scales.
    /// Assets retain their national proportions at a small, fixed point size.
    init(stationID: String, name: String) {
        if let asset = StationCatalog.station(id: stationID)?.flagAssetName {
            self = Text(Image(decorative: asset).renderingMode(.original)).baselineOffset(-1)
                + Text(" ") + Text(name)
        } else {
            self = Text(name)
        }
    }
}
