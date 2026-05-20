import http.server, json, os, sys, time

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/api/delete':
            length = int(self.headers.get('Content-Length', 0))
            body = json.loads(self.rfile.read(length))
            svg = body.get('svg', '')
            if not svg or '..' in svg or svg.startswith('/'):
                self.send_error(400)
                return
            svg_path = os.path.realpath(os.path.join(os.getcwd(), svg))
            if not svg_path.startswith(os.path.realpath(os.getcwd()) + os.sep):
                self.send_error(400)
                return
            manifest_path = os.path.join(os.getcwd(), 'manifest.json')
            if not os.path.exists(manifest_path):
                self.send_error(400)
                return
            with open(manifest_path) as f:
                manifest = json.load(f)
            if svg not in [e['svg'] for e in manifest.get('files', [])]:
                self.send_error(400)
                return
            if os.path.exists(svg_path):
                os.remove(svg_path)
            manifest['files'] = [e for e in manifest['files'] if e['svg'] != svg]
            manifest['updated_at'] = int(time.time())
            with open(manifest_path, 'w') as f:
                json.dump(manifest, f, indent=2)
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"ok":true}')
        else:
            self.send_error(404)

    def log_message(self, format, *args):
        pass

os.chdir(sys.argv[2])
http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()
