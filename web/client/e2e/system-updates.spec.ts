import { expect, test } from '@playwright/test'

test('running version opens global system details in expanded, collapsed and mobile navigation', async ({ page }) => {
  const release = {
    metadataFormatVersion: 1, version: '1.4.0-beta.3', channel: 'beta', commit: 'a'.repeat(40),
    notes: 'Installed offline release notes.', upgradeNotes: [], limitations: []
  }
  await page.route('**/api/info', route => route.fulfill({ json: {
    name: 'ROM Checker', version: release.version, channel: release.channel, commit: release.commit,
    buildNumber: 143, buildAttempt: 1, metadataFormatVersion: 1, library: '/library', pathBase: '/roms',
    schema: { version: 1, minimumSupported: 1, maximumSupported: 1 }, antivirus: 'ClamAV'
  } }))
  await page.route('**/api/updates/status', route => route.fulfill({ json: {
    status: 'available', message: 'A newer beta version is available.',
    result: { status: 'available', version: '1.4.0-beta.4', buildNumber: 144 }
  } }))
  await page.route('**/api/system', route => route.fulfill({ json: {
    release, updates: { enabled: true, scheduled: false },
    system: { scope: 'Container', operatingSystem: 'Ubuntu', architecture: 'X64', runtime: '.NET 10',
      startedUtc: '2026-11-11T12:00:00Z', uptimeSeconds: 3660 },
    paths: { library: '/library', data: '/data', engine: '/app', pathBase: '/roms' }
  } }))
  await page.goto('./')
  await page.getByLabel('Administrator password').fill('browser-fixture-password')
  await page.getByRole('button', { name: 'Sign in' }).click()
  const version = page.getByRole('button', { name: 'System & updates: 1.4.0-beta.3, beta, update available' })
  await expect(version).toBeVisible()
  await expect(version.locator('.update-indicator')).toBeVisible()
  await version.click()
  await expect(page.getByRole('heading', { name: 'System & updates', exact: true })).toBeVisible()
  await page.getByText('Installed release notes', { exact: true }).click()
  await expect(page.getByText('Installed offline release notes.', { exact: true })).toBeVisible()
  await page.getByText('Runtime & storage details', { exact: true }).click()
  await expect(page.getByText('.NET 10', { exact: true })).toBeVisible()
  await expect(page.getByRole('switch', { name: 'Advanced mode' })).not.toBeChecked()
  await page.getByRole('button', { name: 'Collapse sidebar' }).click()
  await expect(version).toBeVisible()
  await expect(version.locator('.version-expanded')).toBeHidden()
  await expect(version.locator('.version-compact')).toBeVisible()
  await version.click()
  await page.setViewportSize({ width: 390, height: 844 })
  await page.getByRole('button', { name: 'Open navigation' }).click()
  await expect(version.locator('.version-expanded')).toBeVisible()
  await expect(version.locator('.version-compact')).toBeHidden()
  await version.click()
  await expect(page.getByRole('heading', { name: 'System & updates', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Open navigation' })).toHaveAttribute('aria-expanded', 'false')
})
