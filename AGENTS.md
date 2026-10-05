# Gradient agent rules

## Product
Gradient is an Android-first remote coding client. Keep it focused on GitHub, coding, CI, releases, web research, models, and skills.

## UI
Keep the mobile experience visually close to Kelivo: floating rounded surfaces, minimal top bar, drawer/history, compact model selector, fluid composer, restrained settings, and streaming-first chat.

## Architecture
- Route GitHub reads and mutations through typed wrappers around the bundled GitHub CLI (`gh`).
- Do not reintroduce direct REST as the primary app backend. Use WebView only as a fallback for GitHub surfaces not rebuilt natively yet.
- Native DuckDuckGo search is the default web search.
- No MCP dependency for standard GitHub or web search.
- Route work through skills and task-specific model roles.
- Show diffs before remote writes.
- Keep one task branch per agent task and batch multi-file changes into one coherent commit when possible.
- Preserve chat/task state across app restarts.
- Never silently write to the default branch.
- Keep Android size and memory usage conservative.

## Safety
Never include secrets in model context. Treat .env, keystores, signing files, credentials, tokens, and private keys as protected by default.
