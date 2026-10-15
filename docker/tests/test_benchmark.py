import contextlib
import importlib.util
import io
import json
from pathlib import Path
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('cpu_benchmark', ROOT / 'benchmark.py')
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


def event(value):
    return (json.dumps(value) + '\n').encode()


class BenchmarkTests(unittest.TestCase):
    def test_stream_measures_answer_latency_and_decoding_separately(self):
        response = [event({'message': {'thinking': 'Reasoning'}}),
                    event({'message': {'content': 'A backup '}}),
                    event({'message': {'content': 'helps.'}, 'done': True,
                           'eval_count': 12, 'eval_duration': 2_000_000_000,
                           'prompt_eval_count': 20, 'prompt_eval_duration': 1_000_000_000})]
        result = bench.consume_stream(response, 0, clock=Mock(side_effect=[0.5, 3]))
        self.assertEqual(result['first_answer_seconds'], 0.5)
        self.assertEqual(result['decode_tokens_per_second'], 6)
        self.assertEqual(result['answer'], 'A backup helps.')

    def test_truncated_and_error_streams_fail(self):
        for response in ([event({'message': {'content': 'partial'}})],
                         [event({'error': 'out of memory'})]):
            with self.subTest(response=response), self.assertRaises(RuntimeError):
                bench.consume_stream(response, 0)

    def test_reasoning_only_limit_reports_metrics_and_no_answer(self):
        result = bench.consume_stream([
            event({'message': {'thinking': 'Reasoning fills the budget.'}}),
            event({'message': {'content': ''}, 'done': True, 'done_reason': 'length',
                   'eval_count': 160, 'eval_duration': 20_000_000_000})], 0)
        self.assertFalse(result['answered'])
        self.assertIsNone(result['first_answer_seconds'])
        self.assertEqual(result['done_reason'], 'length')
        self.assertEqual(result['decode_tokens_per_second'], 8)
        self.assertGreater(result['thinking_characters'], 0)

    def test_only_correct_structured_proposal_passes(self):
        self.assertFalse(bench.tool_ok({'message': {'content': 'Calling diagnostic_ping(7)'}}))
        for arguments, expected in [({'value': 7}, True), ('{"value":7}', True),
                                    ({'value': True}, False), ({'value': 7.0}, False),
                                    ('not JSON', False), ({'value': 8}, False)]:
            self.assertEqual(bench.tool_ok({'message': {'tool_calls': [
                {'function': {'name': 'diagnostic_ping', 'arguments': arguments}}]}}), expected)

    def test_thinking_levels_are_not_overwritten_with_a_boolean(self):
        self.assertNotIn('think', bench.set_thinking({}, {'thinking': {'values': ['low', 'high']}}))
        self.assertEqual(bench.set_thinking({}, {'thinking': {'values': [True, False]}}), {'think': False})
        self.assertEqual(bench.set_thinking({}, {'capabilities': ['thinking']}), {'think': False})
        self.assertNotIn('think', bench.set_thinking({}, {'thinking': {'values': [True]}}))

    def test_lfm_probe_preserves_native_format_and_reasoning_budget(self):
        from unittest.mock import patch
        with patch.object(bench, 'post', return_value={'message': {'tool_calls': []}}) as request:
            bench.tool_probe('http://localhost', 'lfm2.5-zarzysseus-cpu:2.6b',
                             {'thinking': {'values': [True]}}, 4, 4096, 300)
        payload = request.call_args.args[2]
        self.assertEqual(payload['options']['num_predict'], 1024)
        self.assertNotIn('think', payload)
        self.assertIn('<|tool_call_start|>', payload['messages'][0]['content'])
        self.assertNotIn('structured tool call', payload['messages'][1]['content'])

    def test_native_api_workflow_never_executes_a_tool(self):
        seen = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                seen.append((self.path, payload))
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                if self.path == '/api/show':
                    self.wfile.write(event({'capabilities': ['completion', 'tools']}))
                elif payload.get('messages') == []:
                    self.wfile.write(event({'done': True, 'done_reason': 'load',
                                           'load_duration': 1_000_000_000}))
                elif payload.get('tools'):
                    self.wfile.write(event({'message': {'tool_calls': [{'function':
                        {'name': 'diagnostic_ping', 'arguments': {'value': 7}}}]}}))
                else:
                    self.wfile.write(event({'message': {'content': 'Backups preserve files. '}}))
                    self.wfile.write(event({'done': True, 'message': {'content': 'RAID helps availability.'},
                                           'eval_count': 8, 'eval_duration': 1_000_000_000}))

        server = HTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                rc = bench.main(['fixture-model', '--url', f'http://127.0.0.1:{server.server_port}', '--threads', '2'])
            self.assertEqual(rc, 0)
            self.assertEqual([path for path, _ in seen], ['/api/show'] + ['/api/chat'] * 5)
            for path, payload in seen:
                if path == '/api/chat':
                    self.assertEqual(payload['options']['num_ctx'], 4096)
                    self.assertEqual(payload['options']['num_gpu'], 0)
                    self.assertEqual(payload['options']['num_thread'], 2)
                    self.assertNotIn('tool', [message['role'] for message in payload['messages']])
                    self.assertEqual(payload['options']['num_predict'], 1024)
            seen.clear()
            with contextlib.redirect_stdout(io.StringIO()):
                rc = bench.main(['fixture-model', '--url', f'http://127.0.0.1:{server.server_port}',
                                 '--threads', '2', '4', '--quick'])
            self.assertEqual(rc, 0)
            self.assertEqual([path for path, _ in seen], ['/api/show'] + ['/api/chat'] * 3)
            self.assertEqual([payload['options']['num_thread'] for path, payload in seen if path == '/api/chat'], [2, 4, 4])
            seen.clear()
            with contextlib.redirect_stdout(io.StringIO()) as output:
                rc = bench.main(['fixture-model', '--url', f'http://127.0.0.1:{server.server_port}',
                                 '--threads', '2', '--preload-only'])
            self.assertEqual(rc, 0)
            self.assertEqual([path for path, _ in seen], ['/api/show', '/api/chat'])
            self.assertEqual(seen[-1][1]['messages'], [])
            self.assertNotIn('tools', seen[-1][1])
            self.assertEqual(seen[-1][1]['keep_alive'], bench.KEEP_ALIVE)
            self.assertIn('"done_reason": "load"', output.getvalue())
        finally:
            server.shutdown()
            thread.join()
            server.server_close()


if __name__ == '__main__':
    unittest.main()
