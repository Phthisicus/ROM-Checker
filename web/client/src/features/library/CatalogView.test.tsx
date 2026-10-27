import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import type { Settings } from '../../api'
import CatalogView, { finding, type CatalogEntry, type CatalogPage } from './CatalogView'

const entry: CatalogEntry = {
  id: 'import-a:rom-a', batchId: 'import-a', collectionId: 'rom-a', fileName: 'Translation.nes',
  console: 'NES', consoleName: 'Nintendo Entertainment System', category: 'Translation', relativePath: 'NES\\Translation.nes',
  length: 1024, sha256: 'abc123', checkedUtc: '2026-10-27T12:00:00Z', checkStatus: 'checked',
  referenceStatus: 'modified', integrityStatus: 'Valid', security: 'Clean', organization: 'Held',
  publishEligible: false, publishBlockReason: 'Explicit approval required', evidence: { Publisher: 'Fixture studio' },
  syncStatus: 'not-published', holdReason: 'Intentional modification needs review',
}
const catalog: CatalogPage = {
  items: [entry], total: 3, filtered: 2, page: 1, size: 1, ids: [entry.id, 'import-b:rom-b'],
  groups: [{ key: 'NES', name: entry.consoleName, total: 2, checked: 1, attention: 1, ids: [entry.id, 'import-b:rom-b'] }],
  categories: ['Original', 'Translation'], counts: { checked: 1, unchecked: 2, attention: 1, eligible: 0 },
}
const settings = { autoDat: false, hasheous: 'Off', onlineCheck: 'Off', identifyUnknown: false, defenderScan: true } as Settings
function setup({ online = false, linked = false, advanced = false } = {}) {
  const fail = vi.fn()
  const fetcher = vi.fn(async (path: string, init?: RequestInit) => {
    if (path === '/api/romm/links') return Response.json(linked ? [{ entryId: entry.id, rommId: 7, status: 'linked', metadata: { name: 'Translated adventure', summary: 'A descriptive game summary.', url_cover: 'https://untrusted.invalid/cover?token=never-fetch', metadatum: { genres: ['Adventure'] } } }] : [])
    if (path === '/api/settings') return Response.json({ ...settings, autoDat: online })
    if (path.includes('/history')) return Response.json([{ detail: 'Fixture evidence' }])
    if (path.endsWith('/copies')) return Response.json([entry, { ...entry, id: 'other-copy', publishEligible: false, checkStatus: 'unchecked' }])
    if (path === '/api/catalog/verify' || path === '/api/catalog/approve') return Response.json({ id: 'queued-run' })
    if (path === '/api/catalog/' + encodeURIComponent(entry.id)) return Response.json(entry)
    if (path === '/api/catalog' || path.startsWith('/api/catalog?')) return Response.json(path === '/api/catalog' ? { ...catalog, ids: [...catalog.ids, 'import-c:rom-c'] } : catalog)
    throw new Error(`Unexpected request ${path} ${init?.method}`)
  })
  vi.stubGlobal('fetch', fetcher)
  const props = { fail, imports: vi.fn(), activity: vi.fn(), jobs: [], progress: null, changed: vi.fn().mockResolvedValue(undefined), advanced }
  const rendered = render(<CatalogView {...props} />)
  return { fetcher, fail, rendered, props }
}
const posted = (fetcher: ReturnType<typeof setup>['fetcher'], path: string) => {
  const call = fetcher.mock.calls.find(([value, init]) => value === path && init?.method === 'POST')
  return call ? JSON.parse(call[1]!.body as string) : undefined
}
async function more() { fireEvent.click(screen.getByText('More actions')) }
describe('collection browser', () => {
  it('distinguishes visible-page and all-filtered selection across imports', async () => {
    const { fetcher } = setup()
    await screen.findByRole('button', { name: entry.fileName })
    fireEvent.click(screen.getByRole('button', { name: 'Select page' }))
    expect(screen.getByText('1 selected files')).toBeInTheDocument()
    fireEvent.click(screen.getByText('Selection', { selector: 'summary' }))
    fireEvent.click(screen.getByRole('button', { name: 'Select all 2 filtered' }))
    fireEvent.click(screen.getByRole('button', { name: 'Check selected' }))
    const dialog = await screen.findByRole('dialog', { name: 'Verify 2 ROMs' })
    expect(within(dialog).queryByText('Individual checks for this run')).not.toBeInTheDocument()
    fireEvent.click(within(dialog).getByRole('button', { name: 'Queue verification' }))
    await waitFor(() => expect(posted(fetcher, '/api/catalog/verify')).toEqual(expect.objectContaining({ ids: catalog.ids, confirm: true, organize: true })))
    expect(posted(fetcher, '/api/catalog/verify')).not.toHaveProperty('batchId')
    expect(await screen.findByText(/Verification queued/)).toBeInTheDocument()
  })
  it('requires informed online consent even with advanced controls hidden', async () => {
    const { fetcher } = setup({ online: true })
    await screen.findByRole('button', { name: entry.fileName })
    await more()
    fireEvent.click(screen.getByRole('button', { name: 'Check 2 filtered files' }))
    const dialog = await screen.findByRole('dialog')
    const queue = within(dialog).getByRole('button', { name: 'Queue verification' })
    expect(queue).toBeDisabled()
    fireEvent.click(within(dialog).getByRole('checkbox', { name: /I consent/ }))
    fireEvent.change(within(dialog).getByLabelText('After verification'), { target: { value: 'false' } })
    fireEvent.click(queue)
    await waitFor(() => expect(posted(fetcher, '/api/catalog/verify')?.organize).toBe(false))
  })
  it('uses explicit global IDs for whole-library checks rather than current filters', async () => {
    const { fetcher } = setup()
    await screen.findByRole('button', { name: entry.fileName })
    fireEvent.click(screen.getByRole('button', { name: 'Open library filters' }))
    fireEvent.change(screen.getByRole('combobox', { name: 'Category' }), { target: { value: 'Translation' } })
    fireEvent.click(screen.getByRole('button', { name: 'Show results' }))
    await more()
    const button = screen.getByRole('button', { name: 'Check entire library' })
    await waitFor(() => expect(button).toBeEnabled())
    fireEvent.click(button)
    const dialog = await screen.findByRole('dialog', { name: 'Verify 3 ROMs' })
    fireEvent.click(within(dialog).getByRole('button', { name: 'Queue verification' }))
    await waitFor(() => expect(posted(fetcher, '/api/catalog/verify')?.ids).toEqual([...catalog.ids, 'import-c:rom-c']))
  })
  it('keeps reference, integrity, security and publishing blocks visible in normal game details', async () => {
    setup()
    fireEvent.click(await screen.findByRole('button', { name: entry.fileName }))
    const dialog = await screen.findByRole('dialog', { name: 'Translation' })
    for (const value of ['Reference identity', 'Integrity', 'Security', 'Organization', 'Publication blocked', entry.publishBlockReason!])
      expect(within(dialog).getByText(value)).toBeInTheDocument()
    expect(within(dialog).queryByText('Review explicit approval')).not.toBeInTheDocument()
    expect(within(dialog).queryByText('Evidence, hashes & current location')).not.toBeInTheDocument()
    expect(await within(dialog).findByText(/Exact content copy/)).toBeInTheDocument()
    expect(location.hash).toContain('file=import-a%3Arom-a')
  })
  it('records advanced approval against the exact hash without automatic publication', async () => {
    const { fetcher } = setup({ advanced: true })
    fireEvent.click(await screen.findByRole('button', { name: entry.fileName }))
    const dialog = await screen.findByRole('dialog')
    fireEvent.click(within(dialog).getByText('Evidence, hashes & current location'))
    expect(within(dialog).getByText('Fixture studio')).toBeInTheDocument()
    fireEvent.click(within(dialog).getByRole('button', { name: 'Review explicit approval' }))
    expect(within(dialog).getByRole('button', { name: 'Record approval' })).toBeDisabled()
    fireEvent.change(within(dialog).getByLabelText('Approval reason'), { target: { value: 'Intentional translation patch' } })
    fireEvent.click(within(dialog).getByRole('button', { name: 'Record approval' }))
    await waitFor(() => expect(posted(fetcher, '/api/catalog/approve')).toEqual({
      ids: [entry.id], sha256: { [entry.id]: entry.sha256 }, reason: 'Intentional translation patch', confirm: true,
    }))
    expect(fetcher.mock.calls.some(([path]) => path === '/api/romm/publish')).toBe(false)
  })
  it('stores filters, sort and pagination in URLs and remembers display preferences', async () => {
    const { fetcher } = setup()
    await screen.findByRole('button', { name: entry.fileName })
    fireEvent.click(screen.getByRole('button', { name: 'Open library filters' }))
    fireEvent.change(screen.getByRole('combobox', { name: 'RomM sync' }), { target: { value: 'stale' } })
    fireEvent.change(screen.getByRole('combobox', { name: 'Exact copies' }), { target: { value: 'true' } })
    fireEvent.click(screen.getByRole('button', { name: 'Show results' }))
    fireEvent.change(screen.getByRole('combobox', { name: 'Sort library' }), { target: { value: 'size' } })
    await waitFor(() => expect(fetcher.mock.calls.some(([path]) => path.includes('syncStatus=stale') && path.includes('sort=size') && path.includes('duplicates=true'))).toBe(true))
    expect(location.hash).toContain('sort=size')
    fireEvent.click(screen.getByRole('button', { name: 'List view' }))
    expect(localStorage.getItem('romchecker-library-view')).toBe('table')
    expect(screen.getByRole('table')).toBeInTheDocument()
    expect(screen.queryByRole('columnheader', { name: 'Security' })).not.toBeInTheDocument()
  })
  it('defaults to cover grid without requiring metadata, with safe artwork and details', async () => {
    const { fetcher } = setup({ linked: true })
    await screen.findByRole('button', { name: entry.fileName })
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    const cover = await screen.findByRole('img', { name: `Cover for ${entry.fileName}` })
    expect(cover).toHaveAttribute('src', `/api/romm/artwork/${encodeURIComponent(entry.id)}`)
    fireEvent.error(cover)
    expect(screen.getByRole('img', { name: `No cover available for ${entry.fileName}` })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: entry.fileName }))
    const dialog = await screen.findByRole('dialog')
    expect(within(dialog).getByText('A descriptive game summary.')).toBeInTheDocument()
    expect(fetcher.mock.calls.some(([path]) => path.includes('untrusted.invalid'))).toBe(false)
  })
  it('restores a bookmarked game without needing the first catalog page', async () => {
    window.history.replaceState(null, '', '#/library?file=import-a%3Arom-a&page=2&q=Translation')
    setup()
    expect(await screen.findByRole('dialog', { name: 'Translation' })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Close dialog' }))
    expect(location.hash).toContain('page=2')
    expect(location.hash).not.toContain('file=')
  })
  it('never hides unsafe or incomplete findings behind an unchecked summary', () => {
    expect(finding({ ...entry, checkStatus: 'unchecked', security: 'Malicious' }).text).toBe('Needs attention')
    expect(finding({ ...entry, checkStatus: 'unchecked', security: 'Not checked', integrityStatus: '' }).text).toBe('Unchecked')
    expect(finding({ ...entry, holdReason: undefined, organization: 'Organized' }).text).toBe('Checked')
  })
  it('saves a named view and restores its filters without changing files', async () => {
    const { fetcher } = setup()
    await screen.findByRole('button', { name: entry.fileName })
    fireEvent.change(screen.getByRole('textbox', { name: 'Search library' }), { target: { value: 'Translation' } })
    await more()
    fireEvent.click(screen.getByRole('button', { name: 'Save this view' }))
    const dialog = await screen.findByRole('dialog')
    fireEvent.change(within(dialog).getByLabelText('View name'), { target: { value: 'Translations' } })
    fireEvent.click(within(dialog).getByRole('button', { name: 'Save view' }))
    expect(JSON.parse(localStorage.getItem('romchecker-saved-views')!)[0].query.q).toBe('Translation')
    fireEvent.change(screen.getByRole('textbox', { name: 'Search library' }), { target: { value: '' } })
    fireEvent.click(screen.getByRole('button', { name: 'Translations' }))
    expect(screen.getByRole('textbox', { name: 'Search library' })).toHaveValue('Translation')
    expect(fetcher.mock.calls.some(([, init]) => init?.method === 'POST')).toBe(false)
  })
  it('refreshes an open file in place without clearing an advanced review draft', async () => {
    const { fetcher, rendered, props } = setup({ advanced: true })
    fireEvent.click(await screen.findByRole('button', { name: entry.fileName }))
    const dialog = await screen.findByRole('dialog')
    fireEvent.click(within(dialog).getByRole('button', { name: 'Review explicit approval' }))
    const input = within(dialog).getByLabelText('Approval reason')
    fireEvent.change(input, { target: { value: 'Review in progress' } })
    const before = fetcher.mock.calls.filter(([path]) => path === '/api/catalog/' + encodeURIComponent(entry.id)).length
    rendered.rerender(<CatalogView {...props} jobs={[...props.jobs]} />)
    await waitFor(() => expect(fetcher.mock.calls.filter(([path]) => path === '/api/catalog/' + encodeURIComponent(entry.id)).length).toBeGreaterThan(before))
    expect(input).toHaveValue('Review in progress')
    expect(screen.getByRole('dialog')).toBe(dialog)
  })
})
