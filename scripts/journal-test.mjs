import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {Journal,JournalSource} from './journal.mjs';
import {engine} from './engine.mjs';
const base=fs.mkdtempSync(path.join(os.tmpdir(),'tracelens-journal-'));
let assertions=0;
const eq=(a,b)=>{assert.deepEqual(a,b);assertions++;};
try {
  // UTF-8 and CRLF split, fresh object restart, continuation replay across durable commits.
  const file=path.join(base,'live.log');fs.writeFileSync(file,'');
  const store=new Journal(path.join(base,'live'));let source=new JournalSource(store,file,{format:'pipe'});
  const text='2026-10-20T00:00:00Z|error|api|r1|中\r\n  stack frame\n';const bytes=Buffer.from(text);
  const cut=bytes.indexOf(Buffer.from('中'))+1;
  fs.appendFileSync(file,bytes.subarray(0,cut));source.poll();source.close();
  eq(new Journal(path.join(base,'live')).recover().state.offset,cut);
  source=new JournalSource(store,file,{format:'pipe'});
  fs.appendFileSync(file,bytes.subarray(cut));source.poll();
  const recovered=store.recover();eq(Buffer.concat(recovered.records.filter(r=>r.hex).map(r=>Buffer.from(r.hex,'hex'))).toString(),text);
  const before=store.replay();eq(before.analysis.metrics.count,1);
  fs.renameSync(file,file+'.1');fs.appendFileSync(file+'.1','  late frame\n');fs.writeFileSync(file,'2026-10-20T00:00:01Z|info|api|r2|new\n');
  source.poll();eq(store.replay().analysis.metrics.count,1);
  source.rotate();eq(store.replay().analysis.metrics.count,2);
  eq(store.recover().state.generation,1);
  fs.truncateSync(file,0);source.poll();eq(store.recover().records.at(-1).loss_possible,true);source.close();
  // A second writer must not enter the journal.
  fs.writeFileSync(path.join(store.root,'writer.lock'),'');assert.throws(()=>store.commit({type:'seal'}));assertions++;
  fs.unlinkSync(path.join(store.root,'writer.lock'));
  // Kill a separate process after every persistence action. Stale lock cleanup is explicit test-owned recovery.
  for(let crash=1;crash<=7;crash++) {
    const journal=new Journal(path.join(base,'crash'+crash));journal.commit({type:'init',source:'x',identity:'inode1'});
    const result=spawnSync(process.execPath,['scripts/journal.mjs',journal.root,'commit',JSON.stringify({type:'append',offset:0,hex:'610a'})],{env:{...process.env,TRACE_CRASH_AFTER:String(crash)},encoding:'utf8'});
    eq(result.status,88);fs.unlinkSync(path.join(journal.root,'writer.lock'));
    const r=journal.recover();eq(r.state.offset,crash<6?0:2);
    if(r.state.offset===0)journal.commit({type:'append',offset:0,hex:'610a'});
    eq(journal.recover().records.filter(r=>r.hex).length,1);
  }
  const journal=new Journal(path.join(base,'corrupt'));journal.commit({type:'init',source:'x',identity:'1'});
  const committed=journal.load().manifest.head;const target=path.join(journal.batches,committed+'.json');const saved=fs.readFileSync(target);
  const tampered=JSON.parse(saved);tampered.state.offset=99;fs.writeFileSync(target,JSON.stringify(tampered));assert.throws(()=>journal.recover());assertions++;
  fs.writeFileSync(target,saved);fs.unlinkSync(target);assert.throws(()=>journal.recover());assertions++;
  // Pure framer: every byte survives arbitrary boundaries, oversized and invalid UTF-8 quarantine.
  for(let seed=1;seed<=12;seed++) {
    const input=Buffer.concat([Buffer.from('中文\r\n'+('x'.repeat(45))+'\n'),Buffer.from([255,10]),Buffer.from('last')]);
    let state=engine({operation:'stream_apply',state:null,action:{type:'init',source:'r',identity:'i',max_line_bytes:16}}).state;
    const records=[];let at=0;
    while(at<input.length){let size=Math.min(1+(at*seed+seed)%13,input.length-at);const next=engine({operation:'stream_apply',state,action:{type:'append',offset:at,hex:input.subarray(at,at+size).toString('hex')}});records.push(...next.records);state=next.state;at+=size;}
    const close=engine({operation:'stream_apply',state,action:{type:'seal'}});records.push(...close.records);
    eq(Buffer.concat(records.map(r=>Buffer.from(r.hex,'hex'))),input);eq(close.state.tail_hex,'');
    assert(records.some(r=>r.reason==='invalid_utf8'));assertions++;
  }
  console.log(JSON.stringify({journal_assertions:assertions,crash_points:7,durability:process.platform==='win32'?'process_crash_only':'file_and_directory_fsync'}));
}finally{fs.rmSync(base,{recursive:true,force:true});}
