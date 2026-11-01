#!/usr/bin/env python3
"""Launch Joey development tools without unrelated inherited credentials.

Use direct executable arguments, never a login/interactive shell. Output and
exit status are preserved; protection happens before the child is launched.
"""
import os
from pathlib import Path
import sys


def child_environment(parent):
    allowed = (
        "HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "DEVELOPER_DIR",
        "JOEY_REAL_MEDIA_INPUTS", "JOEY_MODEL_INDEPENDENT_EVIDENCE",
        "JOEY_LOCAL_ASSISTANT_SMOKE",
    )
    result = {name: parent[name] for name in allowed if name in parent}
    result["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    return result


def main(arguments):
    if not arguments:
        print("Usage: python3 Tools/run-local.py EXECUTABLE [ARG ...]", file=sys.stderr)
        return 2
    if Path(arguments[0]).name in {"sh", "bash", "zsh", "fish", "csh", "tcsh"}:
        print("Launch the tool directly; shell startup files can restore credentials.", file=sys.stderr)
        return 2
    try:
        # Replace this launcher so PID/parent tracking, signals and the tool's
        # exact exit status retain their ordinary direct-launch semantics.
        os.execvpe(arguments[0], arguments, child_environment(os.environ))
    except OSError:
        # Do not echo arbitrary command arguments or environment in diagnostics.
        print("Unable to launch the requested local tool.", file=sys.stderr)
        return 126


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
