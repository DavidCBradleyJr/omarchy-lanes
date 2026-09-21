"""Run: python3 tests/test_agents.py"""
import json
import os
import tempfile
from importlib.machinery import SourceFileLoader

agents = SourceFileLoader("lanes_agents", os.path.join(os.path.dirname(__file__), "..", "bin", "lanes-agents")).load_module()


def line(kind, payload, ts="2026-09-21T03:00:00Z"):
    return json.dumps({"timestamp": ts, "type": kind, "payload": payload}) + "\n"


def write(path, text, mode="a"):
    with open(path, mode) as f:
        f.write(text)


def test_open_turn_far_behind_the_tail():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "rollout.jsonl")
        write(path, line("session_meta", {"id": "abc", "cwd": "/w", "originator": "Codex Desktop"}), "w")
        write(path, line("turn_context", {"model": "gpt-test"}))
        write(path, line("event_msg", {"type": "task_started", "turn_id": "t1"}))
        # 6 MB of tool noise: the start marker is well outside any tail read
        filler = line("event_msg", {"type": "token_count", "info": "x" * 900})
        write(path, filler * 6500)
        write(path, line("response_item", {"type": "reasoning", "summary": [{"type": "summary_text", "text": "Inspecting the FBX"}]}))

        log = agents.CodexLog(path)
        assert log.open_turn == "t1", log.open_turn
        assert log.model == "gpt-test"
        assert log.activity == "Inspecting the FBX"

        # appended events are picked up incrementally
        write(path, line("response_item", {"type": "function_call", "arguments": json.dumps({"cmd": "blender -b"})}))
        log.update()
        assert log.activity == "$ blender -b"
        write(path, line("event_msg", {"type": "task_complete", "turn_id": "t1"}))
        log.update()
        assert log.open_turn is None and log.last_complete


def test_partial_line_is_read_whole_later():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "rollout.jsonl")
        write(path, line("session_meta", {"id": "abc"}), "w")
        write(path, line("event_msg", {"type": "task_complete", "turn_id": "t0"}))
        started = line("event_msg", {"type": "task_started", "turn_id": "t2"})
        write(path, started[:20])            # being written right now
        log = agents.CodexLog(path)
        assert log.open_turn is None
        write(path, started[20:])
        log.update()
        assert log.open_turn == "t2", log.open_turn


def test_helpers():
    assert agents.strip_glyph("✳ Local models") == "Local models"
    assert agents.strip_glyph("◐ Omarchy") == "Omarchy"
    assert agents.strip_glyph("plain") == "plain"
    assert agents.claude_project_dir("/home/deej/My Proj.x").endswith("/-home-deej-My-Proj-x")
    assert agents.one_line("a\n  b", 10) == "a b"


if __name__ == "__main__":
    n = 0
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            n += 1
            print("ok -", name)
    print("\n%d tests passed" % n)
