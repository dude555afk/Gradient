# Gradient

Gradient is an Android-first AI coding client for working directly with GitHub repositories from a phone.

## Current features

- Kelivo-inspired chat-first mobile UI
- GitHub OAuth device flow plus PAT fallback
- Android secure storage for GitHub and provider tokens
- Repository and branch picker
- Embedded GitHub WebView
- OpenAI-compatible provider support
- Per-role model routing: fast, coding, reasoning, search, vision, reviewer
- Native keyless DuckDuckGo search
- Web page extraction for research
- Remote GitHub file reads and directory listing
- GitHub Actions run/job/log inspection
- Automatic safe task-branch creation
- Diff-first AI file changes
- User-approved apply + commit
- User-approved pull request creation
- Flutter analyze/test CI
- Release APK artifact workflow

## Agent safety model

Gradient does not expose a direct write-file tool to the model. The model can inspect the repo and prepare complete file replacements, but those become local diff cards. The user must press **Apply & commit** before GitHub is mutated.

If an edit is proposed on the default branch, Gradient creates a task branch before applying it.

## AI providers

Gradient talks to OpenAI-compatible `/chat/completions` endpoints. Configure:

- base URL
- API key, optional for anonymous endpoints
- default model
- optional role-specific models
- optional reasoning effort

This keeps Gradient usable with OpenRouter and compatible gateways without baking provider credentials into the app.

## GitHub OAuth

Gradient implements GitHub's device flow. Create a GitHub OAuth App, enable **Device Flow**, then paste its client ID in Settings. No client secret is stored in the app.

A personal access token fallback is available for development/testing.

## Development

Bootstrap work currently lives on `bootstrap/kelivo-shell`.

## License

AGPL-3.0-or-later. Gradient adapts AGPL-licensed Kelivo concepts and code. See `NOTICE.md`.
