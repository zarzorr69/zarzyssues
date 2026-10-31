import ast
import asyncio
import hashlib
import json
import tempfile
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from zarzysseus_task_continuation_v45 import HELPER, MARKER, patch_source, sha, run_cli

PREFIX='mcp__builtin_browser__'
TARGET=PREFIX+'browser_snapshot'
ORIGINAL='Open https://example.com. Take a screenshot and describe the page.'


def schema(required=None):
    return {'type':'function','function':{'name':TARGET,'parameters':{'type':'object','properties':{},'required':required or []}}}


def helper_functions():
    module=ast.parse(HELPER)
    namespace={}
    exec(compile(module,'<helper>', 'exec'), namespace)
    return namespace


def events(success=True, snap=False):
    out=[{'tool':PREFIX+'browser_navigate','exit_code':0},
         {'tool':PREFIX+'browser_take_screenshot','exit_code':0 if success else 1}]
    if snap:
        out.append({'tool':TARGET,'exit_code':0})
    return out


def eligible(fn,request=ORIGINAL,event=None,offered=None,**updates):
    args=dict(round_num=2,max_rounds=8,attempted=False,guide_only=False,
              force_answer=False,plan_mode=False,doc_mode=False,
              relevant_tools=None,disabled_tools=set(),tool_policy=None)
    args.update(updates)
    return fn(request,events() if event is None else event,
              [schema()] if offered is None else offered,**args)


def fixture():
    # Exact style of agent loop around V3 marker, with a prior conversion call.
    return '''# ZARZYSSEUS_BROWSER_WORKFLOW_V43
# ZARZYSSEUS_TEXT_ONLY_SCREENSHOT_HANDOFF_V44
# ZARZYSSEUS_FORCED_ADDITIVE_FOCUS_V42
import json
async def stream_agent_loop():
    max_rounds = 8
    for round_num in range(1, max_rounds + 1):
        round_response = ""
        tool_blocks, used_native, converted_calls = _resolve_tool_blocks(
            round_response, native_tool_calls, round_num, is_api_model=True)
        # ZARZYSSEUS_AGENT_THINKING_RECOVERY_V3
        if round_num == 5:
            break
'''


class PendingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ns=helper_functions()
        cls.fn=staticmethod(cls.ns['_zar_snapshot_pending_v45'])

    def test_pending(self):
        self.assertEqual(eligible(self.fn),schema())

    def test_snapshot_already_done(self):
        self.assertIsNone(eligible(self.fn,event=events(snap=True)))

    def test_screenshot_failed(self):
        self.assertIsNone(eligible(self.fn,event=events(success=False)))

    def test_unrelated_user(self):
        self.assertIsNone(eligible(self.fn,request='Write a description about Python'))

    def test_uses_user_text_not_assistant_promise(self):
        self.assertIsNone(eligible(self.fn,request='Open https://example.com.'))

    def test_disabled(self):
        self.assertIsNone(eligible(self.fn,disabled_tools={TARGET}))

    def test_explicit_caller_scope(self):
        self.assertIsNone(eligible(self.fn,relevant_tools={'web_search'}))

    def test_flags(self):
        for flag in ['attempted','guide_only','force_answer','plan_mode','doc_mode']:
            with self.subTest(flag=flag):
                self.assertIsNone(eligible(self.fn,**{flag:True}))

    def test_round_floor(self):
        self.assertIsNone(eligible(self.fn,round_num=8,max_rounds=8))

    def test_policy_block(self):
        class P:
            block_all_tool_calls=False
            def blocks(self,name):return True
        self.assertIsNone(eligible(self.fn,tool_policy=P()))

    def test_policy_unknown_fail_closed(self):
        class P: block_all_tool_calls=False
        self.assertIsNone(eligible(self.fn,tool_policy=P()))

    def test_no_snapshot_schema(self):
        self.assertIsNone(eligible(self.fn,offered=[{'type':'function','function':{'name':'web_search'}}]))

    def test_missing_required_params(self):
        self.assertIsNone(eligible(self.fn,offered=[schema(['foo'])]))

    def test_duplicate_schema(self):
        self.assertIsNone(eligible(self.fn,offered=[schema(),schema()]))

    def test_failed_snapshot_not_repeated(self):
        failed=events()+[{'tool':TARGET,'exit_code':1}]
        self.assertIsNone(eligible(self.fn,event=failed))

    def test_approval_schema_respected(self):
        class P:
            block_all_tool_calls=False
            def blocks(self,name):return False
        self.assertEqual(eligible(self.fn,tool_policy=P()),schema())

    def test_model_generated_structured_proposal(self):
        ns=helper_functions()
        class L:
            warnings=[]
            def warning(self,*a):self.warnings.append(a)
        async def fake_stream(*args,**kwargs):
            self.assertEqual([schema()],kwargs['tools'])
            yield 'data: '+json.dumps({'type':'tool_calls','calls':[{'id':'one','name':TARGET,'arguments':'{}'}]})+'\n\n'
        ns['stream_llm']=fake_stream
        ns['logger']=L()
        proposal=asyncio.run(ns['_zar_snapshot_proposal_v45']('http://localhost/v1','model',{},schema(),60))
        self.assertEqual(proposal,[{'id':'one','name':TARGET,'arguments':'{}'}])

    def test_model_narration_is_not_a_call(self):
        ns=helper_functions()
        class L:
            def warning(self,*args):pass
        async def fake_stream(*args,**kwargs):
            yield 'data: '+json.dumps({'delta':'I will call browser_snapshot'})+'\n\n'
        ns['stream_llm']=fake_stream
        ns['logger']=L()
        self.assertEqual(asyncio.run(ns['_zar_snapshot_proposal_v45']('url','model',{},schema(),50)),[])

    def test_reject_bad_args(self):
        ns=helper_functions()
        class L:
            def warning(self,*args):pass
        async def fake_stream(*args,**kwargs):
            yield 'data: '+json.dumps({'type':'tool_calls','calls':[{'name':TARGET,'arguments':'{"filename":"bad.png"}'}]})+'\n\n'
        ns['stream_llm']=fake_stream
        ns['logger']=L()
        self.assertEqual(asyncio.run(ns['_zar_snapshot_proposal_v45']('url','model',{},schema(),50)),[])

    def test_different_call_rejected(self):
        ns=helper_functions()
        class L:
            def warning(self,*args):pass
        async def fake_stream(*args,**kwargs):
            yield 'data: '+json.dumps({'type':'tool_calls','calls':[{'name':PREFIX+'browser_navigate','arguments':'{}'}]})+'\n\n'
        ns['stream_llm']=fake_stream
        ns['logger']=L()
        self.assertEqual(asyncio.run(ns['_zar_snapshot_proposal_v45']('url','model',{},schema(),50)),[])


class PatchTests(unittest.TestCase):
    def test_patch_source_and_idempotent(self):
        out=patch_source(fixture())
        self.assertIn(MARKER,out)
        ast.parse(out)
        self.assertEqual(patch_source(out),out)
        self.assertIn('    _zar_snapshot_attempted_v45 = False',out)

    def test_refuse_other_structure(self):
        with self.assertRaises(ValueError):patch_source(fixture().replace('for round_num in range(1, max_rounds + 1):','for iteration in range(1, max_rounds + 1):'))

    def test_refuse_missing_v44(self):
        with self.assertRaises(ValueError):patch_source(fixture().replace('ZARZYSSEUS_TEXT_ONLY_SCREENSHOT_HANDOFF_V44','missing'))

    def test_source_not_execution_modification(self):
        out=patch_source(fixture())
        self.assertIn('normal_dispatch=True',out)
        self.assertIn('dolphin-mistral',out)
        self.assertIn('not native_tool_calls and not tool_blocks',out)


class CLIIntegrationTests(unittest.TestCase):
    def call_cli(self, action, file):
        script = str(Path(__file__).with_name('zarzysseus_task_continuation_v45.py'))
        return subprocess.run([sys.executable,script,action,str(file)], capture_output=True,text=True)

    def test_dry_run_install_status_rollback(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)
            agent=root/'src'/'agent_loop.py'
            agent.parent.mkdir()
            agent.write_text(fixture())
            old=agent.read_bytes()
            dry=self.call_cli('dry-run',agent)
            self.assertEqual(dry.returncode,0,dry.stderr)
            self.assertEqual(old,agent.read_bytes())
            self.assertEqual(self.call_cli('install',agent).returncode,0)
            self.assertEqual(self.call_cli('status',agent).returncode,0)
            self.assertEqual(self.call_cli('rollback',agent).returncode,0)
            self.assertEqual(old,agent.read_bytes())

    def test_modified_source_refuses_rollback(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td)
            agent=root/'src'/'agent_loop.py'
            agent.parent.mkdir()
            agent.write_text(fixture())
            self.assertEqual(self.call_cli('install',agent).returncode,0)
            agent.write_text(agent.read_text()+'# modified after installation\n')
            rollback=self.call_cli('rollback',agent)
            self.assertNotEqual(rollback.returncode,0)
            self.assertIn('refused',rollback.stderr)


if __name__ == '__main__':unittest.main()
