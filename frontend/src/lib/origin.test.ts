import { isLocalOrigin } from './origin';

describe('isLocalOrigin', () => {
  it.each([
    ['http://localhost:5183', true],
    ['http://127.0.0.1:8000', true],
    ['http://[::1]:8000', true],
    ['https://pc.tail1.ts.net', false],
    ['http://192.168.0.10:8000', false],
  ])('%s → %s', (origin, local) => {
    expect(isLocalOrigin(origin)).toBe(local);
  });
});
