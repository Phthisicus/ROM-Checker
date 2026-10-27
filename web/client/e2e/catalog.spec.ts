import { test, expect } from '@playwright/test'

test('collection redesign keeps scoped checks and publication safe, with URLs, advanced tools and mobile navigation', async ({ page }) => {
  const errors: string[] = []
  page.on('pageerror', error => errors.push(error.message))
  const posts: { path: string; body: Record<string, unknown> }[] = []
  const first = { id: 'a:game', batchId: 'a', collectionId: 'game', fileName: 'Verified.nes', console: 'NES', consoleName: 'Nintendo Entertainment System', category: 'Original', relativePath: 'NES\\Verified.nes', length: 40976, sha256: 'abc123', checkedUtc: '2026-10-27T12:00:00Z', checkStatus: 'checked', referenceStatus: 'matched', integrityStatus: 'Valid', security: 'Clean', organization: 'Organized', publishEligible: true, evidence: { Publisher: 'Local fixture' }, syncStatus: 'not-published' }
  const second = { ...first, id: 'b:game', batchId: 'b', fileName: 'Unchecked.nes', checkedUtc: '', checkStatus: 'unchecked', referenceStatus: 'unknown', publishEligible: false, publishBlockReason: 'Unchecked', sha256: '' }
  const catalog = { items: [first, second], total: 2, filtered: 2, page: 1, size: 100, ids: [first.id, second.id], categories: ['Original'], groups: [{ key: 'NES', name: first.consoleName, total: 2, checked: 1, attention: 1, ids: [first.id, second.id] }], counts: { checked: 1, unchecked: 1, attention: 1, eligible: 1 } }
  const config = { url: 'http://romm-fixture:8080', configured: true, platformMappings: [{ console: 'NES', platformId: 1, slug: 'nes' }], autoPublish: false, exportRoot: 'D:\\verified-export', transport: 'shared-library' }
  await page.route('**/api/**', async route => {
    const request = route.request()
    const path = new URL(request.url()).pathname.replace('/api', '')
    if (request.method() !== 'GET') posts.push({ path, body: request.postDataJSON() ?? {} })
    let data: unknown
    if (path === '/session') data = { authenticated: true }
    else if (path === '/info') data = { version: 'fixture', buildNumber: 142, library: 'D:\\library' }
    else if (path === '/jobs' || path === '/catalog/verifications' || path === '/romm/jobs' || path.endsWith('/history')) data = []
    else if (path === '/romm/links') data = [{ entryId: first.id, rommId: 7, status: 'linked', metadata: { name: 'Verified adventure', summary: 'A locally linked RomM game description.', metadatum: { genres: ['Adventure'] } } }]
    else if (path.startsWith('/romm/artwork/')) { await route.fulfill({ status: 404 }); return }
    else if (path === '/catalog') {
      expect(new URL(request.url()).searchParams.get('attention')).not.toBe('')
      data = catalog
    }
    else if (path === '/catalog/a%3Agame' || path === '/catalog/a:game') data = first
    else if (path === '/catalog/b%3Agame' || path === '/catalog/b:game') data = second
    else if (path.endsWith('/copies')) data = [path.includes('a') ? first : second]
    else if (path === '/settings/integrations') data = { approvedSmbHosts: [] }
    else if (path === '/consoles') data = []
    else if (path === '/settings') data = { autoDat: false, hasheous: 'Off', onlineCheck: 'Off', identifyUnknown: false, defenderScan: true }
    else if (path === '/catalog/verify') data = { id: 'verification', status: 'queued' }
    else if (path === '/romm/config' && request.method() === 'PUT') { await route.fulfill({ status: 204 }); return }
    else if (path === '/romm/config') data = config
    else if (path === '/romm/test') data = { version: '4.0-fixture', compatible: true, capabilities: { scans: true }, platforms: [{ id: 1, name: 'NES', slug: 'nes' }] }
    else if (path === '/romm/preview') data = { selected: 2, eligible: [{ id: first.id, fileName: first.fileName }], blocked: [{ id: second.id, fileName: second.fileName, reason: 'Unchecked' }] }
    else if (path === '/romm/publish') data = { id: 'publication', status: 'queued' }
    else if (path === '/storage/config') data = { enabled: true }
    else if (path === '/storage/batches') data = []
    else { await route.fulfill({ status: 404, json: { error: `Unexpected fixture route: ${path}` } }); return }
    await route.fulfill({ json: data })
  })
  await page.goto('/')
  const navigation = page.getByRole('navigation', { name: 'Main navigation' })
  await expect(page.getByRole('heading', { name: 'Library', exact: true })).toBeVisible()
  await expect(navigation.getByRole('button')).toHaveCount(4)
  await expect(page.getByRole('button', { name: 'Detailed results', exact: true })).toHaveCount(0)
  await expect(page.getByRole('img', { name: `No cover available for ${second.fileName}` })).toBeVisible()
  await page.getByRole('button', { name: /Nintendo Entertainment System.*ROM files/ }).click()
  await expect(page).toHaveURL(/console=NES/)
  await page.getByRole('button', { name: 'Open library filters' }).click()
  await page.getByRole('combobox', { name: 'RomM sync', exact: true }).selectOption('linked')
  await page.getByRole('button', { name: 'Show results' }).click()
  await page.getByRole('combobox', { name: 'Sort library' }).selectOption('name-desc')
  await page.getByRole('button', { name: 'List view' }).click()
  await page.getByRole('button', { name: first.fileName, exact: true }).click()
  await expect(page.getByRole('dialog')).toContainText('A locally linked RomM game description.')
  await expect(page.getByRole('dialog')).toContainText('Eligible to publish')
  await expect(page.getByRole('dialog').getByText('Evidence, hashes & current location')).toHaveCount(0)
  const bookmark = page.url()
  await page.reload()
  await expect(page.getByRole('dialog')).toBeVisible()
  await expect(page).toHaveURL(bookmark)
  await page.getByRole('button', { name: 'Close dialog' }).click()
  await expect(page.getByRole('combobox', { name: 'Sort library' })).toHaveValue('name-desc')
  await page.goBack()
  await expect(page.getByRole('combobox', { name: 'Sort library' })).toHaveValue('name')
  await page.goForward()
  await expect(page.getByRole('combobox', { name: 'Sort library' })).toHaveValue('name-desc')
  await page.getByRole('button', { name: 'Select page' }).click()
  await page.getByRole('button', { name: 'Check selected' }).click()
  await page.getByRole('button', { name: 'Queue verification' }).click()
  await expect(page.getByRole('status')).toContainText('Verification queued')
  await expect(page.getByRole('heading', { name: 'Library', exact: true })).toBeVisible()
  expect(posts.find(post => post.path === '/catalog/verify')?.body.ids).toEqual(catalog.ids)
  expect(posts.find(post => post.path === '/catalog/verify')?.body).not.toHaveProperty('batchId')
  await page.getByRole('button', { name: 'Select page' }).click()
  await page.getByRole('button', { name: 'Publish to RomM…' }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog).toContainText('1 eligible · 1 blocked')
  await expect(dialog.getByRole('button', { name: 'Publish eligible copies' })).toBeDisabled()
  await dialog.getByRole('checkbox').check()
  await dialog.getByRole('button', { name: 'Publish eligible copies' }).click()
  await expect(dialog).toHaveCount(0)
  expect(posts.find(post => post.path === '/romm/publish')?.body).toEqual({ ids: [first.id], confirm: true })
  await navigation.getByRole('button', { name: 'Settings', exact: true }).click()
  await page.getByRole('button', { name: 'Connections', exact: true }).click()
  await expect(page).toHaveURL(/settings\/connections/)
  await expect(page.getByLabel('API token')).toHaveValue('')
  await page.getByRole('button', { name: 'Save connection & mappings' }).click()
  await expect(page.getByRole('status')).toContainText('RomM settings saved')
  expect(posts.find(post => post.path === '/romm/config')?.body).not.toHaveProperty('token')
  await page.getByRole('button', { name: 'Test saved connection' }).click()
  await expect(page.getByText('Connected · RomM 4.0-fixture')).toBeVisible()
  await page.getByRole('switch', { name: 'Advanced mode' }).check()
  await expect(page.getByRole('navigation', { name: 'Advanced tools' })).toBeVisible()
  await navigation.getByRole('button', { name: 'Library', exact: true }).click()
  await page.getByRole('button', { name: first.fileName, exact: true }).click()
  await page.getByText('Evidence, hashes & current location').click()
  await expect(page.getByRole('dialog')).toContainText('Local fixture')
  await page.getByRole('button', { name: 'Close dialog' }).click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(page).not.toHaveURL(/file=/)
  await page.getByRole('switch', { name: 'Advanced mode' }).uncheck()
  await page.getByRole('button', { name: 'Cover grid' }).click()
  await page.evaluate(() => { document.getElementById('main-content')?.focus(); window.scrollTo(0, 0) })
  await page.screenshot({ path: test.info().outputPath('collection-dark.png'), fullPage: true })
  await page.setViewportSize({ width: 390, height: 844 })
  await expect(navigation).not.toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await page.getByRole('button', { name: 'Open navigation' }).click()
  await expect(navigation).toBeVisible()
  await page.keyboard.press('Shift+Tab')
  await expect(page.getByRole('switch', { name: 'Advanced mode' })).toBeFocused()
  await page.keyboard.press('Escape')
  await expect(navigation).not.toBeVisible()
  await expect(page.getByRole('button', { name: 'Open navigation' })).toBeFocused()
  await page.getByRole('button', { name: 'Open navigation' }).click()
  await navigation.getByRole('button', { name: 'Add games', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Import history' })).toBeVisible()
  await page.getByRole('button', { name: 'Open navigation' }).click()
  await navigation.getByRole('button', { name: 'Library', exact: true }).click()
  await expect(page).toHaveURL(/sort=name-desc/)
  await expect(page).toHaveURL(/syncStatus=linked/)
  await page.screenshot({ path: test.info().outputPath('collection-mobile.png'), fullPage: true })
  await page.getByRole('button', { name: 'Use light theme' }).click()
  await page.setViewportSize({ width: 1440, height: 1000 })
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light')
  await page.screenshot({ path: test.info().outputPath('collection-light.png'), fullPage: true })
  expect(errors).toEqual([])
})
