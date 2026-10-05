# Gradient Android update channel

Gradient uses one canonical Android package and signing identity for all updateable builds.

## Permanent identity

- Package ID: `com.dude555afk.gradient`
- Signing key alias: `gradient`
- Signing certificate SHA-256:
  `B6:8F:15:7F:1D:93:15:6C:69:D3:0D:58:2A:69:11:E7:BC:6A:57:69:A5:CA:1C:1C:2A:C7:FB:9D:3E:2D:28:B6`

The certificate fingerprint is public information. The private keystore remains in GitHub Actions secrets and must never be committed.

## Update rules

Android permits an APK to update an installed app only when:

1. The package ID is identical.
2. The signing certificate is identical.
3. The new APK has a greater `versionCode`.

The Gradient Android workflow enforces all three conditions.

Every workflow build uses:

- `versionCode = 100000 + GITHUB_RUN_NUMBER`
- `versionName = 0.3.<GITHUB_RUN_NUMBER>`

This gives every new CI build a strictly newer Android version while keeping the same app identity.

## One-time migration

Bootstrap APKs built before the permanent signing key used temporary CI/debug certificates. Those cannot update to the permanent channel.

Uninstall an old bootstrap build once, then install the first APK produced by the permanent update channel. From that point onward, **do not uninstall Gradient between builds**. New APKs from the `Build Android APK` workflow install over the existing app normally.

Do not mix in locally signed, debug, or old bootstrap APKs.

## CI verification

Before an artifact is uploaded, CI verifies:

- the supplied keystore matches the pinned Gradient signing certificate;
- the final APK is signed with that same certificate;
- the APK package ID is `com.dude555afk.gradient`;
- the APK versionCode matches the monotonically increasing CI value.

Each artifact contains:

- `Gradient-release.apk`
- `signing-certificate.txt`
- `update-info.json`

If any identity check fails, no APK is published.
