import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/browser',
  timeout: 90000,
  expect: { timeout: 10000 },
  reporter: 'line',
  outputDir: 'test-results',
  workers: 1,
  use: {
    browserName: 'chromium',
    headless: true,
    viewport: { width: 1365, height: 900 },
    trace: 'retain-on-failure',
  },
});
