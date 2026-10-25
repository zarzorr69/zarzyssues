#!/usr/bin/env python3
"""Check whether an Ollama model *proposes* native tool calls; execute none.

This isolates the model/transport from Zarzysseus' routing and MCP permissions.
Only asks for a deliberately fake, read-only function. Never executes it.
"""
from __future__ import annotations
import argparse
import json
import sys
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError

TOOL = {"type": "function", "function": {
    "name": "probe_visit_page",
    "description": "A test-only function to inspect a public webpage title. No real call will run.",
    "parameters": {
        "type": "object", "properties": {"url": {"type": "string"}},
        "required": ["url"]
    }
}}
URL = "https://example.com"


def post(base: str, path: str, body: dict, timeout: int = 150) -> dict:
    req = Request(base.rstrip("/") + path, data=json.dumps(body).encode(),
                  headers={"Content-Type": "application/json"}, method="POST")
    with urlopen(req, timeout=timeout) as response:
        return json.load(response)


def get_models(base: str) -> list[str]:
    with urlopen(base.rstrip("/") + "/api/tags", timeout=12) as response:
        return [
            str(m["name"]) for m in json.load(response).get("models", [])
            if isinstance(m, dict) and m.get("name")
        ]


def resolve(names: list[str], hint: str) -> str:
    exact = [n for n in names if n.casefold() == hint.casefold()]
    if len(exact) == 1:
        return exact[0]
    match = [n for n in names if hint.casefold() in n.casefold()]
    if len(match) == 1:
        return match[0]
    raise ValueError(
        f"Model lookup for {hint!r} gave {len(match)} matches. "
        "Specify an exact model name from: " + ", ".join(names)
    )


def interpret(response: dict, transport: str) -> tuple[list, str]:
    if transport == "openai":
        choice = (response.get("choices") or [{}])[0]
        message = choice.get("message") or {}
    else:
        message = response.get("message") or {}
    calls = message.get("tool_calls")
    if not isinstance(calls, list):
        calls = []
    names = []
    for call in calls:
        if not isinstance(call, dict):
            continue
        fn = call.get("function") or {}
        if fn.get("name"):
            names.append(str(fn["name"]))
    content = str(message.get("content") or "")
    return names, content


def probe(base: str, model: str, transport: str, timeout: int) -> tuple[list, str]:
    messages = [
        {"role": "system",
         "content": "You are in a function-calling probe. Make exactly one "
                    "native function call now. Do not describe plans or pretend "
                    "a tool ran."},
        {"role": "user",
         "content": "Use the probe_visit_page function to inspect " + URL
                    + ". Invoke the function; do not narrate the steps."}
    ]
    data = {
        "model": model, "messages": messages, "stream": False,
        "tools": [TOOL], "temperature": 0,
    }
    if transport == "openai":
        data["max_tokens"] = 224
        path = "/v1/chat/completions"
    else:
        data.pop("temperature")
        data["options"] = {"temperature": 0, "num_predict": 224}
        path = "/api/chat"
    response = post(base, path, data, timeout)
    return interpret(response, transport)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--model", default="dolphin-mistral-24b-venice-edition")
    p.add_argument("--base", default="http://127.0.0.1:11434")
    p.add_argument("--transport", choices=("openai", "native", "both"), default="openai")
    p.add_argument("--timeout", type=int, default=150)
    opts = p.parse_args()
    try:
        names = get_models(opts.base)
        model = resolve(names, opts.model)
        print("Model:", model, flush=True)
        print("The probe function is FAKE and will NOT be executed.", flush=True)
        successes = 0
        transports = ("openai", "native") if opts.transport == "both" else (opts.transport,)
        for t in transports:
            try:
                calls, content = probe(opts.base, model, t, opts.timeout)
            except (HTTPError, URLError, TimeoutError, ValueError) as exc:
                print(f"[{t}] request failed: {type(exc).__name__}: {exc}", flush=True)
                continue
            matched = "probe_visit_page" in calls
            successes += int(matched)
            print(f"[{t}] structured tool_calls: {calls or 'NONE'}", flush=True)
            print(f"[{t}] result: {'PASS (proposal only)' if matched else 'NO NATIVE TOOL PROPOSAL'}",
                  flush=True)
            if content.strip():
                print(f"[{t}] narration excerpt: {content.strip()[:260]!r}", flush=True)
        return 0 if successes == len(transports) else 1
    except (HTTPError, URLError, TimeoutError, ValueError) as exc:
        print(f"[probe] {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
