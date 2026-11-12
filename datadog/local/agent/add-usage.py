#!/usr/bin/env python3
"""
add-usage.py -- the agent's recorded LLM responses with token usage put back.

Upstream's recorder (src/agent/src/agents/patch_vcr.py, clean_response) drops `usage` from every
response, so the agent's spans carry no token counts and Agent Observability shows no tokens or
cost. This reads the image's cassette from src/agent and writes a copy next to this script with
`usage` added to each response. values-local.yaml mounts the copy over the image's file.

The counts are ESTIMATES: tiktoken's o200k_base (the GPT-5 family tokenizer) over each request's
messages and tool definitions and each response's content and tool calls, plus OpenAI's usual
per-message overhead. Close to what the model would bill, not a provider's count.

  pip install pyyaml tiktoken
  python3 datadog/local/agent/add-usage.py      # from the repo root; rerun when upstream's cassette changes
"""
import json
from pathlib import Path

import tiktoken
import yaml

HERE = Path(__file__).resolve().parent
NAME = "azure_gpt-5.5_cassette.yaml"
SRC = HERE.parents[2] / "src/agent/fixtures/vcr_cassettes" / NAME
OUT = HERE / NAME
ENC = tiktoken.get_encoding("o200k_base")


def n(value):
    if value is None:
        return 0
    if not isinstance(value, str):
        value = json.dumps(value, sort_keys=True)
    return len(ENC.encode(value))


def prompt_tokens(body):
    total = 3  # the reply's priming
    for m in body.get("messages", []):
        total += 3 + n(m.get("role")) + n(m.get("content")) + n(m.get("tool_calls")) + n(m.get("name"))
    if body.get("tools"):
        total += n(body["tools"])
    return total


def completion_tokens(resp):
    total = 0
    for c in resp.get("choices", []):
        msg = c.get("message", {})
        total += n(msg.get("content")) + n(msg.get("tool_calls"))
    return max(total, 1)


def main():
    text = SRC.read_text()
    header = "".join(l for l in text.splitlines(keepends=True) if l.startswith("#"))
    data = yaml.safe_load(text)
    added = 0
    for it in data["interactions"]:
        # Skip entries that are not chat completions (the cassette also holds one
        # OTLP export the recorder caught, a binary body).
        rs = it["response"]["body"]
        try:
            req = json.loads(it["request"]["body"])
            resp = json.loads(rs["string"])
        except (TypeError, ValueError):
            continue
        if not isinstance(resp, dict) or "choices" not in resp:
            continue
        p, c = prompt_tokens(req), completion_tokens(resp)
        resp["usage"] = {"prompt_tokens": p, "completion_tokens": c, "total_tokens": p + c}
        rs["string"] = json.dumps(resp, sort_keys=True)
        added += 1
    OUT.write_text(
        header
        + "# datadog/local: token usage added by add-usage.py (estimated counts; see that script).\n\n"
        + yaml.safe_dump(data, sort_keys=False, allow_unicode=False, width=10**9)
    )
    print(f"{OUT.name}: usage on {added} of {len(data['interactions'])} responses")


if __name__ == "__main__":
    main()
