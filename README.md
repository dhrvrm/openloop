# OpenLoop

**A private working memory for your Mac.**

OpenLoop captures voice and text, keeps the evidence, and helps you return to unfinished work without reconstructing the entire context. It is a native, local-first macOS application—not a web wrapper and not a task generator disguised as memory.

[Website](https://dhrvrm.github.io/openloop/) · [Download](https://github.com/dhrvrm/openloop/releases/latest) · [Architecture](docs/ARCHITECTURE.md) · [Product principles](docs/PRODUCT.md)

## What exists today

- global text capture and record/transcribe shortcuts;
- live microphone level, duration, partial state, and explicit engine feedback;
- multilingual local transcription with Hindi/English code-switch handling;
- meeting audio import, transcript evidence, summaries, and action candidates;
- encrypted local persistence and permission-aware capture;
- return, recall, semantic threads, and a 3D connected-memory view;
- local and optional model-backed processing paths with visible diagnostics.

OpenLoop keeps suggestions separate from commitments. A sentence can be an observation, question, possibility, decision, or action—and its original evidence remains available.

## Install

Download the latest DMG from [GitHub Releases](https://github.com/dhrvrm/openloop/releases/latest), drag **OpenLoop ADHD** to Applications, and grant access only when you use the matching feature. Microphone powers voice notes and voice typing, Screen Recording captures audio playing on this Mac, and Accessibility writes finished dictation into another app.

The current build targets Apple silicon and macOS 15 or newer.

## Build

Prerequisites: Swift 6.2, Xcode with the Metal toolchain, and Apple silicon.

```bash
git clone https://github.com/dhrvrm/openloop.git
cd openloop
swift build
swift test
Scripts/build-dmg.sh
```

The release script compiles the native application, the required MLX Metal library, and a versioned DMG. It refuses to present an incomplete bundle as a valid release.

The public website is isolated in `website/`:

```bash
cd website
npm install
npm run build
```

Repository maintainers can apply the canonical description, homepage, topics, and GitHub Pages setting with `Scripts/configure-github.sh` after authenticating GitHub CLI with admin access.

## Repository map

```text
Sources/
  ADHDCore/       domain model, ports, use cases
  LocalStore/     local persistence adapter
  VaultStore/     encrypted storage adapter
  RuleClarifier/  deterministic clarification rules
  OpenLoopApp/    native composition, voice, meetings, context, UI
  ThoughtLoopCLI/ command-line interface
Tests/            tests aligned to the production targets
Resources/        application metadata and entitlements
Scripts/          build, release, and focused verification commands
docs/             product, architecture, data, and decision records
website/          public product website
```

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing a dependency boundary. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development flow and [SECURITY.md](SECURITY.md) for private disclosure.

## Principles

- Local is an architectural constraint, not a marketing label.
- Capture must be faster than reconstructing a lost thought.
- Evidence is preserved; generated interpretation is labeled.
- Low-confidence guesses stay quiet.
- Dangerous or external actions require explicit authority.
- Accessibility and reduced motion are product requirements.

## License

MIT. Steal the code, legally.
