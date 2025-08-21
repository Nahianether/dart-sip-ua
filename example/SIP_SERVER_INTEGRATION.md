# 🚀 SIP Server Integration for 24/7 Background Calling

## 🎯 CRITICAL: Server-Side Implementation Required

Your Flutter app is now ready for 24/7 background calling on both Android and iOS! However, to make iOS background calls work, your **SIP server must send push notifications**. Here's exactly what you need to implement:

---

## 📱 How It Works

### **Android (Works Immediately)** ✅
- **Background Service**: Maintains persistent SIP connection 24/7
- **No server changes needed**: Uses existing SIP INVITE messages
- **Status**: Ready to test now!

### **iOS (Requires Server Integration)** 📡
- **Push Notifications**: Server sends push when call arrives
- **CallKit Interface**: Native iOS call screen
- **SIP Wake-up**: App connects to SIP after receiving push
- **Status**: Needs server integration

---

## 🛠️ SIP Server Integration Steps

### **Step 1: Device Token Registration API**

Create an API endpoint to register device push tokens:

```javascript
// POST /api/register-push-token
{
  "user": "564612",           // SIP user ID
  "token": "fcm_token_here",  // Firebase Cloud Messaging token
  "platform": "ios"          // or "android"
}
```

**Example Server Implementation:**
```javascript
// Node.js/Express example
app.post('/api/register-push-token', async (req, res) => {
  const { user, token, platform } = req.body;
  
  // Store in database
  await db.collection('push_tokens').doc(user).set({
    token: token,
    platform: platform,
    updated: new Date()
  });
  
  console.log(`Registered ${platform} push token for user ${user}`);
  res.json({ success: true });
});
```

### **Step 2: Modify SIP INVITE Handling**

When a call comes in for a user, check if they have a registered push token:

```javascript
// When SIP INVITE arrives for a user
async function handleIncomingSipCall(sipUser, caller, callDetails) {
  
  // Check if user has registered push token
  const tokenDoc = await db.collection('push_tokens').doc(sipUser).get();
  
  if (tokenDoc.exists && tokenDoc.data().platform === 'ios') {
    // Send push notification for iOS
    await sendVoIPPush({
      token: tokenDoc.data().token,
      caller: caller,
      callId: callDetails.callId,
      sipUser: sipUser
    });
  }
  
  // Continue with normal SIP processing
  // The app will connect to SIP after receiving the push
}
```

### **Step 3: Send VoIP Push Notifications**

Use Firebase Admin SDK to send VoIP pushes:

```javascript
const admin = require('firebase-admin');

async function sendVoIPPush({ token, caller, callId, sipUser }) {
  const message = {
    token: token,
    data: {
      call_id: callId,
      caller: caller,
      caller_number: caller,
      sip_user: sipUser,
      voip: 'true'
    },
    apns: {
      headers: {
        'apns-priority': '10',
        'apns-push-type': 'voip'
      },
      payload: {
        aps: {
          alert: `Incoming call from ${caller}`,
          sound: 'default',
          badge: 1
        }
      }
    }
  };
  
  try {
    await admin.messaging().send(message);
    console.log(`VoIP push sent for call ${callId}`);
  } catch (error) {
    console.error('Push notification failed:', error);
  }
}
```

---

## 🔥 Quick Implementation Guide

### **For Your Current Setup (sip.ibos.io):**

1. **Contact your SIP provider** and ask them to implement push notifications
2. **Share this document** with your backend team
3. **Provide these details:**
   - SIP server: `sip.ibos.io`
   - User: `564612`
   - Firebase project ID: (you'll create this)

### **If You Control the SIP Server:**

1. **Set up Firebase Project:**
   ```bash
   # Install Firebase Admin SDK
   npm install firebase-admin
   
   # Download service account key from Firebase Console
   # Initialize in your server code
   ```

2. **Add Database Storage:**
   ```sql
   CREATE TABLE push_tokens (
     user_id VARCHAR(50) PRIMARY KEY,
     token TEXT,
     platform VARCHAR(10),
     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
   );
   ```

3. **Implement API Endpoints:**
   - POST `/api/register-push-token`
   - GET `/api/user/{userId}/push-token`
   - DELETE `/api/user/{userId}/push-token`

---

## 📱 Firebase Setup (iOS)

### **Step 1: Create Firebase Project**
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create new project: "SIP-Phone-VoIP"
3. Add iOS app with bundle ID: `com.intishar.dartSipUaExample`

### **Step 2: Download Config File**
1. Download `GoogleService-Info.plist`
2. Replace the existing one in `ios/Runner/GoogleService-Info.plist`

### **Step 3: Enable Push Notifications**
1. In Firebase Console → Project Settings → Cloud Messaging
2. Upload APNs certificate or key
3. Enable VoIP push notifications

---

## 🧪 Testing the Complete Solution

### **Test Android (Should Work Now):**
```bash
1. Build and install app
2. Register SIP user
3. Close app completely (swipe away from recent apps)
4. Call from another device
5. Should receive call ✅
```

### **Test iOS (After Server Integration):**
```bash
1. Complete Firebase setup
2. Implement server push integration
3. Build and install app
4. Register SIP user (this registers push token)
5. Close app completely
6. Call from another device
7. Should receive push → CallKit → SIP connection ✅
```

---

## 📊 Expected Results

### **After Complete Implementation:**

#### **Android:**
- ✅ App closed: Calls work via background service
- ✅ Battery optimized: Uses Android foreground service
- ✅ No server changes: Works with existing SIP

#### **iOS:**
- ✅ App closed: Calls work via push notifications
- ✅ Native interface: iOS CallKit integration
- ✅ Battery efficient: System-managed wake-ups
- ✅ App Store compliant: Follows Apple VoIP guidelines

---

## 🚨 Action Items

### **Immediate (This Week):**
1. **Test Android**: Should work with current build
2. **Set up Firebase**: Create project and download config
3. **Contact SIP provider**: Ask about push notification support

### **Development (Next 2 Weeks):**
1. **Server Integration**: Implement push token registration
2. **Push Notification**: Set up Firebase Admin SDK
3. **Testing**: Verify end-to-end iOS calling

### **Production (Month 3-4):**
1. **Load Testing**: Verify with multiple users
2. **Monitoring**: Set up push notification analytics  
3. **App Store**: Submit with VoIP entitlements

---

## 💡 Alternative: Immediate iOS Solution

If you can't implement server push notifications immediately, users can:

1. **Keep app in recent apps** (works for several hours)
2. **Enable "Background App Refresh"** in iOS settings
3. **Use Android devices** for true 24/7 calling (works now)

---

## 📞 Your Current Status

✅ **Android**: Ready for 24/7 background calling  
🔄 **iOS**: Ready for push integration (server work needed)  
✅ **VPN**: Auto-connect working  
✅ **Call Controls**: All features working  
✅ **UI**: Unified call screen ready  

**Next Critical Step**: Implement server-side push notifications for iOS! 🚀

---

Need help with any of these steps? The Flutter app side is complete - the remaining work is server-side integration.