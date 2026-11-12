# ROM Checker design system

## Purpose and scope

A quiet, dark-first desktop workspace for real ROM collections, evidence, file
operations, background jobs, and RomM. Optimize for scanning filenames and
understanding consequences, not dashboard decoration. Use neutral surfaces,
precise typography, compact controls, and a single restrained indigo accent.
Color communicates meaning; it is not a substitute for evidence or text.

This foundation does not restructure pages, change routes, alter verification
policy, modify API calls, or introduce simulated application features. Existing
light-theme preferences remain supported. Future page work adopts this system
incrementally, not through another parallel theme.

## Architecture and audit

The client is React 19 + TypeScript with Vite, plain CSS, and Lucide React icons.
`App.tsx` owns authentication, theme, navigation, notifications, and confirmation
orchestration. Feature directories own library browsing, storage/imports, jobs,
recovery, settings, and RomM. `api.ts` and feature hooks own integration behavior.
`components/Presentation.tsx` is the established shared presentation boundary.

Before this foundation:

| Evidence | Inconsistency | Foundation decision |
|---|---|---|
| `style.css` and `redesign.css` both defined root themes | Green and indigo palettes competed; several controls retained hardcoded mint colors | One semantic token source with legacy aliases |
| Global button/input rules plus redesign overrides | 7-10px radii, variable heights and padding, primary light-theme contrast differed | 32/36/44px controls and shared variants |
| Panels, menus, dialogs and feature cards | 8-18px radii and several unrelated shadows | Small radius scale; shadows reserved for overlays |
| `Badge`, notices and cover-status CSS | Success reused the accent, status colors varied by context | Separate success, warning, danger and info semantics |
| Feature loading rows, cover skeletons and `.empty` | Different sizes and announcements; state handling scattered | Shared loading, skeleton, empty and notification primitives |
| Modal/drawer rules across three stylesheets | Competing sizing; no explicit opener restoration | One native-dialog implementation and bounded drawer |
| Feature table and heading styles | 9-14px metadata and inconsistent density | Readable shared table/type scale for migrated UI |

### Ownership and stylesheet order

`src/main.tsx` deliberately imports `App` (and its feature CSS), then
`style.css`, `redesign.css`, `design-system/tokens.css`, and finally
`design-system/foundation.css`. Do not import global redesign styles from
individual components. The final foundation owns shared appearance; `ds-*`
classes isolate new primitives from feature selectors. No new styling dependency
or network font service is required.

`tokens.css` is the only theme-token source. Existing `--bg`, `--panel`,
`--panel-alt`, `--line`, `--text`, `--muted`, `--accent`, `--accent-dark`,
`--danger`, `--danger-bg`, `--warning`, `--warning-bg`, and `--shadow` are
compatibility aliases, not a second palette. Use `--ds-*` in new code.
`foundation.css` bridges existing primary buttons, inputs, badges, notices,
panels, logs, and switches so current pages benefit without being rebuilt.

Remaining page-specific cover colors, artwork treatments, layout dimensions,
gradients, tiny metadata, and historical selectors are migration debt, not
approved additions to the system. Do not copy them. Remove the associated
legacy rule when migrating a page; do not append another override file.

## Tokens

Values below are defined in `web/client/src/design-system/tokens.css`. CSS is
the executable source of truth; extend it only for an actual shared requirement.
The root is dark by default; `html[data-theme="light"]` changes semantic colors
and shadows, not dimensions.

| Role | Token(s) | Dark / light |
|---|---|---|
| Canvas | `--ds-bg` | `#101216` / `#f6f7f9` |
| Section surface | `--ds-surface` | `#17191f` / `#ffffff` |
| Raised/hover surface | `--ds-surface-raised`, `--ds-surface-hover` | `#20232b`, `#292d37` / `#edf0f4`, `#e4e8ef` |
| Dividers/control boundary | `--ds-border`, `--ds-border-strong` | `#343945`, `#697386` / `#cbd1dc`, `#788397` |
| Primary/secondary text | `--ds-text`, `--ds-text-muted` | `#edf0f5`, `#a4adbd` / `#202633`, `#586477` |
| Action/focus/selection | `--ds-accent`, `--ds-accent-hover`, `--ds-accent-subtle`, `--ds-on-accent` | Indigo; primary labels use on-accent, never canvas text |
| Evidence and feedback | `--ds-success`, `--ds-warning`, `--ds-danger`, `--ds-info` and matching `-subtle` tokens | Green, amber, red, blue with theme-specific foregrounds |
| Backdrop | `--ds-overlay` | Neutral translucent scrim; no blur |

Use success for completed/clean results, warning for incomplete/unknown checks,
danger for failed/unsafe operations, info for guidance, neutral for ordinary
metadata. Indigo is action/navigation, not proof of verification.

### Typography

Use the local Inter/system sans stack (`--ds-font-sans`); do not download fonts.
Use `--ds-font-mono` for hashes, paths, and logs, not entire data tables.
Keep filenames in normal case and use tabular numbers for quantities.

| Token suffix after `--ds-text-` | Size at 16px root | Usage |
|---|---|---|
| `xs` | 12px | Metadata, hints, badges |
| `sm` | 13px | Controls, table cells, compact descriptions |
| `md` | 14px | Body and state copy |
| `lg` | 16px | Subsection headings |
| `xl` | 20px | Section and dialog headings |
| `title` | 28px | Page title, one h1 per page |

Use normal/medium/semibold weights (400/500/600), tight heading line height
(1.25) and normal body line height (1.5). No new 9px labels, spaced-out
uppercase body copy, or arbitrary heading sizes.

### Geometry, elevation and motion

Spacing uses `--ds-space-{0,1,2,3,4,5,6,8,10,12}` =
0/4/8/12/16/20/24/32/40/48px. Use 8px within controls, 12px between related
controls, 16px between groups, 24px section padding, and 32px page spacing.
Prefer dividers and section headings to nested cards.

Radii: `sm` 4px for badges/skeletons, `md` 6px for controls/tooltips,
`lg` 8px for sections/dialogs; `pill` is reserved for switches and round markers.
Borders are 1px. No shadows on ordinary panels. Use `--ds-shadow-popover` for
tooltips/menus and `--ds-shadow-overlay` for dialogs/drawers.

Control heights: `sm` 32px, `md` 36px, `lg` 44px. Shared table rows have a
44px minimum; content may increase height. Do not force a fixed row height that
clips filenames. Coarse pointers promote shared action targets to at least 44px.

Transitions use `--ds-duration-fast` (120ms) for controls and
`--ds-duration-normal` (180ms) for navigation with `--ds-ease`. Animate only
color/opacity or purposeful navigation; no hover lifting, decorative shimmer,
or success confetti in new work. Static skeletons avoid suggesting progress.
Reduced-motion disables transitions and animation, including spinners; loading
labels remain visible.

## Shared components and rules

Import primitives from `src/design-system/components.tsx` and `Dialog` from
`src/design-system/Dialog.tsx`. Keep ROM-specific interpretation in feature code
or the existing `Presentation.tsx` adapters, not inside generic primitives.

| Component | Variants / contract |
|---|---|
| `Button` | `secondary` default, `primary`, `ghost`, `danger`; sizes `sm`, `md`, `lg`; `loading` disables duplicate actions and sets `aria-busy`; native props/ref supported |
| `IconButton` | Same action contract, mandatory `label`; 16-20px Lucide icon, decorative SVG hidden from assistive technology |
| `TextInput`, `Select` | Required visible `label`; optional `hint`/`error`; generated stable IDs, associated descriptions, `aria-invalid`; native value/change/required/disabled props |
| `StatusBadge` | Explicit `neutral`, `info`, `success`, `warning`, `danger` tone; text always present |
| `Notice` | Same tones; danger is `alert`, others are polite `status`; optional explicit dismissal; never auto-dismiss errors |
| `LoadingState`, `Skeleton` | Named loading status, decorative static skeleton; use one loading announcement per region |
| `EmptyState` | Title, explanatory children, optional icon and real action; no fabricated sample collections |
| `Table` | Required caption; named, keyboard-scrollable region and native table; caller supplies semantic thead/tbody and column headers |
| `NavigationItem` | Native button for existing hash-router navigation, `current` sets `aria-current="page"`; visible text and icon |
| `Tooltip` | One native button child; supplemental plain-text content appears on hover/focus, Escape dismisses; existing descriptions preserved |
| `Dialog` | Native modal `dialog` or right-side `drawer`; required title/onClose; optional description; `closeDisabled` blocks pending-operation cancellation |

### Buttons and inputs

One primary action per logical section, not per row. Use secondary for checks,
previews and navigation actions; ghost for quiet utilities. Danger is reserved
for an explicitly destructive action, not an ordinary warning. Always explain
which files change, and preserve existing confirmation requirements. A loading
button keeps its action text visible. Buttons default to `type="button"`; form
submission must explicitly use `type="submit"`.

Do not use placeholders as labels. Place errors beside the field and associate
them with the control. Preserve the user's draft after failure. Required,
readonly and disabled remain native semantics; do not silently coerce invalid
values. Use native checkboxes/radios/selects; do not build a custom combobox
unless a real requirement justifies its keyboard complexity.

```tsx
<TextInput label="Export directory" value={directory}
  onChange={event => setDirectory(event.target.value)}
  hint="A mount shared with RomM." error={directoryError} />
<Button type="submit" variant="primary" loading={saving}>Save settings</Button>
```

### Tables and collection evidence

Use tables for paths, sizes, hashes, checks and duplicates. Artwork grids remain
a library-specific presentation, not a generic card convention. Header cells
need `scope="col"`; sortable headers use a real button and `aria-sort` on the
header. Selection uses labeled native checkboxes and, where appropriate,
`aria-selected` on rows. The table wrapper is not an ARIA grid: preserve native
table navigation and do not invent arrow-key behavior.

Keep identity, integrity, malware/security, organization and RomM publication
as independent findings. Never label an unchecked ROM safe because it matched a
filename or exists in RomM. Preserve existing domain `Badge` classification
until an explicit evidence-model change. Long hashes/paths wrap in details;
truncate only with a way to inspect/copy the full value. Never silently hide
danger/incomplete findings at smaller widths.

### Dialogs, drawers and navigation

Use `Dialog` for focused confirmation and `variant="drawer"` for file evidence
or detail editing. Modal width is at most 640px with a 16px desktop viewport
margin; drawers are at most 640px and full viewport height. Both scroll within
the viewport. Native `showModal()` supplies top-layer placement, focus containment,
and background inertness; cleanup restores a connected opener. Escape and the
close button share `onClose`; backdrop clicks deliberately do not dismiss.
During a non-cancellable mutation set `closeDisabled` and disable cancel actions.
Do not close the dialog until the caller has handled success.

Keep existing route and mobile-navigation behavior. Current destination has a
subtle accent surface and `aria-current`; never identify it only by color.
Collapsed navigation requires accessible labels and supplemental tooltips.
Use Lucide consistently: 16px inline, 18-20px navigation/actions, stroke width
around 1.5-2. Do not mix emoji, filled icon packs, and outline icons.

### Notifications, tooltips and state copy

Use inline `Notice` for persistent actionable feedback. Do not add a competing
toast service. Error copy states what failed and how to retry; success describes
the actual committed result, not optimism at request start. Warnings must not
claim an operation failed if it completed with warnings.

Tooltips contain supplemental short text only: no links, forms, or essential
instructions. The trigger still needs its own accessible name. Tooltips stay
hoverable and close with Escape; do not nest a second button around the trigger.
For controls near viewport edges, prefer a visible hint rather than a tooltip
that could collide with the edge (this primitive does not implement collision
positioning).

| State | Required behavior |
|---|---|
| Initial loading | Preserve section footprint; `LoadingState` plus optional decorative skeletons; do not announce every skeleton |
| Background processing | Preserve usable results; existing `ProgressCard` reports phase and real progress; indeterminate if percentage is unknown |
| Empty collection | Explain why it is empty and offer the existing Add games action |
| No filter matches | Explain that filters excluded results and offer clearing filters; not an empty-library claim |
| Error | Show explicit failure and a real retry path; never replace failure with empty/success content |
| Success | Confirm only after the backend completes; use a labeled success badge/notice, not an accent dot |
| Partial/incomplete | Keep uncertainty visible with warning text and evidence; never infer verification or publication |

## Responsive and accessibility contract

Existing shell breakpoints remain 900px (off-canvas navigation) and 540px
(compact single-column layout); feature-specific breakpoints remain until those
pages migrate. At desktop widths retain persistent/collapsible navigation,
bounded content width, and high-density horizontal toolbars. Below 900px the
existing menu button, focus trap, Escape handling, and scrim remain authoritative.
Below 540px stack forms/actions and make drawers full width. At every width,
tables scroll horizontally within their named region rather than widening the
document. Do not transform evidence tables into unlabeled cards or remove
columns silently.

Support 320px viewports, keyboard-only use, browser zoom, and reduced motion.
Text should meet WCAG AA 4.5:1 for normal text (3:1 for large text); control
boundaries/focus indicators should meet 3:1 against adjacent surfaces. Muted
text is still readable text, not disabled text. Disabled controls alone may
use reduced opacity. There is a 2px visible focus outline with a 3px offset.
Labels, states, and icons carry meaning in addition to color.

## Adoption and verification

The existing `Badge`, `Modal`, and `Empty` exports delegate to the foundation;
job progress and domain labels remain intact. Workspace loading, main
navigation, global feedback, and confirmation actions use shared primitives.
No API or backend behavior changes are required.

For each later page migration: replace local primitives with shared ones,
remove its obsolete shared styling, keep feature layout local, preserve real
callbacks/requests and confirm/error behavior, and check dark/light themes,
keyboard focus, pending/empty/error states, long paths, and narrow layouts.
No additional runtime theme, component framework, or font dependency should be
added without a demonstrated gap.

Run `npm test` and `npm run build` in `web/client`. Native dialog focus,
viewport behavior, and computed styles need browser coverage in addition to
jsdom; `npm run test:e2e:catalog` covers the library/RomM shell without a live
backend. Full backend browser coverage remains `npm run test:e2e`.
