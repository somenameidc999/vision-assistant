#!/usr/bin/env python3
"""Expose the localhost demo backend on one explicit private LAN address.

Forward bytes in memory. Authentication and request limits remain on the backend.
No request bodies, headers, captures, or conversation content are logged.
"""
import argparse
import asyncio
import ipaddress
from install_iphone import validate_backend


async def forward(client_reader, client_writer, backend_port):
    backend_writer = None
    tasks = []
    try:
        backend_reader, backend_writer = await asyncio.open_connection('127.0.0.1', backend_port)

        async def copy(reader, writer):
            while data := await reader.read(65536):
                writer.write(data)
                await writer.drain()

        tasks = [asyncio.create_task(copy(client_reader, backend_writer)),
                 asyncio.create_task(copy(backend_reader, client_writer))]
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    except (OSError, ConnectionError):
        pass
    finally:
        for task in tasks:
            task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        for writer in [client_writer, backend_writer]:
            if writer:
                writer.close()
                try:
                    await writer.wait_closed()
                except (OSError, ConnectionError):
                    pass


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--listen-address', required=True, help='This Mac’s private IPv4 address on the phone’s Wi-Fi network.')
    parser.add_argument('--port', type=int, default=18787)
    parser.add_argument('--backend-port', type=int, default=18787)
    args = parser.parse_args()
    ipaddress.IPv4Address(args.listen_address)
    validate_backend(f'http://{args.listen_address}:{args.port}')
    server = await asyncio.start_server(
        lambda reader, writer: forward(reader, writer, args.backend_port), args.listen_address, args.port)
    print(f'iPhone LAN proxy listening at http://{args.listen_address}:{args.port}; backend remains on localhost.', flush=True)
    async with server:
        await server.serve_forever()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
