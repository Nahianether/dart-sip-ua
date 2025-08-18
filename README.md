# Dart SIP UA

A comprehensive SIP (Session Initiation Protocol) User Agent library for Flutter/Dart applications. This library enables voice and video calling capabilities through WebRTC, supporting all major SIP servers and platforms.

## 🚀 Features

### 📞 VoIP Capabilities
- **Voice Calls** - High-quality audio calls using WebRTC
- **Video Calls** - Full-featured video calling with camera support
- **Call Management** - Answer, hold, resume, transfer, and hangup calls
- **Call States** - Real-time call state tracking and events
- **Multiple Calls** - Support for multiple concurrent calls
- **Call Recording** - Built-in call recording capabilities

### 🔧 SIP Protocol Support
- **SIP over WebSocket** - Modern WebSocket-based SIP communication
- **SIP over TCP** - Traditional TCP-based SIP signaling
- **Authentication** - Digest authentication with SIP servers
- **Registration** - Automatic SIP server registration and re-registration
- **Presence** - User presence and availability status
- **Instant Messaging** - SIP-based text messaging

### 🌐 Server Compatibility
- **Asterisk** - Full compatibility with Asterisk PBX
- **FreeSWITCH** - Complete FreeSWITCH integration
- **OpenSIPS** - OpenSIPS server support
- **Kamailio** - Kamailio SIP server integration
- **3CX** - 3CX phone system compatibility
- **Generic SIP** - Works with any standard SIP server

### 📱 Platform Support
- ✅ **iOS** - Native iOS app support
- ✅ **Android** - Native Android app support
- ✅ **Web** - Browser-based web applications
- ✅ **macOS** - Native macOS desktop apps
- ✅ **Windows** - Native Windows desktop apps
- ✅ **Linux** - Native Linux desktop apps
- ✅ **Fuchsia** - Google's Fuchsia OS support

### 🎛️ Advanced Features
- **DTMF Support** - RFC2833 and INFO method DTMF
- **Codec Support** - Multiple audio/video codecs
- **NAT Traversal** - ICE, STUN, and TURN support
- **Secure Communication** - DTLS and SRTP encryption
- **Session Timers** - Automatic session keepalive
- **Call Transfer** - Blind and attended call transfer

## 🛠️ Tech Stack

- **Language:** Dart
- **Framework:** Flutter
- **WebRTC:** flutter-webrtc
- **Protocol:** SIP (Session Initiation Protocol)
- **Transport:** WebSocket (WSS), TCP
- **Media:** WebRTC (RTP/SRTP)
- **Authentication:** SIP Digest Authentication
- **Based on:** JsSIP (JavaScript SIP library)

## 📋 Prerequisites

- Flutter SDK (>=2.0.0)
- Dart SDK (>=2.12.0)
- A SIP server (Asterisk, FreeSWITCH, etc.)
- Valid SIP account credentials

## 🚀 Installation

### 1. Add to pubspec.yaml

```yaml
dependencies:
  sip_ua: ^0.5.8
  flutter_webrtc: ^0.9.0
```

### 2. Install packages

```bash
flutter pub get
```

### 3. Platform-specific setup

#### Android Proguard Rules
Add to `android/app/proguard-rules.pro`:

```proguard
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.cloudwebrtc.webrtc.** {*;}
-keep class org.webrtc.** {*;}
```

#### iOS Permissions
Add to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for video calls</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for voice calls</string>
```

## 📖 Usage

### Basic SIP Registration

```dart
import 'package:sip_ua/sip_ua.dart';

class SipService {
  SIPUAHelper? _helper;
  
  void initSip() {
    _helper = SIPUAHelper();
    _helper!.addSipUaHelperListener(this);
    
    // Configure SIP settings
    UaSettings settings = UaSettings();
    settings.webSocketUrl = 'wss://your-sip-server.com:7443/ws';
    settings.uri = 'sip:username@your-sip-server.com';
    settings.authorizationUser = 'username';
    settings.password = 'password';
    settings.displayName = 'Your Name';
    settings.dtmfMode = DtmfMode.RFC2833;
    
    // Start SIP UA
    _helper!.start(settings);
  }
}
```

### Making a Call

```dart
void makeCall(String target) {
  _helper?.call(target, voiceonly: false); // false for video call
}
```

### Handling Incoming Calls

```dart
class MyApp extends StatefulWidget implements SipUaHelperListener {
  @override
  void callStateChanged(Call call, CallState state) {
    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
        print('Call initiated');
        break;
      case CallStateEnum.RINGING:
        print('Call ringing');
        break;
      case CallStateEnum.ACCEPTED:
        print('Call accepted');
        break;
      case CallStateEnum.CONFIRMED:
        print('Call confirmed');
        break;
      case CallStateEnum.ENDED:
        print('Call ended');
        break;
      case CallStateEnum.FAILED:
        print('Call failed: ${state.cause}');
        break;
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    print('New SIP message: ${msg.message}');
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    print('Registration state: ${state.state}');
  }

  @override
  void transportStateChanged(TransportState state) {
    print('Transport state: ${state.state}');
  }
}
```

### Answer/Hangup Calls

```dart
// Answer incoming call
void answerCall(Call call) {
  call.answer(_helper!.buildCallOptions());
}

// Hangup call
void hangupCall(Call call) {
  call.hangup();
}

// Hold/Resume call
void holdCall(Call call) {
  call.hold();
}

void resumeCall(Call call) {
  call.unhold();
}
```

### Send DTMF

```dart
void sendDtmf(Call call, String tone) {
  call.sendDTMF(tone);
}
```

## 🔧 Configuration Options

### UaSettings Properties

```dart
UaSettings settings = UaSettings();

// Server Configuration
settings.webSocketUrl = 'wss://server.com:7443/ws';
settings.uri = 'sip:user@server.com';
settings.authorizationUser = 'username';
settings.password = 'password';
settings.displayName = 'Display Name';

// Transport Settings
settings.transportType = TransportType.WS;
settings.webSocketSettings.extraHeaders = {
  'Origin': 'https://your-domain.com',
  'Host': 'your-sip-server.com'
};

// Call Settings
settings.dtmfMode = DtmfMode.RFC2833;
settings.sessionTimers = true;
settings.iceGatheringTimeout = 3000;

// Security Settings
settings.allowBadCertificate = false;
settings.register = true;
```

## 🎨 Supported Codecs

### Audio Codecs
- **Opus** (payload 111, 48kHz, 2 channels)
- **G.722** (payload 9, 8kHz, 1 channel)
- **PCMU** (payload 0, 8kHz, 1 channel)
- **PCMA** (payload 8, 8kHz, 1 channel)
- **iLBC** (payload 102, 8kHz, 1 channel)
- **CN** (payload 13, 8kHz, 1 channel)
- **telephone-event** (payload 110, DTMF)

### Video Codecs
- **H.264** (various profiles)
- **VP8**
- **VP9**

## 🔒 Security Features

### Encryption
- **DTLS** - Secure transport for WebRTC
- **SRTP** - Secure Real-time Transport Protocol
- **WSS** - WebSocket Secure for SIP signaling
- **TLS** - Transport Layer Security

### Authentication
- **SIP Digest Authentication** - RFC 3261 compliant
- **Token-based Authentication** - JWT support
- **Certificate Validation** - TLS certificate verification

## 🐛 Troubleshooting

### Common Issues

#### WebRTC Error: No DTLS Fingerprint
```
Error: Failed to set remote offer sdp: Called with SDP without DTLS fingerprint
```
**Solution:** Configure your SIP server to include DTLS fingerprint in SDP

#### Codec Mismatch
```
Error: SIP/2.0 488 Not Acceptable Here
```
**Solution:** Ensure your SIP server supports WebRTC codecs listed above

#### Registration Failed
```
Error: Registration failed with 401 Unauthorized
```
**Solution:** Check username, password, and authentication settings

## 📱 Example Implementation

Check out the complete example in the `/example` directory:

```bash
git clone https://github.com/Nahianether/dart-sip-ua.git
cd dart-sip-ua/example
flutter pub get
flutter run
```

## 🧪 Testing

### SIP Server Setup
For testing, you can use:
- **Asterisk Docker:** `docker run -d --name asterisk -p 5060:5060 asterisk`
- **FreeSWITCH:** Available in Docker Hub
- **Online SIP Servers:** Various providers offer test accounts

### Test with JsSIP
You can test interoperability with: https://tryit.jssip.net/

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Setup
```bash
# Clone the repository
git clone https://github.com/Nahianether/dart-sip-ua.git
cd dart-sip-ua

# Install dependencies
flutter pub get

# Run tests
flutter test

# Run example
cd example
flutter run
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👨‍💻 Author

**Nahian Ether**
- **Company:** AKIJ iBOS Limited
- **Location:** Dhaka, Bangladesh
- **GitHub:** [@Nahianether](https://github.com/Nahianether)
- **Portfolio:** [portfolio.int8bit.xyz](https://portfolio.int8bit.xyz/)
- **LinkedIn:** [nahinxp21](https://www.linkedin.com/in/nahinxp21/)

## 🙏 Acknowledgments

- **JsSIP Team** - Original JavaScript SIP library
- **Flutter WebRTC Team** - WebRTC implementation for Flutter
- **SureVoIP** - Sponsor of the first version
- **CloudWebRTC** - Original maintainer
- **Community Contributors** - All the developers who contributed

## 🔗 Related Projects

- **flutter-webrtc** - WebRTC plugin for Flutter
- **JsSIP** - JavaScript SIP library (original inspiration)
- **SIP.js** - Another JavaScript SIP library
- **PJSIP** - Popular SIP stack in C

---

*Build powerful VoIP applications with Flutter using this comprehensive SIP UA library. Perfect for creating calling apps, PBX interfaces, and real-time communication solutions!*
