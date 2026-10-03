---
name: Android
description: Android, Gradle, Kotlin, Compose, APK and signing troubleshooting.
---

# Android skill

Inspect in this order when relevant:

1. settings.gradle / settings.gradle.kts
2. root build.gradle / build.gradle.kts
3. app build.gradle / build.gradle.kts
4. gradle.properties
5. AndroidManifest.xml
6. implicated Kotlin or Compose source
7. workflow and release configuration

Never expose keystores, signing passwords, tokens, or local.properties values to models.
