#!/usr/bin/env python3
"""Deterministic loopback HTTP/SSE contract test. Never used as an app provider."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json,sys
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_POST(self):
        request=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.headers.get('Authorization')!='Bearer test-key':
            self.send_error(401);return
        self.send_response(200);self.send_header('Content-Type','text/event-stream');self.end_headers()
        def event(delta):self.wfile.write(('data: '+json.dumps({'choices':[{'delta':delta}]})+'\n\n').encode());self.wfile.flush()
        if isinstance(request['messages'][-1].get('content'),list):
            assert any(part.get('type')=='image_url' and part['image_url']['url'].startswith('data:image/png;base64,') for part in request['messages'][-1]['content'])
            event({'content':'Mock image context received'})
        elif request['messages'][-1]['role']=='tool':
            event({'content':'Mock tool flow '});event({'content':'completed'})
        else:
            event({'tool_calls':[{'index':0,'id':'call-test','type':'function','function':{'name':'readNote','arguments':'{'}}]})
            event({'tool_calls':[{'index':0,'function':{'arguments':'}'}}]})
        self.wfile.write(b'data: [DONE]\n\n');self.wfile.flush()
server=HTTPServer(('127.0.0.1',0),Handler)
open(sys.argv[1],'w').write(str(server.server_port))
server.serve_forever()
