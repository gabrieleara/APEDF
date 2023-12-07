#!/usr/bin/env python3
import sys

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

try:
    import serial
except (ImportError):
    msg = """ERROR: pyserial library not found
Install pyserial library:
    pip3 install pyserial"""
    eprint(msg)
    sys.exit(1)

# Other Imports
from typing import Literal
from dataclasses import dataclass, field
from argparse_dataclass import ArgumentParser
from signal import signal, SIGINT
from queue import Queue,Empty

# Port Configuration Parameters: pass these as command-line arguments
@dataclass
class SerialData:
    port:       str                                 = 'COM5'
    baudrate:   int                                 = 15200
    bytesize:   Literal[5, 6, 7, 8]                 = 8
    parity:     Literal['N', 'E', 'O', 'M', 'S']    = 'N'
    stopbits:   Literal[1, 2]                       = 1
    rtscts:     Literal[0, 1]                       = 0

def read_args():
    parser = ArgumentParser(SerialData)
    return parser.parse_args(sys.argv[1:])

quit_signal = Queue(2)

def handler(signal_received, frame):
    quit_signal.put(True)

def main(quit_signal):
    signal(SIGINT, handler)

    serial_data = read_args()

    serial_port = None
    try:
        serial_port = serial.Serial(
            port=serial_data.port,
            baudrate=serial_data.baudrate,
            parity=serial_data.parity,
            stopbits=serial_data.stopbits,
            bytesize=serial_data.bytesize,
            rtscts=serial_data.rtscts,
        )
    except Exception as error:
        eprint(f"ERROR: {error}")
        return 4

    # Main loop
    quit = False
    while not quit:
        try:
            # Checking for quit command
            try:
                quit = quit_signal.get(block=False, timeout=0.1)
            except Empty:
                pass

            if quit:
                continue

            data = serial_port.readline().decode('ascii')
            if len(data) > 0:
                sys.stdout.write(data)

        except KeyboardInterrupt:
            quit_signal.put(True)
    #-- while

    return 0
#-- main()



if __name__ == "__main__":
    main(quit_signal)
