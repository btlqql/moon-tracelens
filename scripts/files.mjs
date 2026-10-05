import fs from 'node:fs';
import path from 'node:path';
import {engine} from './engine.mjs';
try {
  const [manifest] = process.argv.slice(2);
  if (!manifest) throw new Error('Usage: node scripts/files.mjs manifest.json');
  const base = fs.realpathSync(path.dirname(path.resolve(manifest)));
  const request = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  request.sources = request.sources.map(source => {
    const file = fs.realpathSync(path.resolve(base, source.path));
    if (!file.startsWith(base + path.sep)) throw new Error('Log file leaves manifest directory');
    if (!fs.statSync(file).isFile() || fs.statSync(file).size > 4 * 1024 * 1024) throw new Error('Log source must be a file under 4 MiB');
    return {...source, name: source.name ?? source.path,
      text: new TextDecoder('utf-8', {fatal: true}).decode(fs.readFileSync(file))};
  });
  console.log(JSON.stringify(engine(request), null, 2));
} catch (err) { console.error(err.message); process.exitCode = 1; }
