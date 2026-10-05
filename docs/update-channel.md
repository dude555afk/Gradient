# Gradient update channel

Gradient uses a rolling GitHub Release tagged `gradient-latest`.

Every successful signed Android build:

1. keeps the package ID `com.dude555afk.gradient`,
2. uses the same persistent release signing key,
3. uses `GITHUB_RUN_NUMBER` as Android's monotonically increasing versionCode,
4. moves the `gradient-latest` tag to the new commit,
5. replaces the release APK and `update.json`,
6. exposes the update in Settings → Updates.

The app compares its installed build number with `update.json`. If a newer build exists, the Download button opens the signed APK. Android then performs an in-place update and preserves the app's data.

## One-time migration

Bootstrap APKs signed with the old ephemeral CI/debug certificate cannot be updated in place to the permanent signing certificate. They must be uninstalled once. After the first permanently signed Gradient build is installed, later updates use the same certificate and no uninstall is required.

## Required Actions secrets

- `GRADIENT_KEYSTORE_BASE64`
- `GRADIENT_KEYSTORE_PASSWORD`

Do not rotate or delete the release keystore unless you intentionally want to break the update chain.
