import { describe, expect, it } from 'vitest';
import { poolConfig, pooledEndpointWarning } from '../src/db/pool.js';

const neon = 'postgresql://owner:secret@ep-cool-name-123456.eu-central-1.aws.neon.tech/neondb';

describe('poolConfig', () => {
  it('makes Neon-style TLS settings explicit', () => {
    const config = poolConfig(`${neon}?sslmode=require&channel_binding=require`);
    expect(config.connectionString).toBe(`${neon}?sslmode=verify-full`);
    expect(config.enableChannelBinding).toBe(true);
  });

  it('leaves plain local URLs alone', () => {
    const local = 'postgres://slavian:slavian@localhost:5432/slavian';
    expect(poolConfig(local)).toEqual({ connectionString: local });
  });

  it('keeps stricter or explicit modes as they are', () => {
    expect(poolConfig(`${neon}?sslmode=verify-full`).connectionString).toBe(`${neon}?sslmode=verify-full`);
    expect(poolConfig(`${neon}?sslmode=disable`).connectionString).toBe(`${neon}?sslmode=disable`);
  });
});

describe('pooledEndpointWarning', () => {
  it('warns about pooled endpoints only', () => {
    expect(pooledEndpointWarning(neon)).toBeNull();
    expect(pooledEndpointWarning(neon.replace('ep-cool-name-123456', 'ep-cool-name-123456-pooler'))).toMatch(/direct connection string/);
  });
});
