# Local Mac Feasibility

Assessment date: 2026-08-12.

## Verdict

Yes, this application can be built entirely on the current Mac and distributed
for free as a `.dmg`. It does not need a cloud account, backend, hosted model,
website, or domain.

The current machine is an Apple M4 MacBook Air with 24 GB unified memory running
macOS 26.2. It is sufficient for the native application, local search,
embeddings, offline speech recognition, and compact local language models.

Full Xcode is not currently selected; Apple Command Line Tools and Swift 6.2.3
are present. Full Xcode will eventually be useful for entitlements, profiling,
app bundles, and polished release builds, but the domain model and command-line
test harness can begin with Swift Package Manager.

## Free `.dmg` distribution

The minimum distribution path is:

1. build `OpenLoop ADHD.app`;
2. place it in a disk-image staging folder with an Applications shortcut;
3. create `OpenLoop-ADHD.dmg` using `hdiutil create`;
4. share the file directly.

An ad-hoc or unsigned build may trigger Gatekeeper friction for other users. That
is acceptable during personal development. Developer ID signing and notarization
remain optional polish for a later public release, not a current product gate.

A domain is unnecessary. If one is used later, a static page can serve the DMG;
the application still has no hosted runtime dependency.

## Apple Silicon access

The application can use supported Apple hardware paths:

| Framework | Accessible compute | Intended role |
| --- | --- | --- |
| Core ML | CPU, GPU, Neural Engine | Production model inference |
| Metal / MPSGraph | GPU and supported compute scheduling | Specialized high-performance work |
| MLX Swift | Apple Silicon GPU and unified memory | Local-model experimentation |
| Accelerate / BNNS | Optimized CPU primitives | Audio DSP, vector operations, small models |

Direct arbitrary Neural Engine programming is unnecessary. Core ML schedules
compatible models across Apple compute devices; MPSGraph supports compiled
compute graphs; MLX provides an Apple-Silicon-native experimentation path.

References:

- https://developer.apple.com/documentation/coreml
- https://developer.apple.com/documentation/metalperformanceshadersgraph
- https://github.com/ml-explore/mlx-swift

## Speech recognition feasibility

Good local speech recognition is feasible, but voice is an input adapter—not the
center of the product. It should be added only after typed capture proves the
ADHD interaction loop.

Two providers should be compared behind one interface:

- Apple `SpeechAnalyzer` and `SpeechTranscriber` on macOS 26;
- `whisper.cpp` using Apple Silicon optimizations.

The benchmark must use the actual user's accent, language switching, names,
technical vocabulary, room noise, rushed speech, and abandoned sentences. It
measures:

- first text latency;
- final text latency;
- word error rate;
- exact names and technical terms;
- memory and energy over long sessions;
- recovery after audio-device changes;
- whether corrections improve the personal vocabulary.

References:

- https://developer.apple.com/documentation/speech/speechanalyzer
- https://github.com/ggml-org/whisper.cpp

## Feasibility order

1. Prove the ADHD loop with typed capture and local persistence.
2. Prove focus and interruption recovery.
3. Package the working local application as a DMG.
4. Add local voice input.
5. Add evidence-backed memory compression and recall.
6. Add ambient sensing only where it reduces user effort.

No step depends on cloud infrastructure or organizational identity.
