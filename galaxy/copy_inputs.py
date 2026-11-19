"""Copies the datasets of the Galaxy tool inputs to where the escriptorium user can read them.

Usage: copy_inputs.py <inputs.json> <folder>

This runs as root, so it can read datasets the escriptorium user cannot.
Writes the same json <folder>/inputs.json but with each dataset's source_path pointing to the copy belonging to the escriptorium user.
"""
import itertools
import json
import os
import shutil
import sys

inputs_path, folder = sys.argv[1:]
numbers = itertools.count()


def copy(value):
    if isinstance(value, list):
        return [copy(item) for item in value]
    if isinstance(value, dict) and value.get("source_path"):
        target = os.path.join(folder, str(next(numbers)))
        shutil.copyfile(value["source_path"], target)
        return {**value, "source_path": target}
    if isinstance(value, dict):
        return {key: copy(item) for key, item in value.items()}
    return value


with open(inputs_path) as inputs_file:
    inputs = json.load(inputs_file)
with open(os.path.join(folder, "inputs.json"), "w") as copied_file:
    json.dump(copy(inputs), copied_file)
