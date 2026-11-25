"""Exercise our isolated diagnostic APK; an emulator cannot verify audible sound."""
import json, os, pathlib, re, subprocess, time

folder = pathlib.Path('android-diagnostics')
folder.mkdir(exist_ok=True)
sdk = pathlib.Path(os.environ['ANDROID_HOME'])
adb = [str(sdk / 'platform-tools/adb'), '-s', 'emulator-5554']
package = 'app.bechiflix.codecchecks'
activity = 'app.bechiflix.bechi_player_prototype.MainActivity'
report = {'platform': 'Android emulator API 35', 'physical_device': False,
          'system_audio_verified': False, 'passed': False, 'results': []}

def call(*args, timeout=30):
    value = subprocess.run([*adb, *args], stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, timeout=timeout, text=True)
    if value.returncode:
        raise RuntimeError('ADB diagnostic failed at ' + args[0])
    return value.stdout

reader = None
installed = False
with (folder / 'emulator.log').open('w') as emulator_log:
    emulator = subprocess.Popen([
        str(sdk / 'emulator/emulator'), '-avd', 'bechi-native', '-port', '5554',
        '-no-window', '-no-snapshot', '-no-boot-anim', '-gpu', 'swiftshader_indirect',
        '-memory', '2048'], stdout=emulator_log, stderr=subprocess.STDOUT)
    try:
        boot_deadline = time.monotonic() + 240
        while True:
            if emulator.poll() is not None:
                raise RuntimeError('The isolated emulator exited during boot.')
            try:
                if call('shell', 'getprop', 'sys.boot_completed', timeout=10).strip() == '1':
                    break
            except (RuntimeError, subprocess.TimeoutExpired):
                pass
            if time.monotonic() > boot_deadline:
                raise RuntimeError('Android boot deadline reached.')
            time.sleep(2)
        call('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
        call('shell', 'input', 'keyevent', 'KEYCODE_MENU')
        call('install', '-r', 'dist/Bechi-Codec-Checks-0.2.0.apk', timeout=120)
        installed = True
        call('shell', 'am', 'start', '-W', '-n', package + '/' + activity, timeout=45)
        pid = call('shell', 'pidof', package).strip()
        if not re.fullmatch('[0-9]+', pid):
            raise RuntimeError('The native diagnostic did not start.')
        log = folder / 'codec-logcat.txt'
        with log.open('w') as output:
            reader = subprocess.Popen([*adb, 'logcat', '--pid=' + pid, '-v', 'brief', '-T', '2000'],
                                      stdout=output, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 480
            results = {}
            while time.monotonic() < deadline:
                for line in log.read_text(errors='replace').splitlines():
                    match = re.search(r'NATIVE_CODEC_RESULT (\{.*\})', line)
                    if not match:
                        continue
                    try:
                        row = json.loads(match.group(1))
                    except ValueError:
                        continue
                    if row.get('source') not in results:
                        # The decoder uses Android's real AO interface, but the
                        # host is virtual. Never label this as audible hardware.
                        row['system_audio_verified'] = False
                        results[row['source']] = row
                        print(json.dumps(row), flush=True)
                if len(results) == 11:
                    break
                time.sleep(2)
            report['results'] = list(results.values())
            report['passed'] = len(results) == 11 and all(row.get('passed') is True for row in results.values())
        image = subprocess.run([*adb, 'exec-out', 'screencap', '-p'], stdout=subprocess.PIPE, timeout=15)
        if image.returncode == 0:
            (folder / 'screen.png').write_bytes(image.stdout)
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        if reader is not None:
            reader.terminate()
            reader.wait(timeout=10)
        if installed:
            try:
                call('shell', 'am', 'force-stop', package)
                call('uninstall', package)
            except (RuntimeError, subprocess.TimeoutExpired):
                pass
        emulator.terminate()
        try:
            emulator.wait(timeout=20)
        except subprocess.TimeoutExpired:
            emulator.kill()
        (folder / 'results.json').write_text(json.dumps(report, indent=2))
if not report['passed']:
    raise SystemExit('A complete passing result is required for all eleven codecs.')
