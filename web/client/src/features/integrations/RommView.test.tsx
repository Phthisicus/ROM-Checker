import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import RommView, { PublishDialog } from './RommView'
import { defaultPublishRules } from './RommPublishRules'

describe('RomM integration', () => {
  it('tracks unsaved settings and warns on reload until a successful save', async () => {
    let rejectSave = true
    let config = { url: 'http://fixture:8080', configured: true, platformMappings: [], autoPublish: false }
    const fetcher = vi.fn(async (path: string, init?: RequestInit) => {
      if (path === '/api/romm/config' && init?.method === 'PUT') {
        if (rejectSave) return Response.json({ error: 'Connection unavailable' }, { status: 503 })
        config = { ...config, ...JSON.parse(init.body as string) }
        return new Response(null, { status: 204 })
      }
      if (path === '/api/romm/config') return Response.json(config)
      return Response.json([])
    })
    const fail = vi.fn()
    vi.stubGlobal('fetch', fetcher)
    render(<RommView fail={fail} />)
    await screen.findByText(/All settings saved/)
    expect(screen.getAllByRole('button', { name: 'Save RomM settings' })).toHaveLength(1)
    fireEvent.change(screen.getByLabelText('API token'), { target: { value: 'new-token' } })
    expect(screen.getByText(/Unsaved changes/)).toBeInTheDocument()
    const beforeSave = new Event('beforeunload', { cancelable: true })
    window.dispatchEvent(beforeSave)
    expect(beforeSave.defaultPrevented).toBe(true)
    fireEvent.click(screen.getByRole('button', { name: 'Save RomM settings' }))
    await waitFor(() => expect(fail).toHaveBeenCalledOnce())
    expect(screen.getByText(/Unsaved changes/)).toBeInTheDocument()
    expect(screen.getByLabelText('API token')).toHaveValue('new-token')
    rejectSave = false
    fireEvent.click(screen.getByRole('button', { name: 'Save RomM settings' }))
    await screen.findByText(/RomM settings saved/)
    expect(screen.getByText(/All settings saved/)).toBeInTheDocument()
    expect(screen.getByLabelText('API token')).toHaveValue('')
    const afterSave = new Event('beforeunload', { cancelable: true })
    window.dispatchEvent(afterSave)
    expect(afterSave.defaultPrevented).toBe(false)
  })

  it('previews draft publishing rules without saving or enabling publication, then persists them explicitly', async () => {
    let config = { url: 'http://fixture:8080', configured: true, platformMappings: [{ console: 'NES', platformId: 1, slug: 'nes' }], autoPublish: false, publishRules: defaultPublishRules }
    const fetcher = vi.fn(async (path: string, init?: RequestInit) => {
      if (path === '/api/romm/config' && init?.method === 'PUT') {
        config = { ...config, ...JSON.parse(init.body as string) }
        return new Response(null, { status: 204 })
      }
      if (path === '/api/romm/config') return Response.json(config)
      if (path === '/api/romm/publish-options') return Response.json({
        consoles: ['NES', 'SNES'], categories: ['Original', 'Translations'], regions: ['Europe', 'USA'],
        imports: [{ id: 'import-a', name: 'My verified collection' }],
      })
      if (path === '/api/romm/auto-publish/preview') {
        const request = JSON.parse(init!.body as string)
        return Response.json({
          total: 26, matched: 20, ready: 17, excluded: 6, linked: 1, pending: 1, failed: 1,
          page: request.page, size: 25, items: [{ id: `group-${request.page}`, name: `Game page ${request.page}`,
            files: 2, console: 'NES', status: 'excluded', reason: 'A reference match is required.',
            regions: [{ values: ['Europe'], source: 'dat-title' }] }],
        })
      }
      return Response.json([])
    })
    vi.stubGlobal('fetch', fetcher)
    render(<RommView fail={vi.fn()} />)
    await screen.findByRole('radio', { name: 'Selected imports' })
    fireEvent.click(screen.getByRole('radio', { name: 'Reference matches only (approval is not enough)' }))
    for (const [label, value] of [['Consoles', 'NES'], ['Game categories', 'Original'], ['Regions', 'Europe'], ['Imports', 'import-a']]) {
      const group = within(screen.getByRole('group', { name: label }))
      fireEvent.click(group.getByRole('radio', { name: `Selected ${label.toLowerCase()}` }))
      fireEvent.click(await group.findByRole('checkbox', { name: value === 'import-a' ? 'My verified collection' : value }))
    }
    fireEvent.click(screen.getByRole('checkbox', { name: 'Allow filename-inferred regions' }))
    const rules = { ...defaultPublishRules, referenceRequirement: 'matched', consoles: ['NES'], categories: ['Original'],
      regions: ['Europe'], batchIds: ['import-a'], allowFilenameRegions: true }
    fireEvent.click(screen.getByRole('button', { name: 'Preview draft publishing rules' }))
    expect(await screen.findByText(/A reference match is required\./)).toBeInTheDocument()
    expect(screen.getByText('Europe (dat-title)')).toBeInTheDocument()
    expect(screen.getByText(/26 games · 20 match rules · 17 ready/)).toBeInTheDocument()
    expect(JSON.parse(fetcher.mock.calls.find(([path]) => path === '/api/romm/auto-publish/preview')![1]!.body as string))
      .toEqual({ rules, page: 1, size: 25 })
    expect(fetcher.mock.calls.some(([, init]) => init?.method === 'PUT')).toBe(false)
    expect(config.autoPublish).toBe(false)
    fireEvent.click(screen.getByRole('button', { name: 'Next preview page' }))
    await screen.findByText('Game page 2')
    fireEvent.click(within(screen.getByRole('group', { name: 'Regions' })).getByRole('button', { name: 'Clear selection' }))
    expect(screen.queryByText('Game page 2')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Save RomM settings' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Preview draft publishing rules' })).toBeDisabled()
    fireEvent.click(screen.getByRole('radio', { name: 'Any regions' }))
    fireEvent.click(screen.getByRole('button', { name: 'Save RomM settings' }))
    await screen.findByText(/RomM settings saved/)
    expect(config.publishRules).toEqual({ ...rules, regions: [] })
    expect(config.autoPublish).toBe(false)
  })
  it('keeps unavailable selections and reports preview and option errors with retry controls', async () => {
    let optionsFailed = true
    let previewFailed = true
    const fail = vi.fn()
    const fetcher = vi.fn(async (path: string) => {
      if (path === '/api/romm/config') return Response.json({ url: 'http://fixture:8080', configured: true,
        platformMappings: [], autoPublish: false, publishRules: { ...defaultPublishRules, batchIds: ['removed-import'] } })
      if (path === '/api/romm/publish-options') {
        if (optionsFailed) return Response.json({ error: 'Import storage unavailable' }, { status: 503 })
        return Response.json({ consoles: [], regions: [], categories: [], imports: [] })
      }
      if (path === '/api/romm/auto-publish/preview') {
        if (previewFailed) return Response.json({ error: 'Invalid publishing rules' }, { status: 400 })
        return Response.json({ total: 0, matched: 0, ready: 0, excluded: 0, linked: 0, pending: 0, failed: 0, page: 1, size: 25, items: [] })
      }
      return Response.json([])
    })
    vi.stubGlobal('fetch', fetcher)
    render(<RommView fail={fail} />)
    expect(await screen.findByText('Import storage unavailable')).toBeInTheDocument()
    expect(screen.getByRole('checkbox', { name: 'removed-import (not currently available)' })).toBeChecked()
    optionsFailed = false
    fireEvent.click(screen.getByRole('button', { name: 'Retry rule options' }))
    await waitFor(() => expect(screen.queryByText('Import storage unavailable')).not.toBeInTheDocument())
    fireEvent.click(screen.getByRole('button', { name: 'Preview draft publishing rules' }))
    expect(await screen.findByText('Invalid publishing rules')).toBeInTheDocument()
    previewFailed = false
    fireEvent.click(screen.getByRole('button', { name: 'Preview draft publishing rules' }))
    expect(await screen.findByText(/0 games · 0 match rules/)).toBeInTheDocument()
    expect(screen.queryByText('Invalid publishing rules')).not.toBeInTheDocument()
    expect(fail).not.toHaveBeenCalled()
  })
  it('requires explicit auto-publish opt-in and preserves the saved policy on subsequent saves', async () => {
    let config = { url: 'http://fixture:8080', configured: true, platformMappings: [], autoPublish: false }
    const fetcher = vi.fn(async (path: string, init?: RequestInit) => {
      if (path === '/api/romm/config' && init?.method === 'PUT') {
        config = { ...config, ...JSON.parse(init.body as string) }
        return new Response(null, { status: 204 })
      }
      if (path === '/api/romm/config') return Response.json(config)
      return Response.json([])
    })
    vi.stubGlobal('fetch', fetcher)
    render(<RommView fail={vi.fn()} />)
    const checkbox = await screen.findByRole('checkbox', { name: 'Automatically publish eligible verified copies' })
    expect(checkbox).not.toBeChecked()
    fireEvent.click(checkbox)
    expect(screen.getByRole('dialog', { name: 'Enable automatic publication?' })).toBeInTheDocument()
    expect(checkbox).not.toBeChecked()
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Cancel' }))
    expect(checkbox).not.toBeChecked()
    fireEvent.click(checkbox)
    fireEvent.click(screen.getByRole('button', { name: 'Confirm auto-publish opt-in' }))
    expect(checkbox).toBeChecked()
    expect(fetcher.mock.calls.some(([, init]) => init?.method === 'PUT')).toBe(false)
    fireEvent.click(screen.getByRole('button', { name: 'Save RomM settings' }))
    await screen.findByText(/RomM settings saved/)
    expect(config.autoPublish).toBe(true)
    fireEvent.change(screen.getByLabelText('RomM URL'), { target: { value: 'http://fixture:8081' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save RomM settings' }))
    await waitFor(() => expect(config.url).toBe('http://fixture:8081'))
    expect(config.autoPublish).toBe(true)
    fireEvent.click(checkbox)
    fireEvent.click(screen.getByRole('button', { name: 'Save RomM settings' }))
    await waitFor(() => expect(config.autoPublish).toBe(false))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })
  it('previews blocked reasons and sends only explicitly confirmed eligible files', async () => {
    const published = vi.fn()
    const fetcher = vi.fn(async (path: string, _init?: RequestInit) => Response.json(path === '/api/romm/preview'
      ? { selected: 2, eligible: [{ id: 'good', fileName: 'Verified.nes' }], blocked: [{ id: 'unchecked', fileName: 'Unchecked.nes', reason: 'No completed checks' }] }
      : { id: 'publish-job' }))
    vi.stubGlobal('fetch', fetcher)
    render(<PublishDialog ids={['good', 'unchecked']} close={vi.fn()} fail={vi.fn()} published={published} />)
    expect(await screen.findByText('No completed checks', { exact: false })).toBeInTheDocument()
    const publish = screen.getByRole('button', { name: 'Publish eligible copies' })
    expect(publish).toBeDisabled()
    fireEvent.click(screen.getByRole('checkbox', { name: /Publish these 1 eligible copies/ }))
    fireEvent.click(publish)
    await waitFor(() => expect(published).toHaveBeenCalledOnce())
    const request = fetcher.mock.calls.find(([path]) => path === '/api/romm/publish')!
    expect(JSON.parse((request[1] as RequestInit).body as string)).toEqual({ ids: ['good'], confirm: true })
  })
  it('does not offer publication when all selected files are blocked', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ selected: 1, eligible: [], blocked: [{ id: 'unchecked', fileName: 'Unchecked.nes', reason: 'Unchecked' }] })))
    render(<PublishDialog ids={['unchecked']} close={vi.fn()} fail={vi.fn()} published={vi.fn()} />)
    expect(await screen.findByText('Unchecked.nes')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('checkbox'))
    expect(screen.getByRole('button', { name: 'Publish eligible copies' })).toBeDisabled()
  })
  it('never echoes stored credentials, preserves a blank token, and explains the shared-library mount', async () => {
    const fail = vi.fn()
    const config = { url: 'http://romm:8080', configured: true, platformMappings: [{ console: 'NES', platformId: 1, slug: 'nes' }], autoPublish: false, exportRoot: 'D:\\exports\\romm-library', transport: 'shared-library' }
    const fetcher = vi.fn(async (path: string, init?: RequestInit) => {
      if (path === '/api/romm/config') return init?.method === 'PUT' ? new Response(null, { status: 204 }) : Response.json(config)
      if (path === '/api/romm/jobs' || path === '/api/romm/links') return Response.json([])
      if (path === '/api/romm/test' && init?.method === 'POST') return Response.json({ version: '4.0', capabilities: { scan: true }, platforms: [{ id: 1, name: 'NES', slug: 'nes' }] })
      throw new Error(`Unexpected ${path}`)
    })
    vi.stubGlobal('fetch', fetcher)
    render(<RommView fail={fail} />)
    const token = await screen.findByLabelText('API token')
    expect(token).toHaveAttribute('type', 'password')
    expect(token).toHaveValue('')
    expect(screen.getByText('/romm/library')).toBeInTheDocument()
    expect(screen.getByText(config.exportRoot)).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Save RomM settings' }))
    await screen.findByText(/RomM settings saved/)
    const saved = fetcher.mock.calls.find(([path, init]) => path === '/api/romm/config' && init?.method === 'PUT')!
    expect(JSON.parse(saved[1]!.body as string)).not.toHaveProperty('token')
    expect(JSON.parse(saved[1]!.body as string).autoPublish).toBe(false)
    fireEvent.click(screen.getByRole('button', { name: 'Test saved connection' }))
    expect(await screen.findByText(/Connected · RomM 4.0/)).toBeInTheDocument()
    expect(within(screen.getByRole('combobox', { name: 'RomM platform 1' })).getByRole('option', { name: 'NES (nes)' })).toBeInTheDocument()
    expect(fail).not.toHaveBeenCalled()
  })
  it('requires confirmation for remote imports and metadata refresh, and retries failed integration work', async () => {
    const fetcher = vi.fn(async (path: string, init?: RequestInit) => {
      if (init?.method === 'POST' && path !== '/api/romm/roms') return Response.json({ id: 'queued' })
      if (path === '/api/romm/config') return Response.json({ url: 'http://fixture:8080', configured: true, platformMappings: [], autoPublish: false })
      if (path.startsWith('/api/romm/roms?')) return Response.json({ items: [{ id: 12, name: 'Remote fixture.nes', platformId: 1 }], total: 1 })
      if (path === '/api/romm/links') return Response.json([{ entryId: 'local:fixture', rommId: 12, status: 'linked', metadata: { name: 'Remote fixture' } }])
      if (path === '/api/romm/jobs') return Response.json([{ id: 'failed-job', kind: 'publish', automatic: true, status: 'completed-with-errors', created: '2026-10-27T12:00:00Z', items: [{ entryId: 'local:fixture', status: 'failed', error: 'Fixture failure' }] }])
      throw new Error(`Unexpected ${path}`)
    })
    vi.stubGlobal('fetch', fetcher)
    render(<RommView fail={vi.fn()} />)
    fireEvent.click(await screen.findByRole('button', { name: 'Browse RomM' }))
    expect(screen.getByText('Automatic publication')).toBeInTheDocument()
    fireEvent.click(await screen.findByRole('checkbox', { name: /Remote fixture.nes/ }))
    fireEvent.click(screen.getByRole('button', { name: 'Import 1 remote ROMs…' }))
    expect(fetcher.mock.calls.some(([path]) => path === '/api/romm/import')).toBe(false)
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Confirm import' }))
    await screen.findByText(/Remote import queued/)
    const imported = fetcher.mock.calls.find(([path]) => path === '/api/romm/import')!
    expect(JSON.parse(imported[1]!.body as string)).toEqual({ romIds: [12], confirm: true })
    expect(screen.queryByText('Raw metadata')).not.toBeInTheDocument()
    fireEvent.click(screen.getByRole('checkbox', { name: /Remote fixture · linked/ }))
    fireEvent.click(screen.getByRole('button', { name: /Refresh selected metadata/ }))
    fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: 'Confirm metadata refresh' }))
    await screen.findByText(/Metadata refresh queued/)
    const metadata = fetcher.mock.calls.find(([path]) => path === '/api/romm/metadata')!
    expect(JSON.parse(metadata[1]!.body as string)).toEqual({ ids: ['local:fixture'], confirm: true })
    fireEvent.click(screen.getByRole('button', { name: 'Retry failed items' }))
    await screen.findByText(/Retry queued/)
    expect(fetcher.mock.calls.some(([path, init]) => path === '/api/romm/jobs/failed-job/retry' && init?.method === 'POST')).toBe(true)
  })
})
