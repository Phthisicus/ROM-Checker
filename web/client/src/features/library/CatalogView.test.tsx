import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import type { Settings } from '../../api'
import CatalogView, { type CatalogEntry, type CatalogPage } from './CatalogView'

const entry: CatalogEntry = {
  id: 'import-a:rom-a', batchId: 'import-a', collectionId: 'rom-a', fileName: 'Translation.nes',
  console: 'NES', consoleName: 'Nintendo Entertainment System', category: 'Translation', relativePath: 'NES\\Translation.nes',
  length: 1024, sha256: 'abc123', checkedUtc: '2026-10-27T12:00:00Z', checkStatus: 'checked',
  referenceStatus: 'modified', integrityStatus: 'Valid', security: 'Clean', organization: 'Held',
  publishEligible: false, publishBlockReason: 'Explicit approval required', evidence: { Publisher: 'Fixture studio', DatMatch: 'No match' },
  syncStatus: 'not-published',
}
const catalog: CatalogPage = {
  items: [entry], total: 3, filtered: 2, page: 1, size: 1, ids: [entry.id, 'import-b:rom-b'],
  groups: [{ key: 'NES', name: entry.consoleName, total: 2, checked: 1, attention: 1, ids: [entry.id, 'import-b:rom-b'] }],
  categories: ['Original', 'Translation'], counts: { checked: 1, attention: 1, eligible: 0 },
}
const settings = { autoDat: false, hasheous: 'Off', onlineCheck: 'Off', identifyUnknown: false, defenderScan: true } as Settings
function setup(online = false, linked = false) {
  const fail = vi.fn()
  const changed = vi.fn().mockResolvedValue(undefined)
  const fetcher = vi.fn(async (path: string, init?: RequestInit) => {
    if (path === '/api/romm/links') return Response.json(linked ? [{ entryId: entry.id, rommId: 7, status: 'linked', metadata: { name: 'Translated adventure', summary: 'A descriptive game summary.', url_cover: 'https://untrusted.invalid/cover?token=never-fetch', metadatum: { genres: ['Adventure'], companies: [{ name: 'Fixture studio' }] } } }] : [])
    if (path === '/api/settings') return Response.json({ ...settings, autoDat: online })
    if (path.includes('/history')) return Response.json([{ kind: 'checked', detail: 'Fixture evidence' }])
    if (path === '/api/catalog/verify' || path === '/api/catalog/approve') return Response.json({ id: 'queued-run' })
    if (path === '/api/catalog' || path.startsWith('/api/catalog?')) return Response.json(path === '/api/catalog' ? { ...catalog, ids: [...catalog.ids, 'import-c:rom-c'] } : catalog)
    throw new Error(`Unexpected request ${path} ${init?.method}`)
  })
  vi.stubGlobal('fetch', fetcher)
  render(<CatalogView fail={fail} imports={vi.fn()} jobs={[]} progress={null} changed={changed} />)
  return { fetcher, fail, changed }
}
const posted = (fetcher: ReturnType<typeof setup>['fetcher'], path: string) => {
  const call = fetcher.mock.calls.find(([value, init]) => value === path && init?.method === 'POST')
  return call ? JSON.parse(call[1]!.body as string) : undefined
}
describe('canonical library', () => {
  it('distinguishes visible-page and all-filtered selection across imports', async () => {
    const { fetcher } = setup()
    await screen.findByRole('button', { name: entry.fileName })
    fireEvent.click(screen.getByRole('button', { name: 'Select visible page' }))
    expect(screen.getByText('1 selected')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Select all 2 filtered' }))
    expect(screen.getByText('2 selected')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Verify selection' }))
    const dialog = await screen.findByRole('dialog', { name: 'Verify 2 ROMs' })
    fireEvent.click(within(dialog).getByRole('button', { name: 'Queue verification' }))
    await waitFor(() => expect(posted(fetcher, '/api/catalog/verify')).toEqual(expect.objectContaining({ ids: catalog.ids, confirm: true, organize: true })))
    expect(posted(fetcher, '/api/catalog/verify')).not.toHaveProperty('batchId')
    expect(await screen.findByText(/Verification queued/)).toBeInTheDocument()
  })
  it('requires informed consent when online checks are enabled', async () => {
    const { fetcher } = setup(true)
    await screen.findByRole('button', { name: entry.fileName })
    fireEvent.click(screen.getByRole('button', { name: 'Verify console' }))
    const dialog = await screen.findByRole('dialog')
    const queue = within(dialog).getByRole('button', { name: 'Queue verification' })
    expect(queue).toBeDisabled()
    fireEvent.click(within(dialog).getByRole('checkbox', { name: /I consent/ }))
    expect(queue).toBeEnabled()
    fireEvent.change(within(dialog).getByLabelText('After verification'), { target: { value: 'false' } })
    fireEvent.click(queue)
    await waitFor(() => expect(posted(fetcher, '/api/catalog/verify')?.organize).toBe(false))
  })
  it('uses explicit global IDs for whole-library verification, not the current filters or previous import', async () => {
    const { fetcher } = setup()
    await screen.findByRole('button', { name: entry.fileName })
    fireEvent.change(screen.getByRole('combobox', { name: 'Category' }), { target: { value: 'Translation' } })
    fireEvent.click(screen.getByRole('button', { name: 'Verify entire library' }))
    const dialog = await screen.findByRole('dialog', { name: 'Verify 3 ROMs' })
    fireEvent.click(within(dialog).getByRole('button', { name: 'Queue verification' }))
    await waitFor(() => expect(posted(fetcher, '/api/catalog/verify')?.ids).toEqual([...catalog.ids, 'import-c:rom-c']))
  })
  it('keeps reference, integrity, security, organization, and remote sync separate', async () => {
    setup()
    await screen.findByRole('button', { name: entry.fileName })
    const table = screen.getByRole('table')
    for (const name of ['Checks', 'Reference', 'Integrity', 'Security', 'Organization', 'RomM sync', 'Publication'])
      expect(within(table).getByRole('columnheader', { name })).toBeInTheDocument()
    expect(within(table).getByText('modified')).toBeInTheDocument()
    expect(within(table).getByText('Clean')).toBeInTheDocument()
    expect(within(table).getByText('Blocked')).toBeInTheDocument()
  })
  it('records approval with a reason and the exact reviewed hash, without automatic publication', async () => {
    const { fetcher } = setup()
    fireEvent.click(await screen.findByRole('button', { name: entry.fileName }))
    const dialog = await screen.findByRole('dialog', { name: entry.fileName })
    expect(within(dialog).getByText('Fixture studio')).toBeInTheDocument()
    expect(await within(dialog).findByText(/Fixture evidence/)).toBeInTheDocument()
    fireEvent.click(within(dialog).getByRole('button', { name: 'Review explicit approval' }))
    expect(within(dialog).getByRole('button', { name: 'Record approval' })).toBeDisabled()
    fireEvent.change(within(dialog).getByLabelText('Approval reason'), { target: { value: 'Intentional translation patch' } })
    fireEvent.click(within(dialog).getByRole('button', { name: 'Record approval' }))
    await waitFor(() => expect(posted(fetcher, '/api/catalog/approve')).toEqual({
      ids: [entry.id], sha256: { [entry.id]: entry.sha256 }, reason: 'Intentional translation patch', confirm: true,
    }))
    expect(fetcher.mock.calls.some(([path]) => path === '/api/romm/publish')).toBe(false)
  })
  it('omits empty optional query values and keeps sync filtering server-scoped', async () => {
    const { fetcher } = setup()
    await screen.findByRole('button', { name: entry.fileName })
    const initial = fetcher.mock.calls.find(([path]) => path.startsWith('/api/catalog?'))![0]
    expect(initial).toBe('/api/catalog?page=1')
    fireEvent.change(screen.getByRole('combobox', { name: 'RomM sync' }), { target: { value: 'stale' } })
    await waitFor(() => expect(fetcher.mock.calls.some(([path]) => path === '/api/catalog?syncStatus=stale&page=1')).toBe(true))
    fireEvent.click(screen.getByRole('checkbox', { name: 'Needs attention' }))
    await waitFor(() => expect(fetcher.mock.calls.some(([path]) => path.includes('attention=true') && path.includes('syncStatus=stale'))).toBe(true))
    fireEvent.click(screen.getByRole('button', { name: 'Clear filters' }))
    await waitFor(() => expect(screen.getByRole('combobox', { name: 'RomM sync' })).toHaveValue(''))
    expect(fetcher.mock.calls.filter(([path]) => path.startsWith('/api/catalog?')).every(([path]) => !path.includes('attention=&'))).toBe(true)
  })
  it('defaults to table, enables optional covers for linked metadata, and shows safe descriptive details', async () => {
    const { fetcher } = setup(false, true)
    await screen.findByRole('button', { name: entry.fileName })
    expect(screen.getByRole('table')).toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('button', { name: 'Cover grid' })).toBeEnabled())
    fireEvent.click(screen.getByRole('button', { name: 'Cover grid' }))
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
    const cover = screen.getByRole('img', { name: `Cover for ${entry.fileName}` })
    expect(cover).toHaveAttribute('src', `/api/romm/artwork/${encodeURIComponent(entry.id)}`)
    fireEvent.error(cover)
    expect(screen.getByRole('img', { name: `No cover available for ${entry.fileName}` })).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: entry.fileName }))
    const dialog = screen.getByRole('dialog')
    expect(within(dialog).getByText('Translated adventure')).toBeInTheDocument()
    expect(within(dialog).getByText('A descriptive game summary.')).toBeInTheDocument()
    expect(within(dialog).getByText('Adventure')).toBeInTheDocument()
    expect(fetcher.mock.calls.some(([path]) => path.includes('untrusted.invalid'))).toBe(false)
  })
  it('keeps cover grid unavailable without linked metadata', async () => {
    setup()
    await screen.findByRole('button', { name: entry.fileName })
    expect(screen.getByRole('button', { name: 'Cover grid' })).toBeDisabled()
  })
})
