// Read-only access to the xfw3 database through the SQLTools PostgreSQL driver
// that is installed in VS Code, with the connection from the user settings.
// Nothing is installed, nothing is stored here: the credentials stay in
// %APPDATA%/Code/User/settings.json (sqltools.connections).
const fs = require('fs');
const path = require('path');
const os = require('os');

function driverClass() {
  const dir = path.join(os.homedir(), '.vscode', 'extensions');
  const ext = fs.readdirSync(dir).filter(d => d.startsWith('mtxr.sqltools-driver-pg-')).sort().pop();
  if (!ext) throw new Error('SQLTools PostgreSQL driver not found under ' + dir);
  const plugin = require(path.join(dir, ext, 'out', 'ls', 'plugin.js')).default;
  const drivers = new Map();
  plugin.register({ getContext: () => ({ drivers }) });
  return drivers.get('PostgreSQL');
}

function connection(name) {
  const settings = JSON.parse(fs.readFileSync(path.join(process.env.APPDATA, 'Code', 'User', 'settings.json'), 'utf8'));
  const list = settings['sqltools.connections'] || [];
  const conn = name ? list.find(c => c.name === name) : list.find(c => c.driver === 'PostgreSQL');
  if (!conn) throw new Error('no SQLTools PostgreSQL connection in the VS Code user settings');
  return conn;
}

// query(sql) -> rows. Only select/with/explain/show; anything else throws.
async function query(sql, connName) {
  if (!/^\s*(select|with|explain|show)\b/i.test(sql)) throw new Error('read-only: only select/with/explain/show');
  const Driver = driverClass();
  const conn = connection(connName);
  const d = new Driver(conn, () => []);
  try {
    const res = await d.query(sql, {});
    const r = res[0];
    if (r.error) {
      const msg = (r.rawError && r.rawError.message) || JSON.stringify(r.messages);
      // the driver wraps a refused connection in an AggregateError without text
      throw new Error(/AggregateError|ECONNREFUSED/.test(msg)
        ? `cannot reach ${conn.server}:${conn.port} — is the ssh tunnel (VS Code task ssh-tunnel-postgres) running?`
        : msg);
    }
    return r.results;
  } finally {
    await d.close().catch(() => {});
  }
}

module.exports = { query };
