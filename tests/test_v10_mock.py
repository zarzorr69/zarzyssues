#!/usr/bin/env python3
"""Safe offline fixture tests for V10 recommendation/routing/consent."""
import contextlib
import importlib.util
import io
import json
import os
import pathlib
import tempfile
from unittest import mock

ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('advisor',ROOT/'zarzysseus_model_advisor_v10.py')
a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)


def main():
    with tempfile.TemporaryDirectory() as d:
        root=pathlib.Path(d)
        skill=root/'data/skills/imported/website-screenshot'
        skill.mkdir(parents=True)
        (skill/'SKILL.md').write_text('---\nname: Website Screenshot\n---\nUse browser_take_screenshot and playwright.\n')
        assert a.determine_category(a.load_skill(root,'website-screenshot'))=='vision'
        assert a.determine_category('Update a Python script and run.py')=='coding'
        assert a.determine_category('Search the web')=='research'
        assert a.determine_category('ComfyUI and text-to-image')=='image_generation'
        assert a.needs('vision')=={'vision','tools'}
        assert a.candidates('audio',{},32,8,{})==[]
        # Hardware fit prioritizes small fully GPU-resident models over CPU-offload.
        ranks=a.candidates('vision',{},16,8,{})
        assert ranks[0]['id']=='qwen3-vl:4b',ranks
        assert ranks[-1]['fit']=='unlikely'
        # Already-installed models outrank uninstalled candidates where runnable.
        installed={'qwen3-vl:8b':{'name':'qwen3-vl:8b'}}
        ranks=a.candidates('vision',installed,16,8,{})
        assert ranks[0]['id']=='qwen3-vl:8b'
        assert all('vision' in m['caps'] for m in ranks)
        assert all('vision' not in m['caps'] for m in a.candidates('coding',{},24,12,{}))
        # Approval and remote edits not allowed for arbitrary model IDs.
        with mock.patch.object(a,'installed_inventory',return_value={}):
            with mock.patch.object(a,'gpu_info',return_value={'names':[],'vram_gb':8}):
                buf=io.StringIO()
                with contextlib.redirect_stdout(buf), mock.patch.object(a,'subprocess') as run:
                    rc=a.main(['install','--project',str(root),'--skill','website-screenshot','--model','bad:unknown','--yes','--ram-gb','16'])
                    assert rc==2
                    run.run.assert_not_called()
                with contextlib.redirect_stdout(io.StringIO()):
                    try:
                        a.main(['pin','--project',str(root),'--skill','website-screenshot','--model','qwen3-vl:4b','--ram-gb','16'])
                        assert False, 'Missing --yes should fail'
                    except SystemExit as exc: assert exc.code==2
                    rc=a.main(['pin','--project',str(root),'--skill','website-screenshot','--model','qwen3-vl:4b','--yes','--ram-gb','16'])
                    assert rc==0
        assert a.prefs(root)=={'website-screenshot':'qwen3-vl:4b'}
        assert not list((root/'data/local').glob('*tests.json'))
        # Fake tool response: one structured proposal, no execution.
        with mock.patch.object(a,'api',return_value={'message':{'tool_calls':[{'function':{'name':'diagnostic_ping','arguments':{'value':7}}}]}}) as req:
            assert a.safe_ollama_tool_test('qwen3-vl:8b') is True
            assert req.call_args.args[:2]==('POST','/api/chat')
        # Embedded helper must have exact same bytes in both launchers.
        h=(ROOT/'zarzysseus_model_advisor_v10.py').read_text().rstrip()
        bash=(ROOT/'zarzysseus.sh').read_text()
        ps1=(ROOT/'zarzysseus.ps1').read_text()
        assert bash.split("<<'PY_SKILL_MODEL_V10'\n",1)[1].split('\nPY_SKILL_MODEL_V10',1)[0]==h
        assert ps1.split('function Invoke-ModelAdvisorV10',1)[1].split("$source=@'\n",1)[1].split("\n'@",1)[0]==h
        print('PASS: categorization, hardware fit, installed preference, consent, Ollama tool probe, embedded source identity')

if __name__=='__main__': main()
