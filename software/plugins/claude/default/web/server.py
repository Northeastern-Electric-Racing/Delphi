#!/usr/bin/env python3
"""The delphi mod's browser view of /ws-delphi: python3 web/server.py <clone> serves index.html (the same
cards: select one, then Switch workspace) on 127.0.0.1 at a random port, and prints its URL, the
first line on stdout. The page asks it for .delphi/switch.sh --list and runs switch.sh <name>; each
switch prints `switched <name>`, which the mod reads to update its pane. Pull runs switch.sh on the
workspace the clone is on (fetch, fast-forward, setup.sh) and prints `pulled <what it did>`. The mod starts it with
/ws-delphi --web (or the pane's Open in browser) and stops it with the session; by hand, Ctrl-C ends it.

Only this machine reaches it, and only a page holding the URL's token: any web page the browser has
open can send requests to 127.0.0.1, so every request needs the token in its path and a Host of
127.0.0.1 or localhost (against DNS rebinding), and a switch needs a JSON body (which a page of
another origin can't send without a preflight, which this answers with nothing). Python 3.7+, stdlib.
"""
import http.server
import json
import secrets
import subprocess
import sys
import threading
from pathlib import Path

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
switch = root / '.delphi' / 'switch.sh'
if not switch.is_file():
    sys.exit('server: no .delphi/switch.sh in ' + str(root) + '; give a Delphi clone')
token = secrets.token_urlsafe(18)
page = (Path(__file__).parent / 'index.html').read_bytes()
busy = threading.Lock()  # one switch at a time
switching = ''  # the workspace being switched to (or pulled), while one runs


def run(argv, timeout):
    try:
        return subprocess.run(argv, cwd=root, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as err:
        return subprocess.CompletedProcess(argv, -1, '', str(err))


def last_line(text, otherwise):
    lines = [line for line in text.strip().splitlines() if line.strip()]
    return lines[-1] if lines else otherwise


def state():
    listed = run(['bash', str(switch), '--list'], 60)
    lines = [line for line in listed.stdout.splitlines() if line.strip()]
    return {
        'here': next((line[2:] for line in lines if line.startswith('* ')), ''),
        'workspaces': [line[2:] for line in lines],
        'isDirty': run(['git', 'diff', '--quiet', 'HEAD', '--'], 10).returncode != 0,
        'switching': switching,
        'error': '' if listed.returncode == 0 else 'Could not list the workspaces: ' + last_line(listed.stderr, 'switch.sh --list failed'),
    }


def do_switch(name):
    global switching
    if not busy.acquire(blocking=False):
        return 409, {'ok': False, 'message': 'a switch to ' + switching + ' is running'}
    try:
        switching = name
        done = run(['bash', str(switch), name], 600)
    finally:
        switching = ''
        busy.release()
    if done.returncode != 0:
        return 200, {'ok': False, 'message': last_line(done.stderr, 'switch.sh failed')}
    print('switched ' + name, flush=True)
    return 200, {'ok': True, 'message': last_line(done.stdout, 'switched')}


def do_pull():
    global switching
    here = state()['here']
    if not here:
        return 400, {'ok': False, 'message': 'this clone is on no workspace'}
    if not busy.acquire(blocking=False):
        return 409, {'ok': False, 'message': 'a switch to ' + switching + ' is running'}
    leaf = here.split('/')[-1]
    try:
        switching = here
        before = run(['git', 'rev-parse', 'HEAD'], 10).stdout.strip()
        done = run(['bash', str(switch), here], 600)
        after = run(['git', 'rev-parse', 'HEAD'], 10).stdout.strip()
    finally:
        switching = ''
        busy.release()
    if done.returncode != 0:
        return 200, {'ok': False, 'message': 'Not pulled: ' + last_line(done.stderr, 'switch.sh failed')}
    if 'diverged' in done.stderr:
        return 200, {'ok': False, 'message': last_line(done.stderr, 'diverged from origin')}
    count = run(['git', 'rev-list', '--count', before + '..' + after], 10).stdout.strip() if before and after and before != after else '0'
    n = int(count or 0)
    message = leaf + ' is up to date with origin' if n == 0 else 'Pulled %d commit%s into %s' % (n, '' if n == 1 else 's', leaf)
    print('pulled ' + message, flush=True)
    return 200, {'ok': True, 'message': message}


class Handler(http.server.BaseHTTPRequestHandler):
    def send(self, status, body, kind):
        self.send_response(status)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Referrer-Policy', 'no-referrer')  # the token stays in this page
        self.send_header('Content-Security-Policy', "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(body)

    def json(self, status, value):
        self.send(status, json.dumps(value).encode(), 'application/json')

    def route(self):
        """The path after the token, or None (and the refusal sent) for a request not from the page."""
        port = self.server.server_address[1]
        if self.headers.get('Host') not in ('127.0.0.1:%d' % port, 'localhost:%d' % port):
            self.send(403, b'forbidden\n', 'text/plain')
            return None
        prefix = '/' + token + '/'
        if not self.path.split('?')[0].startswith(prefix):
            self.send(404, b'not found\n', 'text/plain')
            return None
        return self.path.split('?')[0][len(prefix):]

    def do_GET(self):
        path = self.route()
        if path == '':
            self.send(200, page, 'text/html; charset=utf-8')
        elif path == 'api/state':
            self.json(200, state())
        elif path is not None:
            self.send(404, b'not found\n', 'text/plain')

    def do_POST(self):
        path = self.route()
        if path is None:
            return
        if path not in ('api/switch', 'api/pull'):
            return self.send(404, b'not found\n', 'text/plain')
        if self.headers.get('Content-Type', '').split(';')[0].strip() != 'application/json':
            return self.json(415, {'ok': False, 'message': 'send JSON'})
        if path == 'api/pull':
            return self.json(*do_pull())
        try:
            name = json.loads(self.rfile.read(int(self.headers.get('Content-Length') or 0)) or b'{}').get('name', '')
        except (ValueError, AttributeError):
            name = ''
        if not isinstance(name, str) or not name:
            return self.json(400, {'ok': False, 'message': 'no workspace named'})
        self.json(*do_switch(name))

    def log_message(self, format, *args):  # quiet: stderr is the mod's debug log
        pass


server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print('http://127.0.0.1:%d/%s/' % (server.server_address[1], token), flush=True)
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
