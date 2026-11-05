import UIKit
import Sentry

final class ChildVC: UIViewController {
  override func loadView() { view = UIView(); view.backgroundColor = .systemBlue }
}

final class RootVC: UIViewController {
  let clock = UILabel(), status = UILabel(), start = CACurrentMediaTime()

  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .white
    for (l, y, size) in [(clock, 80.0, 64.0), (status, 160.0, 20.0)] {
      l.frame = CGRect(x: 0, y: y, width: view.bounds.width, height: size + 10)
      l.font = .monospacedDigitSystemFont(ofSize: size, weight: .bold); l.textAlignment = .center
      view.addSubview(l)
    }
    status.text = "waiting..."
    // The clock ticks every 0.1 s on the main thread, so it freezes during the hang.
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.clock.text = String(format: "%.1f s", CACurrentMediaTime() - self.start)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.status.text = "adding 2000 child VCs..." }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.burst() }
  }

  func burst() {
    let t = CFAbsoluteTimeGetCurrent()
    for i in 0..<2000 { // 2000 child VCs in one runloop turn, drawn as a grid of small squares
      let v = ChildVC(); addChild(v); view.addSubview(v.view); v.didMove(toParent: self)
      v.view.frame = CGRect(x: 4 + (i % 50) * 7, y: 220 + (i / 50) * 7, width: 5, height: 5)
    }
    view.layoutIfNeeded() // Sentry's swizzled appearance/layout callbacks run here for all 2000 VCs
    let dt = CFAbsoluteTimeGetCurrent() - t
    status.text = String(format: "done: 2000 child VCs in %.2f s", dt)
    print(String(format: "[REPRO] added 2000 child VCs in %.3fs", dt))
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
        o.sessionReplay.maskAllText = false // show the clock in replays
      }
    }
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = RootVC(); window?.makeKeyAndVisible()
    return true
  }
}
