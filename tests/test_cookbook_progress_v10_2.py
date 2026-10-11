from pathlib import Path
import importlib.util, tempfile, subprocess, json, shutil
root=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('p',root/'zarzysseus_cookbook_progress_v10_2.py'); p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
# Known Odysseus upstream anchors from dev branch in an intentionally tiny fixture.
fixture='''function _downloadBadgeText(progress) { return progress; }
function testCards(el,task) {
      const terminalDiag = _terminalServeDiagnosis(task, el.querySelector('.cookbook-output-pre')?.textContent || task.output || '');
     const _waveEl = el.querySelector('.cookbook-task-wave');
     const a = `<div class="cookbook-output-wrap cookbook-task-collapsible${(_mobileCollapseDefault && !_shouldAutoExpandTaskOutput(task)) ? ' cookbook-task-collapsed' : ''}">`;
    const _streamExpanded = _wrapForStream && !_wrapForStream.classList.contains('cookbook-task-collapsed');
  if (!_isRunningTabVisible() || !wrap || wrap.classList.contains('cookbook-task-collapsed')) return;
    if (!el.isConnected || !_isRunningTabVisible() || !liveWrap || liveWrap.classList.contains('cookbook-task-collapsed')) {
        output.textContent = snapshot;
        if (el._abort) {
          try { el._abort.abort(); } catch {}
          el._abort = null;
        }
}
'''
with tempfile.TemporaryDirectory() as td:
    rootp=Path(td);path=rootp/p.P;path.parent.mkdir(parents=True);path.write_text(fixture)
    assert p.run(rootp,'install')==0
    text=path.read_text()
    assert p.MARKER in text
    assert p.run(rootp,'status')==0
    assert p.run(rootp,'install')==0
    assert p.run(rootp,'rollback')==0
    assert path.read_text()==fixture
    # fail-closed on unexpected new versions; no backup writing
    path.write_text(fixture.replace('function _downloadBadgeText(progress)', 'function _oldBadge(progress)'))
    try:p.run(rootp,'install')
    except ValueError:pass
    else:assert False,'expected mismatch'
    assert not (rootp/p.M).exists()
    # JS test: actual injected helper, console output and realistic HF formats
    parser=text.split('function _downloadBadgeText(progress) {',1)[0]
    nodeTest=parser+'''
const assert=require('node:assert/strict');
let r=_zarDlParse('Downloading (incomplete total...): 73% | 1.81G/2.49G');
assert.equal(r.percent,73);assert.equal(r.unit,'bytes');
r=_zarDlParse('Downloading bytes: 31.5MB\\nReconstructing (incomplete total...): 28%\\nFetching 5 files: 40%');
assert.equal(r.percent,40);assert.equal(r.unit,'files');
r=_zarDlParse('model-00001-of-00008.safetensors: 56%|###');
assert.equal(r.percent,null);
r=_zarDlParse('DOWNLOAD_OK');assert.equal(r.percent,100);
console.log('JS progress parser PASS');
'''
    f=rootp/'parse.cjs';f.write_text(nodeTest)
    subprocess.run(['node','--check',str(f)],check=True)
    subprocess.run(['node',str(f)],check=True)
print('SOURCE PATCH/ROLLBACK/FAIL-CLOSED PASS')
# Assert helpers embedded identically in both installer languages.
helper=(root/'zarzysseus_cookbook_progress_v10_2.py').read_text()
assert helper in (root/'zarzysseus.sh').read_text()
assert helper in (root/'zarzysseus.ps1').read_text()
print('EMBEDDED LINUX/WINDOWS HELPER MATCH: PASS')
