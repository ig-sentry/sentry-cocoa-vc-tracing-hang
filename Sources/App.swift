import UIKit
import Sentry

final class ChildVC: UIViewController {
  override func loadView() { view = UIView(); view.backgroundColor = .systemBlue }
}

final class RootVC: UIViewController {
  let clock = UILabel(), status = UILabel(), start = CACurrentMediaTime()
  var lines = ["waiting..."], lastTick = CACurrentMediaTime(), burstAt = 0.0

  override func viewDidLoad() {
    super.viewDidLoad(); view.backgroundColor = .white
    for (l, y, size) in [(clock, 100.0, 72.0), (status, 200.0, 60.0)] {
      l.frame = CGRect(x: 0, y: y, width: view.bounds.width, height: size + 10)
      l.font = .monospacedDigitSystemFont(ofSize: size > 60 ? size : 18, weight: .bold); l.textAlignment = .center; l.textColor = .black; l.numberOfLines = 0
      view.addSubview(l)
    }
    status.text = lines[0]
    // The clock ticks on the main thread every frame, so it freezes during the hang.
    CADisplayLink(target: self, selector: #selector(tick)).add(to: .main, forMode: .common)
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
      let f = DateFormatter(); f.dateFormat = "HH:mm:ss.S"
      self.show(0, "Adding 2000 VCs at \(f.string(from: Date()))")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { self.burst() }
  }

  @objc func tick() {
    let now = CACurrentMediaTime(), gap = now - lastTick; lastTick = now
    // the freeze has 2 parts (the loop, then the first layout pass); report total since burst start
    if gap > 0.5, burstAt > 0 { show(2, String(format: "Main thread resumed after %.2fs freeze", now - burstAt)) }
    let s = String(format: "%.1f s", now - start)
    if s.hasSuffix(".0 s"), s != clock.text { print("[REPRO] clock", s) } // once a second
    clock.text = s
  }

  func show(_ i: Int, _ text: String) {
    while lines.count <= i { lines.append("") }
    lines[i] = text; status.text = lines.joined(separator: "\n"); print("[REPRO]", text)
  }

  func burst() {
    let t = CFAbsoluteTimeGetCurrent(); burstAt = CACurrentMediaTime()
    for i in 0..<2000 { // 2000 child VCs in one runloop turn, drawn as a grid of small squares
      let v = ChildVC(); addChild(v); view.addSubview(v.view); v.didMove(toParent: self)
      v.view.frame = CGRect(x: 4 + (i % 50) * 7, y: 260 + (i / 50) * 7, width: 5, height: 5)
    }
    view.bringSubviewToFront(clock); view.bringSubviewToFront(status)
    view.layoutIfNeeded() // Sentry's swizzled appearance/layout callbacks run here for all 2000 VCs
    let dt = CFAbsoluteTimeGetCurrent() - t
    show(1, String(format: "Loop done in %.2fs", dt))
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
