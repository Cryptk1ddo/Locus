#!/usr/bin/env python3
"""Run native suites sequentially; each launch/profile is disposable."""
import os,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
results=[]
for name in ['canvas','wall_gestures','wall_drops','wall_tabs']:
    path=root/'artifacts/canvas'/f'{name}-tests.log'
    with path.open('w') as output:
        result=subprocess.run([sys.executable,'-u',str(root/'Tests'/f'{name}.py')],env=os.environ,stdout=output,stderr=subprocess.STDOUT)
    results.append(result.returncode); print(name,result.returncode,flush=True)
sys.exit(1 if any(results) else 0)
