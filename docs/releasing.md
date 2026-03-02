# Releasing Launchyard

## Prerequisites

1. **Developer ID certificate** installed in Keychain: `Developer ID Application: Your Name (YOURTEAMID)`
2. **Notarization credentials** stored in Keychain:
   ```bash
   xcrun notarytool store-credentials "AC_PASSWORD" \
     --apple-id "your-apple-id@example.com" \
     --team-id "YOURTEAMID" \
     --password "<app-specific-password>"
   ```
   Generate an app-specific password at [appleid.apple.com](https://appleid.apple.com/account/manage) → Sign-In and Security → App-Specific Passwords.
3. **Environment file** at `~/.config/launchyard/notarize.env`:
   ```bash
   APPLE_ID=your-apple-id@example.com
   TEAM_ID=YOURTEAMID
   SIGNING_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)"
   ```

## Steps

### 1. Bump the version

Edit `Launchyard.xcodeproj/project.pbxproj` and update `MARKETING_VERSION`:

```bash
# Example: bump to 1.0.2
sed -i '' 's/MARKETING_VERSION = 1.0.1;/MARKETING_VERSION = 1.0.2;/' Launchyard.xcodeproj/project.pbxproj
```

### 2. Commit and push

```bash
git add -A
git commit -m "Bump version to 1.0.2"
git push
```

### 3. Build, sign, notarize

The Makefile handles the full pipeline:

```bash
source ~/.config/launchyard/notarize.env
make notarize SIGNING_IDENTITY="$SIGNING_IDENTITY" TEAM_ID="$TEAM_ID"
```

This will:
- **Build** a Release configuration (unsigned initially)
- **Sign** with the Developer ID certificate + hardened runtime + timestamp
- **Zip** the signed .app
- **Submit** to Apple's notary service and wait for approval
- **Staple** the notarization ticket to the .app
- **Re-zip** with the stapled ticket

The final `Launchyard.zip` in the repo root is ready to distribute.

### 4. Verify (optional)

```bash
make verify
```

Checks codesigning, Gatekeeper assessment, and stapler validation.

### 5. Create the GitHub release

```bash
gh release create v1.0.2 \
  --title "Launchyard 1.0.2" \
  --notes "### What's New

- Feature X
- Bug fix Y" \
  Launchyard.zip
```

### 6. Update the screenshot (if UI changed)

```bash
# Clear cached window state
defaults delete com.jayhickey.Launchyard 2>/dev/null
rm -rf ~/Library/Saved\ Application\ State/com.jayhickey.Launchyard.savedState 2>/dev/null

# Launch in screenshot mode, capture, close
open .build/Build/Products/Release/Launchyard.app --args --screenshot
sleep 5
# Use screencapture or take manually, save to screenshot.png
```

## Troubleshooting

### "no identity found" during signing
The `SIGNING_IDENTITY` must exactly match what's in Keychain. Check available identities:
```bash
security find-identity -v -p codesigning
```

### Notarization rejected
Check the detailed log:
```bash
xcrun notarytool log <submission-id> --keychain-profile "AC_PASSWORD"
```

Common issues:
- Missing hardened runtime (`--options runtime` in codesign)
- Missing timestamp (`--timestamp` in codesign)
- Unsigned nested binaries (use `--deep`)

### Keychain profile not found
Re-run `xcrun notarytool store-credentials "AC_PASSWORD"` with your app-specific password.
