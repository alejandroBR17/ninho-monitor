#!/usr/bin/env python3
"""Publish a fictional room as a loopback-only RTSP demo. No camera is accessed."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mediamtx', default='mediamtx', help='Path to the MediaMTX executable')
parser.add_argument('--ffmpeg', default='ffmpeg', help='Path to the FFmpeg executable')
args = parser.parse_args()
room = Path(__file__).resolve().parents[1] / 'docs' / 'media' / 'demo-room.webp'
processes = []

def stop(*_):
    raise KeyboardInterrupt

signal.signal(signal.SIGTERM, stop)
font = (Path(os.environ.get('WINDIR', 'C:/Windows')) / 'Fonts' / 'segoeui.ttf') if os.name == 'nt' else Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')
# A small pan makes this a moving source, not a placeholder over the player.
filters = "scale=960:540,zoompan=z=1.06:x='(iw-iw/zoom)/2+20*sin(on/20)':y='(ih-ih/zoom)/2+8*cos(on/30)':d=1:s=640x360:fps=15"
if font.exists():
    font_name = font.as_posix().replace(':', '\\:')
    filters += f",drawtext=fontfile='{font_name}':text='DEMO - CENA FICTICIA':fontcolor=white:fontsize=12:box=1:boxcolor=black@0.45:boxborderw=6:x=12:y=12"
config = '''logLevel: warn
rtsp: yes
rtspAddress: 127.0.0.1:8554
rtspTransports: [tcp]
rtmp: no
hls: no
webrtc: no
srt: no
moq: no
authMethod: internal
authInternalUsers:
  - user: publisher
    pass: publish-only
    ips: [127.0.0.1]
    permissions:
      - action: publish
        path: onvif1
  - user: viewer
    pass: test-only
    ips: [127.0.0.1]
    permissions:
      - action: read
        path: onvif1
paths:
  onvif1:
    source: publisher
'''
try:
    with tempfile.TemporaryDirectory(prefix='ninho-scene-') as directory:
        configuration = Path(directory) / 'mediamtx.yml'
        configuration.write_text(config, encoding='utf-8')
        processes.append(subprocess.Popen([args.mediamtx, str(configuration)]))
        time.sleep(1)
        if processes[0].poll() is not None:
            raise RuntimeError('MediaMTX did not start; check whether port 8554 is in use.')
        processes.append(subprocess.Popen([
            args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-re', '-loop', '1',
            '-framerate', '15', '-i', str(room), '-an', '-vf', filters,
            '-c:v', 'libx264', '-preset', 'ultrafast', '-tune', 'zerolatency',
            '-g', '15', '-pix_fmt', 'yuv420p', '-threads', '2', '-rtsp_transport', 'tcp',
            '-f', 'rtsp', 'rtsp://publisher:publish-only@127.0.0.1:8554/onvif1']))
        print('Fictional scene demo: rtsp://127.0.0.1:8554/onvif1 (viewer / test-only)', flush=True)
        while all(p.poll() is None for p in processes):
            time.sleep(.5)
        raise RuntimeError('The synthetic scene source stopped.')
except KeyboardInterrupt:
    pass
finally:
    for process in reversed(processes):
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
