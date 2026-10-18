import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
rows = [line.split('|') for line in (root/'Resources/localization.tsv').read_text().splitlines()[1:] if line]
assert all(len(row)==5 for row in rows)
for code,index in [('en',0),('it',1),('fr',2),('de',3),('es',4)]:
    folder = root/'Sources/AudioCore/Localizations'/f'{code}.lproj'
    folder.mkdir(parents=True,exist_ok=True)
    text = '// Generated from Resources/localization.tsv.\n' + '\n'.join(f'{json.dumps(row[0],ensure_ascii=False)} = {json.dumps(row[index],ensure_ascii=False)};' for row in rows)
    (folder/'Localizable.strings').write_text(text+'\n')

