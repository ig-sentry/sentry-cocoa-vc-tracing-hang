# sentry-cocoa: main-thread hang from UIViewController tracing with many child VCs

Adding ~2000 child view controllers in one runloop turn hangs the main thread for 6–8 s with Sentry (0.3 s without). Cost is O(N²) in Sentry's UIViewController tracking.

## Env
- sentry-cocoa 9.32.0 (also seen on 9.13.0), SPM
- iPhone SE (2nd gen), iOS 18.6.2, Release build
- Options: `enableAppHangTracking`, `appHangTimeoutInterval = 2`, `tracesSampleRate = 1.0`, Session Replay 1.0 (same hang at `tracesSampleRate = 0.00001`)

## Steps
1. `brew install xcodegen && xcodegen`
2. Open `HangRepro.xcodeproj`, set your team, run on a device (Release).
3. ~1 s after launch the app adds 2000 child VCs. The clock label freezes for the length of the hang, then resumes and the status shows the time taken.
4. Relaunch so the hang event is sent. Control: launch with `-nosentry`.

### Automated (connected iPhone)
```
TEAM=<your team id> BUNDLE_ID=com.you.hangrepro scripts/run.sh        # build, install, 3 runs, replay run, -nosentry control
TEAM=... scripts/run.sh -n 5 -t                                       # 5 runs + Time Profiler traces into traces/
```
The replay run keeps the app in the foreground for 60 s after the hang, backgrounds it (opens Settings) for 30 s, then relaunches so the replay and hang events upload. Logs go to `logs/`.

### Upload debug symbols (with sources, for symbolicated stacks and source context)
```
export SENTRY_AUTH_TOKEN=<org token with org:ci>
sentry-cli debug-files upload --org sentry-sn0 --project 4512377547390976 --include-sources \
  build/Build/Products/Release-iphoneos/HangRepro.app.dSYM
```

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
