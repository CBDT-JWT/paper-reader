#!/usr/bin/env python3
"""Exercise upstream signing/verification with disposable test keys, never production keys."""
from pathlib import Path
import base64,json,os,plistlib,secrets,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
build=Path(os.environ.get('PAPER_READER_BUILD_DIR',str(Path.home()/'Library/Caches/PaperReader/Build')))
tool=build/'artifacts/sparkle/Sparkle/bin/sign_update'
info=plistlib.loads((root/'scripts/Info.plist').read_bytes())
assert info['SUFeedURL']=='https://www.weitao-jiang.cn/paper-reader/appcast.xml'
assert len(base64.b64decode(info['SUPublicEDKey']))==32
assert info['SUVerifyUpdateBeforeExtraction'] is True
checks=['Stable HTTPS feed and public Ed25519 key configured','Archive signature verification before extraction enabled']
with tempfile.TemporaryDirectory(prefix='PaperReader-SignatureTest-') as folder:
 p=Path(folder);key=p/'test.key';key.write_bytes(base64.b64encode(secrets.token_bytes(32)));key.chmod(0o600)
 archive=p/'update.zip';archive.write_bytes(b'Paper Reader disposable signature fixture')
 def run(*args):return subprocess.run([str(tool),'--ed-key-file',str(key),*map(str,args)],capture_output=True,text=True)
 signature=run('-p',archive);assert signature.returncode==0,signature.stderr
 assert run('--verify',archive,signature.stdout.strip()).returncode==0
 checks.append('Official Sparkle sign_update signs and verifies a disposable archive')
 archive.write_bytes(archive.read_bytes()+b'TAMPERED')
 assert run('--verify',archive,signature.stdout.strip()).returncode!=0
 checks.append('Official Sparkle verifier rejects modified archive bytes')
 feed=p/'appcast.xml';feed.write_bytes((root/'website/appcast.xml').read_bytes())
 assert run(feed).returncode==0
 assert run('--verify',feed).returncode==0
 checks.append('Official Sparkle tool signs and verifies an actual RSS appcast')
 feed.write_bytes(feed.read_bytes().replace(b'Paper Reader Updates',b'TAMPERED Updates'))
 assert run('--verify',feed).returncode!=0
 checks.append('Official Sparkle verifier rejects modified feed content')
print(json.dumps({'passed':len(checks),'checks':checks},indent=2))
