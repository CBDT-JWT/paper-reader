"""Fail closed before distributing a stable release."""
import os, plistlib, subprocess, sys
from pathlib import Path
root=Path(__file__).resolve().parents[2]
identity=os.environ.get('PAPER_READER_SIGN_IDENTITY','')
profile=os.environ.get('PAPER_READER_NOTARY_PROFILE','PaperReader')
if not identity.startswith('Developer ID Application:'):
 sys.exit('Set PAPER_READER_SIGN_IDENTITY to your Developer ID Application identity (Apple Development/ad-hoc are not distribution identities).')
identities=subprocess.run(['security','find-identity','-v','-p','codesigning'],capture_output=True,text=True,check=True).stdout
if f'"{identity}"' not in identities: sys.exit('The requested Developer ID Application identity is not available in the current Keychain.')
p=plistlib.loads((root/'scripts/Info.plist').read_bytes())
if not p.get('SURequireSignedFeed') or not p.get('SUVerifyUpdateBeforeExtraction'):sys.exit('Stable releases require signed feeds and archive signature verification before extraction.')
if len(p.get('SUPublicEDKey',''))!=44:sys.exit('Missing Sparkle public key. Run scripts/release/setup-update-key.sh first.')
tool=Path(os.environ.get('PAPER_READER_BUILD_DIR',str(Path.home()/'Library/Caches/PaperReader/Build')))/'artifacts/sparkle/Sparkle/bin/generate_keys'
public=subprocess.run([str(tool),'--account','dev.paperreader.mac','-p'],capture_output=True,text=True,check=True).stdout.strip()
if public!=p['SUPublicEDKey']:sys.exit('The Keychain update public key does not match the shipped app. Stop and plan key rotation; do not replace the public key silently.')
subprocess.run(['xcrun','notarytool','history','--keychain-profile',profile],check=True,stdout=subprocess.DEVNULL)
print('Developer ID identity, public update key and notarization profile available.')
