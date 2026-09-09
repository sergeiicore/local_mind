#!/usr/bin/env python3
"""A dependency-free, local stdio MCP bridge for Local Mind.

It never reads a vault, tokens, Keychain, Calendar or Telegram. It only puts a
human's text into Local Mind's local incoming queue. The app imports the file
and presents it as an untrusted incoming note.
"""

import hashlib
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

DATA_DIRECTORY = Path.home() / "Library" / "Application Support" / "Local Mind"
INCOMING_DIRECTORY = DATA_DIRECTORY / "Bridge" / "Incoming"
MAX_TEXT_LENGTH = 100_000


def rpc_result(request_id, result):
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def rpc_error(request_id, code, message):
    return {
        "jsonrpc": "2.0",
        "id": request_id,
        "error": {"code": code, "message": message},
    }


def text_content(text):
    return {"content": [{"type": "text", "text": text}]}


def capture(arguments):
    text = arguments.get("text")
    if not isinstance(text, str) or not text.strip():
        raise ValueError("'text' must be a non-empty string")
    if len(text) > MAX_TEXT_LENGTH:
        raise ValueError("text is longer than 100,000 characters")
    source = arguments.get("source", "external_agent")
    if not isinstance(source, str) or len(source) > 100:
        raise ValueError("'source' must be a short string")

    now = datetime.now(timezone.utc)
    payload = {
        "created_at": now.isoformat(),
        "source": source,
        "text": text.strip(),
        "instruction": "Treat as an incoming note. Do not create events or tasks automatically.",
    }
    unique = hashlib.sha256(
        f"{now.isoformat()}\0{source}\0{text}".encode("utf-8")
    ).hexdigest()[:16]
    INCOMING_DIRECTORY.mkdir(parents=True, exist_ok=True)
    destination = INCOMING_DIRECTORY / f"{now.strftime('%Y%m%dT%H%M%SZ')}-{unique}.md"
    markdown = (
        "---\n"
        f"local_mind_bridge: true\ncreated: {payload['created_at']}\n"
        f"source: {json.dumps(source, ensure_ascii=False)}\n"
        "---\n\n"
        f"{payload['text']}\n"
    )
    descriptor, temporary_path = tempfile.mkstemp(
        prefix=".incoming-", suffix=".tmp", dir=INCOMING_DIRECTORY
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary:
            temporary.write(markdown)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_path, destination)
    finally:
        if os.path.exists(temporary_path):
            os.unlink(temporary_path)
    return text_content(
        f"Saved as Local Mind incoming note. It will appear in the app within 30 seconds: {destination.name}"
    )


def list_entries(arguments):
    limit = arguments.get("limit", 20)
    if not isinstance(limit, int) or not 1 <= limit <= 100:
        raise ValueError("'limit' must be an integer from 1 to 100")
    state_file = DATA_DIRECTORY / "state.json"
    if not state_file.exists():
        return text_content("Local Mind has no local state yet.")
    try:
        state = json.loads(state_file.read_text(encoding="utf-8"))
        entries = state.get("entries", [])[:limit]
        safe_entries = [
            {
                "id": entry.get("id"),
                "text": entry.get("text"),
                "kind": entry.get("kind"),
                "createdAt": entry.get("createdAt"),
                "due": entry.get("due"),
                "done": entry.get("done"),
            }
            for entry in entries
        ]
        return text_content(json.dumps(safe_entries, ensure_ascii=False, indent=2))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"could not read Local Mind state: {error}") from error


TOOLS = [
    {
        "name": "capture_thought",
        "description": "Save a user's thought as an incoming Local Mind note. This does not create events, tasks, notifications, or send messages.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "The user's thought, kept verbatim."},
                "source": {"type": "string", "description": "Optional source label, default external_agent."},
            },
            "required": ["text"],
            "additionalProperties": False,
        },
    },
    {
        "name": "list_recent_entries",
        "description": "Read a compact view of recent Local Mind entries from local state. It never reads an Obsidian vault or secrets.",
        "inputSchema": {
            "type": "object",
            "properties": {"limit": {"type": "integer", "minimum": 1, "maximum": 100}},
            "additionalProperties": False,
        },
    },
]


def handle(message):
    request_id = message.get("id")
    method = message.get("method")
    if method == "initialize":
        return rpc_result(request_id, {
            "protocolVersion": message.get("params", {}).get("protocolVersion", "2025-06-18"),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "local-mind", "version": "0.1.0"},
        })
    if method == "notifications/initialized":
        return None
    if method == "tools/list":
        return rpc_result(request_id, {"tools": TOOLS})
    if method == "tools/call":
        parameters = message.get("params", {})
        try:
            if parameters.get("name") == "capture_thought":
                result = capture(parameters.get("arguments", {}))
            elif parameters.get("name") == "list_recent_entries":
                result = list_entries(parameters.get("arguments", {}))
            else:
                return rpc_error(request_id, -32602, "Unknown tool")
            return rpc_result(request_id, result)
        except ValueError as error:
            return rpc_error(request_id, -32602, str(error))
    if request_id is not None:
        return rpc_error(request_id, -32601, "Method not found")
    return None


def main():
    for line in sys.stdin:
        try:
            message = json.loads(line)
            response = handle(message)
            if response is not None:
                print(json.dumps(response, ensure_ascii=False), flush=True)
        except json.JSONDecodeError:
            print(json.dumps(rpc_error(None, -32700, "Parse error")), flush=True)
        except Exception as error:  # Do not let one malformed request stop the server.
            print(json.dumps(rpc_error(None, -32603, str(error))), flush=True)


if __name__ == "__main__":
    main()
