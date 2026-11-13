#!/usr/bin/env python3
"""Test-only RTSP relay that reproduces the Jortan missing-/TCP reply."""
import asyncio
import re
async def camera(reader, writer):
    upstream_reader, upstream_writer = await asyncio.open_connection('127.0.0.1',8554)
    async def outbound():
        while data:=await reader.read(65536):
            upstream_writer.write(data)
            await upstream_writer.drain()
    async def inbound():
        buffer=bytearray()
        while data:=await upstream_reader.read(65536):
            buffer.extend(data)
            while buffer:
                if buffer[0]==36:
                    if len(buffer)<4:break
                    length=4+int.from_bytes(buffer[2:4],'big')
                    if len(buffer)<length:break
                    writer.write(buffer[:length]);del buffer[:length]
                else:
                    end=buffer.find(b'\r\n\r\n')
                    if end<0:break
                    header=bytes(buffer[:end])
                    match=re.search(br'Content-Length:\s*(\d+)',header,re.I)
                    length=end+4+(int(match[1]) if match else 0)
                    if len(buffer)<length:break
                    header=re.sub(br'(Transport:\s*)RTP/AVP/TCP',br'\1RTP/AVP',header,flags=re.I)
                    writer.write(header+b'\r\n\r\n'+buffer[end+4:length]);del buffer[:length]
                await writer.drain()
    tasks=[asyncio.create_task(outbound()),asyncio.create_task(inbound())]
    try:
        await asyncio.wait(tasks,return_when=asyncio.FIRST_COMPLETED)
    finally:
        for task in tasks:task.cancel()
        upstream_writer.close();writer.close()
async def main():
    server=await asyncio.start_server(camera,'127.0.0.1',8854)
    async with server:await server.serve_forever()
asyncio.run(main())
