# Instant Capture DMG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Ship the proven thought loop as a local Apple-Silicon menu-bar app whose global shortcut opens capture under 100 ms, whose accepted thoughts are encrypted with a Keychain-owned key, and whose installable artifact is a verified `.dmg`.

**Architecture:** `ADHDCore` separates durable acceptance from optional clarification and owns testable Now/Later projections. `VaultStore` encrypts one atomic snapshot with AES-GCM while a narrow key-provider port keeps Keychain outside domain code; a one-time adapter imports and then removes the plaintext Increment 0 store only after the encrypted write succeeds. `OpenLoopApp` prewarms a small AppKit capture panel, connects a Carbon hot key, and renders Now/Later with SwiftUI. Shell scripts assemble, ad-hoc sign, inspect, mount, and smoke-test the `.app` and `.dmg` without Xcode or network access.

**Tech Stack:** Swift 6.2, Swift Package Manager, AppKit, SwiftUI, Carbon HIToolbox, CryptoKit AES-GCM, Security Keychain Services, Swift Testing, `codesign`, `hdiutil`.

---

## Constraints

- Preserve every Increment 0 behavior and keep the CLI usable.
- The shortcut-to-window path performs no repository, encryption, or clarification work.
- Closing Quick Capture means the raw capture was durably encrypted; clarification continues independently.
- Storage failure remains visible and keeps the capture text on screen.
- The vault key is 32 random bytes stored as a generic-password Keychain item; the vault file never contains it.
- AES-GCM authenticates the schema version and content type as associated data and generates a fresh nonce for every write.
- Migration deletes the plaintext development snapshot only after one encrypted import succeeds and can be reopened.
- Later shows `.later`, `.memory`, and `.unclear`; `.release` remains deliberately absent.
- No account, network, telemetry, model, voice, updater, website, or formal `SUBSYSTEM.md` graph is introduced.

## File map

- `Sources/ADHDCore/ThoughtLoop.swift`: separate accept and clarify commands.
- `Sources/ADHDCore/ReadModels.swift`: Now and Later projections.
- `Sources/LocalStore/DevelopmentStoreSnapshot.swift`: export-only migration value.
- `Sources/VaultStore/VaultKeyProvider.swift`: key-provider protocol and Keychain adapter.
- `Sources/VaultStore/EncryptedThoughtRepository.swift`: authenticated encrypted repository.
- `Sources/VaultStore/DevelopmentStoreMigrator.swift`: one-time plaintext migration.
- `Sources/OpenLoopApp/AppModel.swift`: application state and asynchronous capture flow.
- `Sources/OpenLoopApp/QuickCaptureController.swift`: prewarmed one-field panel.
- `Sources/OpenLoopApp/GlobalHotKey.swift`: Carbon registration adapter.
- `Sources/OpenLoopApp/MainWindowController.swift`: SwiftUI Now/Later host.
- `Sources/OpenLoopApp/OpenLoopApp.swift`: menu-bar lifecycle and diagnostic commands.
- `Resources/Info.plist`: agent-app bundle metadata.
- `Scripts/build-app.sh`: release `.app` assembly and ad-hoc signing.
- `Scripts/build-dmg.sh`: disk-image creation.
- `Scripts/verify-increment-1.sh`: tests, release build, vault inspection, latency benchmark, and DMG mount gate.

### Task 1: Separate durable acceptance from clarification

**Files:**
- Modify: `Sources/ADHDCore/ThoughtLoop.swift`
- Modify: `Tests/ADHDCoreTests/ThoughtLoopTests.swift`

- [x] **Step 1: Write failing orchestration tests**

Add a repository spy and a suspending clarifier. Verify `accept(text:at:)` returns after `save(capture:)` without calling the clarifier, and verify `clarify(_:)` persists the proposal before any intention. Keep the existing `capture(text:at:)` test to prove backward compatibility.

```swift
@Test func acceptanceDoesNotWaitForClarification() async throws {
    let repository = MemoryRepository()
    let clarifier = CountingClarifier()
    let loop = ThoughtLoop(repository: repository, clarifier: clarifier)

    let capture = try await loop.accept(text: "keep this thought", at: .now)

    #expect(await repository.captures[capture.id] == capture)
    #expect(await clarifier.callCount == 0)
}

@Test func clarificationPersistsItsDecision() async throws {
    let repository = MemoryRepository()
    let loop = ThoughtLoop(repository: repository, clarifier: FixedClarifier())
    let capture = try await loop.accept(text: "reply to Riya", at: .now)

    let result = try await loop.clarify(capture)

    #expect(try await repository.proposal(captureID: capture.id) == result.proposal)
}
```

- [x] **Step 2: Verify the tests fail**

Run `Scripts/test.sh --filter 'acceptanceDoesNotWaitForClarification|clarificationPersistsItsDecision'`.

Expected: compilation fails because `accept` and `clarify` do not exist.

- [x] **Step 3: Implement the split commands**

```swift
public func accept(text: String, at date: Date) async throws -> RawCapture {
    let capture = try RawCapture(createdAt: date, text: text)
    try await repository.save(capture: capture)
    return capture
}

public func clarify(_ capture: RawCapture) async throws -> CaptureResult {
    let proposal = try await clarifier.propose(for: capture)
    try await repository.save(proposal: proposal)
    let intention = try await makeIntention(from: proposal, capture: capture)
    return CaptureResult(capture: capture, proposal: proposal, intention: intention)
}

public func capture(text: String, at date: Date) async throws -> CaptureResult {
    let capture = try await accept(text: text, at: date)
    return try await clarify(capture)
}
```

Move existing action-intention construction to private `makeIntention(from:capture:)` without changing its values.

- [x] **Step 4: Run all core tests and commit**

Run `Scripts/test.sh --filter ADHDCoreTests`.

Expected: all core tests pass.

Commit: `feat: separate instant capture acceptance from clarification`.

### Task 2: Add Now and Later read models

**Files:**
- Create: `Sources/ADHDCore/ReadModels.swift`
- Create: `Tests/ADHDCoreTests/ReadModelsTests.swift`

- [x] **Step 1: Write failing projection tests**

Test that Now chooses the active intention before older open intentions, Later merges `.later`, `.memory`, and `.unclear` in creation order, and `.release` never appears.

```swift
public struct NowItem: Equatable, Sendable {
    public let intentionID: UUID
    public let desiredOutcome: String
    public let nextAction: String
    public let state: IntentionState
}

public struct LaterItem: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let text: String
    public let disposition: Disposition
}
```

- [x] **Step 2: Verify failure**

Run `Scripts/test.sh --filter ReadModelsTests`.

Expected: compilation fails because `ThoughtReadModels`, `NowItem`, and `LaterItem` do not exist.

- [x] **Step 3: Implement projections**

`ThoughtReadModels` takes `any ThoughtRepository`. `now()` sorts open intentions so `.active` precedes `.interrupted`, which precedes `.open`, then uses `createdAt` and UUID as stable tie breakers. `later()` queries the three allowed dispositions, maps each capture with its persisted proposal, and sorts by `createdAt` then UUID. Missing proposals are excluded because they have not been clarified.

- [x] **Step 4: Run tests and commit**

Run `Scripts/test.sh --filter ReadModelsTests && Scripts/test.sh`.

Expected: all tests pass.

Commit: `feat: project calm Now and Later views`.

### Task 3: Add the encrypted vault and Keychain key provider

**Files:**
- Modify: `Package.swift`
- Create: `Sources/VaultStore/VaultKeyProvider.swift`
- Create: `Sources/VaultStore/EncryptedThoughtRepository.swift`
- Create: `Tests/VaultStoreTests/EncryptedThoughtRepositoryTests.swift`
- Create: `Tests/VaultStoreTests/KeychainVaultKeyProviderTests.swift`

- [x] **Step 1: Declare the target and failing vault tests**

Add library product `VaultStore`, target dependencies `ADHDCore` and `LocalStore`, linker setting `.linkedFramework("Security")`, and test target `VaultStoreTests`.

Test these exact behaviors:

```swift
@Test func encryptedThoughtsSurviveRestartWithoutPlaintext() async throws
@Test func wrongKeyCannotOpenVault() async throws
@Test func tamperingIsReportedAsAuthenticationFailure() async throws
@Test func dispositionAndIntentionQueriesMatchDevelopmentStore() async throws
@Test func keychainProviderReturnsTheSame32ByteKey() throws
```

The Keychain test uses a UUID service name and deletes only that exact generic-password item in `defer`.

- [x] **Step 2: Verify failure**

Run `Scripts/test.sh --filter VaultStoreTests`.

Expected: package resolution fails because the target and types are absent.

- [x] **Step 3: Implement the key boundary**

```swift
public protocol VaultKeyProvider: Sendable {
    func loadOrCreateKey() throws -> Data
}

public struct KeychainVaultKeyProvider: VaultKeyProvider, Sendable {
    public let service: String
    public let account: String
    public func loadOrCreateKey() throws -> Data
}
```

`loadOrCreateKey()` first calls `SecItemCopyMatching` for a generic password with `kSecReturnData`. On `errSecItemNotFound`, generate 32 bytes with `SecRandomCopyBytes`, then call `SecItemAdd` using `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Return existing data on a duplicate-item race. Reject any key not exactly 32 bytes and map other statuses to a typed error carrying `OSStatus`.

- [x] **Step 4: Implement the repository**

`EncryptedThoughtRepository` is an actor conforming to `ThoughtRepository`. Its in-memory `VaultSnapshot` contains capture, proposal, and intention dictionaries. The file is `openloop.vault`; a missing file starts empty. Encode the snapshot with sorted JSON keys, seal using `AES.GCM.seal(_:using:authenticating:)`, and atomically write `sealed.combined`. Authenticate `Data("openloop.vault|schema=1|content=thought-loop".utf8)`. A fresh seal creates a fresh nonce on every save. Opening failures map to `VaultStoreError.authenticationFailed`; malformed JSON maps to `corruptPayload`.

- [x] **Step 5: Run tests and commit**

Run `Scripts/test.sh --filter VaultStoreTests && Scripts/test.sh`.

Expected: all vault and existing tests pass, and plaintext fixture text is absent from `openloop.vault`.

Commit: `feat: encrypt the local thought vault with a Keychain key`.

### Task 4: Migrate the Increment 0 development store once

**Files:**
- Create: `Sources/LocalStore/DevelopmentStoreSnapshot.swift`
- Create: `Sources/VaultStore/DevelopmentStoreMigrator.swift`
- Create: `Tests/VaultStoreTests/DevelopmentStoreMigratorTests.swift`

- [x] **Step 1: Write migration tests**

Test that migration imports all captures, proposals, and intentions; deletes `thought-loop.json` only after the encrypted repository can reopen; skips when no legacy file exists; skips when the vault already contains data; and leaves the plaintext file intact when decoding or encryption fails.

- [x] **Step 2: Verify failure**

Run `Scripts/test.sh --filter DevelopmentStoreMigratorTests`.

Expected: compilation fails because snapshot export and migration do not exist.

- [x] **Step 3: Implement export and atomic import**

`DevelopmentStoreSnapshot` is a public `Codable`, `Equatable`, `Sendable` value containing arrays of captures, proposals, and intentions. `JSONFileThoughtRepository.developmentSnapshot()` returns stable sorted arrays. `EncryptedThoughtRepository.importDevelopmentSnapshot(_:)` validates every proposal references an imported capture and every intention references an imported capture, replaces only an empty vault snapshot, then persists once.

- [x] **Step 4: Implement migration ordering**

`DevelopmentStoreMigrator.migrateIfNeeded(from:to:)` checks for `thought-loop.json`, checks `vault.isEmpty`, loads the legacy repository, exports it, imports it in one encrypted write, calls the vault-owned `verifyPersistedSnapshot()` method to reopen and authenticate the just-written file with its private key, then removes exactly the legacy file. It returns an enum `.notNeeded`, `.imported(count:)`, or `.vaultAlreadyInitialized`.

- [x] **Step 5: Run tests and commit**

Run `Scripts/test.sh --filter DevelopmentStoreMigratorTests && Scripts/test.sh`.

Expected: all tests pass.

Commit: `feat: migrate the plaintext development store into the vault`.

### Task 5: Build the native menu-bar host and Quick Capture

**Files:**
- Modify: `Package.swift`
- Create: `Sources/OpenLoopApp/AppModel.swift`
- Create: `Sources/OpenLoopApp/QuickCaptureController.swift`
- Create: `Sources/OpenLoopApp/GlobalHotKey.swift`
- Create: `Sources/OpenLoopApp/MainWindowController.swift`
- Create: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Create: `Tests/OpenLoopAppTests/AppModelTests.swift`

- [x] **Step 1: Declare app targets and write model tests**

Add executable product `OpenLoopADHD`, executable target `OpenLoopApp` depending on `ADHDCore`, `RuleClarifier`, and `VaultStore` with linked frameworks `AppKit`, `Carbon`, and `Security`, plus `OpenLoopAppTests`.

Test that successful submit clears the field only after `accept` returns, failed save preserves text and publishes an error, clarification begins after acceptance, and refresh publishes the core Now/Later projections.

- [x] **Step 2: Implement `AppModel`**

`@MainActor final class AppModel: ObservableObject` publishes `captureText`, `captureError`, `isSaving`, `now`, and `later`. `submitCapture()` awaits `loop.accept`; on success it clears text, asks the presenter to close, then launches a child `Task` that calls `loop.clarify` and refreshes projections. On failure it leaves text and panel visible.

- [x] **Step 3: Implement the prewarmed panel**

`QuickCaptureController` constructs one reusable `NSPanel` at app launch with a single `NSTextField`, a subtle status label used only for errors/saving, and Enter/Escape handling. `show(startedAt:)` clears stale errors, centers the panel, calls `makeKeyAndOrderFront`, focuses the field, and records elapsed nanoseconds after the panel becomes visible. It performs no async work.

- [x] **Step 4: Implement the hot key adapter**

`GlobalHotKey` registers Command-Shift-Space via `RegisterEventHotKey`, installs one `kEventClassKeyboard/kEventHotKeyPressed` handler on the application event target, records `ContinuousClock.now` at callback entry, and dispatches the provided `@MainActor` closure. Registration and handler failures are typed and visible in the menu.

- [x] **Step 5: Implement the main surfaces and menu**

`MainWindowController` owns a reusable `NSWindow` hosting a SwiftUI `TabView` with Now and Later. Now shows only desired outcome, smallest next action, and state; Later shows quiet rows with text and disposition and no badge/count. The `NSStatusItem` menu exposes Capture, Now, Later, a disabled shortcut-error row when needed, and Quit. The app uses `.accessory` activation policy.

- [x] **Step 6: Wire production startup**

`OpenLoopApp.swift` creates the Keychain provider, encrypted repository, migrator, rule clarifier, model, prewarmed panel, windows, status item, and hot key in that order. Default data lives in `~/Library/Application Support/OpenLoopADHD`; tests and diagnostics may override it with `OPENLOOP_DATA_DIR` and the Keychain service with `OPENLOOP_KEYCHAIN_SERVICE`.

- [x] **Step 7: Run tests and commit**

Run `Scripts/test.sh --filter OpenLoopAppTests && Scripts/test.sh && swift build -c release`.

Expected: app model and all repository/core tests pass and the app target links.

Commit: `feat: add instant menu bar capture with Now and Later`.

### Task 6: Add repeatable latency and smoke diagnostics

**Files:**
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Create: `Sources/OpenLoopApp/CaptureLatency.swift`
- Create: `Tests/OpenLoopAppTests/CaptureLatencyTests.swift`

- [x] **Step 1: Test p95 calculation**

Verify samples sort correctly, fewer than one sample returns nil, and the nearest-rank p95 of 100 samples returns sample 95.

- [x] **Step 2: Add diagnostic modes**

`OpenLoopADHD --smoke-test` initializes Keychain, runs migration, accepts and clarifies `todo: packaged smoke capture`, reopens the vault, asserts one matching intention, and exits. `--benchmark-capture 100` constructs the real prewarmed panel, repeatedly invokes its show/hide path on the main actor, prints `capture-visible-p95-ms=<value>`, and exits nonzero when p95 is 100 ms or greater. `--benchmark-save 100` accepts unique typed captures into a temporary encrypted vault, prints `capture-save-p95-ms=<value>`, and exits nonzero when p95 is 50 ms or greater.

- [x] **Step 3: Run tests and commit**

Run `Scripts/test.sh --filter CaptureLatencyTests && swift run OpenLoopADHD --benchmark-capture 100 && swift run OpenLoopADHD --benchmark-save 100`.

Expected: calculation tests pass and the current Mac reports presentation p95 below 100 ms and encrypted durable acceptance p95 below 50 ms.

Commit: `test: measure instant capture presentation latency`.

### Task 7: Assemble the app and DMG

**Files:**
- Create: `Resources/Info.plist`
- Create: `Scripts/build-app.sh`
- Create: `Scripts/build-dmg.sh`
- Modify: `.gitignore`

- [x] **Step 1: Add bundle metadata**

`Info.plist` sets `CFBundleExecutable` to `OpenLoopADHD`, identifier `dev.openloop.adhd`, name `OpenLoop ADHD`, version `0.1.0`, `LSMinimumSystemVersion` `15.0`, `LSUIElement` true, and supported architecture arm64.

- [x] **Step 2: Build and sign the app**

`build-app.sh` runs `swift build -c release --arch arm64`, recreates only `.artifacts/app/OpenLoop ADHD.app`, copies `Info.plist` and `.build/arm64-apple-macosx/release/OpenLoopADHD`, then runs `codesign --force --deep --sign -`. It verifies the signature and prints the final path.

- [x] **Step 3: Build the disk image**

`build-dmg.sh` calls `build-app.sh`, recreates only `.artifacts/dmg-stage`, copies the app, creates an `Applications` symlink, and uses `hdiutil create -volname "OpenLoop ADHD" -srcfolder ... -ov -format UDZO .artifacts/OpenLoop-ADHD.dmg`.

- [x] **Step 4: Ignore artifacts and commit**

Add `.artifacts/` to `.gitignore`.

Run `Scripts/build-dmg.sh`.

Expected: `.artifacts/OpenLoop-ADHD.dmg` exists and `codesign --verify` succeeds for the staged app.

Commit: `build: package OpenLoop ADHD as a local DMG`.

### Task 8: Verify Increment 1

**Files:**
- Create: `Scripts/verify-increment-1.sh`
- Modify: `README.md`
- Modify: `docs/DECISIONS.md`

- [x] **Step 1: Create the complete gate script**

The script runs, in order:

1. `Scripts/verify.sh`.
2. `Scripts/build-dmg.sh`.
3. `codesign --verify --deep --strict` on the app.
4. The packaged binary with a unique temporary data directory and Keychain service in `--smoke-test` mode.
5. A byte search proving the smoke capture text is absent from all vault files.
6. The packaged binary with `--benchmark-capture 100` and a p95 assertion below 100 ms.
7. The packaged binary with `--benchmark-save 100` and an encrypted-save p95 assertion below 50 ms.
8. `hdiutil attach -nobrowse -readonly`, verification that `OpenLoop ADHD.app` and the Applications link exist, then `hdiutil detach` in a trap.
9. Exact cleanup of the temporary Keychain generic-password item and temporary directory.

- [x] **Step 2: Document development and security behavior**

README documents the shortcut, menu surfaces, verification command, artifact path, unsigned/ad-hoc Gatekeeper expectation, local data directory, and lack of network/telemetry. Decision log records encrypted snapshot storage for the current small local dataset, with SQLite deferred until FTS/search behavior requires it.

- [x] **Step 3: Run the gate**

Run `Scripts/verify-increment-1.sh`.

Expected: all tests and release builds pass; presentation p95 is below 100 ms; durable encrypted acceptance p95 is below 50 ms; the vault contains no plaintext fixture; the app is ad-hoc signed; and the DMG mounts with the expected install layout.

- [x] **Step 4: Commit**

Commit: `build: verify the encrypted instant capture DMG`.

## Completion gate

Increment 1 is complete only when a real menu-bar app registers its shortcut, the prewarmed capture path measures below 100 ms p95 and durable encrypted acceptance measures below 50 ms p95 on the current Mac, raw typed input is encrypted before the panel closes, saved data survives app restart, the Keychain owns the only persistent vault key, an Increment 0 plaintext store migrates exactly once without loss, Now and Later render from repository projections, vault inspection finds no plaintext captures or intentions, and the mounted `.dmg` contains an installable ad-hoc-signed Apple-Silicon `.app` with no network dependency.
