import UIKit
import SwiftUI

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let contentView = ContentView().preferredColorScheme(.dark)
        let hostingController = UIHostingController(rootView: contentView)
        hostingController.view.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.1, alpha: 1.0)
        window.rootViewController = hostingController
        self.window = window
        window.makeKeyAndVisible()
        return true
    }
    
    // Handle opening .img file from other apps (Files, AirDrop, Safari)
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        NotificationCenter.default.post(name: NSNotification.Name("OpenIMGFileNotification"), object: url)
        return true
    }
}
