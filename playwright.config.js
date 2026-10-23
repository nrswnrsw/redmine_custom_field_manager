'use strict';

const {defineConfig} = require('playwright/test');

module.exports = defineConfig({
  testDir: './test/browser',
  fullyParallel: false,
  workers: 1,
  timeout: 120000,
  expect: {timeout: 10000},
  use: {
    baseURL: process.env.RCFM_BASE_URL || 'http://127.0.0.1:3210',
    headless: true,
    launchOptions: process.env.RCFM_CHROME_PATH ? {executablePath: process.env.RCFM_CHROME_PATH} : {},
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure'
  },
  reporter: [['list']]
});
