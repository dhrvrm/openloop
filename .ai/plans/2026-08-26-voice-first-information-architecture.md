# Voice-first information architecture increment

## Outcome

Make the app understandable without prior product knowledge and add an explicit local audio-source path for microphone, Mac audio, or both. A user should always know whether OpenLoop is idle, listening, transcribing, or ready, and where the result will appear.

## Constraints

- Do not launch the app during implementation or verification.
- Keep all capture and transcription local.
- Preserve the existing recording, transcription, semantic-memory, task, and global-hotkey behavior.
- Use macOS 15 APIs and ScreenCaptureKit for Mac audio; request Screen Recording only when a Mac-audio source is first used.
- Keep implementation and verification bounded to focused unit/integration tests plus one final suite run.

## Task 1 — Simplify the visible product map

Files:

- `Sources/OpenLoopApp/App/WorkspaceNavigation.swift`
- `Sources/OpenLoopApp/App/MainWindowController.swift`
- `Tests/OpenLoopAppTests/V1ReliabilityTests.swift`

Steps:

1. Replace the default 11-item sidebar with four novice-readable destinations: Home, Voice notes, Tasks, and Ask OpenLoop.
2. Keep scheduling, review, resume, threads, and patterns available under Advanced mode instead of deleting their routes.
3. Rename headings and empty states that expose internal terms such as Capture, Inbox, Act, Context, and Emerging.
4. Keep legacy tab mappings and Quick Find access intact.
5. Update navigation tests for default and Advanced sections.

## Task 2 — Add an explicit audio-source model

Files:

- `Sources/OpenLoopApp/Meetings/MeetingAudioRecorder.swift`
- `Sources/OpenLoopApp/Meetings/SystemAudioRecorder.swift`
- `Sources/OpenLoopApp/Meetings/MeetingTranscriptionController.swift`
- `Sources/OpenLoopApp/App/AppModel.swift`
- `Sources/OpenLoopApp/App/OpenLoopApp.swift`
- `Resources/Info.plist`
- `Package.swift`
- `Tests/OpenLoopAppTests/MeetingTranscriptionControllerTests.swift`
- `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`

Steps:

1. Define `AudioCaptureSource` with Microphone, This Mac, and Both display metadata and permission requirements.
2. Make recording start/stop asynchronous so ScreenCaptureKit can configure and finalize safely.
3. Add a router that keeps the existing microphone recorder and selects a ScreenCaptureKit recorder for This Mac or Both.
4. Capture system and microphone tracks locally; mix Both into one M4A before transcription.
5. Store the selected source in AppModel preferences and pass it through the meeting job for accurate status copy.
6. Add the Screen Recording usage description and framework link.
7. Add tests for source routing, source persistence, and job-state copy.

## Task 3 — Build a clear listening control and continuous session mode

Files:

- `Sources/OpenLoopApp/App/AppModel.swift`
- `Sources/OpenLoopApp/UI/WorkspaceChrome.swift`
- `Sources/OpenLoopApp/App/OpenLoopApp.swift`
- `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`

Steps:

1. Add a persisted `Keep listening` preference that starts a local voice-note session and keeps it active until explicitly stopped.
2. Show a red, source-labelled listening pill in the top bar during recording and a readable Start listening control when idle.
3. Put source selection, continuous listening, appearance, and Advanced mode in one labelled Settings menu.
4. Keep the global shortcut behavior and show source-aware feedback.
5. Disable unsafe source changes while recording or transcribing.

## Task 4 — Replace ambiguous capture controls and menu language

Files:

- `Sources/OpenLoopApp/UI/WorkspaceChrome.swift`
- `Sources/OpenLoopApp/App/OpenLoopApp.swift`
- `Sources/OpenLoopApp/App/MainWindowController.swift`

Steps:

1. Rename the text input to “Write something to remember.”
2. Rename Record to “Voice note,” expose “Type by voice” as a labelled action, and rename Import audio to “Transcribe a file.”
3. Explain the output destination in short status text: voice notes go to Voice notes; dictation goes to the active app.
4. Rewrite the menu-bar items using the same terms and remove ambiguous Capture/Act language.
5. Keep icons within one SF Symbols family and one size/weight hierarchy.

## Task 5 — Verify and package without opening the app

Steps:

1. Run focused OpenLoopApp tests for navigation, preferences, recording routing, and transcription-controller integration.
2. Run the package test suite once.
3. Build the release app and DMG without launching either artifact.
4. Report any permission limitation honestly: Screen Recording permission can require a one-time restart after first grant on macOS.

