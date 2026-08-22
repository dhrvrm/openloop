# OpenLoop UI Kit

This kit translates the calm, list-first behavior studied in Things into an original OpenLoop interface for voice, tasks, transcripts, and semantic memory. It does not copy Things assets, icons, names, or proprietary layouts.

## Product grammar

1. The list is the surface. Rows sit on the canvas; cards are reserved for editors, active recording, errors, or a separate object that can move.
2. Space carries hierarchy. Titles, section headings, tasks, and metadata align to one reading column instead of receiving separate boxes.
3. Color is punctuation. Blue marks selection, navigation, and safe primary action. Red means recording, stopping, or destructive action. Semantic categories can use subdued secondary tints.
4. Editing opens in place. A task or transcript expands from its row and preserves its position. Sheets are used only when the object needs focused detail.
5. Evidence stays legible. Human titles lead; dates, model details, filenames, confidence, and identifiers remain secondary or Advanced-only.

## Shared tokens

The implementation source of truth is `Sources/OpenLoopApp/UI/OpenLoopVisualSystem.swift`.

| Role | Light | Dark | Use |
|---|---:|---:|---|
| Canvas | `#FBFAF7` | `#202228` | Main reading surface |
| Sidebar | `#F3F4F6` | `#191B20` | Navigation plane |
| Raised | `#FFFFFF` | `#292C33` | Editors, recording, movable panels |
| Selection | `#E3ECF7` | `#313B49` | Current row or destination |
| Accent | `#3973B9` | `#71A5E3` | Primary action and navigation |
| Recording | `#D84A4A` | `#FF6666` | Live microphone and stop action |

Spacing follows `4 / 8 / 12 / 20 / 32`, with deliberate larger edge space:

- Main content: `48` horizontal, `68` top, `92` bottom.
- Task row: at least `56` high.
- Sidebar row: at least `40` high.
- Text input: at least `46` high; quick capture: `56` high.
- Checkbox: `18` visual inside a `28` hit target.
- Corners: `10` navigation, `12` field, `14` editor/panel.

## Component contracts

### Sidebar destination

- One icon, one label, optional quiet count.
- No permanent border.
- Selection uses the selection fill and medium label weight.
- Hover uses the inactive selection fill.

### Task row

- Square rounded checkbox aligned with the first text baseline.
- Title at 16 points; metadata at 13 points.
- Actions remain hidden until hover, focus, or explicit selection.
- Divider is optional; it never encloses the row.
- Drag preserves the row preview and reveals the insertion target.

### Open text field

- Plain text field with 12-point horizontal and 10-point vertical padding.
- Quiet surface fill, no permanent bezel or inner shadow.
- Focus uses the system focus ring; validation appears below the field.

### Action button

- Minimum height `34`; primary capture actions can use `40–44`.
- Horizontal padding `13` or greater; vertical padding `8`.
- Blue is the safe primary action. Recording and Stop use red.
- Text-only secondary actions do not receive a capsule until hover.

### Transcript row

- Human subject title first.
- Duration, detected language, and capture time second.
- Storage filename and model identifier appear only after expansion or in Advanced.
- Expanded content groups summary, unresolved questions, decisions, possible actions, and exact timestamped evidence.

### Context graph

- Nodes display concepts and human recording titles, never raw storage filenames.
- File paths, vector identifiers, and model routes are Advanced-only facts.
- Selecting a node opens its evidence in the adjacent list; the graph is navigation, not the sole reading view.

## macOS composition

- Use a three-column split only when Advanced is visible: sidebar, centered reading column, inspector.
- Preserve a sidebar-free narrow mode without losing keyboard commands.
- Quick Capture is a floating non-activating panel with an open field and optional status line.
- Separate task or thread windows are allowed when comparison or cross-window drag provides real value.
- Use native window materials and controls so newer macOS appearances can evolve without custom imitation.

## iPad adaptation

The kit is portable because its tokens and components are SwiftUI-native. A future iPad target should:

- Use `NavigationSplitView` for sidebar and content.
- Present Advanced as an inspector on wide layouts and a sheet on compact layouts.
- Increase interactive hit targets to at least `44` while keeping the 18-point checkbox visual.
- Replace hover-only actions with swipe actions, context menus, and visible selection state.
- Support pointer hover and keyboard shortcuts when a trackpad or keyboard is attached.
- Keep the same task, transcript, and semantic-node models; do not fork product behavior by platform.

An iPad binary is outside this increment because the package currently declares macOS only. The kit avoids macOS-only visual assumptions, but shipping iPad requires a separate application target, entitlement review, responsive navigation tests, and touch interaction tests.

## Reference boundary

- [Things 3 App Store reference](https://apps.apple.com/in/app/things-3/id904237743)
- [Banani Things 3 screen index](https://www.banani.co/references/apps/things-3)
- [macOS 27 community kit](https://www.figma.com/community/file/1651309434229735362/macos-27)
- [`docs/design-references/things3/README.md`](design-references/things3/README.md)

Reference images remain the property of their respective owners and stay in the internal research directory. OpenLoop ships only its original interface and assets.
