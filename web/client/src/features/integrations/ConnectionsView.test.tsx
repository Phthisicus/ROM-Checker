import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import ConnectionsView from './ConnectionsView'

describe('Connections overview', () => {
  it('loads configuration status without mounting RomM settings or polling operational APIs', async () => {
    const fetcher = vi.fn(async () => Response.json({ configured: true }))
    vi.stubGlobal('fetch', fetcher)
    render(<ConnectionsView fail={vi.fn()} />)
    expect(await screen.findByText('Configured')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Open RomM settings' })).toHaveAttribute('href', '#/settings/connections/romm')
    expect(screen.queryByLabelText('API token')).not.toBeInTheDocument()
    expect(fetcher.mock.calls).toEqual([['/api/romm/config', expect.anything()]])
  })

  it('shows a retryable status error and still allows opening integration settings', async () => {
    let failed = true
    vi.stubGlobal('fetch', vi.fn(async () => failed
      ? Response.json({ error: 'Configuration unavailable' }, { status: 503 }) : Response.json({ configured: false })))
    render(<ConnectionsView fail={vi.fn()} />)
    expect(await screen.findByRole('alert')).toHaveTextContent('Configuration unavailable')
    expect(screen.getByRole('link', { name: 'Open RomM settings' })).toBeInTheDocument()
    failed = false
    fireEvent.click(screen.getByRole('button', { name: 'Retry status' }))
    await waitFor(() => expect(screen.queryByRole('alert')).not.toBeInTheDocument())
    expect(screen.getByText('Not configured')).toBeInTheDocument()
  })

  it('handles unknown integration URLs without opening another settings page', () => {
    render(<ConnectionsView integration="missing" fail={vi.fn()} />)
    expect(screen.getByRole('heading', { name: 'Integration not found' })).toBeInTheDocument()
    expect(screen.getByText(/Connections in the top breadcrumb/)).toBeInTheDocument()
    expect(screen.queryByLabelText('API token')).not.toBeInTheDocument()
  })
})
