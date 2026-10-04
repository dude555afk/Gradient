# Gradient

Gradient is an **AI-native GitHub mobile client for Android**.

The UI is native Flutter. GitHub operations are executed through a bundled Android build of the official **GitHub CLI (`gh`)**, and Gradient's AI agent uses the same controlled CLI backend for repository work.

## Architecture

```
Native Gradient UI
        ↓
GitHub CLI backend
        ↓
      GitHub

        +

Gradient AI
   ↓
Skill + model router
   ↓
Controlled gh tools + web research + diff engine
```

## Current features

- Native GitHub home/dashboard
- Native repository list
- Native repository code browser
- Branch picker
- Native issue list
- Native pull request list
- Native GitHub Actions list
- Native workflow job/log viewer
- WebView fallback for pages not rebuilt natively yet
- Bundled GitHub CLI 2.102.0 for Android arm64
- GitHub CLI web/device login, no custom OAuth app required
- Secure token storage
- OpenAI-compatible AI providers
- Kelivo-style provider model fetching from `/models`
- Searchable model picker
- Fast / Coding / Reasoning / Search / Vision / Reviewer model roles
- DuckDuckGo web research
- AI repo/file/workflow context
- Diff-first AI edits
- Explicit Apply & commit approval
- Explicit pull request approval
- Automatic task branches instead of silent default-branch writes

## GitHub backend

Gradient does not give the model unrestricted shell access. App features and AI tools call structured wrappers around `gh` commands such as:

- `gh repo list`
- `gh api`
- `gh issue list`
- `gh pr list`
- `gh run list`
- `gh run view`
- `gh pr create`

Authentication is supplied to the CLI through `GH_TOKEN` from Android secure storage.

## AI providers

Gradient supports OpenAI-compatible endpoints. Configure a base URL and optional API key, press **Fetch models**, then select models instead of manually remembering IDs.

Role-specific model slots can override the default model for coding, reasoning, search, vision, reviewing, and fast tasks.

## Safety

- GitHub credentials are never passed into model prompts.
- Sensitive file paths are excluded from page-context extraction.
- AI file writes become reviewable diffs first.
- Default-branch mutations are blocked by the agent flow.
- The model never receives an unrestricted terminal.

## Development

Current bootstrap branch: `bootstrap/kelivo-shell`

## License

AGPL-3.0-or-later. Gradient adapts AGPL-licensed Kelivo concepts and code. See `NOTICE.md`.
