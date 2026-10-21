import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {Journal,JournalSource,checkEnvelope} from './journal.mjs';
import {engine} from './engine.mjs';
const base=fs.mkdtempSync(path.join(os.tmpdir(),'tracelens-review-'));
let checks=0;
try {
  const file=path.join(base,'input.log');fs.writeFileSync(file,'');
  const journal=new Journal(path.join(base,'store'));
  const first=new JournalSource(journal,file,{source:'audit',format:'pipe',max_line_bytes:128});
  for(const options of [{source:'wrong'},{format:'jsonl'},{max_line_bytes:4096}]) {
    assert.throws(()=>new JournalSource(journal,file,options),/configuration differs/);checks++;
  }
  const stale=new JournalSource(journal,file); // unspecified options inherit committed configuration
  fs.renameSync(file,file+'.old');fs.writeFileSync(file,'');first.rotate();
  assert.throws(()=>stale.poll(),/stale source reader/);checks++;stale.close();first.close();
  journal.commit({type:'seal'});
  assert.throws(()=>new JournalSource(journal,file),/sealed/);checks++;
  const before=journal.recover().revision;
  assert.throws(()=>journal.replay({sources:[]}),/cannot replace/);checks++;
  assert.equal(journal.recover().revision,before);checks++;
  assert.throws(()=>engine({operation:'stream_replay',manifest:null,batches:[],typo:true}),/unknown replay field/);checks++;
  const sample={manifest:null,batches:[{text:'中文'}]};const size=Buffer.byteLength(JSON.stringify(sample));
  checkEnvelope(sample,size);checks++;
  assert.throws(()=>checkEnvelope(sample,size-1),/serialization quota/);checks++;
  // PID reuse/old temp residue must not collide with a new commit or be deleted implicitly.
  const next=new Journal(path.join(base,'temporary'));
  const residue=path.join(next.root,'manifest.'+process.pid+'.tmp');fs.writeFileSync(residue,'old residue');
  next.commit({type:'init',source:'test',identity:'1'});
  assert.equal(next.recover().revision,1);checks++;
  assert.equal(fs.readFileSync(residue,'utf8'),'old residue');checks++;
  assert.throws(()=>new JournalSource(new Journal(path.join(base,'directory')),base),/regular file|EPERM|EISDIR/);checks++;
  const bounded=new Journal(path.join(base,'bounded'),{maxEnvelopeBytes:4096});
  bounded.commit({type:'init',source:'q',identity:'1'});const head=bounded.load().manifest.head;
  assert.throws(()=>bounded.commit({type:'append',offset:0,hex:'0a'.repeat(64)}),/serialization quota/);checks++;
  assert.equal(bounded.load().manifest.head,head);checks++;
  assert.equal(bounded.recover().state.offset,0);checks++;
  assert.equal(fs.readdirSync(bounded.batches).length,1);checks++;
  console.log(JSON.stringify({review_host_checks:checks}));
}finally{fs.rmSync(base,{recursive:true,force:true});}
