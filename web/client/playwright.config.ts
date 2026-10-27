import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  testIgnore: 'catalog.spec.ts',
  fullyParallel: false,
  workers: 1,
  timeout: 90_000,
  use: { baseURL: 'http://127.0.0.1:5299/roms/', trace: 'retain-on-failure', screenshot: 'only-on-failure' },
  webServer: {
    command: 'node ../tests/start-server.mjs',
    url: 'http://127.0.0.1:5299/roms/healthz',
    reuseExistingServer: false,
    timeout: 60_000,
  },
})
