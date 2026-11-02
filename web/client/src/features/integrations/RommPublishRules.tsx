import { useEffect, useState } from 'react'
import { api } from '../../api'
import { Badge } from '../../components/Presentation'

export type PublishRules = {
  referenceRequirement: 'eligible' | 'matched'
  consoles: string[]; regions: string[]; categories: string[]; batchIds: string[]
  allowFilenameRegions: boolean; includeUnknownRegions: boolean
}
export const defaultPublishRules: PublishRules = {
  referenceRequirement: 'eligible', consoles: [], regions: [], categories: [], batchIds: [],
  allowFilenameRegions: false, includeUnknownRegions: false,
}
type Options = { consoles: string[]; regions: string[]; categories: string[]; imports: { id: string; name: string }[] }
type Preview = {
  total: number; matched: number; ready: number; excluded: number; pending: number; linked: number; failed: number
  page: number; size: number
  items: { id: string; name: string; files: number; console: string; status: string; reason: string
    regions: { values: string[]; source: string }[] }[]
}
type Props = { rules: PublishRules; change: (rules: PublishRules) => void; disabled: boolean; consoles: string[] }

export default function RommPublishRules({ rules, change, disabled, consoles }: Props) {
  const [options, setOptions] = useState<Options>()
  const [optionsError, setOptionsError] = useState('')
  const [preview, setPreview] = useState<{ key: string; value: Preview }>()
  const [previewError, setPreviewError] = useState('')
  const [loading, setLoading] = useState(false)
  const key = JSON.stringify(rules)
  const current = preview?.key === key ? preview.value : undefined
  async function loadOptions() {
    setOptionsError('')
    try { setOptions(await api<Options>('/romm/publish-options')) }
    catch (error) { setOptionsError(error instanceof Error ? error.message : String(error)) }
  }
  useEffect(() => { void loadOptions() }, [])
  async function showPreview(page = 1) {
    setLoading(true); setPreviewError('')
    try {
      const value = await api<Preview>('/romm/auto-publish/preview', {
        method: 'POST', body: JSON.stringify({ rules, page, size: 25 }),
      })
      setPreview({ key, value })
    } catch (error) { setPreviewError(error instanceof Error ? error.message : String(error)) }
    finally { setLoading(false) }
  }
  function choose(field: 'consoles' | 'regions' | 'categories' | 'batchIds', title: string, values: { id: string; name: string }[]) {
    const choices = [...values, ...rules[field].filter(id => !values.some(value => value.id === id))
      .map(id => ({ id, name: `${id} (not currently available)` }))]
    return <div><label htmlFor={`romm-rule-${field}`}>{title}</label><select id={`romm-rule-${field}`} multiple size={5} disabled={disabled} value={rules[field]}
      onChange={event => change({ ...rules, [field]: Array.from(event.target.selectedOptions, option => option.value) })}>
      {choices.map(value => <option key={value.id} value={value.id}>{value.name}</option>)}
    </select><button type="button" disabled={disabled || !rules[field].length} onClick={() => change({ ...rules, [field]: [] })}>Clear {title.toLowerCase()}</button></div>
  }
  const named = (values: string[]) => values.map(value => ({ id: value, name: value }))
  return <section className="panel" style={{ marginTop: 22 }}>
    <h2>Automatic publishing rules</h2>
    <p>All selected filters must match. Within each list, any selected value matches; an empty list adds no restriction.
      These rules only narrow automatic publishing. Manual publication still requires its own preview and confirmation.</p>
    <p className="small muted">Unchecked, unsafe, stale, or incomplete games always stay blocked. Primary game files must match the filters;
      companion files stay with their game and must still pass all required checks. Nothing here deletes or replaces existing RomM files.</p>
    {optionsError && <div role="alert" className="notice error">{optionsError}<button type="button" onClick={loadOptions}>Retry rule options</button></div>}
    <div className="integration-grid">
      <label>Reference requirement<select disabled={disabled} value={rules.referenceRequirement}
        onChange={event => change({ ...rules, referenceRequirement: event.target.value === 'matched' ? 'matched' : 'eligible' })}>
        <option value="eligible">All policy-eligible files, including explicitly approved files</option>
        <option value="matched">Reference matches only (approval is not enough)</option>
      </select></label>
      {choose('consoles', 'Consoles', named([...new Set([...(options?.consoles ?? []), ...consoles])].sort()))}
      {choose('categories', 'Game categories', named(options?.categories ?? []))}
      {choose('batchIds', 'Imports', options?.imports ?? [])}
      {choose('regions', 'Regions', named(options?.regions ?? []))}
      <div>
        <p>Regions come from checked DAT/hash-match titles, otherwise from filename tags. Filename inference is not verification evidence.
          Multi-region games match any selected region. “World” is a separate value, not every region.</p>
        <label className="catalog-check"><input type="checkbox" disabled={disabled} checked={rules.allowFilenameRegions}
          onChange={event => change({ ...rules, allowFilenameRegions: event.target.checked })} />Allow filename-inferred regions</label>
        <label className="catalog-check"><input type="checkbox" disabled={disabled} checked={rules.includeUnknownRegions}
          onChange={event => change({ ...rules, includeUnknownRegions: event.target.checked })} />Include unknown or disallowed-source regions</label>
        <p className="small muted">These options apply when regions are selected. By default, unknown or filename-only regions are held for review.</p>
      </div>
    </div>
    <p className="small muted">Save connection & mappings to apply these rules. Preview uses the draft rules and the saved platform mappings;
      it does not save settings or transfer files. Existing auto-publish settings are preserved until you save.
      Rules are checked again before an automatic export is made visible. Already exported copies remain available and can finish linking.</p>
    <div className="row wrap"><button type="button" disabled={disabled || loading} onClick={() => showPreview()}>Preview matching games</button>
      <button type="submit" form="romm-connection" disabled={disabled}>Save publishing rules</button></div>
    {loading && <p role="status">Evaluating publishing rules...</p>}
    {previewError && <p role="alert" className="notice error">{previewError}</p>}
    {current && <div>
      <p role="status">{current.total} games · {current.matched} match rules · {current.ready} ready · {current.excluded} excluded · {current.pending} pending · {current.linked} linked · {current.failed} need retry</p>
      <div className="integration-list">{current.items.map(group => <article className="integration-item" key={group.id}>
        <div className="row spread"><strong>{group.name}</strong><Badge value={group.status} /></div>
        <p className="small">{group.console} · {group.files} files · {group.reason}</p>
        <p className="small muted">{group.regions.map(region => `${region.values.join(', ') || 'Unknown region'} (${region.source})`).join('; ')}</p>
      </article>)}</div>
      {current.total > current.size && <div className="row">
        <button type="button" disabled={loading || current.page <= 1} onClick={() => showPreview(current.page - 1)}>Previous preview page</button>
        <span>Page {current.page} of {Math.ceil(current.total / current.size)}</span>
        <button type="button" disabled={loading || current.page * current.size >= current.total} onClick={() => showPreview(current.page + 1)}>Next preview page</button>
      </div>}
    </div>}
  </section>
}
