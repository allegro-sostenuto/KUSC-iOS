import UIKit

@MainActor final class ArtworkCache {
    private let cache = NSCache<NSURL, UIImage>()
    init() { cache.countLimit = 16; cache.totalCostLimit = 12 * 1024 * 1024 }
    func image(at url: URL) async -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        do {
            let data: Data
            if url.isFileURL {
                // The station supplies inline image data; MetadataService materializes
                // it in a bounded cache and passes its file URL here.
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, let size = values.fileSize,
                      size <= 5 * 1024 * 1024 else { return nil }
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } else {
                guard url.scheme == "https" else { return nil }
                var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
                request.setValue("image/*", forHTTPHeaderField: "Accept")
                let (downloaded, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                data = downloaded
            }
            guard data.count <= 5 * 1024 * 1024, let image = UIImage(data: data) else { return nil }
            let size = CGSize(width: 512, height: 512)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let reduced = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            cache.setObject(reduced, forKey: url as NSURL, cost: 512 * 512 * 4)
            return reduced
        } catch { return nil }
    }
}
