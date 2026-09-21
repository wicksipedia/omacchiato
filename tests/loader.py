"""Import a script from bin/ as a module. The scripts have no .py name."""
import importlib.machinery
import importlib.util
from pathlib import Path


def load(name):
    path = Path(__file__).resolve().parent.parent / "bin" / name
    loader = importlib.machinery.SourceFileLoader(name.replace("-", "_"), str(path))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(module)
    return module
