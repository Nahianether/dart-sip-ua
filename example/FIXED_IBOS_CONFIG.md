# 🎯 FIXED: iBOS SIP Registration Configuration

## ✅ What Was Fixed

The registration failure with the "invalid" domain was caused by missing configuration properties:

1. **Missing Registrar Server** - Added `settings.registrarServer = domain`
2. **Missing Realm** - Added `settings.realm = domain` 
3. **Proper Domain Parsing** - Fixed SIP URI parsing to extract correct domain

## 📱 Exact Configuration Steps

### 1. Open App Settings
- Launch the app
- Tap menu (3 dots) → "Account"

### 2. Enter These EXACT Values:

```
Transport Type: WebSocket (WS) ✓
WebSocket URL: wss://sip.ibos.io:8089/ws
SIP URI: 564613@sip.ibos.io
Authorization User: 564613
Password: iBOS123
Display Name: Your Name
```

### 3. Important Notes:
- ✅ **SIP URI**: Enter `564613@sip.ibos.io` (NO "sip:" prefix)
- ✅ **WebSocket URL**: Must be exactly `wss://sip.ibos.io:8089/ws`
- ✅ **Transport**: Select "WebSocket (WS)" - the app auto-detects WSS from URL
- ✅ **Authorization User**: Must be `564613` (matches username in SIP URI)

## 🔍 Debug Output You Should See

When you tap "Register", check the console for:

```
I/flutter: SIP Registration Settings:
I/flutter:   URI: sip:564613@sip.ibos.io
I/flutter:   WebSocket URL: wss://sip.ibos.io:8089/ws
I/flutter:   Host: sip.ibos.io
I/flutter:   Registrar Server: sip.ibos.io
I/flutter:   Realm: sip.ibos.io
I/flutter:   Auth User: 564613
I/flutter:   Display Name: Your Name
I/flutter:   Transport: TransportType.WS
```

## 🚫 What Was Wrong Before

The original error showed:
```
<sip:92pn524a@uxrgpjrvy2zd.invalid;transport=wss>
```

This happened because:
- No registrar server was set
- No realm was configured
- The library generated a random invalid domain

## ✅ What Should Happen Now

The contact URI should now show:
```
<sip:564613@sip.ibos.io;transport=wss>
```

## 🎯 Registration Status

- **Before**: `REGISTRATION_FAILED`
- **After**: `REGISTERED` ✅

## 🔧 If Still Having Issues

1. **Clear App Data**: Completely restart the app
2. **Check Network**: Ensure `sip.ibos.io:8089` is accessible
3. **Verify Credentials**: Double-check username `564613` and password `iBOS123`
4. **Test WebSocket**: Try connecting to `wss://sip.ibos.io:8089/ws` in browser dev tools

## 📞 After Registration Success

Once registered, you can:
- **Make calls** to other extensions (e.g., `564614`)
- **Receive calls** on your extension `564613`
- **See registration status** as "REGISTERED" on main screen

Your iBOS SIP registration should now work exactly like the web client!