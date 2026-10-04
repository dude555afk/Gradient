# Android release signing

Gradient release APKs are signed with one persistent key so sideloaded builds can update in place.

The build workflow requires two repository Actions secrets:

- `GRADIENT_KEYSTORE_BASE64`: base64 encoding of the release keystore.
- `GRADIENT_KEYSTORE_PASSWORD`: password for the keystore and the `gradient` key alias.

The private keystore must never be committed to this repository.

The workflow verifies the keystore before building and runs `apksigner verify --print-certs` on every uploaded APK. The resulting public certificate information is uploaded beside the APK as `signing-certificate.txt`.

Because older bootstrap APKs were signed with ephemeral CI/debug keys, users must uninstall one of those old builds once before installing the first permanently signed release. After that migration, future releases can update normally as long as the signing secrets remain unchanged.
