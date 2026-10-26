import { describe, expect, it, vi } from 'vitest'
import { uploadFolder } from './transfers'

describe('bounded folder transfers', () => {
  it('resumes from a server offset and never uploads a whole large file in one request', async () => {
    const fixture = new File([new Uint8Array(20 * 1024 * 1024)], 'large.nes', { lastModified: 10 })
    Object.defineProperty(fixture, 'webkitRelativePath', { value: 'Games/large.nes' })
    let offset = 1024 * 1024
    const chunks: number[] = []
    vi.stubGlobal('fetch', vi.fn(async (path: string, options: RequestInit) => {
      if (options.method === 'POST') return Response.json({ id: 'upload', offset, complete: false })
      expect(path).toContain(`offset=${offset}`)
      const chunk = options.body as Blob
      expect(chunk.size).toBeLessThanOrEqual(8 * 1024 * 1024)
      chunks.push(chunk.size); offset += chunk.size
      return Response.json({ id: 'upload', offset, complete: offset === fixture.size })
    }))
    const progress = vi.fn()
    await uploadFolder('batch', [fixture], new AbortController().signal, progress)
    expect(chunks).toEqual([8 * 1024 * 1024, 8 * 1024 * 1024, 3 * 1024 * 1024])
    expect(progress).toHaveBeenLastCalledWith(expect.objectContaining({ done: 1, total: 1, bytes: fixture.size }))
  })
  it('does not retry invalid input or continue uploading after cancellation', async () => {
    const fetcher = vi.fn(async () => Response.json({ error: 'Invalid file name.' }, { status: 400 }))
    vi.stubGlobal('fetch', fetcher)
    const file = new File(['test'], 'test.nes')
    await expect(uploadFolder('batch', [file], new AbortController().signal, vi.fn())).rejects.toThrow('Invalid file name.')
    expect(fetcher).toHaveBeenCalledOnce()
    const controller = new AbortController()
    controller.abort()
    await expect(uploadFolder('batch', [file], controller.signal, vi.fn())).rejects.toThrow()
    expect(fetcher).toHaveBeenCalledOnce()
  })
})
