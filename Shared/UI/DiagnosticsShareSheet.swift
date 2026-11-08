import SwiftUI
import UIKit

/// Native share presentation adapted from the user's recovered diagnostics bundle.
struct DiagnosticsShareSheet: UIViewControllerRepresentable {
    let reportURL: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [reportURL], applicationActivities: nil)
        controller.view.accessibilityIdentifier = "debug-share-sheet"
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
