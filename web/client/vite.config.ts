import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'
import { readFileSync } from 'node:fs'

export default defineConfig({
  base: './',
  define: { __APP_VERSION__: JSON.stringify(JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8')).version) },
  plugins: [react()],
  server: { proxy: { '/api': 'http://127.0.0.1:5200' } },
  test: { environment: 'jsdom', setupFiles: ['./src/test-setup.ts'], include: ['src/**/*.test.{ts,tsx}'] },
})
