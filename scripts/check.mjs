import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {engine, root} from './engine.mjs';
let passed = 0;
for (const test of JSON.parse(fs.readFileSync(path.join(root, 'tests/cases.json'), 'utf8'))) {
  if (test.error) assert.throws(() => engine(test.request), undefined, test.name);
  else {
    const result = engine(test.request);
    for (const [key, expected] of Object.entries(test.expected)) {
      const parts = key.startsWith('origins/') ? ['origins', key.slice(8)] : key.split('/');
      let actual = result;
      for (const part of parts) actual = actual[part];
      assert.deepEqual(actual, expected, test.name + ': ' + key);
    }
  }
  passed++;
}
console.log('CLI fixture cases passed:', passed);
