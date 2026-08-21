# OpenLoop Open-Source Launch Plan

> **Goal:** Present OpenLoop as a complete, design-led macOS product with a truthful public website, legible repository architecture, and repeatable versioned releases.

## Phase 1 — Product website

- Build an eight-part editorial launch narrative in `website/`.
- Use the real application capture as the product source of truth.
- Add screen-in-screen spatial choreography, recording feedback, and a semantic-memory visualization.
- Respect reduced-motion, keyboard focus, mobile layouts, and readable contrast.

## Phase 2 — Repository surface

- Replace the overloaded README with a concise product and contributor entry point.
- Document architecture, data boundaries, contribution flow, security, and releases separately.
- Organize app source by capability while preserving SwiftPM dependency direction.

## Phase 3 — Distribution

- Produce versioned DMG names from the app plist.
- Add CI, Pages deployment, and tag-driven GitHub Release workflows.
- Merge the existing remote MIT license without rewriting history.
- Push through the verified personal SSH host.

## Phase 4 — Local handoff

- Build and test without launching the GUI.
- Package and install only when the MLX Metal library can be compiled correctly.
- Never replace the installed application with a known-incomplete bundle.
