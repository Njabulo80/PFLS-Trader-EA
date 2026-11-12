# PFLS Read-Only MT5 Collector — Windows 10 Setup

## Safety
- Use a Deriv DEMO account only.
- The collector reads account metrics, open positions and recent deal history.
- It contains no order placement, modification or closing calls.
- Never share your MT5 password, PFLS bridge secret or mobile read token in chat.
- Do not enable trading permissions for this collector.

## 1. Add the collector to MetaTrader 5
1. Keep the Deriv MT5 desktop terminal logged into the DEMO account.
2. Press F4 to open MetaEditor.
3. In MetaEditor choose File > Open Data Folder (or return to MT5 and use File > Open Data Folder).
4. Open MQL5 > Experts.
5. Download PFLS_ReadOnly_Collector.mq5 from this repository and copy it into that Experts folder.
6. Return to MetaEditor. In Navigator > Experts, right-click and choose Refresh if needed.
7. Open PFLS_ReadOnly_Collector.mq5 and press F7 to compile.
8. Confirm the Errors tab says 0 errors. Do not attach it if compilation reports errors; share the error text instead.

## 2. Allow the HTTPS bridge address in MT5
1. In MT5 choose Tools > Options > Expert Advisors.
2. Enable "Allow WebRequest for listed URL".
3. Add this exact base URL:
   https://pfls-communication-bridge-v2.dlamininjabulombhodziya.workers.dev
4. Click OK.

This permission allows the collector to send its read-only snapshot to the PFLS bridge. It does not give the bridge control of MT5.

## 3. Configure the collector
1. In MT5 Navigator > Experts, drag PFLS_ReadOnly_Collector onto a chart for the demo account.
2. In Inputs, leave InpDemoAccountsOnly = true.
3. Set InpBridgeSecret to the existing PFLS_BRIDGE_SECRET value configured in your Cloudflare Worker. Enter it locally in MT5 only; do not send it in chat.
4. Keep the default bridge URL and 20-second sync interval.
5. Click OK. Allow Algo Trading only if MT5 requires it for the EA to run its timer/WebRequest; the EA has no trade execution code. If you prefer, leave the global trade button off and verify the collector still runs.
6. Check the Experts tab for "read-only demo snapshot delivered". HTTP 200 means the bridge accepted the snapshot.

## 4. Mobile read token
The Android app reads account data using a separate token, not the collector write secret and not the MT5 password.
1. In Cloudflare Dashboard open Workers & Pages > pfls-communication-bridge-v2 > Settings > Variables and Secrets.
2. Add a Secret named PFLS_MOBILE_READ_TOKEN.
3. Set a long random value (at least 32 characters). Save it locally in a password manager.
4. Deploy the updated Worker code from the connected GitHub repository if automatic deployment has not already run.
5. In PFLS Predictor > Connection configuration, enter the same token in "PFLS mobile read-only access token" and tap Save read token.

Do not use the same value for PFLS_BRIDGE_SECRET and PFLS_MOBILE_READ_TOKEN.

## 5. Expected behaviour
- MT5 Experts tab: periodic successful HTTP 200 snapshot messages.
- PFLS Predictor: DEMO · LIVE SYNC, account balance/equity, open positions and recent completed-deal statistics.
- If the PC sleeps, closes MT5 or loses internet, the phone shows the last snapshot as stale. Public market analysis can continue separately.
- The bridge rejects snapshots unless account_type is DEMO.

## Troubleshooting
- WebRequest error 401: InpBridgeSecret does not match the Worker PFLS_BRIDGE_SECRET.
- WebRequest error -1: add the Worker base URL to MT5 WebRequest allow-list; check internet/Windows firewall.
- HTTP 401 in the app: check PFLS_MOBILE_READ_TOKEN in Cloudflare and the token saved in the app.
- "No MT5 snapshot": confirm the EA is attached to a chart, MT5 is online, and Experts tab shows HTTP 200.
