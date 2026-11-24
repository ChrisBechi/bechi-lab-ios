"""Reproducible synthetic codec samples; never downloads programme content."""
import os
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
folder = root / 'assets/fixtures'
ffmpeg = os.environ.get('FFMPEG', 'ffmpeg')
cases = {
    'native-vp9-opus.webm': ['-c:v', 'libvpx-vp9', '-deadline', 'realtime', '-cpu-used', '8', '-b:v', '350k', '-c:a', 'libopus', '-b:a', '64k'],
    'native-h264-pcm.mov': ['-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '30', '-c:a', 'pcm_s16le', '-movflags', '+faststart'],
    'native-h264-aac.ts': ['-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '30', '-g', '24', '-c:a', 'aac', '-b:a', '64k', '-f', 'mpegts'],
    'native-flv1-mp3.flv': ['-c:v', 'flv', '-q:v', '8', '-c:a', 'libmp3lame', '-b:a', '64k'],
    'native-wmv2-wma.wmv': ['-c:v', 'wmv2', '-q:v', '8', '-c:a', 'wmav2', '-b:a', '64k'],
    'native-mpeg2-mp2.mpg': ['-c:v', 'mpeg2video', '-q:v', '8', '-c:a', 'mp2', '-b:a', '128k', '-f', 'mpeg'],
    'native-h264-dts.mkv': ['-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '30', '-c:a', 'dca', '-strict', '-2', '-b:a', '768k'],
}
for filename, options in cases.items():
    subprocess.run([
        ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=24:duration=8',
        '-f', 'lavfi', '-i', 'sine=frequency=660:sample_rate=48000:duration=8',
        '-map', '0:v', '-map', '1:a', *options,
        '-metadata:s:a:0', 'language=por', '-shortest', str(folder / filename),
    ], check=True)
    print(filename)
