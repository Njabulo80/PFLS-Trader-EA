# PFLS Predictor for Android

Native Android shell with an embedded mobile dashboard for Deriv Volatility 75 (R_75) public market data.

## Build
GitHub Actions workflow: `.github/workflows/android-apk.yml`. Run it from Actions -> Build PFLS Android APK -> Run workflow. Without signing secrets it creates a debug APK artifact for first testing only.

## Required signing secrets for installable updates
Create a persistent Android release keystore once, then add these repository Actions secrets:
- `PFLS_KEYSTORE_BASE64`: base64 of the keystore file
- `PFLS_KEYSTORE_PASSWORD`
- `PFLS_KEY_ALIAS`
- `PFLS_KEY_PASSWORD`

Never regenerate or replace the keystore after publishing the first signed APK. Every update must be signed with exactly the same key. Do not commit the keystore or passwords.

## Scope
Research-only market analysis. The app does not authenticate to Deriv accounts and has no order placement functionality. Rule scores are not calibrated probabilities or verified win rates.
