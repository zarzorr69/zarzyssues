"""V4.8 synthetic/offline regression checks. No network/LLM/MCP calls."""
import ast
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from zarzysseus_screenshot_planner_v48 import patched_source, MARKER

DIR = Path(__file__).parent
BEFORE = (DIR / 'fixture_pre_v48_agent.py').read_text()
SCREEN = 'mcp__builtin_browser__browser_take_screenshot'
NAV = 'mcp__builtin_browser__browser_navigate'


def helpers(source=None):
    tree=ast.parse(patched_source(BEFORE) if source is None else source)
    nodes=[x for x in tree.body if isinstance(x,ast.FunctionDef) and
           x.name in ('_zar_shot_plan_v48', '_zar_shot_args_valid_v46','_zar_shot_pending_v46')]
    assert len(nodes)==3
    env={}
    exec(compile(ast.Module(body=nodes,type_ignores=[]),'<helpers>','exec'),env)
    return env


def schema(required=None, properties=None):
    return {'type':'function','function':{'name':SCREEN,'parameters':{
        'type':'object','properties':properties if properties is not None else {
            'type':{'type':'string','enum':['png','jpeg']},
            'scale':{'type':'string','enum':['css','device']},
            'fullPage':{'type':'boolean'}},'required':required if required is not None else []}}}


class TestArgPlanner(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.env = helpers()

    def plan(self,s=None,full=False):
        return self.env['_zar_shot_plan_v48'](schema() if s is None else s,full_page_requested=full,round_number=2)

    def args(self,x):
        self.assertEqual(len(x),1)
        self.assertEqual(x[0]['name'],SCREEN)
        self.assertTrue(x[0]['id'].startswith('zar_schema_screenshot_v48_'))
        return json.loads(x[0]['arguments'])

    def test_minimal_valid(self):
        x=self.args(self.plan());self.assertEqual(x,{'type':'png','scale':'css','fullPage':False})
    def test_fullpage(self):
        x=self.args(self.plan(full=True));self.assertIs(x['fullPage'],True)
    def test_required_values(self):
        x=self.args(self.plan(schema(required=['scale','type','fullPage'])));self.assertEqual(x['type'],'png')
    def test_no_filename(self):
        x=self.args(self.plan());self.assertTrue(all(k not in x for k in ('filename','target','element')))
    def test_only_optional_type(self):
        x=self.args(self.plan(schema(properties={'type':{'type':'string'}})));self.assertEqual(x,{'type':'png'})
    def test_fullpage_requires_support(self):
        self.assertEqual(self.plan(schema(properties={'type':{'type':'string'}}),full=True),[])
    def test_unknown_required(self):
        self.assertEqual(self.plan(schema(required=['filename'])),[])
    def test_unadvertised_required(self):
        self.assertEqual(self.plan(schema(required=['scale'],properties={'type':{'type':'string'}})),[])
    def test_disallowed_type_enum(self):
        self.assertEqual(self.plan(schema(properties={'type':{'type':'string','enum':['jpeg']}})),[])
    def test_disallowed_scale_enum(self):
        self.assertEqual(self.plan(schema(properties={'scale':{'type':'string','enum':['device']}})),[])
    def test_reject_wrong_fullpage_type(self):
        self.assertEqual(self.plan(schema(properties={'fullPage':{'type':'string'}})),[])
    def test_reject_oneof(self):
        s=schema();s['function']['parameters']['oneOf']=[{}]
        self.assertEqual(self.plan(s),[])
    def test_reject_property_ref(self):
        s=schema();s['function']['parameters']['properties']['scale']['$ref']='#/$defs/foo'
        self.assertEqual(self.plan(s),[])
    def test_reject_const_mismatch(self):
        s=schema();s['function']['parameters']['properties']['type']['const']='jpeg'
        self.assertEqual(self.plan(s),[])
    def test_reject_wrong_name(self):
        s=schema();s['function']['name']=NAV
        self.assertEqual(self.plan(s),[])
    def test_reject_missing_params(self):
        s=schema();del s['function']['parameters']
        self.assertEqual(self.plan(s),[])
    def test_reject_duplicate_required(self):
        self.assertEqual(self.plan(schema(required=['type','type'])),[])
    def test_reject_unknown_required_schema(self):
        s=schema();s['function']['parameters']['dependentRequired']={}
        self.assertEqual(self.plan(s),[])


class TestUpstreamGuard(unittest.TestCase):
    @classmethod
    def setUpClass(cls): cls.env=helpers()
    def pending(self,request='Open https://example.com screenshot it', *, nav=0, screenshot=None,
                offered=None, scope=None, approval=False, policy=None, disabled=None):
        fn=self.env['_zar_shot_pending_v46']
        events=[{'tool':NAV,'exit_code':nav}]
        if screenshot is not None:events.append({'tool':SCREEN,'exit_code':screenshot})
        return fn(request,events,[schema()] if offered is None else offered,
                  attempted=False,round_num=2,max_rounds=8,guide_only=False,
                  force_answer=False,plan_mode=False,doc_mode=False,
                  relevant_tools=scope,disabled_tools=set() if disabled is None else disabled,
                  tool_policy=policy,approval_replay=approval)
    def test_explicit_request_allowed_after_nav(self):self.assertIsNotNone(self.pending())
    def test_no_screenshot_request(self):self.assertIsNone(self.pending(request='Open https://example.com'))
    def test_nav_failure(self):self.assertIsNone(self.pending(nav=1))
    def test_existing_screenshot_blocks_duplicate(self):self.assertIsNone(self.pending(screenshot=0))
    def test_existing_failed_screenshot_blocks_duplicate(self):self.assertIsNone(self.pending(screenshot=1))
    def test_disabled_tool(self):self.assertIsNone(self.pending(disabled={SCREEN}))
    def test_denied_scoped(self):self.assertIsNone(self.pending(scope={NAV},approval=True))
    def test_allowed_scoped_replay(self):self.assertIsNotNone(self.pending(scope={NAV,SCREEN},approval=True))
    def test_no_approval_with_scope(self):self.assertIsNone(self.pending(scope={NAV,SCREEN},approval=False))
    def test_no_advertised_schema(self):self.assertIsNone(self.pending(offered=[]))
    def test_policy_block(self):
        class Policy:
            block_all_tool_calls=False
            def blocks(self,n):return True
        self.assertIsNone(self.pending(policy=Policy()))
    def test_policy_permit(self):
        class Policy:
            block_all_tool_calls=False
            def blocks(self,n):return False
        self.assertIsNotNone(self.pending(policy=Policy()))


class TestPatchAndCLI(unittest.TestCase):
    def test_patch_ast(self):
        ast.parse(patched_source(BEFORE))
    def test_idempotent(self):
        once=patched_source(BEFORE)
        self.assertEqual(patched_source(once),once)
    def test_require_v471(self):
        with self.assertRaises(ValueError):patched_source(BEFORE.replace('# ZARZYSSEUS_APPROVED_REPLAY_SCREENSHOT_V471',''))
    def test_refuse_missing_resolver(self):
        with self.assertRaises(ValueError):patched_source(BEFORE.replace('_resolve_tool_blocks(', '_other_tool_blocks('))
    def test_refuse_missing_proposal(self):
        with self.assertRaises(ValueError):patched_source(BEFORE.replace('_zar_shot_proposal_v46(', '_no_proposal('))
    def test_refuse_changed_screenshot_if(self):
        with self.assertRaises(ValueError):patched_source(BEFORE.replace('                if _zar_proposals_v46:\n','                if bool(_zar_proposals_v46):\n'))
    def test_no_dispatch_alteration(self):
        out=patched_source(BEFORE)
        self.assertEqual(out.count('_resolve_tool_blocks('),BEFORE.count('_resolve_tool_blocks('))
        self.assertIn('if _zar_proposals_v46:',out)
    def test_install_dry_run_rollback(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);src=root/'src'/'agent_loop.py'
            src.parent.mkdir(parents=True);src.write_text(BEFORE)
            installer=DIR/'zarzysseus_screenshot_planner_v48.py'
            def cmd(a):return subprocess.run([sys.executable,str(installer),a,str(src)],capture_output=True,text=True)
            before=src.read_bytes()
            self.assertEqual(cmd('dry-run').returncode,0)
            self.assertEqual(src.read_bytes(),before)
            self.assertEqual(cmd('install').returncode,0)
            self.assertIn(MARKER,src.read_text())
            self.assertEqual(cmd('status').returncode,0)
            self.assertEqual(cmd('rollback').returncode,0)
            self.assertEqual(src.read_bytes(),before)
    def test_rollback_rejects_other_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);src=root/'src'/'agent_loop.py';src.parent.mkdir(parents=True)
            src.write_text(BEFORE)
            script=DIR/'zarzysseus_screenshot_planner_v48.py'
            def run(a):return subprocess.run([sys.executable,str(script),a,str(src)],capture_output=True,text=True)
            self.assertEqual(run('install').returncode,0)
            src.write_text(src.read_text()+'# another change\n')
            self.assertEqual(run('rollback').returncode,2)
    def test_refuse_symlink(self):
        with tempfile.TemporaryDirectory() as folder:
            base=Path(folder);a=base/'agent_loop.py';a.write_text(BEFORE)
            l=base/'src'/'agent_loop.py';l.parent.mkdir();l.symlink_to(a)
            script=DIR/'zarzysseus_screenshot_planner_v48.py'
            ret=subprocess.run([sys.executable,str(script),'dry-run',str(l)],capture_output=True)
            self.assertEqual(ret.returncode,2)

if __name__=='__main__':unittest.main()
