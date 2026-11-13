import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import StorageView from './StorageView'

describe('SMB connection lifecycle', () => {
  it('clears an expired connection and lets the administrator reconnect after a storage restart', async () => {
    sessionStorage.setItem('romchecker-smb', 'expired-connection')
    const fail = vi.fn()
    vi.stubGlobal('fetch', vi.fn(async (path: string) => {
      if (path.endsWith('/storage/config')) return Response.json({ enabled: true })
      if (path.endsWith('/storage/batches')) return Response.json([])
      return Response.json({ error: 'SMB connection expired. Connect again.' }, { status: 410 })
    }))
    render(<StorageView batchId="" select={vi.fn()} start={vi.fn()} active={false} fail={fail} />)
    fireEvent.click(await screen.findByRole('button', { name: 'Browse SMB root' }))
    await waitFor(() => expect(screen.getByRole('button', { name: 'Connect to SMB share' })).toBeInTheDocument())
    expect(sessionStorage.getItem('romchecker-smb')).toBeNull()
    expect(fail).toHaveBeenCalledWith(expect.objectContaining({ status: 410 }))
  })
})
