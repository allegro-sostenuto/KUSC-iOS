import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
final class MetadataService {
    private struct DayCache {
        var records: [StationMetadataRecord]
        var programmes: [StationProgramme]
        var fetched: Date
    }
    private struct DayResponse {
        let key: String
        let result: Result<Data, Error>
    }

    private let session: URLSession
    private let artwork = StationArtworkStore()
    private var days: [String: DayCache] = [:]
    private var artworkByID: [String: URL] = [:]
    private(set) var lastWarning: String?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = StationConfiguration.metadataRequestTimeout
        configuration.timeoutIntervalForResource = StationConfiguration.metadataRequestTimeout + 5
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    func programme(at timestamp: Date) -> StationProgramme? {
        days.values.flatMap(\.programmes).first { timestamp >= $0.start && timestamp < $0.end }
    }

    func nextProgrammeStart(after timestamp: Date) -> Date? {
        days.values.flatMap(\.programmes).map(\.start).filter { $0 > timestamp }.min()
    }

    /// The owner starts/stops polling with playback. No independent background polling task
    /// survives a stopped player. Partial failures keep usable station data available.
    func fetch() async throws -> [ProgrammeItem] {
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = StationConfiguration.stationTimeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: now)
        let keys = (-1...1).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: now).map { formatter.string(from: $0) }
        }
        days = days.filter { keys.contains($0.key) }
        let due = keys.filter { key in
            guard let cache = days[key] else { return true }
            let interval: TimeInterval = key == today ? StationConfiguration.playlistRefreshInterval : 900
            return now.timeIntervalSince(cache.fetched) >= interval
        }

        async let nowResponse = Self.download(StationConfiguration.nowPlayingURL, session: session)
        async let dayResponses = Self.downloadDays(due, session: session)
        var failure: Error?
        var success = false
        for response in await dayResponses {
            do {
                let parsed = try StationMetadataParser.combined(response.result.get())
                days[response.key] = DayCache(records: parsed.records, programmes: parsed.programmes, fetched: now)
                success = true
            } catch { failure = error }
        }
        let programmes = days.values.flatMap(\.programmes)
        var records = days.values.flatMap(\.records)
        do {
            let data = try await nowResponse.get()
            if let current = try StationMetadataParser.now(data, programmes: programmes) {
                records.append(current)
            }
            success = true
        } catch { failure = error }
        lastWarning = failure?.localizedDescription
        if !success && records.isEmpty, let failure { throw failure }

        var byID: [String: ProgrammeItem] = [:]
        for record in records {
            var item = record.item
            if let source = record.artworkSource,
               let url = artwork.resolve(source, itemID: item.id) {
                artworkByID[item.id] = url
            }
            item.artworkURL = artworkByID[item.id]
            // The live response arrives last and supplies the richer artwork field.
            byID[item.id] = item
        }
        // Keep history bounded without allowing a large future schedule to evict all
        // of the last 15 minutes. Future entries, if the station publishes them, are limited.
        let sorted = byID.values.sorted { $0.start < $1.start }
        let items = Array(sorted.filter { $0.start <= now }.suffix(224)) + Array(sorted.filter { $0.start > now }.prefix(32))
        let keepIDs = Set(items.map(\.id))
        artworkByID = artworkByID.filter { keepIDs.contains($0.key) }
        return items
    }

    private nonisolated static func downloadDays(_ keys: [String], session: URLSession) async -> [DayResponse] {
        await withTaskGroup(of: DayResponse.self) { group in
            for key in keys {
                group.addTask { DayResponse(key: key, result: await download(StationConfiguration.playlistURL(date: key), session: session)) }
            }
            var responses: [DayResponse] = []
            for await response in group { responses.append(response) }
            return responses
        }
    }

    private nonisolated static func download(_ url: URL, session: URLSession) async -> Result<Data, Error> {
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData,
                                     timeoutInterval: StationConfiguration.metadataRequestTimeout)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw StationMetadataError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            guard data.count <= 4 * 1024 * 1024 else { throw StationMetadataError.payloadTooLarge }
            return .success(data)
        } catch { return .failure(error) }
    }
}

/// Artwork is supplied inline by the station. Its declared MIME type can be wrong (the
/// observed "image/png" payload was JPEG), so select the extension from the file signature.
/// Sixteen files, at most 1 MiB each, no persistent listening history and no backup.
private final class StationArtworkStore {
    private let directory: URL?
    private var resolved: [String: URL] = [:]

    init() {
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            var location = caches.appendingPathComponent("KUSCStationArtwork", isDirectory: true)
            try? FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? location.setResourceValues(values)
            directory = location
        } else { directory = nil }
        trim()
    }

    func resolve(_ source: String, itemID: String) -> URL? {
        if source.hasPrefix("https://"), let url = URL(string: source) {
            // An artwork URL explicitly supplied by the station is authoritative.
            return url
        }
        if let existing = resolved[itemID], FileManager.default.fileExists(atPath: existing.path) { return existing }
        guard let directory, source.hasPrefix("data:image/"), source.utf8.count <= 1_400_000,
              let comma = source.firstIndex(of: ","), source[..<comma].hasSuffix(";base64"),
              let data = Data(base64Encoded: String(source[source.index(after: comma)...])),
              data.count <= 1024 * 1024 else { return nil }
        let signature = Array(data.prefix(8))
        let suffix: String
        if signature.starts(with: [0xff, 0xd8, 0xff]) { suffix = "jpg" }
        else if signature == [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a] { suffix = "png" }
        else { return nil }
        // Stable filename only; this checksum is not used for security.
        let hash = itemID.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        let url = directory.appendingPathComponent(String(hash, radix: 16)).appendingPathExtension(suffix)
        do {
            if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
            resolved[itemID] = url
            trim()
            return url
        } catch { return nil }
    }

    private func trim() {
        guard let directory,
              let contents = try? FileManager.default.contentsOfDirectory(at: directory,
                 includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        let now = Date()
        let files = contents.map { url in
            (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }.sorted { $0.1 > $1.1 }
        for (index, file) in files.enumerated() where index >= 16 || now.timeIntervalSince(file.1) > 24 * 3600 {
            try? FileManager.default.removeItem(at: file.0)
        }
        resolved = resolved.filter { FileManager.default.fileExists(atPath: $0.value.path) }
    }
}
