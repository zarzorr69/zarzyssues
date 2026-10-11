#!/usr/bin/env python3
"""Zarzysseus V10 skill-aware model advisor. Python 3.11+, standard library.

Offline catalog + read-only hardware/installed-model discovery. Download and
per-skill preference changes are explicit. The non-mutating tool probe never
executes proposed tools. No Odysseus chat/model settings are altered.
"""
from __future__ import annotations
import argparse
import ctypes
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# Catalog sizes are approximate Ollama Q4 download sizes in decimal GB, NOT
# peak RAM or tested Odysseus compatibility guarantees.
CATALOG = [
    dict(id='qwen3-vl:2b', gb=1.9, caps=['vision','tools'], quality=2, note='Small vision + tool calling'),
    dict(id='qwen3-vl:4b', gb=3.3, caps=['vision','tools'], quality=3, note='Mid-size visual agent'),
    dict(id='qwen3-vl:8b', gb=6.1, caps=['vision','tools'], quality=5, note='Browser screenshots verified in project testing with V8'),
    dict(id='qwen3-vl:30b', gb=20.0, caps=['vision','tools'], quality=7, note='Larger visual agent; tool flow unverified'),
    dict(id='qwen2.5-coder:3b', gb=1.9, caps=['code','tools'], quality=2, note='Small coding assistant'),
    dict(id='qwen2.5-coder:7b', gb=4.7, caps=['code','tools'], quality=4, note='Coding + native tools'),
    dict(id='qwen2.5-coder:14b', gb=9.0, caps=['code','tools'], quality=6, note='Larger code model'),
    dict(id='qwen3-coder:30b', gb=19.0, caps=['code','tools'], quality=8, note='Long-context coding model'),
    dict(id='llama3.1:8b', gb=4.9, caps=['tools'], quality=4, note='General tool calls; browser success depends on runtime'),
]
BY_ID = {m['id']: m for m in CATALOG}


def safe_local_url():
    host = os.environ.get('OLLAMA_HOST', '127.0.0.1:11434').strip()
    host = host.replace('http://','').replace('https://','').rstrip('/')
    if not re.fullmatch(r'(127\.0\.0\.1|localhost|\[::1\]):\d{2,5}', host):
        return 'http://127.0.0.1:11434'
    return 'http://' + host


def api(method, endpoint, payload=None, timeout=3):
    raw = None if payload is None else json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(safe_local_url()+endpoint, raw,
        {'Content-Type': 'application/json'}, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read(2_000_000).decode('utf-8'))


def installed_inventory():
    try:
        obj = api('GET', '/api/tags')
        return {m.get('name',''): m for m in obj.get('models',[]) if m.get('name')}
    except (OSError, ValueError, urllib.error.URLError):
        return {}


def installed_match(model_id, inventory):
    if model_id in inventory: return model_id
    if model_id.endswith(':latest') and model_id[:-7] in inventory: return model_id[:-7]
    if model_id + ':latest' in inventory: return model_id+':latest'
    # qwen3-vl:8b may also be labeled qwen3-vl:latest; do not infer equality
    return None


def host_ram_gb():
    if sys.platform.startswith('linux'):
        try:
            raw = Path('/proc/meminfo').read_text()
            return int(re.search(r'^MemTotal:\s*(\d+)',raw,re.M).group(1)) / 1024**2
        except (OSError, AttributeError, ValueError): pass
    if sys.platform == 'win32':
        class Memory(ctypes.Structure):
            _fields_ = [('dwLength',ctypes.c_ulong),('dwMemoryLoad',ctypes.c_ulong),
                        ('ullTotalPhys',ctypes.c_ulonglong),('ullAvailPhys',ctypes.c_ulonglong),
                        ('ullTotalPageFile',ctypes.c_ulonglong),('ullAvailPageFile',ctypes.c_ulonglong),
                        ('ullTotalVirtual',ctypes.c_ulonglong),('ullAvailVirtual',ctypes.c_ulonglong),
                        ('ullAvailExtendedVirtual',ctypes.c_ulonglong)]
        try:
            mem=Memory(); mem.dwLength=ctypes.sizeof(Memory)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(mem)):
                return mem.ullTotalPhys/1e9
        except Exception: pass
    return None


def gpu_info():
    names=[]; vram=[]
    if shutil.which('nvidia-smi'):
        try:
            out=subprocess.run(['nvidia-smi','--query-gpu=name,memory.total','--format=csv,noheader,nounits'],
                               capture_output=True,text=True,timeout=3,check=True).stdout
            for row in out.splitlines():
                name,mem=row.rsplit(',',1); names.append(name.strip()); vram.append(float(mem.strip())/1024)
        except (OSError,ValueError,subprocess.CalledProcessError): pass
    if sys.platform.startswith('linux'):
        for p in Path('/sys/class/drm').glob('card*/device/mem_info_vram_total'):
            try:
                value=int(p.read_text().strip())/1e9
                if value > .1: vram.append(value); names.append('DRM GPU')
            except (ValueError,OSError): pass
    if sys.platform == 'win32' and not vram:
        try:
            cmd=['powershell','-NoProfile','-Command',
                 'Get-CimInstance Win32_VideoController | Select-Object Name,AdapterRAM | ConvertTo-Json -Compress']
            out=subprocess.run(cmd,capture_output=True,text=True,timeout=5,check=True).stdout
            objs=json.loads(out or '[]'); objs=[objs] if isinstance(objs,dict) else objs
            for obj in objs:
                names.append(str(obj.get('Name') or 'GPU'))
                # WMI AdapterRAM often overflows above 4GiB: treat as unknown.
        except (OSError, ValueError, subprocess.CalledProcessError): pass
    return {'names':sorted(set(names)), 'vram_gb':max(vram) if vram else None}


def load_skill(project: Path, skill_name: str):
    if not re.fullmatch(r'[\w.-]{1,100}', skill_name or '') or skill_name in ('.','..'):
        raise ValueError('Skill name must be an installed folder name')
    path=project/'data'/'skills'/'imported'/skill_name/'SKILL.md'
    if not path.is_file():
        raise ValueError('Imported skill not found: '+skill_name)
    return path.read_text(encoding='utf-8',errors='replace')[:16000]


def determine_category(skill_text, explicit='auto'):
    if explicit != 'auto': return explicit
    text=skill_text.lower()
    # Strongest signals first; do not let a generic "image" text imply vision
    if re.search(r'browser_take_screenshot|playwright|screenshot|screen\s*captur|visual\s*(?:browser|agent)|computer\s*use',text): return 'vision'
    if re.search(r'generate[_ -]?image|stable diffusion|comfyui|text.to.image',text): return 'image_generation'
    if re.search(r'coding|code review|write code|refactor|git\b|javascript|typescript|development|python script|apply_patch|edit_file|run\.py',text): return 'coding'
    if re.search(r'transcription|speech.to.text|text.to.speech|audio\b|podcast',text): return 'audio'
    if re.search(r'pdf|ocr\b|analy[sz]e image|interpret photo|visual|image understanding',text): return 'vision'
    if re.search(r'research|search the web|web_search|web_fetch|browsing',text): return 'research'
    return 'general'


def needs(category):
    if category in ('vision','visual_docs'): return {'vision','tools'}
    if category=='coding': return {'code','tools'}
    if category in ('general','research','automation'): return {'tools'}
    return set()


def fit(model, ram, vram):
    # Conservative rough estimate: quant weights plus KV cache / runtime headroom.
    estimate = model['gb']*1.25 + 1.6
    if vram is not None and estimate <= vram*0.90:
        return 'gpu-fit', 3, estimate
    if ram is not None and estimate > ram*0.90:
        return 'unlikely', 0, estimate
    if ram is not None and estimate <= ram*0.75:
        return ('hybrid/CPU' if vram is not None else 'RAM-fit/GPU-unknown'), 2, estimate
    if ram is not None:
        return 'tight', 1, estimate
    return 'unknown', 1, estimate


def test_data(project):
    path=project/'data/local/zarzysseus-model-v10-tests.json'
    try:
        obj=json.loads(path.read_text(encoding='utf-8'))
        return obj if isinstance(obj,dict) else {}
    except (OSError, ValueError): return {}


def prefs_path(project): return project/'data/local/zarzysseus-model-v10-prefs.json'


def prefs(project):
    try: return json.loads(prefs_path(project).read_text(encoding='utf-8'))
    except (OSError,ValueError): return {}


def save_json(path, obj):
    path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_name(path.name+'.tmp')
    tmp.write_text(json.dumps(obj,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    try: os.chmod(tmp,0o600)
    except OSError: pass
    tmp.replace(path)


def candidates(category, inventory, ram, vram, tests, preferred=None):
    required=needs(category)
    if category in ('audio','image_generation'):
        return []  # separate runtime, not language model
    results=[]
    for m in CATALOG:
        if not required.issubset(set(m['caps'])): continue
        status, f, memory=fit(m,ram,vram)
        installed=installed_match(m['id'],inventory)
        tested=tests.get(m['id'],{})
        probed=tested.get('tool_probe') is True
        score=m['quality']*4 + (25 if f==3 else 10 if f==2 else -10 if f==1 else -35) + (36 if installed else 0) + (12 if probed else 0) - (m['gb']*.6)
        if status=='unlikely': score-=75
        if vram is None and m['gb'] > 7: score-=18  # avoid recommending very large CPU-only loads
        if category=='research' and 'vision' in m['caps']: score-=4
        if m['id']==preferred: score+=7
        results.append({**m,'installed':bool(installed),'installed_name':installed,
                        'fit':status,'estimated_gb':round(memory,1),'tool_test':'pass' if probed else ('fail' if tested.get('tool_probe') is False else 'not-tested'),
                        'score':score,'preferred':m['id']==preferred})
    return sorted(results,key=lambda x:(x['fit']=='unlikely', -x['score'] if x['fit']!='unlikely' else x['gb'],x['gb'],x['id']))


def safe_ollama_tool_test(model_id):
    # Model must be installed; does not dispatch any tool, visit sites or use files.
    schema={'type':'function','function':{'name':'diagnostic_ping','description':'A safe simulated ping; do not execute.',
            'parameters':{'type':'object','properties':{'value':{'type':'integer'}},'required':['value']}}}
    answer=api('POST','/api/chat',{'model':model_id,'stream':False,'messages':[
        {'role':'system','content':'Call diagnostic_ping with value=7. Use a structured tool call, not text.'},
        {'role':'user','content':'Call diagnostic_ping with value 7 now.'}], 'tools':[schema], 'options':{'num_predict':768}},timeout=90)
    calls=answer.get('message',{}).get('tool_calls',[])
    for c in calls:
        fn=c.get('function',{})
        arguments=fn.get('arguments',{})
        if isinstance(arguments,str):
            try: arguments=json.loads(arguments)
            except ValueError: arguments={}
        if fn.get('name')=='diagnostic_ping' and isinstance(arguments,dict) and arguments.get('value')==7:
            return True
    return False


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=['recommend','json','best','test','install','pin','pins'])
    p.add_argument('--project',required=True)
    p.add_argument('--skill',default='')
    p.add_argument('--category',choices=['auto','vision','coding','general','research','automation','audio','image_generation'],default='auto')
    p.add_argument('--model',default='')
    p.add_argument('--yes',action='store_true')
    p.add_argument('--ram-gb',type=float,default=None,help='Override undetectable RAM (for tests)')
    p.add_argument('--vram-gb',type=float,default=None,help='Override undetectable GPU VRAM (for tests)')
    args=p.parse_args(argv)
    project=Path(args.project).expanduser().resolve()
    text=load_skill(project,args.skill) if args.skill else ''
    category=determine_category(text,args.category)
    inventory=installed_inventory()
    ram=args.ram_gb if args.ram_gb is not None else host_ram_gb()
    gpu=gpu_info()
    vram=args.vram_gb if args.vram_gb is not None else gpu['vram_gb']
    saved=prefs(project)
    preferred=saved.get(args.skill,'') if args.skill else ''
    ranked=candidates(category,inventory,ram,vram,test_data(project),preferred)
    if args.action in ('recommend','json','best'):
        doc={'skill':args.skill or 'general','category':category,'hardware':{'ram_gb':round(ram,1) if ram else None,
            'gpu_names':gpu['names'],'gpu_vram_gb':round(vram,1) if vram else None},
            'ollama_reachable':bool(inventory),'suggestions':ranked,'saved_preference':preferred}
        if args.action=='json': print(json.dumps(doc,indent=2));return 0
        if args.action=='best':
            if not ranked: return 3
            print(ranked[0]['id']);return 0
        print('=== ZARZYSSEUS V10 SKILL-AWARE MODEL ADVISOR ===')
        print(f"Skill: {doc['skill']} | Workload: {category}")
        print(f"RAM: {ram:.1f} GB" if ram else 'RAM: unknown', '| GPU:', ', '.join(gpu['names']) or 'undetected', '| dedicated VRAM:',f'{vram:.1f} GB' if vram else 'unknown')
        print(f'Installed Ollama models: {len(inventory)} (0 may mean Ollama offline)')
        if not ranked:
            print('No text/vision model can directly perform this workload; configure its specialized runtime/backend.');return 0
        for i,m in enumerate(ranked[:9],1):
            print(f" {i}. {m['id']:<24} {m['fit']:<20} {'INSTALLED' if m['installed'] else 'download'} | tool-test={m['tool_test']}")
            print(f"    ~{m['gb']} GB download, ~{m['estimated_gb']} GB estimated runtime; {m['note']}")
        if preferred: print('Saved skill preference:',preferred,'(not an automatic Odysseus model switch)')
        print('Memory figures are estimates, not guarantees. Published capability != proven Odysseus integration.')
        print('Nothing is downloaded or switched by this command.')
        return 0
    if args.action=='pins':
        print(json.dumps(saved,indent=2,sort_keys=True));return 0
    if args.action=='pin':
        if not args.skill or not args.model or args.model not in BY_ID:
            p.error('pin requires --skill INSTALLED_SKILL --model KNOWN_MODEL')
        if args.model not in [m['id'] for m in ranked]: p.error('model lacks mandatory workload capabilities')
        if not args.yes: p.error('pin requires explicit --yes')
        saved[args.skill]=args.model
        save_json(prefs_path(project),saved)
        print('Saved advisory preference; active Odysseus chat model unchanged.')
        return 0
    if args.action=='test':
        if not args.model: p.error('test requires --model')
        installed=installed_match(args.model,inventory)
        if not installed:
            print('ERROR: model is not installed or Ollama is unreachable.',file=sys.stderr);return 2
        try: passed=safe_ollama_tool_test(installed)
        except (OSError,ValueError,urllib.error.URLError) as exc:
            print('ERROR: Ollama tool probe could not complete:',exc,file=sys.stderr);return 2
        results=test_data(project)
        results[args.model]={'tool_probe':passed,'timestamp':int(time.time()),'scope':'Ollama synthetic tool schema only'}
        save_json(project/'data/local/zarzysseus-model-v10-tests.json',results)
        print(('PASS' if passed else 'FAIL')+': structured diagnostic_ping tool proposal'+('' if passed else ' missing')+'. Tool was NOT executed.')
        print('This does not prove MCP, screenshot rendering or agent chat continuity.')
        return 0 if passed else 1
    if args.action=='install':
        selected=args.model or (ranked[0]['id'] if ranked else '')
        if selected not in BY_ID or selected not in [m['id'] for m in ranked]:
            print('ERROR: select a supported model for this workload (no arbitrary pull).',file=sys.stderr);return 2
        row=next(m for m in ranked if m['id']==selected)
        print(f"Proposed Ollama download: {selected} (~{row['gb']} GB). No chat model will be changed.")
        if row['installed']:
            print('Already installed; nothing downloaded.');return 0
        if row['fit']=='unlikely':
            print('WARNING: estimated memory exceeds physical RAM. Refusing automatic selection.',file=sys.stderr);return 2
        if not args.yes:
            if not sys.stdin.isatty():
                print('ERROR: interactive approval required (or explicit --yes).',file=sys.stderr);return 3
            if input('Type YES to download this model: ').strip() != 'YES':
                print('Cancelled.');return 3
        executable=shutil.which('ollama')
        if not executable:
            print('ERROR: ollama executable not found. Install Ollama first.',file=sys.stderr);return 2
        return subprocess.run([executable,'pull',selected],check=False).returncode
    return 2

if __name__=='__main__':
    raise SystemExit(main())
