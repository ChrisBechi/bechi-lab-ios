"""Run real iOS tests with an outer launch deadline and useful diagnostics."""
import os,pathlib,re,signal,subprocess,sys,time

folder=pathlib.Path('native-diagnostics');folder.mkdir(exist_ok=True)
command=['flutter','test','integration_test/native_player_test.dart','-d',os.environ['BECHI_SIMULATOR'],'--no-pub','--timeout','2m','--verbose']
with (folder/'flutter-test.log').open('w') as log:
    process=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    try:code=process.wait(timeout=900)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid,signal.SIGTERM)
        try:process.wait(timeout=20)
        except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL)
        code=124

def capture(name,args):
    try:
        value=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30,text=True).stdout
    except (subprocess.TimeoutExpired,OSError) as error:value=type(error).__name__
    (folder/name).write_text(value)

capture('devices.json',['xcrun','simctl','list','devices','available','--json'])
capture('runner-system.log',['xcrun','simctl','spawn',os.environ['BECHI_SIMULATOR'],'log','show','--last','3m','--style','compact','--predicate','process == "Runner"'])
capture('runner-dependencies.txt',['otool','-L','build/ios/iphonesimulator/Runner.app/Runner'])
for name in pathlib.Path.home().joinpath('Library/Logs/DiagnosticReports').glob('Runner*'):
    if name.is_file(): (folder/name.name).write_bytes(name.read_bytes()[:100000])
try:subprocess.run(['xcrun','simctl','io',os.environ['BECHI_SIMULATOR'],'screenshot',str(folder/'simulator.png')],timeout=20,check=False)
except (subprocess.TimeoutExpired,OSError):pass
lines=(folder/'flutter-test.log').read_text(errors='replace').splitlines()
print('\n'.join(lines[-140:]))
sys.exit(code)
