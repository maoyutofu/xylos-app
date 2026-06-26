# Android Signing And GitHub Actions

## 1. Generate a release keystore

Run locally:

```sh
keytool -genkeypair \
  -v \
  -keystore release.keystore \
  -alias xylos \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

You will be prompted for:

- keystore password
- certificate information

Depending on your JDK version and keystore type, `keytool` may not prompt for a
separate key password. This is normal. In that case, the key password is the same
as the keystore password.

Recommended:

- use `xylos` as the alias
- keep the keystore password and key password the same if you want simpler setup
- store all passwords safely

If you specifically want a different key password, pass it explicitly:

```sh
keytool -genkeypair \
  -v \
  -keystore release.keystore \
  -alias xylos \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass "your-keystore-password" \
  -keypass "your-key-password"
```

For the simpler default setup, use the same value for:

- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`

## 2. Move the keystore to a safe location

Do not keep the real keystore in the git repository.

Example:

```sh
mkdir -p ~/secure
mv release.keystore ~/secure/xylos-release.keystore
```

## 3. Generate base64 for GitHub Secrets

```sh
base64 < ~/secure/xylos-release.keystore
```

On macOS, you can copy it directly:

```sh
base64 < ~/secure/xylos-release.keystore | pbcopy
```

## 4. Configure GitHub Actions secrets

Open:

`Settings -> Secrets and variables -> Actions`

Add these repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Values:

- `ANDROID_KEYSTORE_BASE64`: base64 content of the keystore file
- `ANDROID_KEYSTORE_PASSWORD`: keystore password
- `ANDROID_KEY_ALIAS`: `xylos` or your chosen alias
- `ANDROID_KEY_PASSWORD`: key password

## 5. Configure local release signing

Copy the example file:

```sh
cp android/key.properties.example android/key.properties
```

Edit `android/key.properties`:

```properties
storeFile=/Users/your-name/secure/xylos-release.keystore
storePassword=your-keystore-password
keyAlias=xylos
keyPassword=your-key-password
```

Notes:

- prefer an absolute path for `storeFile`
- do not commit `android/key.properties`
- do not commit the keystore file

## 6. Build a local release APK

```sh
flutter pub get
flutter build apk --release
```

Output path:

```text
build/app/outputs/flutter-apk/
```

## 7. Trigger GitHub Actions release build

This repository currently builds on git tags.

Example:

```sh
git tag v1.0.0+1
git push origin v1.0.0+1
```

After the tag is pushed, GitHub Actions will:

- restore the keystore from secrets
- inject signing env vars
- build the Android release APK
- upload release artifacts

## 8. Required long-term backups

Keep these backed up in a safe place:

- `xylos-release.keystore`
- keystore password
- key alias
- key password

If you lose the keystore, future Android updates cannot be signed with the same identity.
