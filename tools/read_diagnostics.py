#!/usr/bin/env python3
"""Fetch the private bounded playtest journal into ignored project evidence."""
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--attempt', help='16-hex diagnostic ID shown by the game')
parser.add_argument('--minutes', type=int, default=60)
args = parser.parse_args()
if args.attempt and not re.fullmatch(r'[a-f0-9]{16}', args.attempt):
    parser.error('--attempt must be a 16-hex diagnostic ID')
if not 1 <= args.minutes <= 10080:
    parser.error('--minutes must be between 1 and 10080')
operator = Path.home()/'workspace/tooling/cloudflare-api/cloudflare'
command = [str(operator), 'worker-logs', 'coop-side-scroller-issuer', '--minutes', str(args.minutes)]
if args.attempt:
    command += ['--attempt', args.attempt]
result = subprocess.run(command, capture_output=True, text=True)
if result.returncode:
    raise SystemExit(result.stderr.strip() or 'Diagnostic lookup failed')
report = json.loads(result.stdout)
if report.get('version') != 1 or not isinstance(report.get('events'), list):
    raise SystemExit('Invalid journal response')
target = ROOT/'build/diagnostics-latest.json'
target.parent.mkdir(exist_ok=True)
target.write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps({'saved': str(target), 'entries': len(report['events']),
                  'kinds': sorted({e['kind'] for e in report['events']})}))
