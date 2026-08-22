# Blocks migration proposal

Proposal for folding `json/data/block/pages.json` and
`json/data/block/pages-content.json` into the block concept. **The block
json structure is the master**: where the two files name the same thing
differently, the block's property name wins; where they invent structure the
block model already covers, the block model's way wins.

Two principles drive the mapping:

- **blocks are region-agnostic** — a block never knows whether it sits in a
  header, footer, sidebar or main area; placement is the page's business;
- **the page's blocks are the UI rows** — `site.page_block.sort_order`
  stacks them, and inside a block `cols` (with `col_width`) makes the
  columns. That covers what pages.json expresses with `grid.rows`,
  `grid.columns` and `areas`, so none of those come over.

## 1. what exists today

Three descriptions of the same idea live side by side:

| source | shape | serves |
|---|---|---|
| `site.block.block_json` | `block_layout`, `cols[].col[]` cells with `param_json.data_group` / `nav_json.nav` / `body` | pages served by `site.get_blocks`, rendered by `MultiCol` |
| `json/data/block/pages.json` | per `code` the regions `header` / `main` / `footer`, each with a `grid` (`rows`, `columns`, `gap`, `align_items`, `areas`) and `sections[]` (`area`, `data_group`), plus `sidebar_width` | the window/dock views of the react portal |
| `json/data/block/pages-content.json` | per `code` a `block` with `title` + `i18n` titles | the window titles for those views |

The react side is already converging: a floating window mounts
`getBlocks` with a `path` param (`window-outlet.tsx`), exactly the call that
serves database pages. The static files are the last views not yet living in
`site.page` / `site.block` / `site.data_group`.

## 2. gap analysis

Checked against the master type (`packages/xfw-ui/src/types/content.ts`,
interface `Content`) and the renderer (`components/blocks/multi-col.tsx`):

| pages.json has | verdict |
|---|---|
| `header` / `main` / `footer` regions | **does not come over** — blocks are region-agnostic; a page is an ordered stack of blocks (`page_block.sort_order`) |
| `grid.rows` | **already covered** — one section per block; the block order is the row order |
| `grid.columns` | **already covered** — `cols` with `col_width` (`"auto"`, `"1fr"`) |
| `grid.areas` + `sections[].area` | **unnecessary** — rows × cols place everything these views need |
| `grid.gap`, `grid.align_items` | **unnecessary** — spacing and alignment belong to the layout components, not to content config |
| `sections[].data_group` | **already covered** — `param_json.data_group` |
| `data_group: "header_data_groups/timeline-controls.json"` (a file path) | **gap** — a data group reference is always a *name* resolved from `site.data_group`; the file must become a row |
| `sidebar_width` (pages.json root) | **gap** — dock hint, belongs next to `sidebar_side` / `sidebar_title` / `sidebar_icon` in `page.environment` |
| pages-content `block.title` + `block.i18n` | **gap** — `Content.title` items have `text` / `class_name`, no i18n; the dock also needs a translated tab title |

So only two real extensions remain, plus one data cleanup.

## 3. proposed extensions

1. **`i18n` at the root of `block_json`**, `title` as the standard slot —
   the same rule as everywhere else. The bare `title` array stays what it is
   (styled title parts); `i18n.title` is the translated window/tab title.

```json
{
  "i18n": {
    "nl": {"title": "Nest resource agenda"},
    "en": {"title": "Nest resource schedule"}
  },
  "cols": [{"col": [{"param_json": {"data_group": "nest_resource_schedule"}}]}],
  "block_layout": "one-col"
}
```

2. **`sidebar_width` in `page.environment`** — joining the existing
   `sidebar_side` / `sidebar_title` / `sidebar_icon`: it describes the
   page's dock behaviour, never a block's content.

And the cleanup: the two file-referenced data groups
(`header_data_groups/timeline-controls.json`) become real `site.data_group`
rows (`timeline_controls`), referenced by name. File paths as data group
references do not survive this migration, by design.

## 4. property mapping

| from | to |
|---|---|
| `code` | `site.page` (one page per code; the window path stays the route) |
| region + `sections[]` order | `page_block.sort_order` — one block per section, top to bottom: header sections, main sections, footer sections |
| a multi-column region (`grid.columns: "auto 1fr"`) | one block with two `cols`, `col_width` `"auto"` / `"1fr"` |
| `sections[].data_group` | `param_json.data_group` |
| `grid.rows` / `areas` / `gap` / `align_items`, `sections[].area` | dropped (covered or unnecessary, see §2) |
| `sidebar_width` | `page.environment.sidebar_width` |
| pages-content `block.title` | `block_json.title[0].text` |
| pages-content `block.i18n.<lang>.title` | `block_json.i18n.<lang>.title` |
| `"header_data_groups/timeline-controls.json"` | `site.data_group` row `timeline_controls`, by name |

## 5. worked example

`nest-resource-schedule` (the fullest case: a two-column header, a filter, a
schedule and a footer) becomes one page and four blocks:

**page** — path as today's window route, environment carries the dock hints:

```json
{"path": ["xfw/nl/window/nest-resource-schedule"],
 "environment": {"sidebar_width": "30%"}}
```

**blocks**, stacked by `page_block.sort_order`:

```json
{"cols": [{"col": [{}], "col_width": "auto"},
          {"col": [{"param_json": {"data_group": "timeline_controls"}}], "col_width": "1fr"}],
 "block_layout": "grid"}
```

```json
{"i18n": {"nl": {"title": "Nest resource agenda"},
          "en": {"title": "Nest resource schedule"},
          "de": {"title": "Nest Ressourcen Zeitplan"}},
 "cols": [{"col": [{"param_json": {"data_group": "nest_schedule_filter"}}]}],
 "block_layout": "one-col"}
```

```json
{"cols": [{"col": [{"param_json": {"data_group": "nest_resource_schedule"}}]}],
 "block_layout": "one-col"}
```

```json
{"cols": [{"col": [{"param_json": {"data_group": "status_bar"}}]}],
 "block_layout": "one-col"}
```

A simple case (`nest-detail`: one section) collapses to a single block —
indistinguishable from the blocks that exist today.

## 6. migration steps

1. **Data groups first**: create `site.data_group` rows for the two
   file-referenced groups (`header_data_groups/timeline-controls.json` →
   `timeline_controls`).
2. **Frontend types**: extend `Content` with the root `i18n`; the dock reads
   `sidebar_width` from `page.environment` and the tab title from
   `block_json.i18n`.
3. **Convert**: one script generates, per `code` in pages.json, the page row,
   one block per section (title from pages-content.json on the main block),
   the `page_block` rows and the `domain_page` row. 35 layouts, 35 titles —
   small enough to review as one diff in the `json/` mirror before it is
   applied.
4. **Switch over**: windows already load through `getBlocks`; once the pages
   exist, the react portal drops its bundled copies and
   `json/data/block/pages.json` + `pages-content.json` are deleted.
5. **Mirror**: the converted result lives in `json/page/` and `json/block/`
   like every other page and block; `json/data/` disappears.

## 7. open points

- **Where are the files consumed right now?** The react repo contains no
  reference to `pages.json` / `pages-content.json` (searched
  apps + packages); confirm nothing else reads them before step 4 deletes
  them.
- **Two mismatched codes**: `control-room` has a title but no layout, and
  `batch` has a layout but no title. Decide per case: dead entry, or an
  intentional gap to fill during conversion?
- **`json/data/nav/`** (`app-nav.json`, `menu-items.json`, `models.json`)
  is the same story for navigation and deserves the same treatment into
  `site.nav` — separate proposal.
- **The emptied `json/page/` mirror**: the page mirror was cleared locally;
  after this migration it refills from the database with the converted pages
  included.
