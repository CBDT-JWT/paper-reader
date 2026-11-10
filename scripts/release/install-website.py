"""Install the product page into the existing homepage, preserving unrelated routes."""
from pathlib import Path
import ast,shutil,sys
root=Path(__file__).resolve().parents[2]
destination=Path(sys.argv[1]);app=destination/'app.py';source=app.read_text()
anchor="@app.route('/')\ndef index():"
routes="""@app.route('/paper-reader')
def paper_reader_redirect():
    return redirect('/paper-reader/', code=308)


@app.route('/paper-reader/appcast.xml')
def paper_reader_appcast():
    response = send_from_directory('static/paper-reader', 'appcast.xml', conditional=False, max_age=0)
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate'
    return response


@app.route('/paper-reader/')
def paper_reader_site():
    return send_from_directory('static/paper-reader', 'index.html')


"""
if "def paper_reader_site():" not in source:
 if anchor not in source:raise SystemExit('Existing homepage index anchor not found. No changes written.')
 source=source.replace(anchor,routes+anchor,1)
elif "def paper_reader_appcast():" not in source:
 raise SystemExit('Partial product routes already exist. Review before upgrading.')
ast.parse(source)
app.write_text(source)
shutil.copytree(root/'website',destination/'static/paper-reader',dirs_exist_ok=True)
print('Installed product routes, site assets and stable feed without modifying existing homepage routes.')
