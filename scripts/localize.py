#!/usr/bin/env python3
"""Collect Chinese Swift literals, preserving Swift interpolation, and enforce localized lookups."""
import pathlib,json,re,sys
root=pathlib.Path(__file__).resolve().parents[1]
map_path=root/'scripts/translations.json'
translations=json.loads(map_path.read_text()) if map_path.exists() else {}
keys=set()
def string_end(s,i):
    j=i+1
    while j<len(s):
        if s.startswith('\\(',j):
            depth=1;j+=2
            while depth and j<len(s):
                if s[j]=='"':j=string_end(s,j)
                elif s[j]=='(':depth+=1;j+=1
                elif s[j]==')':depth-=1;j+=1
                else:j+=1
        elif s[j]=='\\':j+=2
        elif s[j]=='"':return j+1
        else:j+=1
    return j
def key_for(literal):
    value=literal[1:-1];out='';j=0
    while j<len(value):
        if value.startswith('\\(',j):
            depth=1;j+=2
            while depth and j<len(value):
                if value[j]=='"':j=string_end(value,j)
                elif value[j]=='(':depth+=1;j+=1
                elif value[j]==')':depth-=1;j+=1
                else:j+=1
            out+='%@'
        else:out+=value[j];j+=1
    try:return json.loads('"'+out+'"')
    except:return out
for path in list((root/'Sources/PaperReader').glob('*.swift'))+list((root/'Sources/PaperCore').glob('*.swift')):
    if path.name in ['Localization.swift','IntegrationSelfTest.swift']:continue
    text=path.read_text();result='';i=0;changed=False
    while i<len(text):
        if text.startswith('//',i):
            j=text.find('\n',i);j=len(text) if j<0 else j;result+=text[i:j];i=j
        elif text.startswith('#"""',i) or text.startswith('"""',i):
            raw=text.startswith('#',i);opening=4 if raw else 3;end='"""#' if raw else '"""';j=text.find(end,i+opening);j=len(text) if j<0 else j+len(end);result+=text[i:j];i=j
        elif text[i]=='"':
            j=string_end(text,i);literal=text[i:j]
            if re.search('[\u4e00-\u9fff]',literal):
                key=key_for(literal);keys.add(key)
                if text[max(0,i-2):i]!='L(':result+='L('+literal+')';changed=True
                else:result+=literal
            else:result+=literal
            i=j
        else:result+=text[i];i+=1
    if changed and '--check' not in sys.argv:
        if path.parent.name=='PaperReader' and 'import PaperCore' not in result:result='import PaperCore\n'+result
        path.write_text(result)
missing=sorted(keys-translations.keys())
(root/'build/localization-missing.json').write_text(json.dumps(missing,ensure_ascii=False,indent=2))
all_values={key:translations.get(key,key) for key in sorted(keys)}
resources=root/'Sources/PaperCore/Resources'
if '--check' in sys.argv:
    print('Localization keys:',len(keys),'Missing English translations:',len(missing))
    sys.exit(1 if missing else 0)
(resources/'en.json').write_text(json.dumps(all_values,ensure_ascii=False,indent=2)+'\n')
for language,values in [('en',all_values),('zh-Hans',{key:key for key in keys})]:
    (resources/f'{language}.lproj/Localizable.strings').write_text('\n'.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(v,ensure_ascii=False)+';' for k,v in sorted(values.items()))+'\n')
print('Localization keys:',len(keys),'Missing English translations:',len(missing))
