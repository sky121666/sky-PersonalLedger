import { defineConfig, devices } from '@playwright/test'

const baseURL = process.env.LEDGER_WEB_E2E_BASE_URL || 'http://127.0.0.1:4173'
const timezoneId = 'Asia/Shanghai'
process.env.TZ = timezoneId

export default defineConfig({
  testDir: './e2e',
  testMatch: '**/*.e2e.ts',
  fullyParallel: false,
  workers: 1,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  timeout: 30_000,
  expect: {
    timeout: 7_500
  },
  reporter: process.env.CI
    ? [['line'], ['html', { open: 'never', outputFolder: 'playwright-report' }]]
    : 'list',
  use: {
    baseURL,
    locale: 'zh-CN',
    timezoneId,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure'
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] }
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] }
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] }
    }
  ],
  snapshotPathTemplate: process.env.LEDGER_WEB_VISUAL_BASELINE_DIR
    ? `${process.env.LEDGER_WEB_VISUAL_BASELINE_DIR}/{projectName}/{arg}{ext}`
    : undefined,
  outputDir: 'test-results'
})
