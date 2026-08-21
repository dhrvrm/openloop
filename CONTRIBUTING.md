# Contributing

OpenLoop welcomes focused issues and pull requests. Start with the smallest complete change that improves capture, understanding, recall, or safe action.

## Development setup

```bash
git clone https://github.com/dhrvrm/openloop.git
cd openloop
swift build
swift test
```

Packaging additionally requires Xcode's Metal toolchain because local speech dependencies include MLX kernels.

For the website:

```bash
cd website
npm install
npm run build
```

## Change flow

1. Open an issue for behavior changes or new product surface area.
2. Keep commits narrow and use imperative subjects.
3. Add or update focused tests for deterministic behavior.
4. Keep generated models, private audio, runtime data, and signing material out of Git.
5. Update architecture or decision documentation when a boundary changes.
6. Explain visible behavior, tradeoffs, and verification in the pull request.

Do not launch the GUI from an automated test. Exercise presentation models, controllers, ports, and adapters directly; reserve manual app checks for release candidates.

## Design bar

Native UI should preserve clear hierarchy, platform behavior, keyboard access, reduced-motion support, and explicit system feedback. Website changes must keep the product representation truthful and pass its production build.

## Commit convention

Use `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `build:`, or `chore:` followed by a concise present-tense description.
