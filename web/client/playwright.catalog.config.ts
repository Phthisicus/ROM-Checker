import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  testMatch: ['catalog.spec.ts', 'design-system.catalog.spec.ts'],
  workers: 1,
  timeout: 30_000,
  use: { baseURL: 'http://127.0.0.1:5301', trace: 'retain-on-failure', screenshot: 'only-on-failure' },
  webServer: {
    command: 'node node_modules/vite/bin/vite.js --host 127.0.0.1 --port 5301 --strictPort',
    url: 'http://127.0.0.1:5301',
    reuseExistingServer: false,
  },
})
