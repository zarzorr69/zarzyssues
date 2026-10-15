#!/usr/bin/env python3
"""Measure an installed Ollama model; proposed diagnostic tools are never executed.

Uses only Python's standard library. Run inside the supplied bench service or
on a host with Python 3.10+. Timing is measured on the machine running Ollama.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

KEEP_ALIVE = os.getenv('MODEL_KEEP_ALIVE', '30m')


def request(url, path, payload, timeout):
    req = urllib.request.Request(
        url.rstrip('/') + path, json.dumps(payload).encode(),
        {'Content-Type': 'application/json'}, method='POST')
    return urllib.request.urlopen(req, timeout=timeout)


def post(url, path, payload, timeout=300):
    with request(url, path, payload, timeout) as response:
        result = json.load(response)
    if result.get('error'):
        raise RuntimeError(str(result['error']))
    return result


def options(threads, context, predict=1024):
    return dict(num_thread=threads, num_ctx=context, num_predict=predict,
                num_gpu=0, num_batch=128, seed=7)


def set_thinking(payload, info):
    # Some models allow only named levels; boolean false is sent only when
    # advertised or when an older Ollama reports a boolean-style capability.
    controls = info.get('thinking', {}).get('values')
    if controls is not None:
        if False in controls:
            payload['think'] = False
    elif 'thinking' in info.get('capabilities', []):
        payload['think'] = False
    return payload


def consume_stream(response, started, clock=time.perf_counter):
    first = None
    pieces = []
    thought = []
    final = None
    for line in response:
        if not line.strip():
            continue
        event = json.loads(line)
        if event.get('error'):
            raise RuntimeError(str(event['error']))
        content = event.get('message', {}).get('content', '')
        thinking = event.get('message', {}).get('thinking', '')
        if thinking:
            thought.append(thinking)
        if content:
            if first is None:
                first = clock() - started
            pieces.append(content)
        if event.get('done'):
            final = event
    if final is None:
        raise RuntimeError('Stream ended without an Ollama done event.')
    text = ''.join(pieces).strip()
    duration = final.get('eval_duration', 0) / 1e9
    prompt_duration = final.get('prompt_eval_duration', 0) / 1e9
    return dict(first_answer_seconds=round(first, 3) if first is not None else None,
                output_tokens=final.get('eval_count', 0),
                decode_tokens_per_second=round(final.get('eval_count', 0) / duration, 2) if duration else None,
                prompt_tokens=final.get('prompt_eval_count', 0),
                prompt_tokens_per_second=round(final.get('prompt_eval_count', 0) / prompt_duration, 2) if prompt_duration else None,
                load_seconds=round(final.get('load_duration', 0) / 1e9, 3),
                wall_seconds=round(clock() - started, 3),
                answered=bool(text),
                done_reason=final.get('done_reason'),
                thinking_characters=sum(len(part) for part in thought),
                note=('No final answer; output limit may have been consumed by reasoning.' if not text else
                      'Decode rate includes reasoning and final-answer tokens.'),
                answer=text)


def chat_timing(url, model, info, threads, context, timeout, prompt=None, predict=1024):
    payload = set_thinking(dict(model=model, stream=True, keep_alive=KEEP_ALIVE,
        messages=[{'role': 'user', 'content': prompt or
            'Explain why backups and RAID solve different problems. Use five short sentences and a concrete example.'}],
        options=options(threads, context, predict)), info)
    started = time.perf_counter()
    with request(url, '/api/chat', payload, timeout) as response:
        return consume_stream(response, started)


def tool_ok(response):
    for call in response.get('message', {}).get('tool_calls', []):
        function = call.get('function', {})
        arguments = function.get('arguments', {})
        if isinstance(arguments, str):
            try:
                arguments = json.loads(arguments)
            except ValueError:
                continue
        if (function.get('name') == 'diagnostic_ping' and isinstance(arguments, dict)
                and type(arguments.get('value')) is int and arguments['value'] == 7):
            return True
    return False


def tool_probe(url, model, info, threads, context, timeout, predict=1024):
    schema = dict(type='function', function=dict(name='diagnostic_ping',
        description='Return a diagnostic ping for the given integer.',
        parameters=dict(type='object', properties={'value': {'type': 'integer'}},
                        required=['value'])))
    family = str(info.get('details', {}).get('family', '')).lower()
    system = 'Use the provided tool when requested.'
    if family.startswith('lfm2') or 'lfm2' in model.lower():
        system += (' For tool calls use your native Python-style call list between '
                   '<|tool_call_start|> and <|tool_call_end|>. Do not use JSON or Markdown fences.')
    payload = set_thinking(dict(model=model, stream=False, keep_alive=KEEP_ALIVE,
        tools=[schema], messages=[{'role': 'system', 'content': system},
                                 {'role': 'user', 'content': 'Use diagnostic_ping to ping the integer 7.'}],
        options=options(threads, context, predict)), info)
    started = time.perf_counter()
    result = post(url, '/api/chat', payload, timeout)
    return dict(passed=tool_ok(result), seconds=round(time.perf_counter() - started, 3),
                note='Proposal checked only; no tool was dispatched or executed.',
                output_tokens=result.get('eval_count'),
                done_reason=result.get('done_reason'),
                model_answer=result.get('message', {}))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('model')
    parser.add_argument('--url', default='http://cpu-ollama:11434')
    parser.add_argument('--threads', type=int, nargs='+', default=[2, 4])
    parser.add_argument('--context', type=int, default=4096)
    parser.add_argument('--timeout', type=float, default=300)
    parser.add_argument('--tool-only', action='store_true')
    parser.add_argument('--preload-only', action='store_true', help='Load the model without generating text or proposing a tool')
    parser.add_argument('--predict', type=int, default=1024, help='Budget shared by reasoning and answer')
    parser.add_argument('--tool-predict', type=int, default=1024)
    parser.add_argument('--quick', action='store_true', help='One short chat per thread count, then one tool proposal')
    args = parser.parse_args(argv)
    if args.preload_only and (args.tool_only or args.quick or len(args.threads) != 1):
        parser.error('--preload-only requires one thread count and cannot be combined with --quick/--tool-only.')
    if any(t < 1 for t in args.threads) or args.context < 512 or args.timeout <= 0 or min(args.predict, args.tool_predict) < 1:
        parser.error('Use positive thread counts/timeouts and context >= 512.')
    try:
        info = post(args.url, '/api/show', {'model': args.model}, args.timeout)
        caps = info.get('capabilities', [])
        if caps and 'completion' not in caps:
            raise RuntimeError('The selected model does not advertise text completion.')
        print(json.dumps({'model': args.model, 'capabilities': caps,
            'context': args.context, 'cpu_only_requested': True,
            'thinking_controls': info.get('thinking'),
            'keep_alive': KEEP_ALIVE,
            'generation_budget': args.predict, 'tool_budget': args.tool_predict,
            'method': ('load the model without generation or tools' if args.preload_only else
                       'one simulated tool proposal per thread count' if args.tool_only else
                       'one short chat per thread count and one simulated tool proposal' if args.quick else
                       'one cold/warm-up chat, two repeated warm chats, one longer synthetic prompt per thread count, one simulated tool proposal')}, indent=2), flush=True)
        if args.preload_only:
            payload = dict(model=args.model, messages=[], stream=False, keep_alive=KEEP_ALIVE,
                           options=options(args.threads[0], args.context, args.predict))
            started = time.perf_counter()
            result = post(args.url, '/api/chat', payload, args.timeout)
            if not result.get('done'):
                raise RuntimeError('Preload did not return an Ollama done event.')
            print(json.dumps({'threads': args.threads[0], 'preload': {
                'done': True, 'done_reason': result.get('done_reason'),
                'load_seconds': round(result.get('load_duration', 0) / 1e9, 3),
                'wall_seconds': round(time.perf_counter() - started, 3)}}), flush=True)
            return 0
        passed = True
        if args.quick and not args.tool_only:
            for threads in dict.fromkeys(args.threads):
                print(f'\nChecking short-answer latency with {threads} threads...', flush=True)
                result = chat_timing(args.url, args.model, info, threads, args.context, args.timeout,
                    'In two short sentences, explain why RAID is not a backup.', args.predict)
                print(json.dumps({'threads': threads, **result}), flush=True)
                passed = passed and result['answered']
            threads = args.threads[-1]
            print(f'\nChecking native tool proposal with {threads} threads...', flush=True)
            result = tool_probe(args.url, args.model, info, threads, args.context, args.timeout, args.tool_predict)
            print(json.dumps({'threads': threads, 'tool_probe': result}, indent=2), flush=True)
            return 0 if passed and result['passed'] else 2
        for threads in dict.fromkeys(args.threads):
            if not args.tool_only:
                print(f'\nLoading/warming model with {threads} threads...', flush=True)
                warmup = chat_timing(args.url, args.model, info, threads, args.context, args.timeout, predict=args.predict)
                print(json.dumps({'threads': threads, 'warmup': warmup}), flush=True)
                passed = passed and warmup['answered']
                for trial in (1, 2):
                    result = chat_timing(args.url, args.model, info, threads, args.context, args.timeout, predict=args.predict)
                    print(json.dumps({'threads': threads, 'trial': trial, **result}), flush=True)
                    passed = passed and result['answered']
                print(f'\nChecking longer prompt latency with {threads} threads...', flush=True)
                prompt = ''.join(f'Record {i}: backups preserve files; RAID helps availability.\n' for i in range(128))
                prompt += '\nSummarize the distinction in the records in four short sentences.'
                result = chat_timing(args.url, args.model, info, threads, args.context, args.timeout, prompt, args.predict)
                print(json.dumps({'threads': threads, 'trial': 'longer-prompt', **result}), flush=True)
                passed = passed and result['answered']
            print(f'\nChecking structured tool proposal with {threads} threads...', flush=True)
            result = tool_probe(args.url, args.model, info, threads, args.context, args.timeout, args.tool_predict)
            print(json.dumps({'threads': threads, 'tool_probe': result}, indent=2), flush=True)
            passed = passed and result['passed']
        return 0 if passed else 2
    except (OSError, ValueError, RuntimeError, urllib.error.URLError) as exc:
        print(f'Benchmark failed: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
