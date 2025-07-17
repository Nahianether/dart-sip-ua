# iBOS SIP Server Configuration Guide

## 🔧 Fixed Registration Issues

I've fixed the registration problems by:

1. **Proper SIP URI parsing** - Correctly extracts username and domain
2. **WebSocket URL handling** - Uses the exact WebSocket URL provided
3. **Authorization configuration** - Sets the correct username for authentication
4. **Debug logging** - Added logging to help diagnose issues

## 📱 Configuration for iBOS SIP Server

### Step-by-Step Setup:

1. **Open the app** and tap Menu → Account
2. **Select WebSocket (WS)** transport type
3. **Enter the following information exactly**:

#### Configuration Details:
```
WebSocket URL: wss://sip.ibos.io:8089/ws
SIP URI: 564613@sip.ibos.io
Authorization User: 564613
Password: iBOS123
Display Name: Your Name
```

#### Important Notes:
- **SIP URI Format**: Enter `564613@sip.ibos.io` (without "sip:" prefix)
- **WebSocket URL**: Must be exactly `wss://sip.ibos.io:8089/ws`
- **Authorization User**: Must match the username part of SIP URI (`564613`)
- **Transport**: Must be set to **WebSocket (WS)**

## 🔍 Debugging Information

The app now includes debug logging. To view logs:

### In Development:
- Run `flutter logs` in terminal while the app is running
- Check the console output for registration details

### What You'll See:
```
I/flutter: SIP Registration Settings:
I/flutter:   URI: sip:564613@sip.ibos.io
I/flutter:   WebSocket URL: wss://sip.ibos.io:8089/ws
I/flutter:   Host: sip.ibos.io
I/flutter:   Auth User: 564613
I/flutter:   Display Name: Your Name
I/flutter:   Transport: TransportType.WS
```

## 🚨 Common Issues & Solutions

### If Registration Still Fails:

1. **Check Network Connection**
   - Ensure you have internet access
   - Try connecting to `wss://sip.ibos.io:8089/ws` in browser

2. **Verify Credentials**
   - Double-check username: `564613`
   - Double-check password: `iBOS123`
   - Ensure no extra spaces or characters

3. **Server Issues**
   - Check if the iBOS server is running
   - Verify the WebSocket port (8089) is open
   - Test with the web client at https://tryit.jssip.net/

4. **App Issues**
   - Clear app data and re-enter settings
   - Restart the app
   - Check device firewall/security settings

## 🧪 Testing Steps

1. **Enter Configuration**: Use the exact settings above
2. **Tap Register**: Watch for registration status
3. **Check Logs**: Look for debug output in console
4. **Registration Success**: Status should show "REGISTERED"
5. **Make Test Call**: Try calling another extension

## 📞 Making Calls

Once registered, you can:
- **Call Extensions**: Enter `564614` (or other extension)
- **Call Full SIP URI**: Enter `564614@sip.ibos.io`
- **Receive Calls**: Others can call your extension `564613`

## 🎯 Troubleshooting Checklist

- [ ] WebSocket URL: `wss://sip.ibos.io:8089/ws`
- [ ] SIP URI: `564613@sip.ibos.io` (no "sip:" prefix)
- [ ] Authorization User: `564613`
- [ ] Password: `iBOS123`
- [ ] Transport: WebSocket (WS)
- [ ] Network connectivity to sip.ibos.io
- [ ] Port 8089 accessible
- [ ] Server is running and accepting connections

## 🔄 If Still Having Issues

1. **Test with Web Client**: Verify the same credentials work at https://tryit.jssip.net/
2. **Check Server Logs**: Ask server admin to check SIP server logs
3. **Network Analysis**: Use network tools to verify WebSocket connection
4. **Compare Settings**: Ensure app settings exactly match web client settings

Your registration should now work properly with the iBOS SIP server!