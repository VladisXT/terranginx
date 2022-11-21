#!/usr/bin/python3
import socket
import sys
ports = [i for i in range(1,65536)]
for port in ports:
    sock = socket.socket()
    sock.settimeout(1)
    try:
        sock.connect(('', port))
    except socket.error:
        pass
    else:
        sock.close
        print(str(port) + ' - port available')
