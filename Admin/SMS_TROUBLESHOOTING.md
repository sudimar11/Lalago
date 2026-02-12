# SMS Troubleshooting Guide

## Overview
This guide helps you troubleshoot SMS sending issues in the Grading System app.

## Common Issues and Solutions

### 1. SMS Permissions Not Granted

**Symptoms:**
- App shows "SMS Permissions: Denied"
- Send button is disabled
- Error message: "SMS permission is required"

**Solutions:**
1. **Grant Permissions in App:**
   - Tap the "Grant" button in the SMS Sender screen
   - Follow the system permission dialog

2. **Manual Permission Grant:**
   - Go to Settings > Apps > Grading System > Permissions
   - Enable "SMS" permission

3. **For Android 6.0+:**
   - Settings > Apps > Grading System > Permissions > SMS
   - Toggle "Allow" to ON

### 2. SMS Not Sending

**Symptoms:**
- SMS appears to send but recipient doesn't receive it
- Error message: "Failed to send SMS"

**Solutions:**
1. **Check Device SMS Support:**
   - Ensure device has SMS capability
   - Verify SIM card is properly inserted
   - Check if device has cellular signal

2. **Test with Different Methods:**
   - The app uses multiple SMS sending methods
   - If one fails, it automatically tries another
   - Check the console logs for method used

3. **Phone Number Format:**
   - Ensure phone numbers are in correct format
   - Philippine numbers: 09123456789 or +639123456789
   - International format is automatically applied

### 3. Bulk SMS Issues

**Symptoms:**
- Bulk SMS stops halfway
- Some messages fail to send
- Campaign gets stuck

**Solutions:**
1. **Check Network Connection:**
   - Ensure stable internet connection
   - Bulk SMS requires Firebase connectivity

2. **Rate Limiting:**
   - App includes 1-second delays between messages
   - Some carriers may have additional rate limits
   - Try sending smaller batches

3. **Campaign Monitoring:**
   - Check Firebase Firestore for SMS logs
   - Monitor campaign status in real-time
   - Cancel and restart if needed

### 4. App Crashes When Sending SMS

**Symptoms:**
- App crashes immediately when sending SMS
- Force close error

**Solutions:**
1. **Update Dependencies:**
   ```bash
   flutter pub get
   flutter clean
   flutter pub get
   ```

2. **Check Android Manifest:**
   - Ensure SMS permissions are properly declared
   - Verify minimum SDK version (24+)

3. **Device Compatibility:**
   - Test on different Android versions
   - Some older devices may have compatibility issues

## Testing SMS Functionality

### 1. Basic Test
1. Open the SMS Sender screen
2. Tap the refresh icon (test button)
3. Check the test results:
   - Permissions status
   - Phone formatting
   - Available SIM cards

### 2. Single SMS Test
1. Enter a valid phone number
2. Enter a test message
3. Tap "Send SMS"
4. Check for success/error messages

### 3. Grade Notification Test
1. Go to the Class List page
2. Select a class list
3. Tap the message icon next to a student
4. Verify SMS is sent with grade information

## Debug Information

### Console Logs
The app provides detailed console logs for SMS operations:
```
=== SMS SENDING DEBUG INFO ===
Original Phone: 09123456789
Formatted Phone: +639123456789
Message: Test message
Message Length: 12
SIM Slot: 0
Has Permission: true
==============================
```

### Firebase Logs
SMS operations are logged to Firestore:
- Collection: `sms_logs`
- Fields: phoneNumber, message, success, error, method, timestamp

### Error Codes
- `PERMISSION_DENIED`: SMS permission not granted
- `INVALID_PHONE`: Phone number format is invalid
- `EMPTY_MESSAGE`: Message is empty
- `TELEPHONY_FAILED`: Primary SMS method failed
- `URL_LAUNCHER_FAILED`: Fallback SMS method failed
- `ALL_METHODS_FAILED`: Both SMS methods failed

## Device-Specific Issues

### Samsung Devices
- May require additional permission settings
- Check "Auto-start" permissions
- Enable "Background app refresh"

### Huawei Devices
- May need to add app to "Protected apps"
- Check "Battery optimization" settings
- Enable "Auto-launch" permissions

### Xiaomi Devices
- Check "Autostart" permissions
- Enable "Background app refresh"
- Add to "Battery saver" exceptions

## Performance Optimization

### For Large SMS Campaigns
1. **Batch Size:**
   - Send in smaller batches (50-100 messages)
   - Monitor success rates

2. **Timing:**
   - Avoid peak hours
   - Consider carrier rate limits

3. **Monitoring:**
   - Use Firebase logs to track progress
   - Monitor device battery and network

## Support

If issues persist:
1. Check the console logs for detailed error messages
2. Verify device compatibility
3. Test on different devices/Android versions
4. Contact support with error logs and device information

## Technical Details

### SMS Methods Used
1. **Primary Method:** Telephony plugin
   - Direct SMS sending
   - Requires SMS permissions

2. **Fallback Method:** URL Launcher
   - Opens default SMS app
   - User must manually send

### Permission Requirements
- `android.permission.SEND_SMS`
- `android.permission.READ_PHONE_STATE`
- `android.permission.RECEIVE_SMS`
- `android.permission.READ_SMS`

### Minimum Requirements
- Android API Level 24+
- Flutter 3.3.0+
- SMS-capable device
- Active SIM card
