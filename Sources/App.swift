import UIKit
import Sentry

final class ChildVC: UIViewController {
  override func loadView() { view = UIView(frame: CGRect(x: 0, y: 0, width: 4, height: 4)) }
}

final class RootVC: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .white
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      let t = CFAbsoluteTimeGetCurrent()
      for _ in 0..<2000 { // 2000 child VCs in one runloop turn
        let v = ChildVC(); self.addChild(v); self.view.addSubview(v.view); v.didMove(toParent: self)
      }
      self.view.layoutIfNeeded()
      print(String(format: "[REPRO] added 2000 child VCs in %.3fs", CFAbsoluteTimeGetCurrent() - t))
    }
  }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  func application(_ app: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    if !CommandLine.arguments.contains("-nosentry") { // control: launch with -nosentry
      SentrySDK.start { o in
        o.dsn = "https://687e2b25a9b5de6ea6090e6a5f89dcd4@o4511809407025152.ingest.us.sentry.io/4512377547390976"
        o.enableAppHangTracking = true
        o.appHangTimeoutInterval = 2
        o.tracesSampleRate = 1.0
        o.sessionReplay.sessionSampleRate = 1.0
        o.sessionReplay.onErrorSampleRate = 1.0
      }
    }
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = RootVC(); window?.makeKeyAndVisible()
    return true
  }
}
