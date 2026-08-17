// Merge data groups from the database into the repo, before an update goes the
// other way. The database is the truth for the ids given; the repo file keeps
// its own key order so the diff shows only what really changed.
//   node scripts/pull_data_group.js 76 78
// Writes json/data_group/<data_group>.json, syncs xfw3_site_data_group.json
// and rebuilds sql/update_data_group_inline.sql.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { query } = require('./lib/sqltools_pg');

const ids = process.argv.slice(2).map(Number).filter(Number.isInteger);
if (!ids.length) { console.error('usage: node scripts/pull_data_group.js <data_group_id> [...]'); process.exit(2); }

// Take `db` as the truth, but walk `file` first so existing keys keep their
// place; keys new in db are appended, keys gone from db are dropped.
function merge(file, db) {
  if (Array.isArray(db)) {
    if (!Array.isArray(file)) return db;
    return db.map((v, i) => merge(file[i], v));
  }
  if (db && typeof db === 'object') {
    if (!file || typeof file !== 'object' || Array.isArray(file)) return db;
    const out = {};
    for (const k of Object.keys(file)) if (k in db) out[k] = merge(file[k], db[k]);
    for (const k of Object.keys(db)) if (!(k in out)) out[k] = db[k];
    return out;
  }
  return db;
}

const norm = o => Array.isArray(o) ? o.map(norm)
  : (o && typeof o === 'object') ? Object.fromEntries(Object.keys(o).sort().map(k => [k, norm(o[k])]))
  : o;

(async () => {
  const rows = await query(`select data_group_id, data_group, data_group_json
                            from site.data_group where data_group_id in (${ids.join(',')}) order by 1`);
  const missing = ids.filter(id => !rows.some(r => r.data_group_id === id));
  if (missing.length) console.warn('not in site.data_group:', missing.join(','));

  const exportPath = path.join('json', 'data_group', 'xfw3_site_data_group.json');
  const all = JSON.parse(fs.readFileSync(exportPath, 'utf8'));

  for (const r of rows) {
    const file = path.join('json', 'data_group', `${r.data_group}.json`);
    const prev = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : null;
    const doc = {
      data_group_id: r.data_group_id,
      data_group: r.data_group,
      data_group_json: merge(prev && prev.data_group_json, r.data_group_json),
    };
    if (JSON.stringify(norm(doc.data_group_json)) !== JSON.stringify(norm(r.data_group_json))) throw new Error('merge lost something for ' + r.data_group);
    const changed = !prev || JSON.stringify(norm(prev.data_group_json)) !== JSON.stringify(norm(r.data_group_json));
    fs.writeFileSync(file, JSON.stringify(doc, null, 2) + '\n');
    const i = all.findIndex(x => x.data_group_id === r.data_group_id);
    if (i >= 0) all[i] = doc; else all.push(doc);
    console.log(`${r.data_group_id} ${r.data_group}: ${prev ? (changed ? 'updated from db' : 'already equal') : 'new file'}`);
  }
  fs.writeFileSync(exportPath, JSON.stringify(all, null, 2) + '\n');
  execFileSync(process.execPath, [path.join('scripts', 'build_update_data_group.js')], { stdio: 'inherit' });
})().catch(e => { console.error('ERROR', e.message); process.exit(1); });
