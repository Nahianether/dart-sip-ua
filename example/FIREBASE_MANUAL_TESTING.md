# 🧪 Manual VoIP Push Testing with Firebase Console

## 🎯 Test iOS CallKit Without Server Integration

Since your VoIP server doesn't support push notifications yet, you can manually test the iOS CallKit functionality by sending push notifications directly from Firebase Console.

---

## 📱 **Step 1: Get Your Device Token**

1. **Install the app on your iOS device:**
   ```bash
   flutter build ios --debug
   # Install on physical iOS device via Xcode or iTunes
   ```

2. **Launch the app and check the logs:**
   - Open the app on your iOS device
   - The iOS VoIP service will automatically get the push token
   - Check the debug console for a log like:
   ```
   📱 iOS VoIP: Got APNS token: ABC123DEF456...
   ```

3. **Copy the full push token** from the logs (you'll need this for Firebase Console)

---

## 🔥 **Step 2: Send Manual Push from Firebase Console**

### **A. Go to Firebase Console:**
1. Visit [Firebase Console](https://console.firebase.google.com)
2. Select your project: `sip-phone-voip`
3. Go to **Cloud Messaging** in the left sidebar
4. Click **"Send your first message"**

### **B. Configure the Push Message:**

**Message Title:** `Incoming Call`
**Message Text:** `Call from Test User`

**Target:** 
- Select **"Single device"**
- Paste your iOS device token

**Additional Options (Advanced):**
```json
{
  "data": {
    "call_id": "test_call_123",
    "caller": "Test Caller",
    "caller_number": "+1234567890",
    "sip_user": "564612",
    "voip": "true"
  }
}
```

**iOS Specific Settings:**
- **Content Available:** `true` 
- **Priority:** `high`
- **Sound:** `default`

### **C. Send the Push:**
Click **"Send message"**

---

## 📞 **Step 3: What Should Happen**

When you send the push notification:

1. **📱 Your iOS device will receive the push** (even if app is closed)
2. **🔔 CallKit interface will appear** showing "Incoming Call from Test Caller"
3. **✅ You can Accept/Decline** using the native iOS call interface
4. **🚀 App will open** and show the call screen

**Expected Console Logs:**
```
📱 iOS VoIP: Background push received: {call_id: test_call_123, caller: Test Caller...}
📞 iOS VoIP: Processing incoming VoIP push...
📞 iOS VoIP: Incoming call from Test Caller (+1234567890), ID: test_call_123
📞 iOS VoIP: Showing CallKit incoming call...
✅ iOS VoIP: CallKit incoming call displayed
🚀 iOS VoIP: Waking up SIP connection...
```

---

## 🧪 **Step 4: Advanced Testing**

### **Test Different Scenarios:**

#### **Test 1: App Closed**
1. Close the app completely (swipe up and remove from recent apps)
2. Send push notification from Firebase Console
3. **Should show CallKit interface immediately** ✅

#### **Test 2: App in Background**
1. Open app, then go to home screen (app in background)
2. Send push notification
3. **Should show CallKit interface** ✅

#### **Test 3: App in Foreground**
1. Keep app open and active
2. Send push notification  
3. **Should show CallKit interface** ✅

#### **Test 4: Different Caller Names**
Try different `caller` values in the push data:
- `"caller": "John Doe"`
- `"caller": "Office"`
- `"caller": "Unknown"`

---

## 🔧 **Firebase Console Push JSON Template**

Use this exact JSON in Firebase Console **"Additional options" → "Custom data":**

```json
{
  "call_id": "manual_test_001",
  "caller": "Firebase Test Call",
  "caller_number": "+1-555-TEST",
  "sip_user": "564612",
  "voip": "true",
  "test_mode": "true"
}
```

**iOS APNs Headers (Advanced settings):**
```json
{
  "apns-priority": "10",
  "apns-push-type": "alert"
}
```

---

## 🎯 **Expected Results**

### **✅ Success Indicators:**
- CallKit interface appears with caller name
- Accept/Decline buttons work
- App opens when call is accepted
- Native iOS call experience

### **❌ Troubleshooting:**
- **No CallKit interface:** Check device token is correct
- **App doesn't wake up:** Ensure app has proper entitlements
- **No push received:** Check Firebase project configuration

---

## 📋 **Quick Test Checklist**

- [ ] App installed on physical iOS device
- [ ] Firebase project configured with correct bundle ID
- [ ] Device token copied from app logs
- [ ] Push notification sent from Firebase Console
- [ ] CallKit interface appears
- [ ] Accept/Decline buttons work
- [ ] App navigation works

---

## 🚀 **This Tests Your Complete VoIP Flow!**

Even without server-side integration, this manual testing proves:
1. **Firebase push notifications work** ✅
2. **CallKit integration works** ✅  
3. **VoIP wake-up works** ✅
4. **App navigation works** ✅

Once this manual test succeeds, you'll know your iOS VoIP implementation is perfect! Later, when your server supports push notifications, it will work exactly the same way - just automatically triggered by incoming calls instead of manual Firebase Console pushes.

---

**Ready to test? Install the app and let's see that CallKit interface! 📞✨**