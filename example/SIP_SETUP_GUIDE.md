# SIP Mobile Application Setup Guide

## ✅ Fixed Issues

1. **Android Build Error**: Fixed Kotlin JVM target compatibility issue
2. **Duplicate MainActivity**: Removed duplicate Java MainActivity file
3. **WebSocket Configuration**: Properly implemented WebSocket URL handling
4. **SIP Registration**: Fixed registration flow with proper parameter passing

## 🚀 How to Run

### Android
```bash
flutter build apk --debug
flutter install
```

### iOS
```bash
flutter build ios --debug --no-codesign
```

### Web
```bash
flutter run -d chrome
```

## 📱 How to Use the App

### 1. Configure SIP Account
- Open the app and tap the menu (three dots) → "Account"
- Select **WebSocket (WS)** transport type
- Enter your WebSocket URL: `wss://your-sip-server.com:port/ws`
- Enter your SIP URI: `sip:username@your-sip-server.com`
- Enter Authorization User: `username`
- Enter Password: `your-password`
- Enter Display Name: `Your Name`
- Tap "Register"

### 2. Make Calls
- On the main screen, enter the destination SIP URI or phone number
- Tap the **video call** button (camera icon) for video calls
- Tap the **voice call** button (phone icon) for voice calls
- Use the keypad to enter numbers or SIP URIs

### 3. Receive Calls
- When someone calls you, the app will automatically show the call screen
- Tap "Accept" to answer the call
- Tap "Hangup" to reject the call

### 4. During Calls
- **Mute/Unmute**: Tap the microphone icon
- **Hold/Unhold**: Tap the pause/play icon
- **Switch Camera**: Tap the camera switch icon (video calls)
- **Speaker On/Off**: Tap the speaker icon (voice calls)
- **DTMF Keypad**: Tap the keypad icon to send DTMF tones
- **Transfer**: Tap the transfer icon to transfer the call
- **Hangup**: Tap the red phone icon to end the call

## 🔧 Configuration Examples

### Popular SIP Servers

#### FreeSWITCH
```
WebSocket URL: wss://your-freeswitch-server.com:7443/ws
SIP URI: sip:1000@your-freeswitch-server.com
Authorization User: 1000
Password: your-password
```

#### Asterisk
```
WebSocket URL: wss://your-asterisk-server.com:8089/ws
SIP URI: sip:1000@your-asterisk-server.com
Authorization User: 1000
Password: your-password
```

#### OpenSIPS
```
WebSocket URL: wss://your-opensips-server.com:443/ws
SIP URI: sip:user@your-opensips-server.com
Authorization User: user
Password: your-password
```

## 📋 Features

✅ **WebSocket SIP Connection**
✅ **Voice Calls**
✅ **Video Calls**
✅ **Call Hold/Resume**
✅ **Mute/Unmute**
✅ **DTMF Support**
✅ **Call Transfer**
✅ **Speaker Phone**
✅ **Camera Switching**
✅ **Incoming Call Handling**
✅ **Dark/Light Theme**

## 🛠️ Technical Details

- **Flutter SDK**: Compatible with latest Flutter versions
- **SIP Stack**: Based on dart-sip-ua library
- **WebRTC**: Uses flutter_webrtc for media handling
- **Platforms**: Android, iOS, Web, Desktop
- **Transport**: WebSocket (WSS) and TCP support

## 📱 Permissions

The app requires the following permissions:
- **Microphone**: For voice calls
- **Camera**: For video calls
- **Internet**: For SIP connection

## 🔍 Troubleshooting

1. **Registration fails**: Check your WebSocket URL and credentials
2. **No audio**: Check microphone permissions
3. **No video**: Check camera permissions
4. **Connection issues**: Verify firewall settings and network connectivity

## 🎯 Ready for Production

The app is now fully functional and ready for:
- Testing with real SIP servers
- Deployment to app stores
- Integration with your existing SIP infrastructure
- Customization for your specific needs

Your SIP mobile application is now complete and ready to use!