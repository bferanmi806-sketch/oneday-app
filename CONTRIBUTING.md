# Contributing to OneDay

Thanks for helping keep OneDay alive. This page gets you from clone to a running build and a first PR.

## Getting set up

You need Xcode 26 and [Tuist](https://tuist.dev):

```sh
tuist generate   # generates OneDay.xcodeproj
```

Open `OneDay.xcodeproj`, run the `OneDayApp` scheme on an iOS 26 simulator or device.
Unit tests: the `OneDayCoreTests` target.

To try the app end-to-end you need a Hermes server (v0.23.0) reachable from the device.
The API surface the client targets is documented in `docs/API-SURFACE.md`.

## Where things live

- `Sources/OneDayCore` — pure logic (no UI): API models, SSE parsing, URL normalization, error taxonomy. Most unit tests target this module — it's the easiest place to start.
- `Sources/OneDayDesign` — design tokens and shared components. UI values (spacing, type scale, colors) come from tokens, not literals.
- `Sources/OneDayApp` — SwiftUI app: connect flow, chat, hub (feed/ideas/goals), files, settings.
- `docs/` — API notes and design records. Long, but they explain *why* things are the way they are.

## Picking something to work on

- Issues labeled **`good first issue`** are scoped to be finishable without knowing the whole codebase.
- Issues labeled **`help wanted`** are the known real problems — including the chat interaction bugs in the current build.
- Nothing fitting? Open an issue describing what you'd like to change before writing a large PR.

## Ground rules

- **One datasource per fact.** If two places keep the same state, that's a bug — converge them.
- **Local-first actions.** User actions respond immediately in the UI; the server catches up in the background, and failures surface as human-readable messages with recovery.
- **API first.** Talk to the Hermes API directly; don't add bridge layers.
- **Design tokens only.** No hard-coded spacing/color/type values in views; extend the token tables instead.
- **Tests for core logic.** Changes in `OneDayCore` should come with unit tests.
- Keep PRs focused: one problem per PR, with a short description of the before/after behavior.

## Becoming a maintainer

If you've landed a couple of PRs and want to stick around, say so in an issue —
the project is actively looking for co-maintainers.
