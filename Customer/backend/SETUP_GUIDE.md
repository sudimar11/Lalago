# Complete Setup Guide for Play Integrity API Backend

This guide provides step-by-step instructions for setting up the Play Integrity API backend server from scratch.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Google Cloud Setup](#google-cloud-setup)
3. [Google Play Console Configuration](#google-play-console-configuration)
4. [Service Account Setup](#service-account-setup)
5. [Backend Server Setup](#backend-server-setup)
6. [Testing and Verification](#testing-and-verification)
7. [Production Deployment](#production-deployment)

## Prerequisites

Before starting, ensure you have:

- [ ] Google Cloud Project (with billing enabled)
- [ ] Google Play Console account
- [ ] Android app published to at least Internal Testing track
- [ ] Node.js 16.0 or higher installed
- [ ] Basic knowledge of REST APIs and environment variables

## Google Cloud Setup

### Step 1: Create or Select Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Either create a new project or select existing one
3. Note your **Project ID** and **Project Number** (found in project info card)

### Step 2: Enable Play Integrity API

1. Navigate to **APIs & Services > Library**
2. Search for "Google Play Integrity API"
3. Click on the API and press **Enable**
4. Wait for the API to be enabled (may take a few minutes)

### Step 3: Enable Billing (Required)

1. Go to **Billing** in the left sidebar
2. Link a billing account to your project
3. The Play Integrity API requires billing to be enabled

## Google Play Console Configuration

### Step 1: Upload Your App

1. Go to [Google Play Console](https://play.google.com/console/)
2. Select your app (or create new app if needed)
3. Upload your APK/AAB to at least the **Internal Testing** track
4. Ensure your app is signed with your release key

### Step 2: Enable Play Integrity

1. Navigate to **Release > Setup > App Integrity**
2. Find the **Play Integrity API** section
3. Click **Turn on Play Integrity API**
4. Link your Google Cloud project:
   - Click **Link Cloud project**
   - Select the project you created earlier
   - Confirm the linking

### Step 3: Verify Configuration

1. In the App Integrity section, you should see:
   - ✅ Play Integrity API: On
   - ✅ Linked to: [Your Project Name]

## Service Account Setup

### Step 1: Create Service Account

1. In Google Cloud Console, go to **IAM & Admin > Service Accounts**
2. Click **Create Service Account**
3. Fill in the details:
   - **Name**: `play-integrity-validator`
   - **Description**: `Service account for validating Play Integrity tokens`
4. Click **Create and Continue**

### Step 2: Add Required Permissions

Add the following role to your service account:
- **Play Integrity API Service Agent** (`roles/playintegrity.serviceagent`)

To add the role:
1. In the service account creation wizard, click **Select a role**
2. Search for "Play Integrity"
3. Select **Play Integrity API Service Agent**
4. Click **Continue**
5. Click **Done**

### Step 3: Create Service Account Key

1. Click on your newly created service account
2. Go to the **Keys** tab
3. Click **Add Key > Create New Key**
4. Select **JSON** format
5. Click **Create**
6. The key file will download automatically
7. **Important**: Save this file securely - it contains credentials

### Step 4: Verify Permissions

1. Go to **IAM & Admin > IAM**
2. Find your service account in the list
3. Verify it has the **Play Integrity API Service Agent** role

## Backend Server Setup

### Step 1: Install Dependencies

```bash
cd backend
npm install
```

### Step 2: Configure Environment

1. Copy the environment template:
```bash
cp env.example .env
```

2. Edit the `.env` file with your values:

```env
# Google Cloud Configuration
GOOGLE_CLOUD_PROJECT_ID=your-actual-project-id
GOOGLE_CLOUD_PROJECT_NUMBER=your-actual-project-number
GOOGLE_APPLICATION_CREDENTIALS=./service-account-key.json

# Expected App Configuration
EXPECTED_PACKAGE_NAME=com.foodies.lalago.android
EXPECTED_APP_CERTIFICATE_SHA256=your-app-certificate-sha256

# Server Configuration
PORT=3000
NODE_ENV=development

# API Security
API_KEY=generate-a-secure-random-key-here
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100

# Logging
LOG_LEVEL=info
LOG_FILE=./logs/app.log
```

### Step 3: Add Service Account Key

1. Move your downloaded service account JSON file to the backend directory
2. Rename it to `service-account-key.json`
3. Ensure the path in `.env` matches: `GOOGLE_APPLICATION_CREDENTIALS=./service-account-key.json`

### Step 4: Find Your App Certificate SHA256

You need your app's certificate SHA256 for validation. Here's how to get it:

#### Method 1: From Google Play Console
1. Go to **Release > Setup > App Signing**
2. Find **App signing key certificate**
3. Copy the **SHA-256 certificate fingerprint**

#### Method 2: From APK/AAB file
```bash
# For APK
keytool -printcert -jarfile your-app.apk

# For AAB (requires bundletool)
java -jar bundletool.jar extract-apks --bundle=your-app.aab --output=output.apks
unzip output.apks
keytool -printcert -jarfile base-master.apk
```

#### Method 3: From Keystore
```bash
keytool -list -v -keystore your-keystore.jks -alias your-alias
```

### Step 5: Generate Secure API Key

Generate a secure API key for authentication:

```bash
# Using Node.js
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

# Using OpenSSL
openssl rand -hex 32

# Using Python
python3 -c "import secrets; print(secrets.token_hex(32))"
```

Update your `.env` file with the generated key.

### Step 6: Create Log Directory

```bash
mkdir -p logs
```

## Testing and Verification

### Step 1: Start the Server

```bash
npm run dev
```

You should see:
```
Play Integrity API server running on port 3000
```

### Step 2: Test Health Endpoint

```bash
curl http://localhost:3000/health
```

Expected response:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "version": "1.0.0"
}
```

### Step 3: Test Configuration Endpoint

```bash
curl -H "Authorization: Bearer your-api-key" \
     http://localhost:3000/api/v1/integrity/config
```

Expected response:
```json
{
  "success": true,
  "data": {
    "projectId": "your-project-id",
    "projectNumber": "123456789",
    "expectedPackageName": "com.foodies.lalago.android",
    "expectedCertificateSha256": "A1B2C3D4...",
    "hasServiceAccount": true
  }
}
```

### Step 4: Test with Real Token

1. In your Flutter app, generate a real integrity token:

```dart
final result = await PlayIntegrityService.getIntegrityDetails();
if (result.isValid && result.token != null) {
  print('Token: ${result.token}');
}
```

2. Test the token with your backend:

```bash
curl -X POST http://localhost:3000/api/v1/integrity/validate \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "token": "actual-token-from-flutter-app",
    "packageName": "com.foodies.lalago.android"
  }'
```

## Production Deployment

### Step 1: Update Environment for Production

```env
NODE_ENV=production
LOG_LEVEL=warn
ALLOWED_ORIGINS=https://your-app-domain.com
```

### Step 2: Security Checklist

- [ ] Use HTTPS only
- [ ] Set strong API keys
- [ ] Configure proper CORS origins
- [ ] Enable rate limiting
- [ ] Set up log monitoring
- [ ] Secure service account key file
- [ ] Use environment-specific configurations

### Step 3: Deploy to Cloud Platform

#### Google Cloud Run (Recommended)

1. Create `Dockerfile`:
```dockerfile
FROM node:16-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
USER node
CMD ["node", "server.js"]
```

2. Deploy:
```bash
gcloud builds submit --tag gcr.io/PROJECT-ID/play-integrity-api
gcloud run deploy --image gcr.io/PROJECT-ID/play-integrity-api --platform managed
```

#### Other Platforms

The server can also be deployed to:
- Google App Engine
- AWS Lambda (with serverless framework)
- Heroku
- DigitalOcean App Platform
- Any Node.js hosting service

## Troubleshooting

### Common Issues and Solutions

#### 1. "API_KEY not configured"
**Solution**: Set the `API_KEY` environment variable in your `.env` file.

#### 2. "Google Cloud project configuration is missing"
**Solution**: Verify `GOOGLE_CLOUD_PROJECT_ID` and `GOOGLE_CLOUD_PROJECT_NUMBER` are set correctly.

#### 3. "Play Integrity API access denied"
**Solutions**:
- Verify service account has correct permissions
- Check that Play Integrity API is enabled
- Ensure billing is enabled on your Google Cloud project

#### 4. "Invalid integrity token format"
**Solutions**:
- Ensure your Flutter app is generating tokens correctly
- Verify the token hasn't expired (tokens are short-lived)
- Check that your app is properly configured in Play Console

#### 5. "Package name mismatch"
**Solutions**:
- Verify `EXPECTED_PACKAGE_NAME` matches your app's package name
- Check the package name being sent from the client

#### 6. Service account authentication fails
**Solutions**:
- Verify the service account key file exists and is readable
- Check the `GOOGLE_APPLICATION_CREDENTIALS` path
- Ensure the service account has the correct permissions

### Debug Steps

1. **Enable debug logging**:
   ```env
   LOG_LEVEL=debug
   ```

2. **Check server logs**:
   ```bash
   tail -f logs/app.log
   ```

3. **Verify Google Cloud configuration**:
   ```bash
   gcloud auth application-default login
   gcloud config set project YOUR_PROJECT_ID
   ```

4. **Test service account locally**:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="./service-account-key.json"
   node -e "
   const { google } = require('googleapis');
   const auth = new google.auth.GoogleAuth({
     scopes: ['https://www.googleapis.com/auth/playintegrity']
   });
   auth.getClient().then(client => console.log('Auth successful'));
   "
   ```

## Next Steps

After successful setup:

1. **Integrate with your Flutter app** - Update your client code to send tokens to your backend
2. **Set up monitoring** - Add application monitoring and alerting
3. **Configure CI/CD** - Automate deployment with your preferred CI/CD platform
4. **Scale considerations** - Plan for horizontal scaling if needed
5. **Security audit** - Review security settings and access controls

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review server logs for detailed error messages
3. Verify all configuration steps were completed
4. Test each component individually (health check → config → token validation)

The setup is complete when you can successfully validate integrity tokens from your Flutter app through your backend server.
