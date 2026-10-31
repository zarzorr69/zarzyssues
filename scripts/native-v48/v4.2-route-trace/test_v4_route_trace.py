"""Offline safety/behavior checks for targeted V4 routing gate trace."""
import importlib.util
import io
import logging
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE=Path(__file__).parent

def load(name, path):
    spec=importlib.util.spec_from_file_location(name, path)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

trace=load('route_trace',HERE/'zarzysseus_v4_route_trace.py')
focus=load('focus_v41',HERE/'zarzysseus_schema_focus_v4.py')
fixture=load('focus_fixture',HERE/'test_schema_focus_v4.py')

class RouteTraceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original=focus.apply_patch(fixture.BASE)
        cls.instrumented=trace.updated(cls.original)

    def test_ast_guard_and_idempotence(self):
        self.assertEqual(trace.updated(self.instrumented),self.instrumented)
        self.assertEqual(self.instrumented.count(trace.TRACE_MARKER),1)
        compile(self.instrumented,'<trace>','exec')

    def test_traced_route_behavior_unchanged_and_logs_flags(self):
        lg=logging.getLogger('zar_v4_route_test')
        lg.setLevel(logging.INFO)
        stream=io.StringIO()
        handler=logging.StreamHandler(stream)
        lg.addHandler(handler)
        try:
            a={'logger':lg}; b={'logger':lg}
            exec(compile(self.original,'<original>','exec'),a)
            exec(compile(self.instrumented,'<trace>','exec'),b)
            cases=[
                ('Open example.com',[],{},[fixture.NAV]),
                ('Open example.com and describe it',[],{},[fixture.NAV]),
                ('Now screenshot it',[{'role':'user','content':'Open example.com'}],{},[fixture.SHOT]),
                ('Hello there',[],{},['web_search']),
                ('Open example.com',[],{'plan_mode':True},['web_search']),
                ('Open example.com',[],{'relevant_tools':{'web_search'}},['web_search']),
            ]
            for prompt, history, flags, _ in cases:
                schemas=[fixture.schema(fixture.NAV),fixture.schema(fixture.SHOT)]
                base=[fixture.schema('web_search')]
                orig=a['agent'](prompt,history,schemas,base,**flags)
                inst=b['agent'](prompt,history,schemas,base,**flags)
                self.assertEqual(orig,inst)
            log=stream.getvalue()
            self.assertIn('targets=',log)
            self.assertIn('plan=True',log)
            self.assertIn('scope=True',log)
            self.assertIn('targets=[]',log)
            self.assertIn('browser_navigate',log)
            self.assertNotIn('example.com',log)  # never print user message
        finally:
            lg.removeHandler(handler)

    def test_missing_or_modified_helper_fails_closed(self):
        for txt in (fixture.BASE, self.original.replace(
            '        _targets = _zar_browser_targets_v4(_last_user, messages)\n',
            '        _targets = ()\n',1)):
            with self.assertRaises(ValueError): trace.updated(txt)

    def test_install_status_rollback(self):
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/'odysseus/src/agent_loop.py'
            path.parent.mkdir(parents=True)
            path.write_text(self.original)
            def run(action):
                return subprocess.run([sys.executable,str(HERE/'zarzysseus_v4_route_trace.py'),action,str(path)],capture_output=True,text=True)
            self.assertEqual(run('dry-run').returncode,0)
            self.assertEqual(path.read_text(),self.original)
            self.assertEqual(run('install').returncode,0)
            self.assertEqual(run('status').returncode,0)
            self.assertEqual(run('install').returncode,0)
            self.assertEqual(run('rollback').returncode,0)
            self.assertEqual(path.read_text(),self.original)

    def test_rollback_refuses_later_modification(self):
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/'odysseus/src/agent_loop.py'
            path.parent.mkdir(parents=True)
            path.write_text(self.original)
            def run(action):
                return subprocess.run([sys.executable,str(HERE/'zarzysseus_v4_route_trace.py'),action,str(path)],capture_output=True,text=True)
            self.assertEqual(run('install').returncode,0)
            path.write_text(path.read_text()+'\n# later change\n')
            self.assertEqual(run('rollback').returncode,2)
            self.assertIn('later change',path.read_text())

if __name__=='__main__': unittest.main()
