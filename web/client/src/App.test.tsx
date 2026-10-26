import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { api, bytes } from './api'
import App from './App'
import { Badge, Modal } from './components/Presentation'

describe('web workspace', () => {
  it('keeps incomplete protection visually distinct from verified results', () => {
    render(<><Badge value="Incomplete" /><Badge value="Original" /><Badge value="Malicious" /></>)
    expect(screen.getByText('Incomplete')).toHaveClass('warning')
    expect(screen.getByText('Original')).toHaveClass('success')
    expect(screen.getByText('Malicious')).toHaveClass('danger')
  })
  it('renders an accessible modal and close action', () => {
    const close = vi.fn()
    render(<Modal title="Apply changes?" close={close}><p>Nothing moves without confirmation.</p></Modal>)
    expect(screen.getByRole('dialog', { name: 'Apply changes?' })).toHaveAttribute('open')
    fireEvent.click(screen.getByRole('button', { name: 'Close dialog' }))
    expect(close).toHaveBeenCalledOnce()
  })
  it('requires sign-in and shows incorrect password errors', async () => {
    const fetcher = vi.fn().mockImplementation(() => Promise.resolve(Response.json({ error: 'Invalid password.' }, { status: 401 })))
    vi.stubGlobal('fetch', fetcher)
    render(<App />)
    fireEvent.change(await screen.findByLabelText('Administrator password'), { target: { value: 'incorrect' } })
    fireEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('Invalid password.')
    expect(fetcher.mock.calls.some(([path]) => path === '/api/login')).toBe(true)
  })
  it('opens the workspace after sign-in and never starts a scan automatically', async () => {
    let signedIn = false
    const fetcher = vi.fn(async (path: string) => {
      if (path === '/api/login') { signedIn = true; return Response.json({ authenticated: true }) }
      if (path === '/api/session') return Response.json({ authenticated: signedIn }, { status: signedIn ? 200 : 401 })
      if (path === '/api/jobs') return Response.json([])
      if (path === '/api/info') return Response.json({ version: '0.2.0', library: '/library' })
      throw new Error(`Unexpected request ${path}`)
    })
    vi.stubGlobal('fetch', fetcher)
    render(<App />)
    fireEvent.change(await screen.findByLabelText('Administrator password'), { target: { value: 'fixture-only-password' } })
    fireEvent.click(screen.getByRole('button', { name: 'Sign in' }))
    expect(await screen.findByRole('heading', { name: 'Library overview' })).toBeInTheDocument()
    await waitFor(() => expect(screen.getByText('/library')).toBeInTheDocument())
    expect(screen.getByRole('button', { name: /Check library/ })).toBeEnabled()
    expect(fetcher.mock.calls.filter(([path]) => path === '/api/jobs')).toHaveLength(1)
  })
  it('sends same-origin credentials and the mutation protection header', async () => {
    const fetcher = vi.fn().mockResolvedValue(Response.json({ ok: true }))
    vi.stubGlobal('fetch', fetcher)
    await api('/jobs', { method: 'POST', body: '{"action":"scan"}' })
    expect(fetcher).toHaveBeenCalledWith('/api/jobs', expect.objectContaining({
      credentials: 'same-origin', headers: expect.objectContaining({ 'X-RomChecker': '1' }),
    }))
  })
  it('formats byte quantities without misleading units', () => {
    expect(bytes(0)).toBe('0 B')
    expect(bytes(1024)).toBe('1.0 KB')
    expect(bytes(1024 ** 3)).toBe('1.0 GB')
  })
})
