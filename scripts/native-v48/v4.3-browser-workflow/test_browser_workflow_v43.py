import ast
import importlib.util
import tempfile
import unittest
from pathlib import Path

BASE = Path(__file__).resolve().parent

def import_file(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

v43 = import_file('v43', BASE/'zarzysseus_browser_workflow_v43.py')
v42 = import_file('v42', BASE/'fixtures'/'zarzysseus_forced_focus_v42.py')
v41 = import_file('v41', BASE/'fixtures'/'zarzysseus_schema_focus_v4.py')

# Fixture is constructed from the actual V4.1 source insert with the V4.2
# additive forced-tools upgrade applied; no fake untested router text.
SOURCE_V41 = ('def agent(_last_user, messages):\n'
              '    # ZARZYSSEUS_CONTEXT_CONTINUITY_V2\n'
              + v41.HELPER + '    return _zar_browser_targets_v4(_last_user, messages)\n')
SOURCE_V42 = v42.upgrade_source(SOURCE_V41)
SOURCE_V43 = v43.updated_source(SOURCE_V42)


def targets(latest, previous=()):
    ns = {}
    tree = ast.parse(SOURCE_V43)
    outer = tree.body[0]
    helper = next(x for x in outer.body
                  if isinstance(x, ast.FunctionDef) and x.name == '_zar_browser_targets_v4')
    node = ast.fix_missing_locations(ast.Module(body=[helper], type_ignores=[]))
    exec(compile(node, '<test>', 'exec'), ns)
    msgs = [{'role': 'user', 'content': m} for m in previous]
    msgs.append({'role': 'user', 'content': latest})
    return tuple(s.removeprefix('mcp__builtin_browser__') for s in ns['_zar_browser_targets_v4'](latest, msgs))


class BrowserWorkflowTests(unittest.TestCase):
    def test_v42_exact_source_and_ast_compatible(self):
        self.assertIn(v43.MARKER, SOURCE_V43)
        ast.parse(SOURCE_V43)
        self.assertIn(v42.MARKER, SOURCE_V43)
        self.assertIn('def _zar_focus_schemas_v4', SOURCE_V43)
        self.assertEqual(v43.updated_source(SOURCE_V43), SOURCE_V43)

    def test_no_change_outside_intent_function(self):
        tree1, tree2 = ast.parse(SOURCE_V42), ast.parse(SOURCE_V43)
        a = next(x for x in ast.walk(tree1) if isinstance(x, ast.FunctionDef) and x.name == '_zar_focus_schemas_v4')
        b = next(x for x in ast.walk(tree2) if isinstance(x, ast.FunctionDef) and x.name == '_zar_focus_schemas_v4')
        self.assertEqual(ast.dump(a), ast.dump(b))

    def test_bare_url_navigation(self):
        self.assertEqual(targets('Open example.com'), ('browser_navigate',))

    def test_https_navigation(self):
        self.assertEqual(targets('Open https://example.com'), ('browser_navigate',))

    def test_combined_screenshot_no_take_verb(self):
        self.assertEqual(targets('open example.com screenshot the page and send it back and describe the page to me'),
                         ('browser_navigate','browser_snapshot','browser_take_screenshot'))

    def test_combined_screenshot_with_take_verb(self):
        self.assertEqual(targets('Open example.com then take a screenshot of the page'),
                         ('browser_navigate','browser_take_screenshot'))

    def test_describe_page_from_history(self):
        self.assertEqual(targets('Describe the page for me', ['Open example.com']),('browser_snapshot',))

    def test_describe_it_from_history(self):
        self.assertEqual(targets('describe it', ['Open example.com']),('browser_snapshot',))

    def test_describe_it_without_history(self):
        self.assertEqual(targets('describe it'),())

    def test_followup_yes_after_description(self):
        self.assertEqual(targets('Yes', ['Open example.com','Describe the page for me']),('browser_snapshot',))

    def test_yes_after_screenshot(self):
        self.assertEqual(targets('Yes', ['Open example.com','Now screenshot it']),('browser_take_screenshot',))

    def test_yes_unrelated(self):
        self.assertEqual(targets('Yes',['Hi there']),())

    def test_now_screenshot_from_history(self):
        self.assertEqual(targets('Now screenshot it',['Open example.com']),('browser_take_screenshot',))

    def test_css_followup(self):
        self.assertEqual(targets('CSS is fine', ['Open example.com','Now screenshot it']),('browser_take_screenshot',))

    def test_stop_no_tool(self):
        self.assertEqual(targets('No, do not screenshot the page',['Open example.com']),())

    def test_instructional_request_no_tool(self):
        self.assertEqual(targets('How to take a screenshot of example.com?'),())

    def test_unrelated_request_no_tool(self):
        self.assertEqual(targets('Explain heterogenous catalysts'),())

    def test_context_open_it_with_prior_site(self):
        self.assertEqual(targets('Open it', ['Visit example.com']),('browser_navigate',))

    def test_open_nonweb_does_not_inherit_url(self):
        self.assertEqual(targets('Open the server port', ['Visit example.com']),())

    def test_fail_closed_modified_helper(self):
        modified = SOURCE_V42.replace('Conservative user-only task classification', 'Different implementation')
        with self.assertRaisesRegex(ValueError, 'differs'):
            v43.updated_source(modified)

    def test_fail_closed_missing_v42(self):
        with self.assertRaisesRegex(ValueError, 'marker'):
            v43.updated_source(SOURCE_V41)

    def test_install_backup_and_rollback(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)/'odysseus'
            src = root/'src'/'agent_loop.py'; src.parent.mkdir(parents=True)
            src.write_text(SOURCE_V42)
            self.assertEqual(v43.main.__name__, 'main')
            import sys
            original = sys.argv
            try:
                sys.argv=['patch','dry-run',str(src)]
                self.assertEqual(v43.main(),0)
                self.assertEqual(src.read_text(),SOURCE_V42)
                sys.argv=['patch','install',str(src)]
                self.assertEqual(v43.main(),0)
                self.assertIn(v43.MARKER,src.read_text())
                sys.argv=['patch','status',str(src)]
                self.assertEqual(v43.main(),0)
                sys.argv=['patch','rollback',str(src)]
                self.assertEqual(v43.main(),0)
                self.assertEqual(src.read_text(),SOURCE_V42)
            finally:
                sys.argv=original

    def test_rollback_refuses_modified_source(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)/'odysseus';src = root/'src'/'agent_loop.py';src.parent.mkdir(parents=True)
            src.write_text(SOURCE_V42)
            import sys
            original = sys.argv
            try:
                sys.argv=['patch','install',str(src)]
                self.assertEqual(v43.main(),0)
                src.write_text(src.read_text()+'# an external edit\n')
                sys.argv=['patch','rollback',str(src)]
                self.assertEqual(v43.main(),2)
            finally:sys.argv=original

if __name__ == '__main__': unittest.main()
