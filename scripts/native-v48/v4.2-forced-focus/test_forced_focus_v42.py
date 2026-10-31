"""Offline V4.2 regression tests; no network, model inference, or service writes."""
import ast
import importlib.util
import json
import logging
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location("v42", HERE / "zarzysseus_forced_focus_v42.py")
v42 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v42)
base_spec = importlib.util.spec_from_file_location("v41", HERE / "test_fixtures" / "zarzysseus_schema_focus_v4.py")
v41 = importlib.util.module_from_spec(base_spec)
base_spec.loader.exec_module(v41)
trace_spec = importlib.util.spec_from_file_location("trace", HERE / "test_fixtures" / "zarzysseus_v4_route_trace.py")
trace = importlib.util.module_from_spec(trace_spec)
trace_spec.loader.exec_module(trace)

# Use actual V4.1 test fixture rather than inventing a source structure.
test_spec = importlib.util.spec_from_file_location("v41tests", HERE / "test_fixtures" / "test_schema_focus_v4.py")
fixture = importlib.util.module_from_spec(test_spec)
test_spec.loader.exec_module(fixture)
BASE = fixture.BASE
NAV = fixture.NAV
SHOT = fixture.SHOT
CODE = fixture.CODE
schema = fixture.schema
V41 = v41.apply_patch(BASE)
TRACED = trace.updated(V41)
UPGRADED = v42.upgrade_source(TRACED)


def agent_from(text):
    d = {"logger":logging.getLogger("focus42tests")}
    exec(compile(text, "<v42synthetic>", "exec"), d)
    return d["agent"]


class FocusV42(unittest.TestCase):
    def setUp(self):
        self.agent = agent_from(UPGRADED)

    def test_model_independent_nav_with_forced_web_search(self):
        result = self.agent("Open example.com", [], [schema(NAV), schema(CODE)],
                            [schema("web_search"), schema("ask_user")],
                            forced_tools={"web_search"})
        self.assertEqual([x['function']['name'] for x in result], [NAV, "web_search"])

    def test_forced_browser_navigation_deduplicated(self):
        result = self.agent("Open example.com", [], [schema(NAV)],
                            [schema(NAV), schema("web_fetch")], forced_tools={NAV})
        self.assertEqual([x['function']['name'] for x in result], [NAV])

    def test_force_nonexistent_tool_never_invented(self):
        result = self.agent("Open example.com", [], [schema(NAV)], [schema("ask_user")],
                            forced_tools={"bash"})
        self.assertEqual([x['function']['name'] for x in result], [NAV])

    def test_disallowed_forced_tool_not_retained(self):
        result = self.agent("Open example.com", [], [schema(NAV)],
                            [schema('web_search'),schema('bash')],
                            forced_tools={'bash','web_search'}, disabled_tools={'bash'})
        self.assertEqual([x['function']['name'] for x in result], [NAV, 'web_search'])

    def test_forced_names_restricted_by_policy(self):
        class Policy:
            block_all_tool_calls = False
            def blocks(self, name): return name == 'bash'
        result = self.agent("Open example.com", [], [schema(NAV)],
                            [schema('web_search'), schema('bash')],
                            forced_tools={'bash','web_search'}, tool_policy=Policy())
        self.assertEqual([x['function']['name'] for x in result], [NAV, 'web_search'])

    def test_policy_blocks_browser(self):
        class Policy:
            block_all_tool_calls = False
            def blocks(self, name): return name == NAV
        base = [schema('web_search')]
        self.assertEqual(self.agent('Open example.com', [], [schema(NAV)], base,
                                    forced_tools={'web_search'},tool_policy=Policy()), base)

    def test_unknown_forced_type_fails_closed(self):
        base = [schema('web_search'), schema('ask_user')]
        self.assertEqual(self.agent('Open example.com', [], [schema(NAV)],base,
                                    forced_tools='web_search'), base)
        self.assertEqual(self.agent('Open example.com', [], [schema(NAV)],base,
                                    forced_tools={1}), base)

    def test_explicit_scope_still_not_widened(self):
        base = [schema('web_search')]
        self.assertEqual(self.agent('Open example.com', [], [schema(NAV)], base,
                                    forced_tools={'web_search'}, relevant_tools={'web_search'}), base)

    def test_guide_plan_approval_force_answer_still_skip(self):
        base = [schema('web_search')]
        for kw in ({'guide_only':True},{'plan_mode':True},{'exact_approval':object()},
                   {'_force_answer':True},{'ody_qwen_finetune_model':True},
                   {'is_api_model':False}):
            with self.subTest(kw=kw):
                self.assertEqual(self.agent('Open example.com', [], [schema(NAV)],base,
                                            forced_tools={'web_search'}, **kw), base)

    def test_screenshot_context_with_forced_tool(self):
        h=[{'role':'user','content':'Open example.com'},
           {'role':'user','content':'Now screenshot it'}]
        result=self.agent('Now screenshot it',h,[schema(NAV),schema(SHOT)],
                          [schema('web_search')],forced_tools={'web_search'})
        self.assertEqual([x['function']['name'] for x in result], [SHOT,'web_search'])

    def test_plain_chat_unchanged(self):
        base=[schema('web_search'),schema('ask_user')]
        self.assertEqual(self.agent('Hello', [], [schema(NAV)], base,
                                    forced_tools={'web_search'}), base)

    def test_without_force_still_focuses(self):
        got=self.agent('Open example.com',[],[schema(NAV)],[schema('web_search')])
        self.assertEqual([x['function']['name'] for x in got], [NAV])

    def test_synthetic_source_with_trace(self):
        self.assertIn(v42.MARKER, UPGRADED)
        self.assertIn(trace.TRACE_MARKER, UPGRADED)
        self.assertEqual(v42.upgrade_source(UPGRADED),UPGRADED)
        ast.parse(UPGRADED)

    def test_without_trace_is_supported(self):
        upgraded=v42.upgrade_source(V41)
        self.assertIn(v42.MARKER, upgraded)
        self.assertEqual(agent_from(upgraded)('Open example.com',[],[schema(NAV)],
                                             [schema('web_search')],forced_tools={'web_search'}),
                         [schema(NAV), schema('web_search')])

    def test_unrecognized_v4_helper_refused(self):
        for bad in (BASE,TRACED.replace(v42.GUARD_OLD, '        return schemas\n',1),
                    TRACED.replace(v42.FOCUSED_OLD,'        return schemas\n',1),
                    TRACED.replace('def _zar_focus_schemas_v4(', 'def unknown(',1)):
            with self.subTest(bad=bad[:70]):
                with self.assertRaises((ValueError,SyntaxError)):
                    v42.upgrade_source(bad)

    def test_file_installer_and_checksum_rollback(self):
        with tempfile.TemporaryDirectory() as d:
            f=Path(d)/'odysseus/src/agent_loop.py'
            f.parent.mkdir(parents=True)
            f.write_text(TRACED)
            def run(action):
                return subprocess.run([sys.executable,str(HERE/'zarzysseus_forced_focus_v42.py'),
                                       action,str(f)],capture_output=True,text=True)
            self.assertEqual(run('dry-run').returncode,0)
            self.assertEqual(f.read_text(), TRACED)
            self.assertEqual(run('install').returncode,0)
            self.assertEqual(run('status').returncode,0)
            self.assertEqual(run('install').returncode,0)
            self.assertEqual(run('rollback').returncode,0)
            self.assertEqual(f.read_text(),TRACED)
            self.assertNotEqual(run('rollback').returncode,0)

    def test_rollback_does_not_erase_later_edits(self):
        with tempfile.TemporaryDirectory() as d:
            f=Path(d)/'odysseus/src/agent_loop.py'
            f.parent.mkdir(parents=True)
            f.write_text(TRACED)
            def run(action):
                return subprocess.run([sys.executable,str(HERE/'zarzysseus_forced_focus_v42.py'),
                                       action,str(f)],capture_output=True,text=True)
            self.assertEqual(run('install').returncode,0)
            f.write_text(f.read_text()+'\n# user patch\n')
            self.assertEqual(run('rollback').returncode,2)
            self.assertIn('# user patch',f.read_text())

if __name__=='__main__': unittest.main(verbosity=2)
