#!/usr/bin/env python3
"""Synthetic local RTSP source. Requires mediamtx and ffmpeg on PATH."""
import argparse
import pathlib
import signal
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mediamtx', default='mediamtx')
parser.add_argument('--audio', action='store_true', help='Inclui tom PCMA/16000 de teste')
parser.add_argument('--dual', action='store_true', help='Publica fluxo alternativo sintético 320x180 em /onvif2')
args = parser.parse_args()
processes = []

def stop(*_):
    raise KeyboardInterrupt

signal.signal(signal.SIGTERM, stop)
try:
    processes.append(subprocess.Popen([args.mediamtx, str(pathlib.Path(__file__).with_name('mediamtx.yml'))]))
    time.sleep(1)
    processes.append(subprocess.Popen([
        'ffmpeg', '-hide_banner', '-loglevel', 'error', '-re', '-f', 'lavfi',
        '-i', 'testsrc2=size=640x360:rate=15',
        *(['-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=16000', '-c:a', 'pcm_alaw', '-ar', '16000', '-ac', '1'] if args.audio else ['-an']),
        '-c:v', 'libx264',
        '-preset', 'ultrafast', '-tune', 'zerolatency', '-g', '15', '-pix_fmt', 'yuv420p',
        '-rtsp_transport', 'tcp', '-f', 'rtsp',
        'rtsp://publisher:publish-only@127.0.0.1:8554/onvif1']))
    if args.dual:
        processes.append(subprocess.Popen([
            'ffmpeg', '-hide_banner', '-loglevel', 'error', '-re', '-f', 'lavfi',
            '-i', 'testsrc2=size=320x180:rate=15',
            *(['-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=16000', '-c:a', 'pcm_alaw', '-ar', '16000', '-ac', '1'] if args.audio else ['-an']),
            '-c:v', 'libx264', '-preset', 'ultrafast', '-tune', 'zerolatency', '-g', '15', '-pix_fmt', 'yuv420p',
            '-rtsp_transport', 'tcp', '-f', 'rtsp', 'rtsp://publisher:publish-only@127.0.0.1:8554/onvif2']))
    print('Fonte de teste em rtsp://IP_DESTE_PC:8554/onvif1 (viewer / test-only)', flush=True)
    while all(p.poll() is None for p in processes):
        time.sleep(.5)
    raise SystemExit('Um processo da fonte de teste foi encerrado.')
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
