#!/usr/bin/env python3
"""V10.2: guarded Cookbook task progress UI repair. Affects display/polling only.

Installs into Odysseus static/js/cookbookRunning.js with SHA256 backups. No
backend/model/download command changes. Does not depend on runtime network.
"""
import argparse, hashlib, json, os, pathlib, tempfile, sys
P='static/js/cookbookRunning.js'
M='data/local/patch-backups/cookbook-progress-v10_2.json'
MARKER='ZARZYSSEUS_COOKBOOK_PROGRESS_V10_2'

def sha(data):return hashlib.sha256(data).hexdigest()
def change(t,old,new,label):
    n=t.count(old)
    if n!=1:raise ValueError(f'{label}: upstream anchor count {n}, expected 1; no changes made')
    return t.replace(old,new,1)

# Inserted in module scope. Renders a compact bar even if the raw tmux logs are
# hidden; reports count-based progress distinctly from aggregate transfer bytes.
JS=r'''
// ZARZYSSEUS_COOKBOOK_PROGRESS_V10_2 — private UI only; no backend changes.
const _zarDlStyleId = 'zar-cookbook-download-progress-v10-2';
function _zarDlStyle() {
  if (document.getElementById(_zarDlStyleId)) return;
  const css = document.createElement('style'); css.id = _zarDlStyleId;
  css.textContent = `
    .zar-dl-card {padding:12px 12px 11px;display:grid;gap:7px;border-top:1px solid rgba(160,180,200,.1)}
    .zar-dl-line{display:flex;justify-content:space-between;gap:8px;align-items:baseline;font-size:12px;color:var(--fg-muted,#9da7b4)}
    .zar-dl-title{color:var(--fg,#e8eaf0);font-weight:600}
    .zar-dl-track{width:100%;height:9px;border-radius:999px;overflow:hidden;background:rgba(150,165,180,.17)}
    .zar-dl-fill{height:100%;width:0;background:linear-gradient(90deg,#49a2ff,#4bd6a0);border-radius:999px;transition:width .35s ease}
    .zar-dl-card[data-indeterminate="true"] .zar-dl-fill{width:30%;animation:zar-dl-move 1.4s ease-in-out infinite alternate}
    .zar-dl-card[data-state="done"] .zar-dl-fill{background:#50c878;animation:none;width:100%}
    .zar-dl-card[data-state="error"] .zar-dl-fill{background:#f26d6d;animation:none}
    .zar-dl-logs{background:none;border:0;padding:0;text-align:left;color:var(--accent,#70bfff);font-size:11px;cursor:pointer;width:max-content}
    .zar-dl-logs:hover{text-decoration:underline}
    @keyframes zar-dl-move{from{transform:translateX(0)}to{transform:translateX(230%)}}
    @media (prefers-reduced-motion:reduce){.zar-dl-fill{transition:none!important;animation:none!important}}
  `; document.head.appendChild(css);
}
function _zarDlParse(raw) {
  const lines = String(raw || '').replace(/\x1b\[[0-9;]*[A-Za-z]/g,'').replace(/\r/g,'\n');
  // Aggregate byte progress (HF Hub/hf_transfer). Prefer this over shard %.
  const bytes = [...lines.matchAll(/Downloading\s*\(incomplete[^)]*\):\s*(\d{1,3})%/ig)];
  const files = [...lines.matchAll(/Fetching\s+(\d+)\s+files:\s*(\d{1,3})%/ig)];
  if (bytes.length) return { percent: Math.min(100,+bytes[bytes.length-1][1]), stage:'Transferring model weights', unit:'bytes' };
  // HF aggregates finished files; this is not a byte-based percentage.
  if (files.length) {
    const x=files[files.length-1]; const pct=Math.min(100,+x[2]);
    return {percent:pct, stage:`Downloading · ${x[1]} files`,unit:'files'};
  }
  const done = lines.includes('DOWNLOAD_OK');
  if (done) return {percent:100,stage:'Download complete',unit:'complete'};
  if (/Reconstructing\s*\(incomplete|Reconstructing/i.test(lines)) return {percent:null,stage:'Verifying downloaded files',unit:'phase'};
  if (/Downloading bytes:/i.test(lines)) return {percent:null,stage:'Transferring model weights',unit:'phase'};
  if (/Downloading|Fetching|FILE\s+/i.test(lines)) return {percent:null,stage:'Downloading model files',unit:'phase'};
  return {percent:null,stage:'Connecting to download source',unit:'phase'};
}
function _zarDlSync(el, task, raw) {
  if (!el || task?.type !== 'download') return;
  _zarDlStyle();
  let card=el.querySelector('.zar-dl-card');
  if (!card) {
    card=document.createElement('div'); card.className='zar-dl-card';
    card.innerHTML=`<div class="zar-dl-line"><span class="zar-dl-title"></span><span class="zar-dl-pct"></span></div>
      <div class="zar-dl-track" role="progressbar" aria-label="Model download progress"><div class="zar-dl-fill"></div></div>
      <button class="zar-dl-logs" type="button">Show logs</button>`;
    const log=el.querySelector('.cookbook-output-wrap');
    if (log) log.parentNode.insertBefore(card,log); else el.appendChild(card);
    card.querySelector('.zar-dl-logs').addEventListener('click',e=>{
      e.stopPropagation();el.querySelector('.cookbook-task-header')?.click();
      const hidden=el.querySelector('.cookbook-output-wrap')?.classList.contains('cookbook-task-collapsed');
      card.querySelector('.zar-dl-logs').textContent=hidden?'Show logs':'Hide logs';
    });
  }
  const status=task.status || el.dataset.status || 'running';
  const failed=['error','failed','crashed','stopped'].includes(status);
  const complete=['done','completed'].includes(status);
  const p=_zarDlParse(raw);
  let pct = complete ? 100 : p.percent;
  if (pct != null && !complete && !failed) {
    // A resumed download may print older and newer snapshots together; don't
    // decrease the displayed value within the same task card.
    pct=Math.max(pct,Number(card.dataset.lastPct || 0));
    card.dataset.lastPct=String(pct);
  }
  card.dataset.state=failed?'error':(complete?'done':'running');
  card.dataset.indeterminate=String(pct===null && !complete && !failed);
  const heading=failed?'Download stopped':complete?'Download complete':status==='queued'?'Queued':p.stage;
  card.querySelector('.zar-dl-title').textContent=heading;
  card.querySelector('.zar-dl-pct').textContent=complete?'100%':(failed?'':(pct!==null?`${pct}%${p.unit==='files'?' of files':''}`:'Working…'));
  const bar=card.querySelector('.zar-dl-track');
  const fill=card.querySelector('.zar-dl-fill');
  fill.style.width=pct!==null?`${pct}%`:'';
  if(pct!==null)bar.setAttribute('aria-valuenow',String(pct));else bar.removeAttribute('aria-valuenow');
  bar.setAttribute('aria-valuetext',heading);
  card.querySelector('.zar-dl-logs').textContent=el.querySelector('.cookbook-output-wrap')?.classList.contains('cookbook-task-collapsed')?'Show logs':'Hide logs';
}
'''


def change_line(t, line, added, label):
    # A complete line is a safer, version-tolerant anchor than a fixed count of
    # leading spaces. Refuse ambiguous or absent matches; preserve indentation.
    import re
    matches = list(re.finditer(r'(?m)^([ \t]*)' + re.escape(line) + r'$', t))
    if len(matches) != 1:
        raise ValueError(f'{label}: upstream anchor count {len(matches)}, expected 1; no changes made')
    match = matches[0]
    indent = match.group(1)
    return t[:match.start()] + indent + added + '\n' + indent + line + t[match.end():]

def patch(t):
    if MARKER in t:raise ValueError('patch marker already present without verified manifest')
    t=change(t,'function _downloadBadgeText(progress) {',JS+'\nfunction _downloadBadgeText(progress) {','helper insertion')
    t=change(t,"      const terminalDiag = _terminalServeDiagnosis(task, el.querySelector('.cookbook-output-pre')?.textContent || task.output || '');",
        "      _zarDlSync(el, task, task.output || el.querySelector('.cookbook-output-pre')?.textContent || '');\n      const terminalDiag = _terminalServeDiagnosis(task, el.querySelector('.cookbook-output-pre')?.textContent || task.output || '');",'existing card update')
    t=change_line(t,"const _waveEl = el.querySelector('.cookbook-task-wave');",
        "_zarDlSync(el, task, task.output || '');",'new card update')
    t=change(t,"(_mobileCollapseDefault && !_shouldAutoExpandTaskOutput(task)) ? ' cookbook-task-collapsed' : ''",
        "(task.type === 'download' ? !_expandedTaskIds.has(task.sessionId) : (_mobileCollapseDefault && !_shouldAutoExpandTaskOutput(task))) ? ' cookbook-task-collapsed' : ''",'default download log collapse')
    t=change(t,"    const _streamExpanded = _wrapForStream && !_wrapForStream.classList.contains('cookbook-task-collapsed');",
        "    const _streamExpanded = task.type === 'download' || (_wrapForStream && !_wrapForStream.classList.contains('cookbook-task-collapsed'));",'polling initial')
    t=change(t,"  if (!_isRunningTabVisible() || !wrap || wrap.classList.contains('cookbook-task-collapsed')) return;",
        "  if (!_isRunningTabVisible() || !wrap || (task.type !== 'download' && wrap.classList.contains('cookbook-task-collapsed'))) return;",'polling start')
    t=change(t,"    if (!el.isConnected || !_isRunningTabVisible() || !liveWrap || liveWrap.classList.contains('cookbook-task-collapsed')) {",
        "    if (!el.isConnected || !_isRunningTabVisible() || !liveWrap || (task.type !== 'download' && liveWrap.classList.contains('cookbook-task-collapsed'))) {",'polling while closed')
    t=change(t,"        output.textContent = snapshot;",
        "        output.textContent = snapshot;\n        _zarDlSync(el, task, snapshot);",'polling refresh')
    # Closing the raw console must not abort a DOWNLOAD's progress polling.
    t=change(t,"        if (el._abort) {\n          try { el._abort.abort(); } catch {}\n          el._abort = null;\n        }",
        "        if (task.type !== 'download' && el._abort) {\n          try { el._abort.abort(); } catch {}\n          el._abort = null;\n        }",'log close behavior')
    return t

def atomic(path,raw):
    fd,tmp=tempfile.mkstemp(prefix='.zar-cb-progress-',dir=str(path.parent))
    try:
        with os.fdopen(fd,'wb') as f:f.write(raw);f.flush();os.fsync(f.fileno())
        os.chmod(tmp,path.stat().st_mode);os.replace(tmp,path)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)

def run(project,action):
    path=project/P; manifest=project/M
    if action=='status':
        if not manifest.exists():print('Cookbook compact progress V10.2: not installed');return 2
        record=json.loads(manifest.read_text()); matched=path.is_file() and sha(path.read_bytes())==record['after'];
        print('Cookbook compact progress V10.2:', 'INSTALLED' if matched else 'CHANGED; review before overwrite'); return 0 if matched else 3
    if action=='install':
        if manifest.exists():return run(project,'status')
        if not path.is_file():raise ValueError(f'missing {path}')
        old=path.read_bytes();new=patch(old.decode('utf-8')).encode('utf-8')
        backup=manifest.parent/'cookbook-progress-v10_2.before.js';backup.parent.mkdir(parents=True,exist_ok=True)
        if backup.exists() and backup.read_bytes()!=old:raise ValueError('backup conflict; refusing overwrite')
        backup.write_bytes(old)
        atomic(path,new)
        manifest.write_text(json.dumps({'version':'V10.2','file':P,'before':sha(old),'after':sha(new),'backup':str(backup.relative_to(project))},indent=2)+'\n')
        print('Cookbook V10.2: compact live download bars installed; raw logs available on demand; no download commands modified.')
        return 0
    if action=='rollback':
        if not manifest.is_file():raise ValueError('not installed')
        record=json.loads(manifest.read_text());back=project/record['backup']
        if not path.is_file() or sha(path.read_bytes())!=record['after']:raise ValueError('current source differs from V10.2; refusing overwrite')
        if not back.is_file() or sha(back.read_bytes())!=record['before']:raise ValueError('backup changed; refusing rollback')
        atomic(path,back.read_bytes());manifest.unlink();print('Cookbook V10.2: restored original progress UI');return 0
    raise ValueError('unknown mode')

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['install','status','rollback']);ap.add_argument('--project',type=pathlib.Path,required=True)
    a=ap.parse_args()
    try:sys.exit(run(a.project.resolve(),a.action))
    except (OSError,ValueError,UnicodeError,KeyError) as ex:print(f'Cookbook V10.2: {ex}',file=sys.stderr);sys.exit(1)
