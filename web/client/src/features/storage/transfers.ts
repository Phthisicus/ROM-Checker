import { api, url } from '../../api'

export type Batch = { id: string; name: string; status: string; created: string; files: number; bytes: number; error?: string; prepared: boolean }
export type Entry = { name: string; path: string; directory: boolean; size: number }
export type Listing = { path: string; entries: Entry[]; page: number; more: boolean }
type Upload = { id: string; path: string; size: number; modified: number; offset: number; complete: boolean }
export type TransferProgress = { file: string; done: number; total: number; bytes: number; totalBytes: number }

export async function uploadFolder(batchId: string, files: File[], signal: AbortSignal,
  progress: (value: TransferProgress) => void) {
  const totalBytes = files.reduce((sum, file) => sum + file.size, 0)
  let done = 0, bytes = 0
  for (const file of files) {
    signal.throwIfAborted()
    const path = file.webkitRelativePath || file.name
    let lastError: unknown
    let finished = false
    for (let attempt = 0; attempt < 4 && !finished; attempt++) {
      try {
        let upload = await api<Upload>(`/storage/batches/${batchId}/uploads`, {
          method: 'POST', body: JSON.stringify({ path, size: file.size, modified: file.lastModified }), signal,
        })
        progress({ file: path, done, total: files.length, bytes: bytes + upload.offset, totalBytes })
        while (!upload.complete) {
          const chunk = file.slice(upload.offset, Math.min(upload.offset + 8 * 1024 * 1024, file.size))
          upload = await api<Upload>(`/storage/batches/${batchId}/uploads/${upload.id}?offset=${upload.offset}`, {
            method: 'PUT', body: chunk, headers: { 'Content-Type': 'application/octet-stream' }, signal,
          })
          progress({ file: path, done, total: files.length, bytes: bytes + upload.offset, totalBytes })
        }
        finished = true
      } catch (error) {
        signal.throwIfAborted()
        lastError = error
        const status = error instanceof Error && 'status' in error ? Number(error.status) : 0
        if (status && ![408, 409, 429, 500, 502, 503, 504].includes(status)) throw error
        if (attempt < 3) await new Promise(resolve => setTimeout(resolve, 500 * 2 ** attempt))
      }
    }
    if (!finished) throw lastError
    done++; bytes += file.size
    progress({ file: path, done, total: files.length, bytes, totalBytes })
  }
}

export const downloadUrl = (id: string, path: string) =>
  url(`/storage/batches/${id}/download?path=${encodeURIComponent(path)}`)
