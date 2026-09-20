#if CARPLAY
import CarPlay
import UIKit

@MainActor final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var controller: CPInterfaceController?
    private var programme: CPListTemplate?
    private var observer: NSObjectProtocol?
    private var contextKey: String?
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        controller = interfaceController
        contextKey = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        let now = CPNowPlayingTemplate.shared
        now.isUpNextButtonEnabled = false
        now.isAlbumArtistButtonEnabled = false
        let live = CPNowPlayingImageButton(image: UIImage(systemName: "dot.radiowaves.left.and.right")!) { _ in
            Task { @MainActor in AppModel.shared.goLive() }
        }
        now.updateNowPlayingButtons([live])
        // The Now Playing template must be pushed into navigation; it is not a
        // supported tab root. A list row provides navigation without seeking audio.
        let showNowPlaying = CPListItem(text: "KUSC FM 91.5", detailText: "Now Playing")
        showNowPlaying.handler = { [weak self] _, completion in
            Task { @MainActor in
                guard let controller = self?.controller else { completion(); return }
                controller.pushTemplate(CPNowPlayingTemplate.shared, animated: true) { success, error in
                    if !success {
                        Task { @MainActor in
                            AppModel.shared.notice = error?.localizedDescription ?? "CarPlay could not open Now Playing."
                        }
                    }
                    completion()
                }
            }
        }
        let playing = CPListTemplate(title: "KUSC", sections: [CPListSection(items: [showNowPlaying])])
        playing.tabTitle = "Playing"; playing.tabImage = UIImage(systemName: "play.circle")
        let list = CPListTemplate(title: "Programme", sections: [])
        list.tabTitle = "Programme"; list.tabImage = UIImage(systemName: "list.bullet")
        programme = list
        let tabs = CPTabBarTemplate(templates: [playing, list])
        interfaceController.setRootTemplate(tabs, animated: false) { success, error in
            if !success {
                Task { @MainActor in
                    AppModel.shared.notice = error?.localizedDescription ?? "CarPlay could not open KUSC."
                }
            }
        }
        observer = NotificationCenter.default.addObserver(forName: .kuscPlaybackChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateProgramme() }
        }
        AppModel.shared.launch()
        updateProgramme()
    }
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController) {
        controller = nil; programme = nil; contextKey = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
    private func updateProgramme() {
        let model = AppModel.shared
        let items = [model.currentItem].compactMap { $0 } + model.previousItems + model.upcomingItems
        let contentKeys = items.map { [$0.id, $0.title, $0.composer].joined(separator: "\u{1f}") }
        let key = ([model.programmeName ?? "", model.hostName ?? ""] + contentKeys).joined(separator: "\u{1e}")
        guard key != contextKey else { return }; contextKey = key
        func row(_ piece: ProgrammeItem) -> CPListItem {
            let item = CPListItem(text: piece.title, detailText: piece.composer)
            item.isEnabled = false // Informational only: no tap or seek handler.
            return item
        }
        let context = CPListItem(text: model.programmeName ?? "Classical California",
                                 detailText: model.hostName ?? "KUSC FM 91.5")
        context.isEnabled = false
        var sections = [CPListSection(items: [context], header: "Programme", sectionIndexTitle: nil)]
        if let current = model.currentItem { sections.append(CPListSection(items: [row(current)], header: "Now heard", sectionIndexTitle: nil)) }
        sections.append(CPListSection(items: model.previousItems.prefix(5).map(row), header: "Previous", sectionIndexTitle: nil))
        if model.upcomingItems.isEmpty {
            let unavailable = CPListItem(text: "Upcoming pieces not published", detailText: nil); unavailable.isEnabled = false
            sections.append(CPListSection(items: [unavailable], header: "Upcoming", sectionIndexTitle: nil))
        } else {
            sections.append(CPListSection(items: model.upcomingItems.prefix(10).map(row), header: "Upcoming", sectionIndexTitle: nil))
        }
        programme?.updateSections(sections)
    }
}
#endif
