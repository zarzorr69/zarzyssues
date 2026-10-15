#!/usr/bin/env python3
"""Offline unit/integration fixtures; no claims of live Ollama/GUI validation."""
import json, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import zarzysseus_cookbook_autoadd_v11_6 as m

BASE = '''import uiModule from './ui.js';
const _tasks = [];
function _loadTasks(){return _tasks;}
function _saveTasks(tasks){}
function _refreshServerDots(){}
function _updateTask(sessionId, updates) {
  const tasks = _loadTasks();
  const task = tasks.find(t => t.sessionId === sessionId);
  if (task) {
    Object.assign(task, updates);
    _saveTasks(tasks);
  }
  if ('status' in updates || '_unreachable' in updates) {
    _refreshServerDots();
  }
}
'''
assert BASE.count(m.ANCHOR)==1
assert 'ZARZYSSEUS_COOKBOOK_OLLAMA_AUTOADD_V11_6' in m.transform(BASE)
assert BASE != m.transform(BASE)
with tempfile.TemporaryDirectory() as t:
    root=pathlib.Path(t)
    f=root/m.TARGET
    f.parent.mkdir(parents=True)
    f.write_text(BASE)
    assert m.status(root)==2
    assert m.install(root)==0
    assert m.install(root)==0
    assert m.status(root)==0
    patched=f.read_text()
    # syntax check ESM (with import at top). Should work even when comment code
    # arrives ahead of function declarations.
    n=subprocess.run(['node','--check','--input-type=module'],input=patched,text=True,capture_output=True)
    assert n.returncode==0,n.stderr
    # Mock browser API to test successful local verified registration + refresh.
    # Extract only the added helper and its hook, avoiding dynamic import resolution.
    block=patched[patched.index('// '+m.MARKER):patched.index('function _updateTask(sessionId, updates)')]
    func=patched[patched.index('function _updateTask(sessionId, updates)'):]
    scripted='''
const calls=[];
const uiModule={showToast:message=>calls.push(['toast',message])};
const window={modelsModule:{refreshModels:async()=>calls.push(['refresh'])}};
const _tasks=[];
const _loadTasks=()=>_tasks;
const _saveTasks=()=>{};
const _refreshServerDots=()=>{};
class FormData{constructor(){this.data={}}set(k,v){this.data[k]=v}}
const fetch=async (url,opts={})=>{
  calls.push(['fetch',url]);
  if(url==='/api/runtime')return {ok:true,json:async()=>({ollama_base_url:'http://127.0.0.1:11434/v1',in_docker:false})};
  if(url==='/api/model-endpoints/test')return {ok:true,json:async()=>({models:['qwen3:8b','llama3.1:8b']})};
  if(url==='/api/model-endpoints')return {ok:true,json:async()=>({})};
  throw Error(url);
};
''' + block +func+'''
_tasks.push({sessionId:'test1',type:'download',payload:{backend:'ollama',repo_id:'qwen3:8b'},remoteHost:''});
_updateTask('test1',{status:'done'});
setTimeout(()=>{
  if(calls.filter(x=>x[0]==='fetch').length!==3)throw Error(JSON.stringify(calls));
  if(calls.filter(x=>x[0]==='refresh').length!==1)throw Error(JSON.stringify(calls));
  _updateTask('test1',{status:'done'});
  _tasks.push({sessionId:'test2',type:'download',payload:{backend:'sglang',repo_id:'google/tipsv2-g14'}});
  _updateTask('test2',{status:'done'});
  _tasks.push({sessionId:'test3',type:'download',payload:{backend:'ollama',repo_id:'qwen3:8b'},remoteHost:'remote'});
  _updateTask('test3',{status:'done'});
  setTimeout(()=>{if(calls.filter(x=>x[0]==='fetch').length!==3)throw Error('unexpected network call');console.log('PASS success + dedupe + no HF or remote registration')},20);
},25);
'''
    result=subprocess.run(['node','--input-type=module','-e',scripted],capture_output=True,text=True)
    assert result.returncode==0,result.stderr
    assert 'PASS success' in result.stdout
    # Negative verification: no Ollama inventory entry => no endpoint created
    scripted2=scripted.replace("models:['qwen3:8b','llama3.1:8b']","models:['llama3.1:8b']").replace("if(calls.filter(x=>x[0]==='fetch').length!==3)","if(calls.filter(x=>x[0]==='fetch').length!==2)").replace("if(calls.filter(x=>x[0]==='refresh').length!==1)","if(calls.filter(x=>x[0]==='refresh').length!==0)").replace("console.log('PASS success + dedupe + no HF or remote registration')", "console.log('PASS missing inventory fails closed')")
    result=subprocess.run(['node','--input-type=module','-e',scripted2],capture_output=True,text=True)
    assert result.returncode==0,result.stderr
    # rollback exact
    assert m.rollback(root)==0
    assert f.read_text()==BASE
    # unfamiliar upstream never patched
    f.write_text(BASE.replace('    _saveTasks(tasks);','    window._saveTasks(tasks);'))
    before=f.read_bytes()
    try: m.install(root)
    except ValueError: pass
    else: raise AssertionError('Unknown upstream accepted')
    assert before==f.read_bytes()
print('PASS V11.6: ESM syntax, ready+missing Ollama inventory, no HF/remote registration, repeated install, guarded rollback, fail-closed layout')
