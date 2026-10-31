"""Offline regression tests; no browser, Ollama or MCP calls."""
import ast
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from zarzysseus_approved_replay_v471 import patch_source, MARKER

ROOT=Path(__file__).parent
SCREENSHOT='mcp__builtin_browser__browser_take_screenshot'
NAV='mcp__builtin_browser__browser_navigate'
REQUEST='Open https://example.com, take a screenshot and display it here, then read and describe it.'


def fake_agent():
    helper=(ROOT/'fixture_v46_helper.py').read_text()
    agent='''# ZARZYSSEUS_TEXT_ONLY_SCREENSHOT_HANDOFF_V44
import re
async def stream_agent_loop(*, exact_approval=None):
    max_rounds = 8
    for round_num in range(1, max_rounds + 1):
        # ZARZYSSEUS_BOUNDED_SCREENSHOT_CONTINUATION_V46
        if (not native_tool_calls and not tool_blocks and not _zar_shot_attempted_v46 and _is_api_model):
            _zar_shot_schema_v46 = _zar_shot_pending_v46(
                _last_user, tool_events, all_tool_schemas,
                attempted=_zar_shot_attempted_v46,
                round_num=round_num, max_rounds=max_rounds,
                guide_only=guide_only, force_answer=_force_answer,
                plan_mode=plan_mode, doc_mode=_ody_doc_finetune_mode,
                relevant_tools=relevant_tools,
                disabled_tools=disabled_tools, tool_policy=tool_policy,
            )
            if _zar_shot_schema_v46 is not None:
                pass
        # ZARZYSSEUS_BOUNDED_SNAPSHOT_CONTINUATION_V45
        if round_num>99:
            break
'''
    return helper + '\n' + agent


def functions():
    source=patch_source(fake_agent())
    ast.parse(source)
    tree=ast.parse(source)
    item=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='_zar_shot_pending_v46')
    ns={}
    exec(compile(ast.Module(body=[item],type_ignores=[]),'<helper>','exec'),ns)
    return ns['_zar_shot_pending_v46']


def schema():
    return {'type':'function','function':{'name':SCREENSHOT,'parameters':{
        'type':'object','required':[],
        'properties':{'type':{'type':'string','enum':['png','jpeg']},
                      'scale':{'type':'string','enum':['css','device']},
                      'fullPage':{'type':'boolean'}}}}}


def permitted(f, request=REQUEST, relevant_tools=None, approval_replay=False,
              offered=None, nav_success=True, already_shot=False, **options):
    events=[{'tool':NAV,'exit_code':0 if nav_success else 1}]
    if already_shot:events.append({'tool':SCREENSHOT,'exit_code':1})
    flags=dict(attempted=False,round_num=2,max_rounds=8,guide_only=False,
               force_answer=False,plan_mode=False,doc_mode=False,
               relevant_tools=relevant_tools,disabled_tools=set(),tool_policy=None,
               approval_replay=approval_replay)
    flags.update(options)
    return f(request,events,[schema()] if offered is None else offered,**flags)

class TestReplayGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.fn=staticmethod(functions())
    def test_normal_unscoped(self): self.assertIsNotNone(permitted(self.fn))
    def test_denied_explicit_scope(self): self.assertIsNone(permitted(self.fn,relevant_tools={SCREENSHOT},approval_replay=False))
    def test_replay_matching_scope(self): self.assertIsNotNone(permitted(self.fn,relevant_tools={SCREENSHOT,NAV},approval_replay=True))
    def test_replay_with_unrelated_scope(self): self.assertIsNone(permitted(self.fn,relevant_tools={'web_fetch'},approval_replay=True))
    def test_replay_scope_unknown_type(self): self.assertIsNone(permitted(self.fn,relevant_tools={'extra':True},approval_replay=True))
    def test_replay_scope_list(self): self.assertIsNotNone(permitted(self.fn,relevant_tools=[SCREENSHOT],approval_replay=True))
    def test_replay_no_screenshot_schema(self): self.assertIsNone(permitted(self.fn,relevant_tools={SCREENSHOT},approval_replay=True,offered=[]))
    def test_replay_disabled(self): self.assertIsNone(permitted(self.fn,relevant_tools={SCREENSHOT},approval_replay=True,disabled_tools={SCREENSHOT}))
    def test_replay_nav_failed(self): self.assertIsNone(permitted(self.fn,relevant_tools={SCREENSHOT},approval_replay=True,nav_success=False))
    def test_replay_already_shot(self): self.assertIsNone(permitted(self.fn,relevant_tools={SCREENSHOT},approval_replay=True,already_shot=True))
    def test_replay_no_intent(self): self.assertIsNone(permitted(self.fn,request='Open https://example.com',relevant_tools={SCREENSHOT},approval_replay=True))
    def test_replay_no_url(self): self.assertIsNone(permitted(self.fn,request='Take a screenshot of this',relevant_tools={SCREENSHOT},approval_replay=True))
    def test_replay_no_call_without_approval(self): self.assertIsNone(permitted(self.fn,relevant_tools={SCREENSHOT},approval_replay=False))
    def test_replay_unknown_policy(self):
        class Policy: block_all_tool_calls=False
        self.assertIsNone(permitted(self.fn,relevant_tools={SCREENSHOT},approval_replay=True,tool_policy=Policy()))
    def test_replay_denied_policy(self):
        class Policy:
            block_all_tool_calls=False
            def blocks(self,n):return True
        self.assertIsNone(permitted(self.fn,relevant_tools={SCREENSHOT},approval_replay=True,tool_policy=Policy()))
    def test_replay_allowed_policy(self):
        class Policy:
            block_all_tool_calls=False
            def blocks(self,n):return False
        self.assertIsNotNone(permitted(self.fn,relevant_tools={SCREENSHOT},approval_replay=True,tool_policy=Policy()))
    def test_replay_plan_blocks(self):self.assertIsNone(permitted(self.fn,relevant_tools={SCREENSHOT},approval_replay=True,plan_mode=True))
    def test_replay_max_rounds(self):self.assertIsNone(permitted(self.fn,relevant_tools={SCREENSHOT},approval_replay=True,round_num=8))
    def test_replay_attempted(self):self.assertIsNone(permitted(self.fn,relevant_tools={SCREENSHOT},approval_replay=True,attempted=True))

class TestASTMatching(unittest.TestCase):
    def test_guard_reformatted_across_lines(self):
        source = fake_agent().replace(
            'or plan_mode or doc_mode or relevant_tools is not None',
            'or plan_mode or doc_mode or (relevant_tools is not None)',
        )
        # Explicit parentheses are outside the comparison; only that comparison changes.
        self.assertIn(MARKER, patch_source(source))

    def test_guard_split_within_comparison(self):
        source = fake_agent().replace(
            'or plan_mode or doc_mode or relevant_tools is not None',
            'or plan_mode or doc_mode or (relevant_tools is\n                not None)',
        )
        self.assertIn(MARKER, patch_source(source))

    def test_multiline_guard_indent_variation(self):
        source = fake_agent().replace(
            'or plan_mode or doc_mode or relevant_tools is not None',
            'or plan_mode or doc_mode or    relevant_tools is not None',
        )
        self.assertIn(MARKER, patch_source(source))

    def test_extra_restriction_is_kept(self):
        source = fake_agent().replace(
            'or plan_mode or doc_mode or relevant_tools is not None',
            'or plan_mode or doc_mode or extra_disable or relevant_tools is not None',
        )
        patched = patch_source(source)
        self.assertIn('or extra_disable or', patched)

    def test_unicode_comment_offsets(self):
        source = fake_agent().replace('import re\n', 'import re\n    # Ω screenshot guard context\n', 1)
        self.assertIn(MARKER, patch_source(source))

    def test_missing_policy_guard_refuses(self):
        source = fake_agent().replace('or name in disabled_tools):', '):')
        with self.assertRaises(ValueError):patch_source(source)

    def test_no_exact_approval_parameter_refuses(self):
        source = fake_agent().replace('async def stream_agent_loop(*, exact_approval=None):', 'async def stream_agent_loop():')
        with self.assertRaises(ValueError):patch_source(source)

    def test_no_double_patch_old_v47(self):
        source = fake_agent() + '\n# ZARZYSSEUS_APPROVED_REPLAY_SCREENSHOT_V47\n'
        with self.assertRaises(ValueError):patch_source(source)

class TestSourcePatch(unittest.TestCase):
    def test_source_compiles(self): self.assertIn(MARKER,patch_source(fake_agent()))
    def test_idempotent(self):
        patched=patch_source(fake_agent())
        self.assertEqual(patch_source(patched),patched)
    def test_no_v46(self):
        with self.assertRaises(ValueError):patch_source(fake_agent().replace('# ZARZYSSEUS_BOUNDED_SCREENSHOT_CONTINUATION_V46','# removed'))
    def test_unknown_guard(self):
        with self.assertRaises(ValueError):patch_source(fake_agent().replace('or plan_mode or doc_mode or relevant_tools is not None','or plan_mode or doc_mode'))
    def test_unknown_call(self):
        with self.assertRaises(ValueError):patch_source(fake_agent().replace('tool_policy=tool_policy,','tool_policy=None,'))
    def test_unknown_helper(self):
        with self.assertRaises(ValueError):patch_source(fake_agent().replace('def _zar_shot_pending_v46(', 'def _other('))
    def test_installer_backup_rollback(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);source=root/'src'/'agent_loop.py';source.parent.mkdir();source.write_text(fake_agent());original=source.read_bytes()
            cmd=lambda op:subprocess.run([sys.executable,str(ROOT/'zarzysseus_approved_replay_v471.py'),op,str(source)],capture_output=True,text=True)
            self.assertEqual(cmd('dry-run').returncode,0)
            self.assertEqual(source.read_bytes(),original)
            self.assertEqual(cmd('install').returncode,0)
            self.assertEqual(cmd('status').returncode,0)
            self.assertEqual(cmd('rollback').returncode,0)
            self.assertEqual(source.read_bytes(),original)
    def test_rollback_refuses_other_edits(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);source=root/'src'/'agent_loop.py';source.parent.mkdir();source.write_text(fake_agent())
            cmd=lambda op:subprocess.run([sys.executable,str(ROOT/'zarzysseus_approved_replay_v471.py'),op,str(source)],capture_output=True,text=True)
            self.assertEqual(cmd('install').returncode,0)
            source.write_text(source.read_text()+'# later change\n')
            self.assertEqual(cmd('rollback').returncode,2)
    def test_refuse_symlink(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);src=root/'agent_loop.py';src.write_text(fake_agent()); link=root/'sub'/'agent_loop.py';link.parent.mkdir();link.symlink_to(src)
            proc=subprocess.run([sys.executable,str(ROOT/'zarzysseus_approved_replay_v471.py'),'dry-run',str(link)],capture_output=True)
            self.assertEqual(proc.returncode,2)

if __name__=='__main__':unittest.main()

