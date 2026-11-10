"""Sign nested code inside-out. Never use --deep to sign a release."""
from pathlib import Path
import os, subprocess, sys
app=Path(sys.argv[1]);identity=os.environ.get('PAPER_READER_SIGN_IDENTITY','-')
release=identity!='-'
if release and not identity.startswith('Developer ID Application:'):
 raise SystemExit('Distribution signing requires a Developer ID Application identity.')
def sign(path,preserve=False):
 args=['codesign','--force','--sign',identity]
 if release: args+=['--options','runtime','--timestamp']
 if preserve:args+=['--preserve-metadata=entitlements']
 subprocess.run(args+[str(path)],check=True)
if release:
 # Framework helper executables may have no bundle wrapper. Preserve their sandbox entitlements.
 for p in sorted(app.rglob('*'),key=lambda x:len(x.parts),reverse=True):
  if p.is_symlink():continue
  if p.is_file() and p.stat().st_mode&0o111:
   kind=subprocess.run(['file','-b',str(p)],capture_output=True,text=True,check=True).stdout
   if 'Mach-O' in kind: sign(p,True)
  elif p.is_dir() and p.suffix in ('.app','.xpc','.framework'):sign(p,True)
sign(app)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
