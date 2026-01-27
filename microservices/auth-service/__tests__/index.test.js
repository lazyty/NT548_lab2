const request = require('supertest');
const app = require('../src/index');

describe('Auth Service', () => {
  test('Health check should return healthy status', async () => {
    const response = await request(app).get('/health');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('healthy');
    expect(response.body.service).toBe('auth-service');
  });

  test('Login with invalid credentials should return 401', async () => {
    const response = await request(app)
      .post('/login')
      .send({ username: 'invalid', password: 'invalid' });
    expect(response.status).toBe(401);
  });

  test('Verify without token should return 401', async () => {
    const response = await request(app).post('/verify');
    expect(response.status).toBe(401);
  });
});
