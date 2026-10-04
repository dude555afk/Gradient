# Gradient

Gradient is a **GitHub website wrapper with an AI coding layer on top**.

The GitHub website is the primary interface. Gradient does not try to recreate repositories, issues, pull requests, Actions, or account navigation with a second custom client UI. Instead it embeds GitHub in a full-screen Android WebView and adds a native AI overlay for coding work.

## Product shape

- Full GitHub website as the main screen
- Persistent GitHub WebView cookies/session
- Floating Gradient AI button
- AI panel overlays the page you are already viewing
- Current repo / PR / issue / file / Actions page inferred from the GitHub URL
- Safe visible-page excerpt passed into AI context
- Sensitive-looking files such as `.env`, keys, keystores, and credential files are excluded from page-text context
- OpenAI-compatible AI provider support
- Native DuckDuckGo web research
- Direct GitHub REST reads behind the scenes
- GitHub Actions run/job/log inspection
- Diff-first edits
- Explicit **Apply & commit** approval before repository writes
- Explicit approval before PR creation
- Automatic task branch if an edit would otherwise touch the default branch

## GitHub authentication

Browsing uses the normal GitHub website/session in WebView.

Direct API mutations still require GitHub API authorization. Gradient supports GitHub OAuth device flow and a PAT fallback in Settings. Those credentials are kept in Android secure storage and are not used as the visual browsing session.

## AI provider

Configure an OpenAI-compatible endpoint in Settings. Gradient supports a default model plus optional role-specific models for fast, coding, reasoning, search, vision, and reviewer tasks.

## Development

Current bootstrap branch: `bootstrap/kelivo-shell`

## License

AGPL-3.0-or-later. Gradient adapts AGPL-licensed Kelivo concepts and code. See `NOTICE.md`.
