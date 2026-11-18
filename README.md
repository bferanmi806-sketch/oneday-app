# OneDay — a native iOS client for your self-hosted Hermes AI agent

![iOS 26](https://img.shields.io/badge/iOS-26-black)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-green)
![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)

**OneDay is a full-featured, native iOS client for Hermes — the self-hosted AI agent server.**
Run your own agent on your own server, then chat with it, watch it work, approve its actions, browse its files and manage its models from your iPhone. No third-party cloud in the middle: the app talks directly to *your* server over its API.

> **Status:** OneDay is under active development by its original author (a solo side project, so the pace is irregular). Development is briefly paused while a Mac is on its way for on-device testing, and resumes as soon as it arrives. The codebase is complete and builds; see the [help-wanted issues](https://github.com/yyyyymmmmm/oneday-app/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22) if you'd like to pick something up, or open an issue to say hello if you want to co-maintain.

## Screenshots

<p>
  <img src="docs/shots/02-chat.png" width="250" alt="Chat">
  <img src="docs/shots/01-connect.png" width="250" alt="Connect to your server">
  <img src="docs/shots/04-overview.png" width="250" alt="Overview">
</p>

## Features

- **Streaming chat** with block-level rendering, tool-call cards, image lightbox and file preview
- **Approvals in the chat stream** — the agent asks, you tap to approve or deny, with a full audit ledger
- **Sessions & channels** — your conversations, plus sessions that arrive from the web/API side, all resumable
- **Work ledger** — every background/scheduled task the agent runs, with live status
- **Files** — browse, preview and manage the agent's working files
- **Feed, Ideas, Goals** — the agent keeps an eye on the world for you, proposes next steps, and tracks your goals
- **Model & provider management** — bring your own providers and model line-ups, switch per session
- **Voice dictation** and on-device connectors (calendar, contacts, reminders, health summaries) with a strict one-switch-per-dataset privacy model
- **iOS 26 native design** — Liquid Glass surfaces, a token-driven design system, full Dark Mode and Dynamic Type support
- **Self-hosted first** — in-app setup wizard: paste your server address and key, the app verifies the connection, done

## Requirements

- A running **Hermes server (v0.23.0)** — see `docs/API-SURFACE.md` for the exact API surface this client is built and tested against
- iPhone with **iOS 26+**
- To build: Xcode 26 + [Tuist](https://tuist.dev)

## Build & run

```sh
tuist generate   # generates OneDay.xcodeproj
```

Open the project in Xcode, pick the `OneDayApp` scheme, run. Unit tests live in `OneDayCoreTests`.

On first launch the app asks only for your Hermes server address and your login key — everything else is configured in-app.

## Project layout

- `Sources/OneDayCore` — pure logic: URL normalization, API models, SSE parsing, error taxonomy
- `Sources/OneDayDesign` — design tokens and base components
- `Sources/OneDayApp` — UI and networking: connect flow, chat, hub, files, settings
- `Tests/OneDayCoreTests` — unit tests for the core
- `docs/` — API surface notes and design records

## 中文简介

OneDay 是自托管 AI Agent 服务端 **Hermes** 的原生 iOS 客户端：把 Agent 跑在你自己的服务器上，再用 iPhone 跟它聊天、看它干活、在聊天里批它的审批、管它的文件和模型。流式对话、工具调用卡片、会话与频道、工作台账、文件预览、语音听写、设备连接器（日历/通讯录/健康摘要）一应俱全，按 iOS 26 原生设计语言打造。

项目仍由原作者持续开发（个人业余项目，节奏不定期），目前短暂暂停，等 Mac 到位后继续推进并做真机测试。也欢迎共同维护：欢迎从 [help wanted issue](https://github.com/yyyyymmmmm/oneday-app/issues) 里挑一个上手，或直接开 issue 报名共同维护。

## Contributing

PRs and new maintainers are welcome — start with [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
