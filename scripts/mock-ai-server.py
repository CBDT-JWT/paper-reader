#!/usr/bin/env python3
"""Deterministic loopback HTTP/SSE contract test. Never used as an app provider."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json,sys
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
        if self.path.startswith('/files/'):
            if self.headers.get('Authorization') or self.path != '/files/evidence.csv':
                self.send_error(404);return
            body=b'name,value\nverified,42\n'
            self.send_response(200);self.send_header('Content-Type','text/csv');self.send_header('Content-Disposition','attachment; filename="evidence.csv"');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body);return
        self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers()
        self.wfile.write(json.dumps({'data':[{'id':'test-model'}]}).encode())
    def do_POST(self):
        request=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if self.path.startswith('/local/') and self.headers.get('Authorization'):
            self.send_error(400);return
        if not self.path.startswith('/local/') and self.headers.get('Authorization')!='Bearer test-key':
            self.send_error(401);return
        self.send_response(200);self.send_header('Content-Type','text/event-stream');self.end_headers()
        def event(delta):self.wfile.write(('data: '+json.dumps({'choices':[{'delta':delta}]})+'\n\n').encode());self.wfile.flush()
        if isinstance(request['messages'][-1].get('content'),list):
            assert any(part.get('type')=='image_url' and part['image_url']['url'].startswith('data:image/png;base64,') for part in request['messages'][-1]['content'])
            event({'content':'Mock image context received'})
        elif request['messages'][-1]['role']=='tool':
            event({'content':'**Mock tool flow '});event({'content':'completed** with *verified context*.\n\n[p.1](paperreader://page/1)\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n$x^2$'})
        elif 'DOWNLOAD_FIXTURE' in str(request['messages'][-1].get('content','')):
            arguments=json.dumps({'url':f'http://127.0.0.1:{self.server.server_port}/files/evidence.csv','folder':'AI Downloads','fileName':'evidence.csv'})
            event({'tool_calls':[{'index':0,'id':'call-download','type':'function','function':{'name':'downloadFile','arguments':arguments}}]})
        else:
            if 'QUOTED_PAYLOAD' in str(request['messages'][-1].get('content','')):
                assert 'Selected evidence for context' in str(request['messages'][-1]['content'])
            event({'tool_calls':[{'index':0,'id':'call-test','type':'function','function':{'name':'readNote','arguments':'{'}}]})
            event({'tool_calls':[{'index':0,'function':{'arguments':'}'}}]})
        self.wfile.write(b'data: [DONE]\n\n');self.wfile.flush()
server=HTTPServer(('127.0.0.1',0),Handler)
open(sys.argv[1],'w').write(str(server.server_port))
server.serve_forever()
