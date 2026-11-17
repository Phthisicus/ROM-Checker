import { render, screen, within } from '@testing-library/react'
import { expect, it } from 'vitest'
import ReleaseNotes from './ReleaseNotes'

it('renders structured release notes with accessible headings, lists and reproducible identities', () => {
  const { container } = render(<ReleaseNotes label="Installed release notes" notes={'# Stable release\n\n## Maintenance\n\n- **Builds:** Predictable runners.\n- Faster checks.\n\n```text\nghcr.io/owner/repo:1.3.0\n```\n\n[Full changelog](https://github.com/owner/repo/compare/v1.2.0...v1.3.0)'} />)
  expect(screen.getByRole('region', { name: 'Installed release notes' })).toHaveAttribute('tabindex', '0')
  expect(screen.getByRole('heading', { name: 'Stable release', level: 3 })).toBeInTheDocument()
  expect(screen.getByRole('heading', { name: 'Maintenance', level: 4 })).toBeInTheDocument()
  expect(within(screen.getByRole('list')).getAllByRole('listitem')).toHaveLength(2)
  expect(container.querySelector('pre code')).toHaveTextContent('ghcr.io/owner/repo:1.3.0')
  expect(screen.getByRole('link', { name: 'Full changelog' })).toHaveAttribute('rel', 'noreferrer')
})

it('does not execute raw HTML, load remote images or link unsafe protocols', () => {
  const { container } = render(<ReleaseNotes label="Available release notes" notes={'## Beta notes\n\n<script>alert(1)</script>\n\n<img src="https://example.invalid/tracker" onerror="alert(1)">\n\n![tracker](https://example.invalid/tracker)\n\n[unsafe](javascript:alert%281%29)\n\n[local](file:///etc/passwd)\n\n[safe](https://github.com/owner/repo)\n\n<details>\n<summary>Old commit log</summary>\n\n- Retained legacy commit.\n\n</details>'} />)
  expect(container.querySelector('script, img, iframe, details')).toBeNull()
  expect(screen.queryByRole('link', { name: 'unsafe' })).not.toBeInTheDocument()
  expect(screen.queryByRole('link', { name: 'local' })).not.toBeInTheDocument()
  expect(screen.getByRole('link', { name: 'safe' })).toHaveAttribute('href', 'https://github.com/owner/repo')
  expect(screen.getByText('Retained legacy commit.')).toBeInTheDocument()
})

it('keeps older plain-text release metadata readable', () => {
  render(<ReleaseNotes label="Installed release notes" notes="Installed offline release notes." />)
  expect(screen.getByText('Installed offline release notes.')).toBeInTheDocument()
})
