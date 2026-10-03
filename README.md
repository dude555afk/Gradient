# Gradient

A lightweight Android-first AI coding client for remote GitHub work.

Gradient keeps the polished chat-first feel of Kelivo while replacing generic assistant plumbing with coding-focused tools: GitHub, workflows, diffs, skills, model routing, and native web research.

## Bootstrap

- Kelivo-inspired mobile chat UI
- Embedded GitHub WebView workspace
- Native GitHub REST seam
- Native keyless DuckDuckGo search adapted from Kelivo
- Task-aware model routing
- Bundled GitHub / CI / Android / Research skills
- Flutter analyze + tests in GitHub Actions
- No MCP requirement for normal GitHub or web access

## Architecture

```
Kelivo-style UI
      ↓
   AI Agent
      ↓
 Skill Router
      ↓
 Model Router
      ↓
 Native Tools
 ├─ GitHub REST
 ├─ GitHub WebView
 ├─ DuckDuckGo Search
 └─ Diff/Patch Engine (next)
```

Development starts on `bootstrap/kelivo-shell`.

Bootstrap status: active.

## License

AGPL-3.0-or-later. Gradient adapts AGPL-licensed Kelivo concepts and code. See `NOTICE.md`.
