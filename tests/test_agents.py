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


def claude_log(path, title, ts="2026-09-21T03:00:00Z"):
    write(path, json.dumps({"type": "ai-title", "aiTitle": title}) + "\n", "w")


def test_claude_info_cache():
    calls = []
    real = agents.claude_session_info
    agents.claude_session_info = lambda p: (calls.append(p), real(p))[1]
    agents.CLAUDE_INFO.clear()
    try:
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "s.jsonl")
            claude_log(path, "One")
            st = os.stat(path)
            stamp = (st.st_mtime, st.st_size)
            assert agents.cached_claude_info(path, stamp)[0] == "One"
            assert agents.cached_claude_info(path, stamp)[0] == "One"
            assert len(calls) == 1, calls          # hit: unchanged mtime/size

            claude_log(path, "Two!")               # size differs
            st = os.stat(path)
            assert agents.cached_claude_info(path, (st.st_mtime, st.st_size))[0] == "Two!"
            assert len(calls) == 2, calls          # miss after the file changed

            assert agents.cached_claude_info(path, (st.st_mtime + 5, st.st_size))[0] == "Two!"
            assert len(calls) == 3, calls          # mtime alone invalidates too
    finally:
        agents.claude_session_info = real
        agents.CLAUDE_INFO.clear()


def test_claude_sessions_prunes_cache():
    with tempfile.TemporaryDirectory() as d:
        old_projects = agents.CLAUDE_PROJECTS
        agents.CLAUDE_PROJECTS = d
        agents.CLAUDE_INFO.clear()
        try:
            cwd = os.path.join(d, "work")
            folder = agents.claude_project_dir(cwd)
            os.makedirs(folder)
            path = os.path.join(folder, "s.jsonl")
            claude_log(path, "One")
            agents.CLAUDE_INFO["/gone/old.jsonl"] = ((0, 0), ("", "", ""))
            procs = {10: ("claude", 1)}
            win = agents.Windows()
            win._clients = [{"pid": 10, "address": "0x1", "title": "✳ One"}]
            old_cwd = agents.proc_cwd
            agents.proc_cwd = lambda pid: cwd
            try:
                out = agents.claude_sessions(os.path.getmtime(path) + 1, procs, win)
            finally:
                agents.proc_cwd = old_cwd
            assert len(out) == 1 and out[0]["title"] == "One", out
            assert list(agents.CLAUDE_INFO) == [path], list(agents.CLAUDE_INFO)
        finally:
            agents.CLAUDE_PROJECTS = old_projects
            agents.CLAUDE_INFO.clear()


def test_windows_is_lazy_and_once():
    calls = []
    real = agents.hypr_clients
    agents.hypr_clients = lambda: (calls.append(1), [{"pid": 5, "address": "a"}])[1]
    try:
        w = agents.Windows()
        assert calls == []                         # nothing fetched up front
        assert agents.claude_sessions(0, {1: ("bash", 0)}, w) == []
        assert agents.codex_sessions(0, {}, w) == [] and calls == []
        assert w.by_pid()[5]["address"] == "a" and w.clients() and len(calls) == 1
    finally:
        agents.hypr_clients = real


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
