#!/usr/bin/env python3
"""Offline fixture validation only; live Odysseus Cookbook untested."""
import pathlib
import subprocess
import tempfile
import sys
import json

FIXTURE_JS = '''// cookbook synthetic upstream fixture
const _hwfitCache = {system:{backend:'rocm'}};
const _isWindows=() => false;
export function _detectBackend(model) {
  const _ollamaName = String(model?.repo_id || model?.name || model?.id || '').trim();
  const _ollamaMeta = `${model?.backend || ''} ${model?.endpoint_kind || ''} ${model?.provider || ''} ${model?.source || ''}`.toLowerCase();
  const _looksLikeOllamaTag = /^[A-Za-z0-9][A-Za-z0-9._-]*(?::[A-Za-z0-9][A-Za-z0-9._-]*)$/.test(_ollamaName);
  if (model?.backend === 'ollama' || model?.is_ollama || _ollamaMeta.includes('ollama') || _looksLikeOllamaTag) return { backend:'ollama' };
  const q = (model.quant || '').toUpperCase();
  const sysBackend = String(_hwfitCache?.system?.backend || '').toLowerCase();
  const isRocm = sysBackend === 'rocm';
  const _nm = `${model.repo_id || ''} ${model.path || ''} ${model.name || ''}`.toLowerCase();
  const hasGgufFile = Array.isArray(model.gguf_files) && model.gguf_files.some(f => f && typeof f.rel_path === 'string' && /\\.gguf$/i.test(f.rel_path));
  const isGgufLike = model.is_gguf || hasGgufFile || /^Q[2-8]/.test(q) || /^IQ/.test(q) || q === 'GGUF' || _nm.includes('gguf');
  // GGUF → llama.cpp/Ollama-compatible.
  if (isGgufLike) { return {backend:'llamacpp'}; }
  if (isRocm) return {backend:'sglang'};
  return {backend:'vllm'};
}
'''
FIXTURE_DL = '''// synthetic
export async function _runModelDownload(panel, model, backend, hostOverride) {
  const ggufSource = null;
  const repo = backend === 'ollama'
    ? (model.ollama || model.ollama_name || model.name)
    : (ggufSource?.repo || model.quant_repo || model.name);
  return repo;
}
'''
FIXTURE_HW = '''// synthetic
export function _hwfitRenderList(el, models) {
  if (!el) return;
  models = _sortHwfitRows(models);
  return models;
}
export function _expandModelRow(row, modelData) {
  let html = '';
  if (modelData.is_image_gen) {
    html += `<div style="font-size:10px;opacity:0.5;margin-top:4px;">${(modelData.capabilities || []).join('')}</div>`;
  }
  return html;
}
'''

HERE=pathlib.Path(__file__).resolve().parent
helper=(HERE/'zarzysseus_cookbook_oneclick_v10_1.py') if (HERE/'zarzysseus_cookbook_oneclick_v10_1.py').exists() else (HERE.parent/'zarzysseus_cookbook_oneclick_v10_1.py')
with tempfile.TemporaryDirectory(prefix='test-zar-cb-') as tmp:
    root=pathlib.Path(tmp)
    for path,text in {'static/js/cookbook.js':FIXTURE_JS,'static/js/cookbookDownload.js':FIXTURE_DL,'static/js/cookbook-hwfit.js':FIXTURE_HW}.items():
        dest=root/path; dest.parent.mkdir(parents=True,exist_ok=True); dest.write_text(text)
    def call(action,rc=0):
        ret=subprocess.run([sys.executable,str(helper),action,'--project',str(root)],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if ret.returncode!=rc: raise RuntimeError(f'{action}: exit {ret.returncode} (expected {rc}) stdout:{ret.stdout} stderr:{ret.stderr}')
        return ret
    call('status',2);call('install');call('install');call('status')
    f=root/'static/js/cookbook.js';txt=f.read_text();assert 'ZARZYSSEUS_COOKBOOK_NATIVE_ROUTING_V10_1' in txt
    for name in ('cookbook.js','cookbookDownload.js','cookbook-hwfit.js'):
        p=root/'static/js'/name
        test=subprocess.run(['node','--check','--input-type=module'],input=p.read_text(),text=True,capture_output=True)
        if test.returncode: raise AssertionError(f'{name}: {test.stderr}')
    # Slice tested function and execute it with synthetically chosen hardware/backend.
    before=txt.index('export function _detectBackend(model)')
    end=txt.index('\n}',before)+2
    func=txt[before:end].replace('export function','function')
    check='''const _hwfitCache={system:{backend:'rocm'}};const _isWindows=()=>false;
    %s
    function fit(m){return _detectBackend(m).backend;}
    function eq(a,b){if(a!==b) throw Error(a+' != '+b);}
    eq(fit({name:'mistralai/Voxtral-Mini-4B-Realtime-Arabic',quant:'Q4_K_M'}),'vllm');
    eq(fit({name:'some-org/Text-Model',quant:'Q4_K_M'}),'sglang');
    eq(fit({name:'some-org/Text-GGUF',quant:'Q4_K_M'}),'llamacpp');
    eq(fit({name:'some-org/Text-Model',quant:'Q4_K_M',gguf_sources:[{repo:'some-org/Text-GGUF'}]}),'llamacpp');
    eq(fit({name:'some-org/Text-Model',quant:'Q4_K_M',quant_repo:'some-org/Text-GGUF'}),'llamacpp');
    eq(fit({name:'some-org/Text-Model',quant:'BF16'}),'sglang');
    eq(fit({name:'qwen3-vl:8b',backend:'ollama'}),'ollama');
    ''' %func
    test=subprocess.run(['node','-e',check],text=True,capture_output=True)
    if test.returncode: raise AssertionError(test.stderr)
    # Verify one-click non-GGUF download uses the official native HF repository,
    # even if an unusable quant_repo is present in catalog metadata.
    dltxt=(root/'static/js/cookbookDownload.js').read_text()
    testdl=dltxt.replace('export async function','async function') + "\n_runModelDownload(null,{name:'mistralai/Voxtral-Mini-4B-Realtime-Arabic',quant_repo:'wrong/quant',_zarNativeOnly:true},'vllm').then(r=>{if(r!=='mistralai/Voxtral-Mini-4B-Realtime-Arabic')throw Error('wrong source: '+r)})"
    test=subprocess.run(['node','-e',testdl],text=True,capture_output=True)
    if test.returncode: raise AssertionError(test.stderr)
    hw=(root/'static/js/cookbook-hwfit.js').read_text()
    hwscript="const _sortHwfitRows=m=>m;"+hw.replace('export function','function')+"\nconst x=_hwfitRenderList({},[{name:'mistralai/Voxtral-Mini-4B-Realtime-Arabic',quant:'Q4_K_M',required_gb:3.2,quant_repo:'wrong/quant'}]);if(x[0].quant!=='BF16'||x[0].required_gb<10||x[0].quant_repo!==null)throw Error(JSON.stringify(x));"
    test=subprocess.run(['node','-e',hwscript],text=True,capture_output=True)
    if test.returncode: raise AssertionError(test.stderr)
    call('rollback');call('status',2)
    assert f.read_text()==FIXTURE_JS
    # Refuse unknown upstream layouts WITHOUT writing anything.
    f.write_text(FIXTURE_JS.replace('// GGUF → llama.cpp/Ollama-compatible.','// source changed elsewhere'))
    err=call('install',1)
    assert (root/'static/js/cookbookDownload.js').read_text()==FIXTURE_DL
    assert not (root/'data/local/patch-backups/cookbook-native-routing-v10_1.json').exists()
print('PASS: patch/install/status/rollback, 3 JS syntactic checks, 7 backend decisions + native download/source label, fail-closed on upstream mismatch')
