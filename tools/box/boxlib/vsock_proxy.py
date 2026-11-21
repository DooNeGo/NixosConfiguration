"""ProxyCommand of ssh: connects stdin and stdout to a port of a guest over AF_VSOCK (no network in the guest)."""

import os
import select
import socket
import sys


def main(argv: list[str]) -> int:
    cid, port = int(argv[1]), int(argv[2])
    guest = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    try:
        guest.connect((cid, port))
    except OSError:
        return 255  # the guest is not listening yet: ssh reports the closed connection, the caller retries
    reading_stdin = True
    while True:
        wanted = [guest] + ([0] if reading_stdin else [])
        ready, _, _ = select.select(wanted, [], [])
        if 0 in ready:
            data = os.read(0, 65536)
            if data:
                guest.sendall(data)
            else:
                reading_stdin = False
                guest.shutdown(socket.SHUT_WR)
        if guest in ready:
            data = guest.recv(65536)
            if not data:
                return 0
            while data:
                data = data[os.write(1, data) :]


if __name__ == "__main__":
    sys.exit(main(sys.argv))
