# LalaGo Referral Code System

This document describes the implementation of the on-demand referral code generation system for LalaGo.

## Overview

The system automatically generates and assigns unique referral codes to users when they:

1. Log in to the app (any authentication method)
2. Access the referral screen

The system is designed to:

- ✅ Never overwrite existing referral codes
- ✅ Generate unique codes using the existing 6-digit format
- ✅ Be controlled by remote settings for gradual rollout
- ✅ Work seamlessly with existing referral functionality
- ✅ Handle high concurrency and prevent duplicate codes

## Architecture

### Backend Components

1. **Firebase Service** (`services/firebaseService.js`)

   - Initializes Firebase Admin SDK
   - Provides Firestore connection
   - Manages Firebase collections

2. **Referral Service** (`services/referralService.js`)

   - Generates unique referral codes
   - Checks for duplicates across all users
   - Handles remote settings for feature toggle
   - Updates legacy collections for backward compatibility

3. **API Routes** (`routes/referral.js`)
   - `POST /api/v1/referral/login-check` - Called during login
   - `POST /api/v1/referral/ensure-code` - Called from referral screen
   - `GET /api/v1/referral/settings` - Gets current settings
   - `POST /api/v1/referral/batch-ensure` - Bulk operations for migration

### Frontend Components

1. **Backend Service** (`lib/services/BackendService.dart`)

   - Handles API calls to backend
   - Manages error handling and retries

2. **Firebase Helper Updates** (`lib/services/FirebaseHelper.dart`)

   - Integrated backend calls into login flows
   - Added helper function for referral code checks

3. **Referral Screen Updates** (`lib/ui/referral_screen/referral_screen.dart`)
   - Triggers backend check on screen load
   - Shows loading state during backend operations

## Configuration

### Environment Variables

Add to your backend `.env` file:

```bash
# Firebase Configuration
FIREBASE_PROJECT_ID=your-firebase-project-id
FIREBASE_SERVICE_ACCOUNT_PATH=./firebase-service-account.json
# OR use JSON string for cloud deployment
# FIREBASE_SERVICE_ACCOUNT_KEY={"type":"service_account",...}
```

### Remote Settings

The system uses Firebase Firestore settings collection for feature control:

**Collection**: `settings`
**Document**: `referralSettings`

```json
{
  "enableAutoGeneration": true,
  "referralRewardAmount": "20.0",
  "maxReferralReward": "100.0",
  "referralCodeLength": 6,
  "lastUpdated": "2024-01-01T00:00:00Z",
  "description": "Toggle enableAutoGeneration to control rollout"
}
```

## Deployment Steps

### 1. Backend Setup

```bash
# Install dependencies
cd backend
npm install

# Set up environment variables
cp env.example .env
# Edit .env with your Firebase credentials

# Initialize referral settings in Firebase
npm run setup-referral

# Start the server
npm start
```

### 2. Frontend Setup

1. Update `lib/services/BackendService.dart`:

   ```dart
   static const String baseUrl = 'https://your-actual-backend-url.com/api/v1';
   ```

2. Deploy the Flutter app with the updated code

### 3. Testing

1. **Test Login Flow**:

   - Log in with a user who doesn't have a referral code
   - Verify code is generated and assigned
   - Log in again - verify code is not overwritten

2. **Test Referral Screen**:

   - Navigate to referral screen with a user without code
   - Verify loading indicator appears
   - Verify code is generated and displayed

3. **Test Feature Toggle**:
   - Set `enableAutoGeneration: false` in Firebase
   - Verify no codes are generated
   - Set back to `true` - verify generation resumes

## API Documentation

### POST /api/v1/referral/login-check

Called during user login to ensure referral code exists.

**Request**:

```json
{
  "userId": "user123"
}
```

**Response**:

```json
{
  "success": true,
  "message": "Login referral check completed",
  "data": {
    "userId": "user123",
    "referralCode": "123456",
    "enabled": true
  }
}
```

### POST /api/v1/referral/ensure-code

Called from referral screen to ensure code exists.

**Request**:

```json
{
  "userId": "user123"
}
```

**Response**:

```json
{
  "success": true,
  "message": "Referral code ensured successfully",
  "data": {
    "userId": "user123",
    "referralCode": "123456",
    "generated": true
  }
}
```

### GET /api/v1/referral/settings

Gets current referral system settings.

**Response**:

```json
{
  "success": true,
  "data": {
    "enableAutoGeneration": true,
    "referralRewardAmount": "20.0",
    "lastUpdated": "2024-01-01T00:00:00Z"
  }
}
```

## Monitoring and Maintenance

### Logs

The system logs all operations:

- ✅ Successful code generation
- ⚠️ Duplicate code attempts
- ❌ Errors and failures
- 🔄 Feature toggle changes

### Database Structure

**Users Collection** - Updated with referral codes:

```json
{
  "userID": "user123",
  "referralCode": "123456",
  "referralCodeGeneratedAt": "2024-01-01T00:00:00Z"
  // ... other user fields
}
```

**Referral Collection** - Legacy compatibility:

```json
{
  "id": "user123",
  "referralCode": "123456",
  "referralBy": "referrer456"
}
```

### Rollout Strategy

1. **Phase 1**: Deploy with `enableAutoGeneration: false`
2. **Phase 2**: Enable for small percentage of users
3. **Phase 3**: Monitor metrics and error rates
4. **Phase 4**: Full rollout with `enableAutoGeneration: true`

### Rollback Plan

If issues occur:

1. Set `enableAutoGeneration: false` immediately
2. System falls back to existing behavior
3. No data loss - existing codes preserved
4. Fix issues and re-enable gradually

## Performance Considerations

- **Uniqueness Checks**: Limited to 10 attempts before fallback
- **Concurrency**: Uses Firestore transactions for consistency
- **Caching**: Backend checks are lightweight and fast
- **Fallback**: Timestamp-based codes ensure uniqueness

## Security

- **Input Validation**: All API endpoints validate user IDs
- **Rate Limiting**: Standard Express rate limiting applied
- **Authentication**: Integrate with existing auth middleware as needed
- **Logging**: All operations logged for audit trail

## Troubleshooting

### Common Issues

1. **Firebase Connection Errors**:

   - Verify service account credentials
   - Check project ID configuration
   - Ensure Firestore is enabled

2. **Duplicate Codes**:

   - System automatically handles with fallback
   - Monitor logs for high collision rates
   - Consider increasing code length if needed

3. **Feature Not Working**:
   - Check `enableAutoGeneration` setting
   - Verify backend URL in Flutter app
   - Check network connectivity

### Support

For issues or questions:

1. Check backend logs for error details
2. Verify Firebase console for data consistency
3. Test API endpoints directly with tools like Postman
4. Review this documentation for configuration steps
