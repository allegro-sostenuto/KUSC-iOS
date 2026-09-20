import SwiftUI
import UIKit

@main struct KUSCApp: App {
    @UIApplicationDelegateAdaptor(KUSCAppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
                #if DEBUG
                .modifier(UIFixtureTextSize())
                #endif
                .preferredColorScheme(model.settings.appearance == "light" ? .light : model.settings.appearance == "dark" ? .dark : nil)
                .tint(Color.kuscRed)
                .task {
                    #if DEBUG
                    if UIFixture.configure(model: model) { return }
                    #endif
                    model.launch()
                }
                .onChange(of: scenePhase) { phase in if phase == .active { model.onForeground() } }
        }
    }
}
final class KUSCAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationCoordinator.shared.install()
        return true
    }
    #if CARPLAY
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if session.role.rawValue == "CPTemplateApplicationSceneSessionRoleApplication" {
            let config = UISceneConfiguration(name: "CarPlay", sessionRole: session.role)
            config.sceneClass = CPTemplateApplicationScene.self
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }
        return session.configuration
    }
    #endif
}
#if CARPLAY
import CarPlay
#endif
