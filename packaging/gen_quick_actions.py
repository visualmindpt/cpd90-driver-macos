#!/usr/bin/env python3
"""Gera as Ações Rápidas do Finder ("Imprimir na CP-D90 (…)") como workflows
do Automator.

Cada ação recebe as imagens selecionadas no Finder e envia-as numa só tarefa
com a cpd90-print (Ultra Fine + perfil CPD90_UF), o que permite à impressora
emparelhar formatos pequenos na mesma folha. Mostra uma notificação quando
corre bem e uma janela com o erro quando falha.

Uso: gen_quick_actions.py <pasta-destino> [--simular]
     (--simular gera ações que só mostram o que fariam; para testes)
"""
import os
import plistlib
import sys
import uuid

TOOL = '/Library/Printers/CPD90Universal/bin/cpd90-print'
# (formato, rótulo, opções extra da cpd90-print)
VARIANTS = [
    ('15x20', '15×20', ''),
    ('10x15', '10×15', ''),
    ('15x20', '15×20, mate', '-o MEPrintFinish=Matte'),
    ('10x15', '10×15, mate', '-o MEPrintFinish=Matte'),
]


def script(fmt, label, opts, simulate):
    extra = (' ' + opts if opts else '') + (' --simular' if simulate else '')
    return f'''# Gerado por packaging/gen_quick_actions.py
out=$("{TOOL}" -t {fmt}{extra} "$@" 2>&1)
if [ $? -eq 0 ]; then
    /usr/bin/osascript -e 'on run argv' \\
        -e 'display notification (item 1 of argv) with title "CP-D90" subtitle "{label}"' \\
        -e 'end run' "$# foto(s) enviada(s) para impressão"
else
    /usr/bin/osascript -e 'on run argv' \\
        -e 'display dialog (item 1 of argv) with title "CP-D90 — erro" buttons {{"OK"}} default button 1 with icon stop' \\
        -e 'end run' "$out"
fi
printf '%s\\n' "$out"
'''


def workflow(fmt, label, opts, simulate):
    ids = [str(uuid.uuid5(uuid.NAMESPACE_URL, f'cpd90/{label}/{k}')).upper() for k in 'aio']
    action = {
        'AMAccepts': {'Container': 'List', 'Optional': True, 'Types': ['com.apple.cocoa.string']},
        'AMActionVersion': '2.0.3',
        'AMApplication': ['Automator'],
        'AMParameterProperties': {
            'COMMAND_STRING': {}, 'CheckedForUserDefaultShell': {},
            'inputMethod': {}, 'shell': {}, 'source': {}},
        'AMProvides': {'Container': 'List', 'Types': ['com.apple.cocoa.string']},
        'ActionBundlePath': '/System/Library/Automator/Run Shell Script.action',
        'ActionName': 'Run Shell Script',
        'ActionParameters': {
            'COMMAND_STRING': script(fmt, label, opts, simulate),
            'CheckedForUserDefaultShell': True,
            'inputMethod': 1,            # entrada como argumentos ("$@")
            'shell': '/bin/zsh',
            'source': ''},
        'BundleIdentifier': 'com.apple.RunShellScript',
        'CFBundleVersion': '2.0.3',
        'CanShowSelectedItemsWhenRun': False,
        'CanShowWhenRun': True,
        'Category': ['AMCategoryUtilities'],
        'Class Name': 'RunShellScriptAction',
        'InputUUID': ids[1],
        'Keywords': ['Shell', 'Script', 'Command', 'Run', 'Unix'],
        'OutputUUID': ids[2],
        'UUID': ids[0],
        'UnlocalizedApplications': ['Automator'],
        'arguments': {},
        'isViewVisible': 1,
        'location': '309.000000:253.000000',
        'nibPath': '/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib',
    }
    return {
        'AMApplicationBuild': '523',
        'AMApplicationVersion': '2.10',
        'AMDocumentVersion': '2',
        'actions': [{'action': action, 'isViewVisible': 1}],
        'connectors': {},
        'workflowMetaData': {
            'applicationBundleIDsByPath': {},
            'applicationPaths': [],
            'inputTypeIdentifier': 'com.apple.Automator.fileSystemObject.image',
            'outputTypeIdentifier': 'com.apple.Automator.nothing',
            'presentationMode': 15,
            'processesInput': False,
            'serviceApplicationBundleID': 'com.apple.finder',
            'serviceApplicationPath': '/System/Library/CoreServices/Finder.app',
            'serviceInputTypeIdentifier': 'com.apple.Automator.fileSystemObject.image',
            'serviceOutputTypeIdentifier': 'com.apple.Automator.nothing',
            'serviceProcessesInput': False,
            'systemImageName': 'NSActionTemplate',
            'useAutomaticInputType': False,
            'workflowTypeIdentifier': 'com.apple.Automator.servicesMenu',
        },
    }


def info_plist(name):
    return {
        'NSServices': [{
            'NSBackgroundColorName': 'background',
            'NSIconName': 'NSActionTemplate',
            'NSMenuItem': {'default': name},
            'NSMessage': 'runWorkflowAsService',
            'NSRequiredContext': {'NSApplicationIdentifier': 'com.apple.finder'},
            'NSSendFileTypes': ['public.image'],
        }]
    }


def main():
    dest = sys.argv[1]
    simulate = '--simular' in sys.argv
    os.makedirs(dest, exist_ok=True)
    for fmt, label, opts in VARIANTS:
        name = f'Imprimir na CP-D90 ({label})'
        contents = os.path.join(dest, f'{name}.workflow', 'Contents')
        os.makedirs(contents, exist_ok=True)
        with open(os.path.join(contents, 'Info.plist'), 'wb') as f:
            plistlib.dump(info_plist(name), f)
        with open(os.path.join(contents, 'document.wflow'), 'wb') as f:
            plistlib.dump(workflow(fmt, label, opts, simulate), f)
        print(os.path.join(dest, f'{name}.workflow'))


if __name__ == '__main__':
    main()
