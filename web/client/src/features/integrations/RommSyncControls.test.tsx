import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import RommView from './RommView'
import { defaultSyncSettings } from './RommSyncControls'

describe('RomM inbound synchronization', () => {
  it('requires explicit platform selection and opt-in, then saves the schedule without publishing', async () => {
    let config = { url: 'http://fixture:8080', configured: true, autoPublish: false,
      platformMappings: [{ console: 'NES', platformId: 1, slug: 'nes' }, { console: 'SNES', platformId: 2, slug: 'snes' }],
      sync: defaultSyncSettings }
    const fetcher = vi.fn(async (path: string, init?: RequestInit) => {
      if (path === '/api/romm/config') {
        if (init?.method === 'PUT') {
          config = { ...config, ...JSON.parse(init.body as string) }
          return new Response(null, { status: 204 })
        }
        return Response.json(config)
      }
      if (path === '/api/romm/publish-options') return Response.json({ consoles: [], regions: [], categories: [], imports: [] })
      return Response.json([])
    })
    vi.stubGlobal('fetch', fetcher)
    render(<RommView fail={vi.fn()} />)
    const auto = await screen.findByRole('checkbox', { name: 'Automatically import new RomM games from selected platforms' })
    fireEvent.click(auto)
    expect(screen.getByRole('button', { name: 'Confirm inbound opt-in' })).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    fireEvent.click(screen.getByRole('checkbox', { name: 'NES (RomM platform 1)' }))
    fireEvent.click(auto)
    expect(auto).not.toBeChecked()
    fireEvent.click(screen.getByRole('button', { name: 'Confirm inbound opt-in' }))
    expect(auto).toBeChecked()
    fireEvent.click(screen.getByRole('checkbox', { name: 'Refresh linked metadata and detect conflicts on a schedule' }))
    fireEvent.change(screen.getByLabelText('Sync interval (minutes)'), { target: { value: '30' } })
    expect(fetcher.mock.calls.some(([, init]) => init?.method === 'PUT')).toBe(false)
    fireEvent.click(screen.getByRole('button', { name: 'Save RomM settings' }))
    await screen.findByText(/RomM settings saved/)
    expect(config.sync).toEqual({ autoImport: true, platformIds: [1], refreshMetadata: true, intervalMinutes: 30 })
    expect(config.autoPublish).toBe(false)
    expect(screen.getByRole('checkbox', { name: 'SNES (RomM platform 2)' })).not.toBeChecked()
    fireEvent.change(screen.getByLabelText('RomM URL'), { target: { value: 'http://fixture:8081' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save RomM settings' }))
    await waitFor(() => expect(config.url).toBe('http://fixture:8081'))
    expect(config.sync.platformIds).toEqual([1])
    fireEvent.click(screen.getByRole('checkbox', { name: 'NES (RomM platform 1)' }))
    expect(screen.getByRole('button', { name: 'Save RomM settings' })).toBeDisabled()
    expect(screen.getByRole('alert')).toHaveTextContent('Select at least one platform')
    fireEvent.click(auto)
    expect(screen.getByRole('button', { name: 'Save RomM settings' })).toBeEnabled()
    expect(config.sync.platformIds).toEqual([1])
  })

  it('confirms saved sync and conflict actions without sending draft settings or deleting files', async () => {
    let conflicts = [
      { rommId: 12, name: 'Changed game', status: 'conflict', detail: 'Remote files changed', updated: '2026-11-02T12:00:00Z' },
      { rommId: 13, name: 'Missing game', status: 'conflict', detail: 'Remote file missing', updated: '2026-11-02T12:00:00Z' },
    ]
    const fetcher = vi.fn(async (path: string, init?: RequestInit) => {
      if (path === '/api/romm/config') return Response.json({ url: 'http://fixture:8080', configured: true, autoPublish: false,
        platformMappings: [{ console: 'NES', platformId: 1, slug: 'nes' }], sync: defaultSyncSettings })
      if (path === '/api/romm/publish-options') return Response.json({ consoles: [], regions: [], categories: [], imports: [] })
      if (path === '/api/romm/conflicts') return Response.json(conflicts)
      if (path === '/api/romm/conflicts/12') {
        conflicts = conflicts.map(value => value.rommId === 12 ? { ...value, status: 'ignored' } : value)
        return new Response(null, { status: 204 })
      }
      if (init?.method === 'POST') return Response.json({ id: 'queued' })
      return Response.json([])
    })
    vi.stubGlobal('fetch', fetcher)
    render(<RommView fail={vi.fn()} />)
    await screen.findByText('Changed game')
    fireEvent.change(screen.getByLabelText('Sync interval (minutes)'), { target: { value: '5' } })
    fireEvent.click(screen.getByRole('button', { name: 'Run saved synchronization' }))
    expect(fetcher.mock.calls.some(([path]) => path === '/api/romm/sync')).toBe(false)
    fireEvent.click(screen.getByRole('button', { name: 'Confirm saved sync' }))
    await screen.findByText(/Work queued/)
    expect(JSON.parse(fetcher.mock.calls.find(([path]) => path === '/api/romm/sync')![1]!.body as string)).toEqual({ ids: [], confirm: true })
    fireEvent.click(within(screen.getByText('Changed game').closest('article')!).getByRole('button', { name: 'Keep local copy' }))
    fireEvent.click(screen.getByRole('button', { name: 'Confirm keep local' }))
    await screen.findByText(/Local copy kept/)
    expect(JSON.parse(fetcher.mock.calls.find(([path]) => path === '/api/romm/conflicts/12')![1]!.body as string))
      .toEqual({ action: 'keep-local', confirm: true })
    fireEvent.click(screen.getByRole('button', { name: 'Import remote as separate copy' }))
    expect(fetcher.mock.calls.some(([path]) => path === '/api/romm/import')).toBe(false)
    fireEvent.click(screen.getByRole('button', { name: 'Confirm separate import' }))
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(JSON.parse(fetcher.mock.calls.find(([path]) => path === '/api/romm/import')![1]!.body as string))
      .toEqual({ romIds: [13], confirm: true, importChanged: true })
    expect(fetcher.mock.calls.some(([, init]) => init?.method === 'PUT' || init?.method === 'DELETE')).toBe(false)
  })

  it('surfaces sync errors and permits retry without losing the conflict list', async () => {
    let fail = true
    const fetcher = vi.fn(async (path: string, init?: RequestInit) => {
      if (path === '/api/romm/config') return Response.json({ url: 'http://fixture:8080', configured: true,
        autoPublish: false, platformMappings: [], sync: { ...defaultSyncSettings, refreshMetadata: true } })
      if (path === '/api/romm/publish-options') return Response.json({ consoles: [], regions: [], categories: [], imports: [] })
      if (path === '/api/romm/sync' && init?.method === 'POST')
        return fail ? Response.json({ error: 'RomM is unreachable' }, { status: 503 }) : Response.json({ id: 'queued' })
      return Response.json([])
    })
    vi.stubGlobal('fetch', fetcher)
    render(<RommView fail={vi.fn()} />)
    fireEvent.click(await screen.findByRole('button', { name: 'Run saved synchronization' }))
    fireEvent.click(screen.getByRole('button', { name: 'Confirm saved sync' }))
    expect(await screen.findByText('RomM is unreachable')).toBeInTheDocument()
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    fail = false
    fireEvent.click(screen.getByRole('button', { name: 'Confirm saved sync' }))
    await screen.findByText(/Work queued/)
    expect(screen.queryByText('RomM is unreachable')).not.toBeInTheDocument()
  })
})
