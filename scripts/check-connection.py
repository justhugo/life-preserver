#!/usr/bin/env python3
"""Read-only helper diagnostic. Prints schema/status only, never credentials or identity."""
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time

helper = sys.argv[1]
connection_dir = Path(sys.argv[2]).resolve()
env = {'HOME': str(Path.home()), 'PATH': '/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin',
       'CODEX_HOME': str(connection_dir), 'LANG': 'en_US.UTF-8'}
proc = subprocess.Popen([helper, 'app-server', '--stdio', '-c', 'cli_auth_credentials_store="keyring"',
                         '-c', 'analytics.enabled=false'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, env=env, cwd=connection_dir)
selector = selectors.DefaultSelector()
selector.register(proc.stdout, selectors.EVENT_READ)
buffer = b''

def send(message):
    proc.stdin.write(json.dumps(message).encode() + b'\n')
    proc.stdin.flush()

def read_response(identifier):
    global buffer
    deadline = time.monotonic() + 25
    while time.monotonic() < deadline:
        if b'\n' not in buffer:
            if not selector.select(timeout=max(0, deadline - time.monotonic())):
                break
            chunk = os.read(proc.stdout.fileno(), 65536)
            if not chunk:
                raise RuntimeError('helper exited')
            buffer += chunk
        while b'\n' in buffer:
            line, buffer = buffer.split(b'\n', 1)
            result = json.loads(line)
            if result.get('id') == identifier:
                return result
    raise TimeoutError('helper response timed out')

try:
    send({'id': 1, 'method': 'initialize', 'params': {'clientInfo': {'name': 'life_preserver', 'version': '1.0.0'}}})
    initialized = read_response(1)
    print('initialize:', 'ok' if 'result' in initialized else 'error')
    send({'method': 'initialized', 'params': {}})
    send({'id': 2, 'method': 'account/read', 'params': {}})
    response = read_response(2)
    account = response.get('result', {}).get('account')
    print('account present:', account is not None)
    print('account type:', account.get('type') if isinstance(account, dict) else None)
    print('response fields:', sorted(response.get('result', {}).keys()))
    print('error code:', response.get('error', {}).get('code'))
    if account:
        send({'id': 3, 'method': 'account/rateLimits/read', 'params': {}})
        limits = read_response(3)
        print('quota response:', 'ok' if 'result' in limits else 'error')
        print('quota fields:', sorted(limits.get('result', {}).keys()))
finally:
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    selector.close()
