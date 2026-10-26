import { act, fireEvent, render, renderHook, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import type { Result } from '../api'
import { useLibrary } from './library/useLibrary'
import OverviewView from './overview/OverviewView'
import RecoveryView from './recovery/RecoveryView'

describe('feature module boundaries', () => {
  it('starts read-only overview jobs directly but requests confirmation before unpacking', () => {
    const start = vi.fn()
    const confirm = vi.fn()
    render(<OverviewView summary={null} jobs={[]} progress={null} pending={false}
      start={start} confirm={confirm} setTab={vi.fn()} setJobId={vi.fn()} />)
    fireEvent.click(screen.getByRole('button', { name: /Check & build a preview/ }))
    expect(start).toHaveBeenCalledWith('scan')
    fireEvent.click(screen.getByRole('button', { name: /Unpack & check/ }))
    expect(confirm).toHaveBeenCalledWith(expect.objectContaining({ action: 'workflow' }))
    expect(start).toHaveBeenCalledOnce()
  })

  it('keeps recovery previews separate from confirmed restore operations', () => {
    const start = vi.fn()
    const confirm = vi.fn()
    render(<RecoveryView journals={[{ Name: 'fixture.csv', Modified: '2026-01-01T00:00:00Z', Entries: 1 }]}
      cleanup={[]} pending={false} start={start} confirm={confirm} />)
    fireEvent.click(screen.getByRole('button', { name: 'Preview undo' }))
    expect(start).toHaveBeenCalledWith('undo-preview', { journal: 'fixture.csv' })
    fireEvent.click(screen.getByRole('button', { name: 'Restore' }))
    expect(confirm).toHaveBeenCalledWith(expect.objectContaining({ action: 'undo', journal: 'fixture.csv' }))
    expect(start).toHaveBeenCalledOnce()
  })

  it('owns library filters and review drafts independently of application orchestration', async () => {
    const fail = vi.fn()
    const notify = vi.fn()
    const fetcher = vi.fn(async (path: string) => Response.json(path.includes('/results?')
      ? { total: 0, page: 1, size: 100, categories: [], consoles: [], items: [] }
      : { summary: { Count: 1, Planned: 1, Warnings: 0 } }))
    vi.stubGlobal('fetch', fetcher)
    const file: Result = {
      FileName: 'Fixture.nes', FullName: '/library/Fixture.nes', Folder: '/library', Console: 'NES',
      Category: 'Original', Reason: '', Threats: '', Notes: '', Authenticity: '', IntegrityStatus: '',
      AntivirusStatus: '', MalwareStatus: '', DatStrength: '', Security: 'Clean', Sources: '',
      Libraries: '', Year: '', Publisher: '', Header: '', SHA256: '', SHA1: '', MD5: '', CRC32: '',
      Length: 40976, Target: '', Action: '', DupOf: '', SetId: '', CheckedUtc: '', AntivirusCheckedUtc: '',
      Reviewable: true,
    }
    const { result } = renderHook(() => useLibrary([], fail, notify))
    act(() => result.current.selectResults('scan-id'))
    await waitFor(() => expect(result.current.summary?.Count).toBe(1))
    act(() => result.current.setFile(file))
    act(() => result.current.review('keep'))
    expect(result.current.reviews).toEqual([{ path: file.FullName, decision: 'keep' }])
    expect(result.current.file).toBeUndefined()
    expect(notify).toHaveBeenCalledOnce()
    expect(fetcher.mock.calls.every(([path]) => !path.endsWith('/jobs'))).toBe(true)
    act(() => { result.current.setQuery('fixture'); result.current.setPage(2) })
    await waitFor(() => expect(fetcher.mock.calls.some(([path]) => path.includes('q=fixture') && path.includes('page=2'))).toBe(true))
    act(() => result.current.selectResults('next-id'))
    expect(result.current.reviews).toEqual([])
    expect(result.current.query).toBe('')
    expect(result.current.page).toBe(1)
    expect(fail).not.toHaveBeenCalled()
  })
})
