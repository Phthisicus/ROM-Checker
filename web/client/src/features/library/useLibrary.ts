import { useEffect, useState } from 'react'
import { api, type Detail, type Job, type Result, type ResultsPage, type Review, type Summary } from '../../api'

export function useLibrary(jobs: Job[], fail: (error: unknown) => void, notify: (message: string) => void) {
  const [resultId, setResultId] = useState('')
  const [summary, setSummary] = useState<Summary | null>(null)
  const [results, setResults] = useState<ResultsPage>()
  const [query, setQuery] = useState('')
  const [category, setCategory] = useState('')
  const [consoleFilter, setConsoleFilter] = useState('')
  const [page, setPage] = useState(1)
  const [file, setFile] = useState<Result>()
  const [reviews, setReviews] = useState<Review[]>([])

  const selected = jobs.find(job => job.id === resultId)
  useEffect(() => {
    setResults(undefined)
    if (!resultId) return
    let alive = true
    const timer = setTimeout(() => {
      const parameters = new URLSearchParams({ q: query, category, console: consoleFilter, page: String(page) })
      api<ResultsPage>(`/jobs/${resultId}/results?${parameters}`).then(data => { if (alive) setResults(data) }).catch(fail)
    }, 200)
    return () => { alive = false; clearTimeout(timer) }
  }, [resultId, query, category, consoleFilter, page, fail])
  useEffect(() => {
    setSummary(null)
    if (!resultId) return
    let alive = true
    api<Detail>(`/jobs/${resultId}`).then(data => { if (alive) setSummary(data.summary) }).catch(fail)
    return () => { alive = false }
  }, [resultId, fail])
  function selectResults(id: string) { setResultId(id); setReviews([]); setPage(1); setCategory(''); setConsoleFilter(''); setQuery('') }
  function review(decision: string) {
    if (!file) return
    setReviews(previous => [...previous.filter(r => r.path !== file.FullName), { path: file.FullName, decision }])
    setFile(undefined); notify('Review saved as a draft. Rebuild the preview before applying it.')
  }

  return { resultId, setResultId, summary, results, query, category, consoleFilter, page, file, reviews,
    selected, setQuery, setCategory, setConsoleFilter, setPage, setFile, setReviews, selectResults, review }
}
