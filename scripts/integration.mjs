import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {root} from './engine.mjs';
const base = fs.mkdtempSync(path.join(os.tmpdir(),'tracelens-integration-'));
try {
  fs.writeFileSync(path.join(base,'app.log'),'1970-01-01T00:00:00Z|info|api|r1|start\n1970-01-01T00:00:01Z|error|api|r1|failed\n  stack continuation\n');
  fs.writeFileSync(path.join(base,'batch.jsonl'),'{"timestamp":3,"level":"warn","message":"warning"}\nbad json\n');
  const manifest=path.join(base,'manifest.json');
  fs.writeFileSync(manifest,JSON.stringify({sources:[{path:'app.log',format:'pipe'},{path:'batch.jsonl',format:'jsonl'}]}));
  const result=spawnSync(process.execPath,[path.join(root,'scripts/files.mjs'),manifest],{encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);
  const report=JSON.parse(result.stdout);
  assert.equal(report.metrics.count,3); assert.equal(report.metrics.errors,1);
  assert.equal(report.diagnostics.length,1); assert.equal(report.groups[0].elapsed_seconds,1);
  assert.ok(report.events[1].message.includes('stack continuation'));
  console.log('Log file integration: real pipe/JSONL files, multiline stack and malformed-line quarantine passed');
} finally { fs.rmSync(base,{recursive:true,force:true}); }
