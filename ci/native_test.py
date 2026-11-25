"""Run real iOS tests with an outer launch deadline and useful diagnostics."""
import json,os,pathlib,re,signal,subprocess,sys,time

providers='--providers' in sys.argv
folder=pathlib.Path('native-diagnostics/providers' if providers else 'native-diagnostics/codecs');folder.mkdir(parents=True,exist_ok=True)
target='provider_flow_test.dart' if providers else 'native_player_test.dart'
command=['flutter','test','integration_test/'+target,'-d',os.environ['BECHI_SIMULATOR'],'--no-pub','--timeout','5m' if providers else '2m']
if not providers:command.append('--verbose')
if providers:
    assert re.fullmatch('[A-Za-z0-9_-]{40,100}',os.environ.get('BECHI_QA_TOKEN','')), 'A normal temporary QA session is required'
    os.environ['SIMCTL_CHILD_BECHI_QA_TOKEN']=os.environ['BECHI_QA_TOKEN']

def safe(value):
    if providers:
        value=value.replace(os.environ['BECHI_QA_TOKEN'],'[temporary QA session]')
        value=re.sub(r'https?://\S+','[media]',value)
        value=re.sub(r'(?im)^(cookie|authorization):.*$',r'\1: [redacted]',value)
    return value
with (folder/'flutter-test.log').open('w') as log:
    process=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    try:code=process.wait(timeout=4000 if providers else 900)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid,signal.SIGTERM)
        try:process.wait(timeout=20)
        except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL)
        code=124
if providers:
    path=folder/'flutter-test.log'
    path.write_text(safe(path.read_text(errors='replace')))

def capture(name,args):
    try:
        value=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30,text=True).stdout
    except (subprocess.TimeoutExpired,OSError) as error:value=type(error).__name__
    (folder/name).write_text(safe(value))

capture('devices.json',['xcrun','simctl','list','devices','available','--json'])
capture('runner-system.log',['xcrun','simctl','spawn',os.environ['BECHI_SIMULATOR'],'log','show','--last','3m','--style','compact','--predicate','process == "Runner"'])
capture('runner-dependencies.txt',['otool','-L','build/ios/iphonesimulator/Runner.app/Runner'])
for name in pathlib.Path.home().joinpath('Library/Logs/DiagnosticReports').glob('Runner*'):
    if name.is_file(): (folder/name.name).write_text(safe(name.read_bytes()[:100000].decode(errors='replace')))
try:subprocess.run(['xcrun','simctl','io',os.environ['BECHI_SIMULATOR'],'screenshot',str(folder/'simulator.png')],timeout=20,check=False)
except (subprocess.TimeoutExpired,OSError):pass
lines=(folder/'flutter-test.log').read_text(errors='replace').splitlines()
results={}
for line in lines:
    match=re.search(r'NATIVE_(?:CODEC|PROVIDER)_RESULT (\{.*\})',line)
    if match:
        try:
            result=json.loads(match.group(1));results[result['source']]=result
        except (ValueError,KeyError):pass
expected=16 if providers else 11
if code==0 and (len(results)!=expected or any(row.get('passed') is not True for row in results.values())):
    print('Native run did not return a passing result for every expected case.')
    code=1
(folder/'results.json').write_text(json.dumps({'exit':code,'results':list(results.values())},indent=2))
print('\n'.join(lines[-140:]))
sys.exit(code)
