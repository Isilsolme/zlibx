# Releasing zlibx-MD3

Releases are cut by GitHub Actions, not from a laptop. A tag push is the
only thing that can publish; everything else is a dry run.

## The flow

1. Bump the version in `pubspec.yaml` (both parts):
   `version: 1.6.3+10603`. `versionName` = `1.6.3`, `versionCode` =
   `10603`. The build number must always increase, otherwise Android
   refuses to upgrade an installed copy.
2. Commit the bump on `main` and push.
3. Wait for the **Analyze and test** job on that commit to go green.
4. Tag the same commit and push the tag:

   ```bash
   git tag v1.6.3
   git push origin v1.6.3
   ```

5. The **Build signed release APK** job runs next:
   - restores the release keystore from secrets,
   - refuses to run if the tag does not match `pubspec.yaml`,
   - builds arm64 with R8, `--obfuscate` and `--split-debug-info`,
   - verifies the APK signature (and the certificate fingerprint when
     `EXPECTED_CERT_SHA256` is configured),
   - publishes a normal (non-prerelease) GitHub Release with the APK,
     `sha256sums.txt` and the Dart symbol map.

6. Normal releases only. `/releases/latest` — which the in-app updater
   polls — ignores prereleases, so a prerelease is invisible to users.

Manual runs (`workflow_dispatch`) build and upload the APK as a workflow
artifact without creating a Release. Use them to test a change to the
workflow itself.

## Required secrets

Set once in **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `KEYSTORE_BASE64` | base64 of `zlibx-md3.jks` |
| `KEYSTORE_PASSWORD` | `storePassword` from `android/key.properties` |
| `KEY_PASSWORD` | `keyPassword` from `android/key.properties` |
| `KEY_ALIAS` | `keyAlias` (`zlibx-md3`) |
| `EXPECTED_CERT_SHA256` | optional; `C93F9658…D75C09` without colons |

The keystore lives outside the repository at
`D:\VSCode\zlibx-MD3-signing\zlibx-md3.jks` and **must** be the same key
that signed v1.6.2. A different key means every installed user has to
uninstall first, which wipes their local Hive data (settings, cache,
download history).

Set all five at once from PowerShell:

```powershell
pwsh -File tool/set-ci-secrets.ps1
```

The script reads `android/key.properties` (and the keystore it points at),
base64-encodes the keystore in memory and uploads the secrets with `gh`.
Nothing is written to the repository. Pass `-Repo` to target another
repository, or `-ExpectedCertSha256 ''` to skip the fingerprint check.

Verify with `gh secret list --repo Isilsolme/zlibx-MD3` (values are never
readable back).

## Local release build

Still supported for offline checks. `android/key.properties` must point at
the keystore, and Gradle refuses to sign a release without it:

```powershell
flutter build apk --release --target-platform android-arm64 `
  --android-project-arg=kotlin.incremental=false `
  --android-project-arg=ksp.incremental=false
```

## After a bad release

- Delete the GitHub Release and the tag, fix, bump to the next build
  number, tag again. Never reuse a versionCode.
- If the bad build already reached users, the fix must ship with a higher
  versionCode; the in-app updater compares versions, not tags.
