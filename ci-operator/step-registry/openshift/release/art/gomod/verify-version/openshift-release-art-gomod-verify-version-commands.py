#!/usr/bin/env python3

import os
from pathlib import Path

path = Path(os.getcwd())
gomod_path = path.joinpath("go.mod")

if gomod_path.exists():
    print(f"go mod file exists at: {gomod_path.absolute()}")
    with open(gomod_path, 'r') as file:
        lines = file.readlines()

        for line in lines:
            if line.startswith("go"):
                line_content = line.strip()
                version = line_content.split(" ")[-1]

                if len(version.split(".")) == 2:
                    raise Exception(f"go version should be of format 1.23.2 (major.minor.patch). Found: {line_content}")
    print("No issues found")
else:
    print(f"go mod file not found at path {gomod_path.absolute()}")
