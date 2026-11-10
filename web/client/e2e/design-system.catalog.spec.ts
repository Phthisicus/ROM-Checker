import { test, expect } from '@playwright/test'

test.beforeEach(async ({ page }) => {
  await page.route('**/__design-system', route => route.fulfill({
    contentType: 'text/html',
    body: '<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><script type="module">import RefreshRuntime from "/@react-refresh"; RefreshRuntime.injectIntoGlobalHook(window); window.$RefreshReg$ = () => {}; window.$RefreshSig$ = () => type => type; window.__vite_plugin_react_preamble_installed__ = true;</script></head><body><div id="root"></div><script type="module" src="/e2e/design-system.fixture.tsx"></script></body></html>',
  }))
  await page.goto('/__design-system')
  await expect(page.getByRole('heading', { name: 'Design system fixture' })).toBeVisible()
})

test('shared dimensions, contrast, overflow and reduced motion hold in both themes', async ({ page }) => {
  for (const theme of ['dark', 'light']) {
    await page.evaluate(value => { document.documentElement.dataset.theme = value }, theme)
    await expect(page.getByRole('button', { name: 'Primary', exact: true })).toHaveCSS('background-color', theme === 'dark' ? 'rgb(165, 180, 252)' : 'rgb(69, 89, 183)')
    for (const [name, height] of [['Small', 32], ['Default', 36], ['Large', 44]] as const) {
      expect((await page.getByRole('button', { name, exact: true }).boundingBox())?.height).toBe(height)
      const icon = await page.getByRole('button', { name: `${name} icon`, exact: true }).boundingBox()
      expect(icon?.height).toBe(height)
      expect(icon?.width).toBe(height)
    }
    expect((await page.getByLabel('ROM directory').boundingBox())?.height).toBe(36)
    const ratios = await page.evaluate(() => {
      function rgb(value: string) { return value.match(/[\d.]+/g)!.slice(0, 3).map(Number) }
      function luminance(color: number[]) {
        return color.map(channel => channel / 255).map(channel => channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4)
          .reduce((sum, channel, index) => sum + channel * [0.2126, 0.7152, 0.0722][index], 0)
      }
      function contrast(a: string, b: string) {
        const values = [luminance(rgb(a)), luminance(rgb(b))].sort((a, b) => b - a)
        return (values[0] + 0.05) / (values[1] + 0.05)
      }
      return [...document.querySelectorAll('.ds-badge, .ds-button--primary, .ds-button--danger, .ds-notice')].map(element => {
        const style = getComputedStyle(element)
        return { label: element.textContent, ratio: contrast(style.color, style.backgroundColor) }
      })
    })
    for (const result of ratios) expect(result.ratio, `${theme}: ${result.label}`).toBeGreaterThanOrEqual(4.5)
    await page.setViewportSize({ width: 320, height: 640 })
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(320)
    const scrollRegion = page.getByRole('region', { name: 'ROM files' })
    expect(await scrollRegion.evaluate(element => element.scrollWidth > element.clientWidth)).toBe(true)
    await page.setViewportSize({ width: 1280, height: 900 })
  }
  await page.emulateMedia({ reducedMotion: 'reduce' })
  expect(await page.getByRole('button', { name: 'Primary', exact: true }).evaluate(element => getComputedStyle(element).transitionDuration)).toBe('0s')
})

test('tooltips and native dialog/drawer preserve keyboard focus and fit mobile', async ({ page }) => {
  const trigger = page.getByRole('button', { name: 'Check information' })
  await trigger.focus()
  await expect(page.getByRole('tooltip')).toBeVisible()
  await trigger.press('Escape')
  await expect(page.getByRole('tooltip')).toHaveCount(0)
  for (const variant of ['dialog', 'drawer']) {
    const opener = page.getByRole('button', { name: `Open ${variant}` })
    await opener.click()
    const dialog = page.getByRole('dialog', { name: 'Review ROM evidence' })
    await expect(dialog).toBeVisible()
    const close = dialog.getByRole('button', { name: 'Close dialog' })
    await expect(close).toBeFocused()
    await close.press('Tab')
    await expect(dialog.getByLabel('Review note')).toBeFocused()
    await page.keyboard.press('Tab')
    await expect(dialog.getByRole('button', { name: 'Done' })).toBeFocused()
    for (let index = 0; index < 5; index++) {
      await page.keyboard.press('Tab')
      // Native modal focus may visit browser chrome, but not the inert page.
      expect(await dialog.evaluate(element => document.activeElement === document.body || element.contains(document.activeElement))).toBe(true)
    }
    await page.setViewportSize({ width: 320, height: 640 })
    const bounds = await dialog.boundingBox()
    expect(bounds!.x).toBeGreaterThanOrEqual(0)
    expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(320)
    expect(bounds!.height).toBeLessThanOrEqual(640)
    await page.keyboard.press('Escape')
    await expect(dialog).toHaveCount(0)
    await expect(opener).toBeFocused()
    await page.setViewportSize({ width: 1280, height: 900 })
  }
})
