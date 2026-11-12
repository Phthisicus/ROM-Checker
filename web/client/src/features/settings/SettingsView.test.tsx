import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import SettingsView from './SettingsView'
import type { Info } from '../../api'

const details = {
  system: { scope: 'Container', operatingSystem: 'Ubuntu', architecture: 'X64', runtime: '.NET 10',
    startedUtc: '2026-11-11T12:00:00Z', uptimeSeconds: 3660 },
  release: { notes: 'Installed release changes.', upgradeNotes: [], limitations: [] },
  paths: { library: '/library', data: '/data', engine: '/app', pathBase: '' },
  updates: { enabled: true, scheduled: false }
}

it('shows baked build identity, downloads diagnostics and only checks updates on request', async () => {
  const fetcher = vi.fn(async (path: string) => {
    if (path === '/api/settings/integrations') return Response.json({ approvedSmbHosts: [] })
    if (path === '/api/settings') return Response.json({ console: 'All' })
    if (path === '/api/consoles') return Response.json([])
    if (path === '/api/system') return Response.json(details)
    if (path === '/api/updates/status') return Response.json({ status: 'unavailable', message: 'No update check has run yet.' })
    if (path === '/api/updates/check') return Response.json({ status: 'available', message: 'A newer version is available.',
      result: { status: 'available', version: '1.3.0-development.143', buildNumber: 143 } })
    throw new Error(`Unexpected request: ${path}`)
  })
  vi.stubGlobal('fetch', fetcher)
  const info: Info = { name: 'ROM Checker', version: '1.3.0-development.142', commit: 'a'.repeat(40),
    buildNumber: 142, buildAttempt: 1, channel: 'development', builtUtc: '2026-10-27T20:00:00Z',
    workflowUrl: 'https://github.com/Phthisicus/ROM-Checker/actions/runs/123',
    schema: { version: 1, minimumSupported: 1, maximumSupported: 1 },
    library: '/library', pathBase: '', platform: 'Linux', antivirus: 'ClamAV' }
  render(<SettingsView info={info} fail={vi.fn()} saved={vi.fn()} />)
  expect(await screen.findByText('142 / 1')).toBeInTheDocument()
  expect(screen.getByText('1 (supported 1-1)')).toBeInTheDocument()
  expect(await screen.findByText('Installed release changes.')).toBeInTheDocument()
  expect(screen.getByText('.NET 10')).toBeInTheDocument()
  expect(screen.getByText('1h 1m')).toBeInTheDocument()
  expect(screen.getByRole('link', { name: 'Download build diagnostics' })).toHaveAttribute('href', '/api/diagnostics/build')
  expect(fetcher.mock.calls.some(([path]) => path === '/api/updates/check')).toBe(false)
  fireEvent.click(screen.getByRole('button', { name: 'Check for updates' }))
  await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('1.3.0-development.143'))
})

it('surfaces failed update checks instead of reporting current', async () => {
  vi.stubGlobal('fetch', vi.fn(async (path: string) => {
    if (path === '/api/settings/integrations') return Response.json({ approvedSmbHosts: [] })
    if (path === '/api/settings') return Response.json({ console: 'All' })
    if (path === '/api/consoles') return Response.json([])
    if (path === '/api/system') return Response.json(details)
    if (path === '/api/updates/status') return Response.json({ status: 'unavailable', message: 'Not checked.' })
    return Response.json({ error: 'Update check failed.' }, { status: 502 })
  }))
  const fail = vi.fn()
  render(<SettingsView fail={fail} saved={vi.fn()} />)
  fireEvent.click(await screen.findByRole('button', { name: 'Check for updates' }))
  await waitFor(() => expect(fail).toHaveBeenCalledOnce())
  expect(screen.getByRole('status')).not.toHaveTextContent(/current|up to date/i)
})

it('retains a stale result and exposes upgrade requirements when the next check fails', async () => {
  vi.stubGlobal('fetch', vi.fn(async (path: string) => {
    if (path === '/api/settings/integrations') return Response.json({ approvedSmbHosts: [] })
    if (path === '/api/settings') return Response.json({ console: 'All' })
    if (path === '/api/consoles') return Response.json([])
    if (path === '/api/system') return Response.json(details)
    return Response.json({ status: 'error', message: 'Registry unavailable.', stale: true,
      lastSuccessUtc: '2026-11-11T12:00:00Z',
      result: { status: 'available', version: '1.4.0', schemaCompatible: false,
        release: { ...details.release, notes: 'New release changes.', upgradeNotes: ['Restore a matching backup to roll back.'], limitations: ['Requires shared storage.'] } } })
  }))
  render(<SettingsView fail={vi.fn()} saved={vi.fn()} />)
  expect(await screen.findByRole('status')).toHaveTextContent('stale')
  expect(screen.getByText('Restore a matching backup to roll back.')).toBeInTheDocument()
  expect(screen.getByText('Requires shared storage.')).toBeInTheDocument()
  expect(screen.getByText('New release changes.')).toBeInTheDocument()
})
