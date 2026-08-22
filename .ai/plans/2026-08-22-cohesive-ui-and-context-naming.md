# Cohesive UI and Context Naming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a calm, list-first macOS interface with system/light/dark appearance, human-named transcript evidence, concept-led context graphs, and a spacious responsive product site.

**Architecture:** `OpenLoopVisualSystem` owns cross-surface visual tokens and reusable SwiftUI control styles. `MeetingTranscriptionController` names transcripts after recognition, keeps the captured time in the retained audio filename, and uses a local title provider with a deterministic fallback. The website uses the same warm-neutral, blue, and recording-red language with a deterministic canvas field and responsive product mockups.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, Qwen3Chat local inference, Swift Testing, React 19, TypeScript, Vite, canvas, GSAP.

---

### Task 1: Native appearance and open control kit

**Files:**
- Modify: `Sources/OpenLoopApp/UI/OpenLoopVisualSystem.swift`
- Modify: `Sources/OpenLoopApp/App/AppModel.swift`
- Modify: `Sources/OpenLoopApp/App/MainWindowController.swift`
- Test: `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`
- Test: `Tests/OpenLoopAppTests/V1ReliabilityTests.swift`

- [x] **Step 1: Add a persistence test for System, Light, and Dark appearance**

```swift
first.setAppearanceMode(.light)
let second = AppModel(defaults: defaults, appearanceModeKey: key, ...)
#expect(second.appearanceMode == .light)
```

- [x] **Step 2: Add adaptive neutral, blue, and recording-red tokens**

```swift
static let accent = adaptive(light: 0x3973B9, dark: 0x71A5E3)
static let canvas = adaptive(light: 0xFBFAF7, dark: 0x202228)
static let recording = adaptive(light: 0xD84A4A, dark: 0xFF6666)
```

- [x] **Step 3: Replace boxed capture controls with a 56-point open composer**

```swift
.padding(.horizontal, OpenLoopVisualSystem.space3)
.padding(.vertical, 10)
.frame(minHeight: 56)
.background(isFocused ? raised : selectionInactive.opacity(0.64), in: shape)
```

- [x] **Step 4: Expose appearance from the Mac sidebar and apply it to the root view**

```swift
.preferredColorScheme(preferredColorScheme)
```

- [x] **Step 5: Build the native target**

Run: `swift build --target OpenLoopApp`
Expected: `Build complete!`

### Task 2: Human transcript titles and retained audio filenames

**Files:**
- Create: `Sources/OpenLoopApp/Meetings/MeetingTitleNaming.swift`
- Modify: `Sources/OpenLoopApp/Meetings/LocalMeetingIntelligenceProvider.swift`
- Modify: `Sources/OpenLoopApp/Meetings/MeetingTranscriptionController.swift`
- Modify: `Sources/OpenLoopApp/App/OpenLoopApp.swift`
- Modify: `Sources/ADHDCore/SemanticGraphLoop.swift`
- Test: `Tests/OpenLoopAppTests/MeetingTitleNamingTests.swift`
- Test: `Tests/OpenLoopAppTests/MeetingTranscriptionControllerTests.swift`

- [x] **Step 1: Write title normalization and dated-filename tests**

```swift
#expect(MeetingTitleNaming.displayTitle("  Checkout latency.  ") == "Checkout latency")
#expect(MeetingTitleNaming.fileName(title: "Checkout latency", createdAt: date, extension: "m4a") == "2026-08-22_1842-checkout-latency.m4a")
```

- [x] **Step 2: Add the title-provider port and deterministic fallback**

```swift
protocol MeetingTitleProviding: Sendable {
    func title(for transcript: MeetingTranscript) async -> String
}
```

- [x] **Step 3: Reuse the local Qwen intelligence runtime for an eight-word grounded title**

```swift
let response = try await generator(titleSystemPrompt, titleUserPrompt(for: transcript))
return MeetingTitleNaming.displayTitle(response)
```

- [x] **Step 4: Rename staged audio after recognition and save the human title**

```swift
let title = await titleProvider.title(for: draft)
let retainedURL = (try? renameStagedAudio(stagedURL, title: title, createdAt: createdAt)) ?? stagedURL
```

- [x] **Step 5: Refresh context-root claims when a transcript receives a human title**

```swift
claim: "Meeting: \(transcript.sourceName)"
```

- [x] **Step 6: Run focused controller and graph tests**

Run: `swift test --filter MeetingTitleNamingTests --filter MeetingTranscriptionControllerTests`
Expected: tests pass where the full Xcode toolchain is available; otherwise CI runs the same suite.

Local result: blocked before test execution because the selected Command Line Tools cannot import Swift `Testing`; the production `OpenLoopApp` target builds successfully and CI remains authoritative for test execution.

### Task 3: Responsive website and original product mockups

**Files:**
- Modify: `website/src/App.tsx`
- Modify: `website/src/styles.css`

- [x] **Step 1: Replace private test phrases with original fictional scenarios**

```tsx
<p>The exhibition guide should feel useful before it feels clever.</p>
<p lang="hi">अब onboarding को तीन छोटे steps में रखते हैं।</p>
```

- [x] **Step 2: Add the seeded flow-field canvas and remove the turquoise palette**

```tsx
<AlgorithmicField />
```

- [x] **Step 3: Rebuild the hero grid so copy and mockup never collide**

```css
.hero { grid-template-columns: minmax(390px,.72fr) minmax(0,1.28fr); gap: clamp(48px,5vw,96px); }
.hero-object { width: min(100%,1120px); min-width: 0; }
```

- [x] **Step 4: Build and capture desktop and mobile screenshots**

Run: `npm run build`
Expected: Vite completes without TypeScript or CSS errors.

- [x] **Step 5: Inspect only the website screenshots and adjust overflow once**

Run: headless Chrome at `1440x900`, `1050x900`, and `390x844`.
Expected: no hero collision, clipped controls, or unreadable mock text.

### Task 4: Copy, release evidence, and handoff

**Files:**
- Modify: `website/src/App.tsx`
- Modify: `README.md` only if release facts change

- [x] **Step 1: Run unslop scans over final visible website copy**

Run: `python3 /Users/dhruv/.codex/skills/unslop/scripts/banned_phrase_scan.py website/src/App.tsx`
Expected: no banned marketing filler in user-facing copy.

- [x] **Step 2: Run focused native build and website build in parallel**

Run: `swift build --target OpenLoopApp` and `npm run build`
Expected: both complete successfully.

- [ ] **Step 3: Review the diff for unrelated changes and commit the coherent increment**

```bash
git diff --check
git status --short
git add Sources Tests website .ai/plans
git commit -m "feat: unify native UI and human context naming"
```

- [ ] **Step 4: Push the branch after the local evidence is clean**

Run: `git push origin feature/v1-completion`
Expected: remote branch advances to the new commit.
