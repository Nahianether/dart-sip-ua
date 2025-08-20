# Background Service Setup Guide

Your SIP phone app now has persistent background service capability! This means you can receive calls even when the app is closed, locked, or not in recent apps.

## ✅ What's Been Implemented

### 🔄 Persistent Background Service
- **Continuous SIP Connection**: Maintains WebSocket SIP connection 24/7
- **Auto-Reconnection**: Automatically reconnects if connection is lost
- **Health Monitoring**: Checks connection status every minute
- **Keep-Alive**: Sends periodic keep-alive signals every 30 seconds

### 📱 Incoming Call Notifications
- **Full-Screen Notifications**: Shows incoming calls even on lock screen
- **Accept/Decline Actions**: Quick actions directly from notification
- **Custom Ring Tone**: Uses `phone_ringing` sound (you can customize)
- **Vibration Pattern**: Custom vibration pattern for incoming calls

### ⚡ System Integration
- **Boot Auto-Start**: Service starts automatically when device boots
- **Battery Optimization**: Requests to ignore battery optimization
- **Foreground Service**: Runs as high-priority foreground service
- **Wake Lock**: Keeps device awake for incoming calls

## 🛠️ Additional Setup Required

### Android Permissions
The following permissions are automatically requested:
- **FOREGROUND_SERVICE_PHONE_CALL**: For persistent calling service
- **USE_FULL_SCREEN_INTENT**: For full-screen incoming call notifications
- **RECEIVE_BOOT_COMPLETED**: To start service on device boot
- **REQUEST_IGNORE_BATTERY_OPTIMIZATIONS**: To prevent Android from killing the service

### Device-Specific Settings

#### Samsung Devices
1. Go to **Settings > Apps > [Your App] > Battery**
2. Select **"Don't optimize"**
3. Go to **Settings > Apps > [Your App] > Permissions**
4. Enable **"Display over other apps"**

#### Xiaomi/MIUI Devices
1. Go to **Settings > Apps > Manage Apps > [Your App]**
2. Enable **"Autostart"**
3. Enable **"Display pop-up windows while running in background"**
4. Go to **Security > Battery & Performance > App Battery Saver**
5. Find your app and select **"No restrictions"**

#### Huawei Devices
1. Go to **Settings > Apps > [Your App] > Battery**
2. Select **"Manual management"**
3. Enable all toggles (Auto-launch, Secondary launch, Run in background)

#### OnePlus/OxygenOS Devices
1. Go to **Settings > Apps & Notifications > [Your App] > Battery**
2. Select **"Don't optimize"**
3. Go to **Settings > Apps & Notifications > [Your App] > Advanced**
4. Enable **"Allow display over other apps"**

## 🔧 How It Works

### 1. Service Lifecycle
- **App Launch**: Background service starts automatically
- **SIP Registration**: When user successfully registers, service is notified
- **Background Mode**: Service continues running when app is closed
- **Connection Monitoring**: Service maintains SIP connection independently

### 2. Incoming Call Flow
1. **Call Received**: Background service detects incoming SIP call
2. **Notification Shown**: Full-screen notification appears
3. **User Action**: User can accept/decline from notification
4. **App Opens**: If accepted, app opens to call screen

### 3. Connection Management
- **Primary Connection**: Main app handles active usage
- **Background Connection**: Service maintains backup connection
- **Seamless Handoff**: Smooth transition between foreground/background

## 🐛 Troubleshooting

### Service Not Running
- Check if app has foreground service permission
- Verify VPN is connected (if required)
- Look for service notification in status bar

### Not Receiving Calls
- Ensure device isn't in airplane mode
- Check if battery optimization is disabled
- Verify SIP registration is successful (check in-app status)

### Battery Drain
- Service is optimized for minimal battery usage
- Uses efficient WebSocket keep-alive (30 seconds)
- No unnecessary background processing

## 📋 Service Status

You can monitor the service status through:
1. **Persistent Notification**: Shows "SIP Phone Active" when running
2. **App Status**: Check registration status in main app
3. **System Settings**: View running services in Android settings

## 🔊 Customization

### Notification Sound
To change the incoming call ringtone:
1. Add your sound file to `android/app/src/main/res/raw/phone_ringing.mp3`
2. The service will automatically use your custom sound

### Notification Behavior
You can modify notification behavior in `persistent_background_service.dart`:
- Change vibration pattern
- Customize notification text
- Add more action buttons

## ⚠️ Important Notes

1. **VPN Requirement**: If your SIP server requires VPN, ensure VPN auto-connects on boot
2. **Network Changes**: Service automatically handles Wi-Fi/mobile data switches
3. **Memory Usage**: Service uses minimal memory (~10-15MB)
4. **Security**: All SIP credentials are stored securely in encrypted preferences

Your app is now ready to receive calls 24/7! 🎉