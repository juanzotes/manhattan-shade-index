#!/usr/bin/env python3
"""Execute a notebook in place using nbclient directly.

`jupyter nbconvert --execute` pulls in nbconvert's ServePostProcessor, which
imports tornado, which trips over a broken Windows certificate store entry on
some machines (ssl.SSLError: [ASN1: NOT_ENOUGH_DATA]) even though this project
never uses that postprocessor. nbclient does the same "run every cell, write
the result back" job without that import chain, so the Makefile targets call
this instead. See docs/DECISIONS.md.

Usage:
    python src/_run_notebook.py src/s0_resolve_sources.ipynb
"""
import sys
from pathlib import Path

import nbformat
from nbclient import NotebookClient


def main(nb_path: str) -> int:
    path = Path(nb_path)
    nb = nbformat.read(path, as_version=4)
    client = NotebookClient(nb, timeout=1800, kernel_name="python3", resources={"metadata": {"path": str(path.parent)}})
    try:
        client.execute()
    finally:
        nbformat.write(nb, path)
    print(f"executed and saved: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
