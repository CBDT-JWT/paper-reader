#!/usr/bin/env python3
"""Local JSONL transport fixture. Receives only synthetic integration-test prompts."""
import json
import sys
from pathlib import Path

scenario = Path("scenario.txt").read_text().strip()
if scenario == "startup-error":
    print("Intentional App Server startup failure", file=sys.stderr, flush=True)
    sys.exit(23)


def send(value):
    print(json.dumps(value), flush=True)


for line in sys.stdin:
    message = json.loads(line)
    if scenario == "hang":
        continue
    method = message.get("method")
    request_id = message.get("id")
    if method == "initialize":
        send({"id": request_id, "result": {"userAgent": "PaperReader-test"}})
    elif method == "model/list":
        send({"id": request_id, "result": {"data": [{"model": "fixture-model"}], "nextCursor": None}})
    elif method == "thread/start":
        params = message["params"]
        assert params["sandbox"] == "read-only"
        assert "shell_tool" in sys.argv and "--disable" in sys.argv
        send({"id": request_id, "result": {"thread": {"id": "fixture-thread"}}})
    elif method == "turn/start":
        send({"id": request_id, "result": {"turn": {"id": "fixture-turn"}}})
        if scenario == "disconnect":
            print("Intentional mid-turn disconnect", file=sys.stderr, flush=True)
            sys.exit(23)
        if scenario in ("failed", "interrupted"):
            send({"method": "turn/completed", "params": {"turn": {"status": scenario, "error": {"message": "Intentional turn failure"}}}})
        else:
            send({"id": 90, "method": "item/permissions/requestApproval", "params": {"permissions": {}}})
    elif request_id == 90:
        assert message["result"]["permissions"] == {}
        send({"id": 91, "method": "item/commandExecution/requestApproval", "params": {}})
    elif request_id == 91:
        assert message["result"]["decision"] == "decline"
        send({"id": 92, "method": "item/tool/call", "params": {"tool": "readNote", "arguments": {}}})
    elif request_id == 92:
        assert message["result"]["success"] is True
        send({"method": "item/agentMessage/delta", "params": {"delta": "**Fixture answer** with *emphasis*."}})
        send({"method": "turn/completed", "params": {"turn": {"status": "completed"}}})
        sys.exit(0)  # Completion followed by EOF must remain a successful turn.
