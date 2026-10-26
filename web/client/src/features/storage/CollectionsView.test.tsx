import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import CollectionsView, { verificationText, type CollectionFile } from './CollectionsView'
import type { Settings } from '../../api'

const settings: Settings = {
  console: 'All', layout: 'ByConsole', datFolder: '', sortByCategory: true, defenderScan: true,
  strict: false, requireDatMatch: true, moveBSandST: false, protectAppFolders: true, moveCompanions: true,
  keepGameFolders: true, duplicateMode: 'Report', cleanEmptyFolders: true, useFolderHints: true,
  hashLimitMB: 4096, autoDat: false, hasheous: 'Off', identifyUnknown: false, retailOnly: false,
  onlineCheck: 'Off', resumeScans: true, archiveMaxMB: 16384, archiveMaxEntries: 10000,
  archiveMaxDepth: 3, archiveTimeoutSeconds: 300,
}
describe('guided collections', () => {
  it('does not equate reference identity with completed checking', () => {
    expect(verificationText({ CheckedUtc: '', HashMatch: 'Known game' } as CollectionFile)).toBe('Not checked')
    expect(verificationText({ CheckedUtc: '2026-01-01', HoldReason: 'Scanner incomplete' } as CollectionFile)).toBe('Needs attention')
    expect(verificationText({ CheckedUtc: '2026-01-01', HoldReason: '' } as CollectionFile)).toBe('Checks completed')
  })
  it('verifies a complete console selection across pagination only after explicit approval', async () => {
    const start = vi.fn().mockResolvedValue(undefined)
    const fail = vi.fn()
    vi.stubGlobal('fetch', vi.fn(async (path: string) => {
      if (path.endsWith('/storage/config')) return Response.json({ enabled: true })
      if (path.endsWith('/storage/batches')) return Response.json([{ id: 'collection', name: 'My games', prepared: true, status: 'ready', files: 2, bytes: 100 }])
      if (path.includes('/collections/collection/files')) return Response.json({
        detected: true, total: 2, filtered: 2, size: 100, page: 1, checkedFiles: 0, attention: 0,
        organized: 0, datMatches: 0, onlineMatches: 0, threats: 0,
        groups: [{ key: 'NES', name: 'Nintendo NES', total: 2, checkedFiles: 0, organized: 0, attention: 0, ids: ['one', 'two'] }],
        items: [{ CollectionId: 'one', GroupId: 'one', FileName: 'Game.nes', Console: 'NES', Length: 100, CheckedUtc: '' }],
      })
      if (path.endsWith('/capacity')) return Response.json({ availableBytes: 10000, preparationBytes: 0, originalBytes: 100, processingBytes: 100, reserveBytes: 0 })
      if (path.endsWith('/settings')) return Response.json(settings)
      throw new Error(`Unexpected request: ${path}`)
    }))
    render(<CollectionsView batchId="collection" select={vi.fn()} start={start} jobs={[]} progress={null} fail={fail} recovery={vi.fn()} />)
    fireEvent.click(await screen.findByRole('checkbox', { name: 'Select Nintendo NES' }))
    expect(screen.getByText('files selected · required companions are included automatically')).toBeInTheDocument()
    fireEvent.click(screen.getByRole('button', { name: 'Verify selected' }))
    await screen.findByRole('dialog')
    expect(start).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole('button', { name: 'Verify & organize working copies' }))
    await waitFor(() => expect(start).toHaveBeenCalledWith('verify', expect.objectContaining({ selection: ['one', 'two'], organize: true, confirm: true })))
    expect(fail).not.toHaveBeenCalled()
  })
})
