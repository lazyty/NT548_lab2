const request = require('supertest');
const app = require('../src/index');

describe('User Service', () => {
  test('Health check should return healthy status', async () => {
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('healthy');
    expect(response.body.service).toBe('user-service');
  });

  test('Get all users should return array', async () => {
    const response = await request(app).get('/');
    expect(response.status).toBe(200);
    expect(Array.isArray(response.body)).toBe(true);
  });

  test('Get non-existent user should return 404', async () => {
    const response = await request(app).get('/999');
    expect(response.status).toBe(404);
  });
});
