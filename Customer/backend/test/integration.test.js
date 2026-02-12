const request = require('supertest');
const app = require('../server');

describe('Play Integrity API Server', () => {
  const validApiKey = process.env.API_KEY || 'test-api-key';

  describe('Health Check', () => {
    test('GET /health should return 200', async () => {
      const response = await request(app)
        .get('/health');

      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('status', 'healthy');
      expect(response.body).toHaveProperty('timestamp');
      expect(response.body).toHaveProperty('version');
    });
  });

  describe('Authentication', () => {
    test('should reject requests without API key', async () => {
      const response = await request(app)
        .get('/api/v1/integrity/config');

      expect(response.status).toBe(401);
      expect(response.body).toHaveProperty('code', 'MISSING_API_KEY');
    });

    test('should reject requests with invalid API key', async () => {
      const response = await request(app)
        .get('/api/v1/integrity/config')
        .set('Authorization', 'Bearer invalid-key');

      expect(response.status).toBe(401);
      expect(response.body).toHaveProperty('code', 'INVALID_API_KEY');
    });

    test('should accept requests with valid API key', async () => {
      const response = await request(app)
        .get('/api/v1/integrity/config')
        .set('Authorization', `Bearer ${validApiKey}`);

      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('success', true);
    });

    test('should accept API key in x-api-key header', async () => {
      const response = await request(app)
        .get('/api/v1/integrity/config')
        .set('x-api-key', validApiKey);

      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('success', true);
    });
  });

  describe('Configuration Endpoint', () => {
    test('GET /api/v1/integrity/config should return configuration', async () => {
      const response = await request(app)
        .get('/api/v1/integrity/config')
        .set('Authorization', `Bearer ${validApiKey}`);

      expect(response.status).toBe(200);
      expect(response.body).toHaveProperty('success', true);
      expect(response.body).toHaveProperty('data');
      expect(response.body.data).toHaveProperty('projectId');
      expect(response.body.data).toHaveProperty('projectNumber');
      expect(response.body.data).toHaveProperty('expectedPackageName');
      expect(response.body.data).toHaveProperty('hasServiceAccount');
    });
  });

  describe('Token Validation', () => {
    test('should reject empty token', async () => {
      const response = await request(app)
        .post('/api/v1/integrity/validate')
        .set('Authorization', `Bearer ${validApiKey}`)
        .send({
          token: '',
          packageName: 'com.foodies.lalago.android'
        });

      expect(response.status).toBe(400);
      expect(response.body).toHaveProperty('code', 'VALIDATION_ERROR');
    });

    test('should reject missing token', async () => {
      const response = await request(app)
        .post('/api/v1/integrity/validate')
        .set('Authorization', `Bearer ${validApiKey}`)
        .send({
          packageName: 'com.foodies.lalago.android'
        });

      expect(response.status).toBe(400);
      expect(response.body).toHaveProperty('code', 'VALIDATION_ERROR');
    });

    test('should reject token that is too short', async () => {
      const response = await request(app)
        .post('/api/v1/integrity/validate')
        .set('Authorization', `Bearer ${validApiKey}`)
        .send({
          token: 'short',
          packageName: 'com.foodies.lalago.android'
        });

      expect(response.status).toBe(400);
      expect(response.body).toHaveProperty('code', 'VALIDATION_ERROR');
    });

    test('should handle invalid token format gracefully', async () => {
      const response = await request(app)
        .post('/api/v1/integrity/validate')
        .set('Authorization', `Bearer ${validApiKey}`)
        .send({
          token: 'this-is-a-fake-token-that-should-fail-validation-but-be-long-enough',
          packageName: 'com.foodies.lalago.android'
        });

      // Should not crash, but return validation failure
      expect([400, 500]).toContain(response.status);
      expect(response.body).toHaveProperty('success', false);
    });
  });

  describe('Batch Validation', () => {
    test('should reject empty tokens array', async () => {
      const response = await request(app)
        .post('/api/v1/integrity/batch-validate')
        .set('Authorization', `Bearer ${validApiKey}`)
        .send({
          tokens: []
        });

      expect(response.status).toBe(400);
      expect(response.body).toHaveProperty('code', 'VALIDATION_ERROR');
    });

    test('should reject too many tokens', async () => {
      const tokens = new Array(11).fill('fake-token-that-is-long-enough-for-validation');
      
      const response = await request(app)
        .post('/api/v1/integrity/batch-validate')
        .set('Authorization', `Bearer ${validApiKey}`)
        .send({
          tokens
        });

      expect(response.status).toBe(400);
      expect(response.body).toHaveProperty('code', 'VALIDATION_ERROR');
    });

    test('should accept valid token array', async () => {
      const tokens = [
        'fake-token-1-that-is-long-enough-for-validation',
        'fake-token-2-that-is-long-enough-for-validation'
      ];
      
      const response = await request(app)
        .post('/api/v1/integrity/batch-validate')
        .set('Authorization', `Bearer ${validApiKey}`)
        .send({
          tokens
        });

      // Should not crash due to validation errors
      expect([200, 500]).toContain(response.status);
      if (response.status === 200) {
        expect(response.body).toHaveProperty('success', true);
        expect(response.body.data).toHaveProperty('results');
        expect(response.body.data.results).toHaveLength(2);
      }
    });
  });

  describe('Error Handling', () => {
    test('should return 404 for unknown routes', async () => {
      const response = await request(app)
        .get('/api/v1/unknown-endpoint');

      expect(response.status).toBe(404);
      expect(response.body).toHaveProperty('error', 'Endpoint not found');
      expect(response.body).toHaveProperty('code', 'NOT_FOUND');
    });

    test('should handle invalid JSON gracefully', async () => {
      const response = await request(app)
        .post('/api/v1/integrity/validate')
        .set('Authorization', `Bearer ${validApiKey}`)
        .set('Content-Type', 'application/json')
        .send('invalid-json');

      expect(response.status).toBe(400);
    });
  });

  describe('Rate Limiting', () => {
    test('should apply rate limiting', async () => {
      // This test would need to be adjusted based on your rate limiting configuration
      // For now, we just verify the middleware is working
      const response = await request(app)
        .get('/health');

      expect(response.headers).toHaveProperty('x-ratelimit-limit');
      expect(response.headers).toHaveProperty('x-ratelimit-remaining');
    });
  });

  describe('Security Headers', () => {
    test('should include security headers', async () => {
      const response = await request(app)
        .get('/health');

      // Helmet.js security headers
      expect(response.headers).toHaveProperty('x-content-type-options');
      expect(response.headers).toHaveProperty('x-frame-options');
      expect(response.headers).toHaveProperty('x-xss-protection');
    });
  });
});
