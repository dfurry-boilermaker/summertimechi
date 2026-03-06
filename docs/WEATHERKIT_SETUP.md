# WeatherKit Setup Guide

SummertimeChi uses Apple WeatherKit for hourly cloud forecasts in each bar's Today's Timeline (sun/shade icons reflect forecast clouds) and for patio suitability on the Favorites tab. WeatherKit **does not work in the iOS Simulator** and requires proper configuration in the Apple Developer Portal.

## Requirements

- **Apple Developer Program** membership ($99/year)
- **Physical device** — WeatherKit uses app attestation and will fail in Simulator
- **iOS 16+**

## Setup Steps

### 1. Enable WeatherKit for Your App ID

1. Go to [developer.apple.com](https://developer.apple.com) → **Account** → **Certificates, Identifiers & Profiles**
2. Click **Identifiers** in the sidebar
3. Select your App ID (e.g. `com.danielfurry.summertimechi`) or create one
4. Under **App Services**, check **WeatherKit**
5. Click **Save**

### 2. Regenerate Provisioning Profile

After enabling WeatherKit, your provisioning profile must be updated:

1. Go to **Profiles**
2. Select your development/distribution profile for SummertimeChi
3. Click **Edit** → **Generate** to create a new profile with the WeatherKit capability

Alternatively, in Xcode: **Signing & Capabilities** → ensure your team is selected — Xcode will automatically manage profiles when "Automatically manage signing" is enabled.

### 3. Verify Xcode Project

The project is already configured with:

- **WeatherKit.framework** linked
- **Entitlement** `com.apple.developer.weatherkit` = true in `SummertimeChi.entitlements`
- **Info.plist** `WeatherKitUsageDescription` key

In Xcode, confirm:
1. **Signing & Capabilities** tab shows the **WeatherKit** capability
2. If not, click **+ Capability** and add **WeatherKit**

### 4. Build and Run on Device

1. Connect a physical iPhone
2. Select it as the run destination (not Simulator)
3. Build and run
4. Open a bar's detail view (Today's Timeline) or the **Favorites** tab — weather should load

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **WDSJWTAuthenticator error 2** (JWT auth failed) | 1) developer.apple.com → Identifiers → select your App ID → under App Services, ensure **WeatherKit** is checked → Save. 2) Xcode → Product → Clean Build Folder. 3) Remove the app from your device and reinstall. 4) If using automatic signing, try: Signing & Capabilities → turn off "Automatically manage signing" → turn it back on (forces profile refresh). |
| "Weather unavailable" / no data | Test on a **real device**, not Simulator |
| Capability errors | Ensure App ID has WeatherKit at developer.apple.com, then regenerate provisioning profile |
| Build fails with WeatherKit | Ensure deployment target is iOS 16+ and the framework is linked |
| Works in Simulator | It won't — WeatherKit requires a physical device |

## Pricing

Apple Developer Program includes **500,000 WeatherKit API calls per month** at no extra cost.
