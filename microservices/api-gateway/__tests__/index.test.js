const request = require('supertest');
const app = require('../src/index');

describe('API Gateway', () => {
  test('Health check should return healthy status', async () => {
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('healthy');
    expect(response.body.service).toBe('api-gateway');
  });
});
