import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { expect, it, vi } from 'vitest'
import SettingsView from './SettingsView'
import type { Info } from '../../api'

it('shows baked build identity, downloads diagnostics and only checks updates on request', async () => {
  const fetcher = vi.fn(async (path: string) => {
    if (path === '/api/settings/integrations') return Response.json({ approvedSmbHosts: [] })
    if (path === '/api/settings') return Response.json({ console: 'All' })
    if (path === '/api/consoles') return Response.json([])
    if (path === '/api/updates/check') return Response.json({ status: 'available', message: 'A newer version is available.', version: '1.3.0-development.143', buildNumber: 143 })
    throw new Error(`Unexpected request: ${path}`)
  })
  vi.stubGlobal('fetch', fetcher)
  const info: Info = { name: 'ROM Checker', version: '1.3.0-development.142', commit: 'a'.repeat(40),
    buildNumber: 142, buildAttempt: 1, channel: 'development', builtUtc: '2026-10-27T20:00:00Z',
    workflowUrl: 'https://github.com/Phthisicus/ROM-Checker/actions/runs/123',
    schema: { version: 1, minimumSupported: 1, maximumSupported: 1 },
    library: '/library', pathBase: '', platform: 'Linux', antivirus: 'ClamAV' }
  render(<SettingsView advanced info={info} fail={vi.fn()} saved={vi.fn()} />)
  expect(await screen.findByText('142 / 1')).toBeInTheDocument()
  expect(screen.getByText('1 (supported 1-1)')).toBeInTheDocument()
  expect(screen.getByRole('link', { name: 'Download build diagnostics' })).toHaveAttribute('href', '/api/diagnostics/build')
  expect(fetcher.mock.calls.some(([path]) => path === '/api/updates/check')).toBe(false)
  fireEvent.click(screen.getByRole('button', { name: 'Check for updates' }))
  expect(await screen.findByRole('status')).toHaveTextContent('1.3.0-development.143')
})

it('surfaces failed update checks instead of reporting current', async () => {
  vi.stubGlobal('fetch', vi.fn(async (path: string) => {
    if (path === '/api/settings/integrations') return Response.json({ approvedSmbHosts: [] })
    if (path === '/api/settings') return Response.json({ console: 'All' })
    if (path === '/api/consoles') return Response.json([])
    return Response.json({ error: 'Update check failed.' }, { status: 502 })
  }))
  const fail = vi.fn()
  render(<SettingsView fail={fail} saved={vi.fn()} />)
  fireEvent.click(await screen.findByRole('button', { name: 'Check for updates' }))
  await waitFor(() => expect(fail).toHaveBeenCalledOnce())
  expect(screen.queryByRole('status')).not.toBeInTheDocument()
})
