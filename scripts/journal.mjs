import fs from 'node:fs';
import path from 'node:path';
import {engine} from './engine.mjs';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
const hashPattern=/^[a-f0-9]{64}$/;
export function checkEnvelope(value,maximum=16000000) {
  if(Buffer.byteLength(JSON.stringify(value))>maximum)throw Error('journal serialization quota');
}
function syncDirectory(dir) {
  if(process.platform==='win32') return; // explicitly reported as process-only durability on Windows
  const fd=fs.openSync(dir,'r');try{fs.fsyncSync(fd);}finally{fs.closeSync(fd);}
}
function safeRead(file) {
  const stat=fs.lstatSync(file);
  if(stat.isSymbolicLink()||!stat.isFile()||stat.size>16777216)throw Error('unsafe or oversized journal file');
  return JSON.parse(fs.readFileSync(file,'utf8'));
}
export class Journal {
  constructor(directory,{maxEnvelopeBytes=16000000}={}) {
    if(!Number.isSafeInteger(maxEnvelopeBytes)||maxEnvelopeBytes<1024||maxEnvelopeBytes>16000000)throw Error('invalid journal envelope limit');
    this.maxEnvelopeBytes=maxEnvelopeBytes;
    fs.mkdirSync(directory,{recursive:true});this.root=fs.realpathSync(directory);
    this.batches=path.join(this.root,'batches');
    fs.mkdirSync(this.batches,{recursive:true});
    if(fs.lstatSync(this.batches).isSymbolicLink())throw Error('symlink batch directory');
    syncDirectory(this.root);
  }
  load() {
    const file=path.join(this.root,'manifest.json');
    const manifest=fs.existsSync(file)?safeRead(file):null;
    const batches=[];const seen=new Set();let head=manifest?.head??null;
    while(head!==null) {
      if(!hashPattern.test(head)||seen.has(head)||batches.length>=256)throw Error('corrupt journal chain');
      seen.add(head);const batch=safeRead(path.join(this.batches,head+'.json'));
      if(batch.hash!==head)throw Error('batch filename/hash mismatch');
      batches.push(batch);head=batch.previous;
    }
    const request={manifest,batches};
    checkEnvelope(request,this.maxEnvelopeBytes);
    return request;
  }
  recover() {return engine({operation:'stream_recover',...this.load()});}
  replay(analysis={}) {return engine({operation:'stream_replay',...this.load(),analysis});}
  commit(action,{crashAfter=0}={}) {
    const lock=path.join(this.root,'writer.lock');
    const lockFd=fs.openSync(lock,'wx');let batchFd,manifestFd;let step=0;
    const checkpoint=()=>{if(++step===crashAfter)process.exit(88);};
    const temporary=path.join(this.root,'manifest.'+process.pid+'.'+randomUUID()+'.tmp');
    try {
      const loaded=this.load();
      const request={operation:'stream_plan',...loaded,action};
      if(Buffer.byteLength(JSON.stringify(request))>16777216)throw Error('request exceeds 16 MiB');
      const plan=engine(request);
      if(plan.expected_head!==(loaded.manifest?.head??null))throw Error('head conflict');
      // A committed result must fit the envelope used by subsequent load/recover.
      checkEnvelope({manifest:plan.manifest,batches:[plan.batch,...loaded.batches]},this.maxEnvelopeBytes);
      const batchPath=path.join(this.batches,plan.batch.hash+'.json');
      const content=JSON.stringify(plan.batch);
      try {batchFd=fs.openSync(batchPath,'wx');fs.writeFileSync(batchFd,content);}
      catch(error) {
        if(error.code!=='EEXIST')throw error;
        // A pre-manifest crash can leave the exact immutable batch. Never overwrite it.
        if(JSON.stringify(safeRead(batchPath))!==content)throw Error('immutable batch conflict');
        batchFd=fs.openSync(batchPath,'r+');
      }
      checkpoint();fs.fsyncSync(batchFd);checkpoint();fs.closeSync(batchFd);batchFd=undefined;
      syncDirectory(this.batches);checkpoint();
      manifestFd=fs.openSync(temporary,'wx');fs.writeFileSync(manifestFd,JSON.stringify(plan.manifest));checkpoint();
      fs.fsyncSync(manifestFd);checkpoint();fs.closeSync(manifestFd);manifestFd=undefined;
      fs.renameSync(temporary,path.join(this.root,'manifest.json'));checkpoint();
      syncDirectory(this.root);checkpoint();
      return {...plan,acknowledged:true,durability:process.platform==='win32'?'process_crash_only':'file_and_directory_fsync'};
    } finally {
      if(batchFd!==undefined)fs.closeSync(batchFd);
      if(manifestFd!==undefined)fs.closeSync(manifestFd);
      if(fs.existsSync(temporary))fs.unlinkSync(temporary);
      fs.closeSync(lockFd);fs.unlinkSync(lock);
    }
  }
}
function identity(fd){const stat=fs.fstatSync(fd,{bigint:true});return stat.dev+':'+stat.ino;}
export class JournalSource {
  constructor(journal,file,options={}) {
    const {format='jsonl',source='log',max_line_bytes=4096}=options;
    this.journal=journal;this.file=path.resolve(file);this.fd=fs.openSync(this.file,'r');
    try {
      if(!fs.fstatSync(this.fd).isFile())throw Error('source must be a regular file');
      const state=journal.recover().state;
      if(state===null)journal.commit({type:'init',source,identity:identity(this.fd),format,max_line_bytes});
      else {
        if(state.identity!==identity(this.fd))throw Error('source identity changed; drain old generation explicitly');
        if(state.closed)throw Error('source generation is sealed');
        for(const key of ['source','format','max_line_bytes']) {
          if(Object.hasOwn(options,key)&&options[key]!==state[key])throw Error('source configuration differs from checkpoint: '+key);
        }
      }
    } catch(error){fs.closeSync(this.fd);throw error;}
  }
  poll() {
    let state=this.journal.recover().state;
    if(state.identity!==identity(this.fd))throw Error('stale source reader: generation identity changed');
    if(state.closed)throw Error('source generation is sealed');
    if(fs.fstatSync(this.fd).size<state.offset){this.journal.commit({type:'rotate',identity:identity(this.fd),kind:'truncate'});state=this.journal.recover().state;}
    while(true) {
      const data=Buffer.alloc(4096);const n=fs.readSync(this.fd,data,0,data.length,state.offset);
      if(!n)break;
      state=this.journal.commit({type:'append',offset:state.offset,hex:data.subarray(0,n).toString('hex')}).state;
    }
    return state;
  }
  rotate() {
    this.poll();const next=fs.openSync(this.file,'r');
    try {
      if(identity(next)===identity(this.fd))throw Error('rename rotation requires a new source identity');
      this.journal.commit({type:'rotate',identity:identity(next),kind:'rename'});
    } catch(error){fs.closeSync(next);throw error;}
    fs.closeSync(this.fd);this.fd=next;return this.poll();
  }
  close(){fs.closeSync(this.fd);}
}
if(process.argv[1]===fileURLToPath(import.meta.url)) {
  try {
    const [directory,operation,argument]=process.argv.slice(2);const journal=new Journal(directory);
    const result=operation==='commit'?journal.commit(JSON.parse(argument),{crashAfter:Number(process.env.TRACE_CRASH_AFTER??0)}):operation==='replay'?journal.replay():operation==='recover'?journal.recover():(()=>{throw Error('usage: journal.mjs STORE recover|replay|commit [ACTION_JSON]');})();
    console.log(JSON.stringify(result));
  }catch(error){console.error(error.message);process.exitCode=1;}
}
