SHELL = /bin/bash

APP_NAME = Launchyard
SCHEME = Launchyard
PROJECT = Launchyard.xcodeproj
CONFIGURATION = Release
BUILD_DIR = $(CURDIR)/.build
APP_PATH = $(BUILD_DIR)/Build/Products/$(CONFIGURATION)/$(APP_NAME).app
ZIP_NAME = $(APP_NAME).zip

# Override these or set in environment / keychain
# SIGNING_IDENTITY = "Developer ID Application: Your Name (TEAMID)"
# TEAM_ID = "YOURTEAMID"

.DEFAULT_GOAL = build

# ── Build ────────────────────────────────────────────────────

.PHONY: build
build:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration $(CONFIGURATION) \
		-derivedDataPath "$(BUILD_DIR)" \
		-arch arm64 \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO
	@echo "✅ Built $(APP_PATH)"

# ── Sign ─────────────────────────────────────────────────────

.PHONY: sign
sign: build
	@test -n "$(SIGNING_IDENTITY)" || (echo "❌ Set SIGNING_IDENTITY"; exit 1)
	codesign \
		--force \
		--deep \
		--sign "$(SIGNING_IDENTITY)" \
		--options runtime \
		--timestamp \
		"$(APP_PATH)"
	@echo "✅ Signed $(APP_PATH)"

# ── Zip ──────────────────────────────────────────────────────

.PHONY: zip
zip: sign
	@rm -f "$(ZIP_NAME)"
	ditto -c -k --keepParent "$(APP_PATH)" "$(ZIP_NAME)"
	@echo "✅ Created $(ZIP_NAME)"

# ── Notarize ─────────────────────────────────────────────────
# Prerequisites:
#   1. Store credentials once:
#      xcrun notarytool store-credentials "AC_PASSWORD" \
#        --apple-id "you@example.com" \
#        --team-id "YOURTEAMID" \
#        --password "app-specific-password"
#
#   2. Then run:
#      make notarize SIGNING_IDENTITY="Developer ID Application: ..." TEAM_ID="YOURTEAMID"

.PHONY: notarize
notarize: zip
	@test -n "$(TEAM_ID)" || (echo "❌ Set TEAM_ID"; exit 1)
	@echo "📤 Submitting to Apple notarization service..."
	xcrun notarytool submit "$(ZIP_NAME)" \
		--keychain-profile "AC_PASSWORD" \
		--team-id "$(TEAM_ID)" \
		--wait
	@echo "📎 Stapling notarization ticket..."
	xcrun stapler staple "$(APP_PATH)"
	@echo "♻️  Re-zipping with stapled ticket..."
	@rm -f "$(ZIP_NAME)"
	ditto -c -k --keepParent "$(APP_PATH)" "$(ZIP_NAME)"
	@echo "✅ $(ZIP_NAME) is notarized and ready to distribute"
	@open -R "$(ZIP_NAME)"

# ── Verify ───────────────────────────────────────────────────

.PHONY: verify
verify:
	codesign --verify --deep --strict "$(APP_PATH)"
	spctl --assess --type execute "$(APP_PATH)"
	stapler validate "$(APP_PATH)"
	@echo "✅ All checks passed"

# ── Clean ────────────────────────────────────────────────────

.PHONY: clean
clean:
	rm -rf "$(BUILD_DIR)" "$(ZIP_NAME)"
	@echo "🧹 Cleaned"
