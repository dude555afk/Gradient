---
name: CI
description: Diagnose failing GitHub Actions and build pipelines.
---

# CI skill

1. Identify the failed run and job.
2. Read the failing step and nearby log context first.
3. Map the error to repository files and dependency/build configuration.
4. Search official documentation when behavior may be version-specific.
5. Propose the smallest fix.
6. Validate YAML and build configuration.
7. Show a diff before applying.
8. Re-run CI only after the approved change is committed.
