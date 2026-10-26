import {
  Check,
  ChevronLeft, ChevronRight,
  Download,
  RefreshCw, Search
} from 'lucide-react'
import {
  bytes, completed, date, label, preview, url,
  type Job
} from '../../api'
import type { useLibrary } from './useLibrary'

import { Badge, Empty } from '../../components/Presentation'
import type { ConfirmAction, StartJob } from '../../workspace'
import { actions } from '../jobs/actions'

type Props = {
  tab: 'Library' | 'Changes'; library: ReturnType<typeof useLibrary>; jobs: Job[]
  active?: Job; pending: boolean; start: StartJob; confirm: ConfirmAction
}
export default function LibraryView({ tab, library, jobs, active, pending, start, confirm }: Props) {
  const { resultId, selected, summary, reviews, selectResults, results, query, category, consoleFilter,
    page, setQuery, setCategory, setConsoleFilter, setPage, setFile } = library
  return <>
          <div className="toolbar"><label className="result-picker">Result snapshot<select aria-label="Result snapshot" value={resultId} onChange={e => selectResults(e.target.value)}><option value="">Choose a completed result</option>{jobs.filter(j => completed(j) && (preview(j) || j.action === 'apply')).map(j => <option key={j.id} value={j.id}>{actions[j.action]} - {date(j.created)}</option>)}</select></label>
            {resultId && <div className="row wrap"><a className="button secondary" href={url(`/jobs/${resultId}/artifacts/report.html`)} download><Download size={16} />HTML</a><a className="button secondary" href={url(`/jobs/${resultId}/artifacts/report.csv`)} download>CSV</a><a className="button secondary" href={url(`/jobs/${resultId}/artifacts/results.json`)} download>JSON</a></div>}</div>
          {tab === 'Changes' && selected && <div className="plan-banner"><div><h3>{summary?.Planned ?? 0} proposed moves</h3><p>Layout: {selected.settings.layout}. Targets are revalidated before applying. File names never change.</p>
            {reviews.length > 0 && <strong>{reviews.length} draft review decision(s) need a rebuilt preview.</strong>}</div><div className="row wrap"><button disabled={!!active || pending || !preview(selected)} onClick={() => start('plan', { sourceId: resultId, reviews })}><RefreshCw size={16} />Rebuild preview</button>
              <button className="primary" disabled={!!active || pending || !preview(selected) || !!reviews.length || !summary?.Planned || jobs.some(j => j.action === 'apply' && j.request.sourceId === resultId)} onClick={() => confirm({ title: 'Apply this move plan?', message: `Move up to ${summary?.Planned ?? 0} files using this saved preview and its settings. File content and inventory are checked again. Existing files are not overwritten. Moves are journaled for recovery.`, action: 'apply', sourceId: resultId })}><Check size={17} />Apply moves</button></div></div>}
          {!resultId ? <section className="panel"><Empty title="No results to review yet">Check the library or build a sort-only inventory from Overview. Your files stay in place until you apply a preview.</Empty></section> : <section className="panel results-panel"><div className="filters"><label className="search"><Search size={17} /><input aria-label="Search files" placeholder="Search files, paths, or findings..." value={query} onChange={e => { setQuery(e.target.value); setPage(1) }} /></label>
            <select aria-label="Filter by console" value={consoleFilter} onChange={e => { setConsoleFilter(e.target.value); setPage(1) }}><option value="">All consoles</option>{results?.consoles.map(c => <option key={c}>{c}</option>)}</select>
            <select aria-label="Filter by category" value={category} onChange={e => { setCategory(e.target.value); setPage(1) }}><option value="">All categories</option>{results?.categories.map(c => <option key={c} value={c}>{label(c)}</option>)}</select></div>
            <div className="table-scroll"><table><thead><tr><th>File / console</th><th>Classification</th><th>Authenticity</th><th>Integrity</th><th>Antivirus</th>{tab === 'Changes' && <th>Proposed destination</th>}<th>Size</th></tr></thead><tbody>{results?.items.map(item => <tr key={item.FullName} onClick={() => setFile(item)}><td><button className="file-name" onClick={() => setFile(item)}>{item.FileName}</button><small>{item.Console} <span className="muted">/ {item.Folder}</span></small></td><td><Badge value={item.Category} />{reviews.some(r => r.path === item.FullName) && <small className="accent">Review drafted</small>}</td><td>{item.Authenticity}</td><td>{item.IntegrityStatus}</td><td><Badge value={item.AntivirusStatus} /></td>{tab === 'Changes' && <td className="target-cell mono">{item.Target || 'Leave in place'}</td>}<td className="nowrap">{bytes(item.Length)}</td></tr>)}</tbody></table></div>
            {results?.items.length === 0 && <Empty title="No matching files">Try a different search or filter, or run a new check if the library is empty.</Empty>}
            <div className="pagination"><span>{results?.total.toLocaleString() ?? 0} files <span className="muted">/ click a file for evidence & review</span></span><div className="row"><button aria-label="Previous page" disabled={page === 1} onClick={() => setPage(page - 1)}><ChevronLeft size={16} /></button><span>Page {page} of {Math.max(1, Math.ceil((results?.total ?? 0) / 50))}</span><button aria-label="Next page" disabled={page * 50 >= (results?.total ?? 0)} onClick={() => setPage(page + 1)}><ChevronRight size={16} /></button></div></div></section>}
        </>
}
