# sentry-cocoa: main-thread hang from UIViewController tracing with many child VCs

Adding ~2000 child view controllers in one runloop turn hangs the main thread for 6–8 s with Sentry (0.3 s without). Cost is O(N²) in Sentry's UIViewController tracking.

## Env
- sentry-cocoa 9.32.0 (also seen on 9.13.0), SPM
- iPhone SE (2nd gen), iOS 18.6.2, Release build
- Options: `enableAppHangTracking`, `appHangTimeoutInterval = 2`, `tracesSampleRate = 1.0`, Session Replay 1.0 (same hang at `tracesSampleRate = 0.00001`)

## Steps
1. `brew install xcodegen && xcodegen`
2. Open `HangRepro.xcodeproj`, set your team, run on a device (Release).
3. Wait ~1 s after launch, then relaunch so the hang event is sent.
4. Control: launch with `-nosentry`.

## Expected
No hang (adding 2000 child VCs takes ~0.3 s without Sentry).

## Actual
App Hang, 6.5–8.1 s, 100% of runs. Main thread (Time Profiler, ~96% of hang in Sentry frames):
- `SentryTracer hasUnfinishedChildSpansToWaitFor` / `canBeFinished` / `spanFinished:` (~60%): each span finish rescans all child spans
- `SentryWeakMap prune` via `objectForKey:` / `setObject:forKey:` from `limitOverride`, `getSpanIdForViewController`, `setLayoutSubviewSpanID` (~27%): prune is O(N) on every access

Entry points: swizzled `viewWillAppear`/`viewDidAppear`, `loadView`/`viewDidLoad`, `viewWillLayoutSubviews`.

## Workaround
`options.swizzleClassNameExcludes = ["ChildVC"]` or `options.enableUIViewControllerTracing = false` → 0.03 s per layout pass, no hang.

## Links
- Sentry event: <link>
- Instruments trace: <link>
