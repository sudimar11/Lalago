# Play Integrity API Backend Server

This backend server provides validation of Google Play Integrity API tokens for the LalaGo Customer app. It replaces the deprecated SafetyNet attestation with the newer, more secure Play Integrity API.

## Features

- **Token Validation**: Validates Play Integrity tokens using Google's official API
- **Package Verification**: Ensures tokens come from your expected app package
- **Integrity Checks**: Validates device and app integrity verdicts
- **Certificate Validation**: Verifies app signing certificate (optional)
- **Batch Processing**: Support for validating multiple tokens at once
- **Security**: API key authentication, rate limiting, comprehensive logging
- **Error Handling**: Detailed error responses with proper HTTP status codes

## Quick Start

### 1. Prerequisites

- Node.js 16.0 or higher
- Google Cloud Project with Play Integrity API enabled
- Service account with Play Integrity API permissions
- Your app uploaded to Google Play Console (at least internal testing)

### 2. Installation

```bash
cd backend
npm install
```

### 3. Configuration

Copy the environment template:
```bash
cp env.example .env
```

Edit `.env` with your configuration:
```env
# Google Cloud Configuration
GOOGLE_CLOUD_PROJECT_ID=your-project-id
GOOGLE_CLOUD_PROJECT_NUMBER=123456789
GOOGLE_APPLICATION_CREDENTIALS=./service-account-key.json

# Expected App Configuration
EXPECTED_PACKAGE_NAME=com.foodies.lalago.android
EXPECTED_APP_CERTIFICATE_SHA256=your-app-certificate-sha256

# Server Configuration
PORT=3000
NODE_ENV=production

# API Security
API_KEY=your-secure-api-key-here
```

### 4. Service Account Setup

1. Download your service account key JSON file
2. Place it in the backend directory as `service-account-key.json`
3. Ensure the service account has Play Integrity API permissions

### 5. Start the Server

```bash
npm start
```

For development with auto-reload:
```bash
npm run dev
```

## API Endpoints

### POST /api/v1/integrity/validate

Validates a single Play Integrity token.

**Headers:**
```
Authorization: Bearer your-api-key
Content-Type: application/json
```

**Request Body:**
```json
{
  "token": "integrity-token-from-client",
  "packageName": "com.foodies.lalago.android",
  "expectedPackageName": "com.foodies.lalago.android"
}
```

**Response (Success):**
```json
{
  "success": true,
  "valid": true,
  "data": {
    "packageName": "com.foodies.lalago.android",
    "deviceVerdict": "MEETS_DEVICE_INTEGRITY",
    "appVerdict": "PLAY_RECOGNIZED",
    "accountVerdict": "LICENSED",
    "timestamp": "2024-01-15T10:30:00.000Z"
  },
  "message": "Integrity token validated successfully"
}
```

**Response (Failure):**
```json
{
  "success": false,
  "valid": false,
  "error": "Package name mismatch",
  "code": "PACKAGE_NAME_MISMATCH",
  "data": {
    "packageName": "com.different.package",
    "deviceVerdict": "MEETS_DEVICE_INTEGRITY",
    "appVerdict": "PLAY_RECOGNIZED",
    "accountVerdict": "LICENSED",
    "timestamp": "2024-01-15T10:30:00.000Z"
  },
  "message": "Integrity token validation failed"
}
```

### POST /api/v1/integrity/batch-validate

Validates multiple integrity tokens in a batch (up to 10 tokens).

**Request Body:**
```json
{
  "tokens": [
    "token1",
    "token2",
    "token3"
  ],
  "expectedPackageName": "com.foodies.lalago.android"
}
```

### GET /api/v1/integrity/config

Returns current server configuration (for debugging).

### GET /health

Health check endpoint - no authentication required.

## Google Cloud Setup

### 1. Enable Play Integrity API

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project
3. Navigate to **APIs & Services > Library**
4. Search for "Play Integrity API"
5. Click **Enable**

### 2. Create Service Account

1. Go to **IAM & Admin > Service Accounts**
2. Click **Create Service Account**
3. Name: `play-integrity-validator`
4. Description: `Service account for Play Integrity API validation`
5. Click **Create and Continue**

### 3. Add Permissions

Add the following roles to your service account:
- **Play Integrity API Service Agent** (roles/playintegrity.serviceagent)

### 4. Create Service Account Key

1. Click on your service account
2. Go to **Keys** tab
3. Click **Add Key > Create New Key**
4. Select **JSON** format
5. Download and save as `service-account-key.json`

### 5. Link Google Play Console

1. Go to [Google Play Console](https://play.google.com/console/)
2. Select your app
3. Go to **Release > Setup > App Integrity**
4. Click **Link Cloud project**
5. Select your Google Cloud project
6. Enable **Play Integrity API**

## Integration with Flutter App

### Client-Side Token Generation

In your Flutter app, use the existing `PlayIntegrityService`:

```dart
import 'package:lalago_customer/services/play_integrity_service.dart';

// Get integrity token
final result = await PlayIntegrityService.getIntegrityDetails();
if (result.isValid && result.token != null) {
  // Send token to your backend
  await validateTokenWithBackend(result.token);
}
```

### Backend Validation

```dart
Future<bool> validateTokenWithBackend(String token) async {
  final response = await http.post(
    Uri.parse('https://your-server.com/api/v1/integrity/validate'),
    headers: {
      'Authorization': 'Bearer your-api-key',
      'Content-Type': 'application/json',
    },
    body: json.encode({
      'token': token,
      'packageName': 'com.foodies.lalago.android',
    }),
  );

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['valid'] == true;
  }

  return false;
}
```

## Security Considerations

### API Key Management

- Use a strong, randomly generated API key
- Store API keys securely (environment variables, secrets manager)
- Rotate API keys regularly
- Use different keys for different environments

### Rate Limiting

The server includes rate limiting (100 requests per 15 minutes by default). Adjust in `.env`:

```env
RATE_LIMIT_WINDOW_MS=900000  # 15 minutes
RATE_LIMIT_MAX_REQUESTS=100   # Max requests per window
```

### HTTPS

Always use HTTPS in production. The server includes security headers via Helmet.js.

### Service Account Security

- Limit service account permissions to only what's needed
- Store service account keys securely
- Monitor service account usage
- Rotate service account keys periodically

## Monitoring and Logging

### Log Levels

- `error`: Critical errors that need immediate attention
- `warn`: Warning conditions (failed validations, security events)
- `info`: General information (successful validations, API usage)
- `debug`: Detailed debugging information

### Log Configuration

```env
LOG_LEVEL=info
LOG_FILE=./logs/app.log
```

### Monitoring Endpoints

- `/health` - Basic health check
- `/api/v1/integrity/config` - Configuration status

## Deployment

### Environment Variables

Ensure all required environment variables are set:

```bash
# Check configuration
node -e "
require('dotenv').config();
console.log('Project ID:', process.env.GOOGLE_CLOUD_PROJECT_ID);
console.log('Package Name:', process.env.EXPECTED_PACKAGE_NAME);
console.log('Has Service Account:', !!process.env.GOOGLE_APPLICATION_CREDENTIALS);
console.log('Has API Key:', !!process.env.API_KEY);
"
```

### Docker Deployment

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

### Cloud Deployment

The server can be deployed to:
- Google Cloud Run
- Google App Engine
- AWS Lambda (with serverless framework)
- Heroku
- Any Node.js hosting platform

## Troubleshooting

### Common Issues

1. **"API_KEY not configured"**
   - Set the `API_KEY` environment variable

2. **"Google Cloud project configuration is missing"**
   - Set `GOOGLE_CLOUD_PROJECT_ID` and `GOOGLE_CLOUD_PROJECT_NUMBER`

3. **"Play Integrity API access denied"**
   - Check service account permissions
   - Ensure API is enabled in Google Cloud Console

4. **"Invalid integrity token format"**
   - Token may be malformed or expired
   - Ensure client is generating tokens correctly

5. **"Package name mismatch"**
   - Check `EXPECTED_PACKAGE_NAME` configuration
   - Verify client is sending correct package name

### Debug Mode

Set `LOG_LEVEL=debug` for detailed logging:

```env
LOG_LEVEL=debug
```

### Testing

Run the test suite:

```bash
npm test
```

Test individual endpoints:

```bash
# Health check
curl http://localhost:3000/health

# Validate token
curl -X POST http://localhost:3000/api/v1/integrity/validate \
  -H "Authorization: Bearer your-api-key" \
  -H "Content-Type: application/json" \
  -d '{"token":"test-token","packageName":"com.foodies.lalago.android"}'
```

## API Response Codes

| Code | Description |
|------|-------------|
| 200 | Success - token validated |
| 400 | Bad Request - validation failed or invalid input |
| 401 | Unauthorized - missing or invalid API key |
| 403 | Forbidden - insufficient permissions |
| 404 | Not Found - endpoint not found |
| 413 | Payload Too Large - request body too large |
| 429 | Too Many Requests - rate limit exceeded |
| 500 | Internal Server Error - server error |
| 503 | Service Unavailable - external service error |

## Support

For issues and questions:

1. Check the troubleshooting section
2. Review server logs
3. Verify Google Cloud Console configuration
4. Test with the health endpoint first

## License

MIT License - see LICENSE file for details.
