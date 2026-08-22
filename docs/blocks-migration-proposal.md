# Blocks migration proposal

Proposal for folding `json/data/block/pages.json` and
`json/data/block/pages-content.json` into the block concept. **The block
json structure is the master**: where the two files name the same thing
differently, the block's property name wins; where they carry something the
block structure cannot express yet, the block structure is extended — as
data, not as code.

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

## 2. gap analysis — what the block structure misses

Checked against the master type (`packages/xfw-ui/src/types/content.ts`,
interface `Content`) and the renderer (`components/blocks/multi-col.tsx`):

| pages.json has | block structure today | gap |
|---|---|---|
| `header` / `main` / `footer` regions | one block is one region-less grid; a page stacks blocks by `page_block.sort_order` | **no region concept** |
| `grid.rows` / `grid.columns` / `grid.areas` / `grid.gap` / `grid.align_items` | `MultiCol` derives an implicit grid from `cols[].col_width` and `col[].row_height`; no named areas, no gap, no alignment | **no explicit grid** |
| `sections[].area` | cells have `class_name` / `row_height`, no area assignment | **no `area` on a cell** |
| `sidebar_width` | `BlockRow.environment` knows `sidebar_side`, `sidebar_title`, `sidebar_icon` | **no `sidebar_width`** |
| `data_group: "header_data_groups/timeline-controls.json"` (a file path) | `param_json.data_group` is always a **name** resolved from `site.data_group` | **file-referenced data groups** |
| — (pages-content) `block.title` + `block.i18n` | `Content.title` items have `text` / `class_name`, **no i18n** | **no multilingual block title** |

Everything else maps one-to-one: a `section` is a cell, `section.data_group`
is `param_json.data_group`, ordering is array order.

## 3. proposed extensions to block_json

Four additions, all optional, all backwards compatible (an existing block
without them renders exactly as before):

```json
{
  "region": "header",
  "grid": {
    "columns": "auto 1fr",
    "rows": "auto",
    "gap": "0.5rem",
    "align_items": "center",
    "areas": ["breadcrumb controls"]
  },
  "i18n": {
    "nl": {"title": "Nest resource agenda"},
    "en": {"title": "Nest resource schedule"}
  },
  "cols": [
    {"col": [{"area": "breadcrumb"}]},
    {"col": [{"area": "controls", "param_json": {"data_group": "timeline_controls"}}]}
  ],
  "block_layout": "grid"
}
```

1. **`region`** — `header` | `main` | `footer`, default `main`. A page-code
   becomes one `site.page` with one block per region; `page_block.sort_order`
   keeps the order within a region. No schema change: it is a `block_json`
   property.
2. **`grid`** — the explicit variant of what `MultiCol` derives implicitly.
   When present it wins over the derived grid; `block_layout` stays the named
   preset for everything that does not need it. Keys exactly as pages.json
   already writes them (they were already snake_case).
3. **`area`** on a cell — pairs with `grid.areas`; a cell without `area`
   falls back to the derived placement, so both styles mix.
4. **`i18n`** at the root, `title` as the standard slot — the same rule as
   everywhere else in the data groups. The bare `title` array stays what it
   is (styled title parts); `i18n.title` is the translated window/tab title,
   which the dock also needs for `TabMeta.title`.

And one addition next to the block: **`sidebar_width`** joins
`sidebar_side` / `sidebar_title` / `sidebar_icon` in `page.environment` —
it describes the page's dock behaviour, not a block's content.

## 4. property mapping

| from | to |
|---|---|
| `code` | `site.page` (one page per code; the window path stays the route) |
| `header` / `main` / `footer` | one block each, `block_json.region` |
| `grid.*` | `block_json.grid.*` (names unchanged) |
| `sections[]` | `cols[].col[]` cells |
| `sections[].data_group` | `param_json.data_group` |
| `sections[].area` | cell `area` |
| `sidebar_width` | `page.environment.sidebar_width` |
| pages-content `block.title` | `block_json.title[0].text` |
| pages-content `block.i18n.<lang>.title` | `block_json.i18n.<lang>.title` |
| `"header_data_groups/timeline-controls.json"` | a real `site.data_group` row (`timeline_controls`), referenced by name |

Note the last row: the two file-referenced data groups must become database
rows first — file paths as data group references do not survive this
migration, by design.

## 5. worked example

`nest-resource-schedule` (the fullest case: three regions, named areas, a
footer) becomes one page and three blocks:

**page** — path as today's window route, environment carries the dock hints:

```json
{"path": ["xfw/nl/window/nest-resource-schedule"],
 "environment": {"sidebar_width": "30%"}}
```

**block 1** (`sort_order` 1):

```json
{
  "region": "header",
  "grid": {"columns": "auto 1fr", "align_items": "center",
           "areas": ["breadcrumb controls"]},
  "cols": [
    {"col": [{"area": "breadcrumb"}]},
    {"col": [{"area": "controls",
              "param_json": {"data_group": "timeline_controls"}}]}
  ],
  "block_layout": "grid"
}
```

**block 2** (`sort_order` 2) — with the titles from pages-content.json:

```json
{
  "region": "main",
  "grid": {"rows": "auto 1fr", "gap": "0.5rem"},
  "i18n": {
    "nl": {"title": "Nest resource agenda"},
    "en": {"title": "Nest resource schedule"},
    "de": {"title": "Nest Ressourcen Zeitplan"}
  },
  "cols": [
    {"col": [
      {"param_json": {"data_group": "nest_schedule_filter"}},
      {"param_json": {"data_group": "nest_resource_schedule"}}
    ]}
  ],
  "block_layout": "grid"
}
```

**block 3** (`sort_order` 3):

```json
{
  "region": "footer",
  "grid": {"rows": "auto", "gap": "0.5rem"},
  "cols": [{"col": [{"param_json": {"data_group": "status_bar"}}]}],
  "block_layout": "grid"
}
```

A simple case (`nest-detail`: one section, no grid, no header/footer)
collapses to a single block — `{"cols": [{"col": [{"param_json":
{"data_group": "nest_detail"}}]}], "block_layout": "one-col", "i18n": {…}}` —
indistinguishable from the blocks that exist today.

## 6. migration steps

1. **Data groups first**: create `site.data_group` rows for the two
   file-referenced groups (`header_data_groups/timeline-controls.json` →
   `timeline_controls`).
2. **Frontend types**: extend `Content` with `region`, `grid`, `i18n` and the
   cell `area`; teach `MultiCol` to prefer an explicit `grid`; teach the page
   renderer to slot blocks by `region`; dock reads `sidebar_width` from
   `page.environment` and the tab title from `block_json.i18n`.
3. **Convert**: one script generates, per `code` in pages.json, the page row,
   the blocks (merged with the title from pages-content.json on the main
   block), the `page_block` rows and the `domain_page` row. 35 layouts, 35
   titles — small enough to review as one diff in the `json/` mirror before
   it is applied.
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
