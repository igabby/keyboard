"""Receive remote keyboard events and type them into the focused Windows app.

Run on the device you want to control:

    python tools/remote_keyboard_receiver.py --host 0.0.0.0 --port 5050

Then enter that device's IP address and port in the Flutter tablet app.
The protocol is newline-delimited JSON:
    {"type": "text", "value": "hello"}
    {"type": "key", "key": "backspace"}
"""

from __future__ import annotations

import argparse
import ctypes
import json
import platform
import socket
import sys
from ctypes import wintypes


KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004
INPUT_KEYBOARD = 1
IS_WINDOWS = platform.system() == "Windows"
ULONG_PTR = wintypes.WPARAM
USER32 = ctypes.WinDLL("user32", use_last_error=True) if IS_WINDOWS else None

VK_CODES = {
    "backspace": 0x08,
    "tab": 0x09,
    "enter": 0x0D,
    "escape": 0x1B,
}


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD),
        ("wScan", wintypes.WORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ULONG_PTR),
    ]


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", wintypes.LONG),
        ("dy", wintypes.LONG),
        ("mouseData", wintypes.DWORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ULONG_PTR),
    ]


class HARDWAREINPUT(ctypes.Structure):
    _fields_ = [
        ("uMsg", wintypes.DWORD),
        ("wParamL", wintypes.WORD),
        ("wParamH", wintypes.WORD),
    ]


class INPUT_UNION(ctypes.Union):
    _fields_ = [
        ("mi", MOUSEINPUT),
        ("ki", KEYBDINPUT),
        ("hi", HARDWAREINPUT),
    ]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("union", INPUT_UNION)]


if USER32 is not None:
    USER32.SendInput.argtypes = (
        wintypes.UINT,
        ctypes.POINTER(INPUT),
        ctypes.c_int,
    )
    USER32.SendInput.restype = wintypes.UINT


def _send_input(*inputs: INPUT) -> None:
    if USER32 is None:
        return

    input_array = (INPUT * len(inputs))(*inputs)
    sent = USER32.SendInput(len(inputs), input_array, ctypes.sizeof(INPUT))
    if sent != len(inputs):
        raise ctypes.WinError(ctypes.get_last_error())


def _keyboard_input(vk: int = 0, scan: int = 0, flags: int = 0) -> INPUT:
    return INPUT(
        type=INPUT_KEYBOARD,
        union=INPUT_UNION(ki=KEYBDINPUT(vk, scan, flags, 0, 0)),
    )


def type_text(value: str) -> None:
    for char in value:
        codepoint = ord(char)
        _send_input(
            _keyboard_input(scan=codepoint, flags=KEYEVENTF_UNICODE),
            _keyboard_input(
                scan=codepoint, flags=KEYEVENTF_UNICODE | KEYEVENTF_KEYUP
            ),
        )


def press_key(key: str) -> None:
    vk = VK_CODES.get(key)
    if vk is None:
        print(f"Unsupported key: {key}")
        return
    _send_input(_keyboard_input(vk=vk), _keyboard_input(vk=vk, flags=KEYEVENTF_KEYUP))


def handle_event(event: dict[str, object], print_only: bool = False) -> None:
    event_type = event.get("type")
    if event_type == "hello":
        print("Handshake received")
        return

    if print_only or not IS_WINDOWS:
        print(f"Would type: {event}")
        return

    if event_type == "text":
        type_text(str(event.get("value", "")))
    elif event_type == "key":
        press_key(str(event.get("key", "")))
    else:
        print(f"Unsupported event type: {event_type}")


def _local_ip_hint() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("8.8.8.8", 80))
            return probe.getsockname()[0]
    except OSError:
        return "unknown"


def serve(host: str, port: int, print_only: bool = False) -> None:
    if not IS_WINDOWS:
        print("This receiver currently injects keys on Windows only.")
        print("Incoming events will be printed instead of typed.")

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((host, port))
        server.listen(1)
        print(f"Remote keyboard receiver listening on {host}:{port}")
        if host in {"0.0.0.0", ""}:
            print(f"Try connecting the tablet to {_local_ip_hint()}:{port}")
        sys.stdout.flush()

        while True:
            connection, address = server.accept()
            print(f"Connected by {address[0]}:{address[1]}")
            sys.stdout.flush()
            with connection, connection.makefile("r", encoding="utf-8") as lines:
                for line in lines:
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        print(f"Invalid event: {line.strip()}")
                        continue

                    print(event)
                    sys.stdout.flush()
                    try:
                        handle_event(event, print_only=print_only)
                    except OSError as error:
                        print(f"Failed to inject input: {error}")
                        print(
                            "Tip: do not run the target app as administrator "
                            "unless this receiver is also running as administrator."
                        )
                    sys.stdout.flush()

            print("Disconnected")
            sys.stdout.flush()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5050)
    parser.add_argument(
        "--print-only",
        action="store_true",
        help="Print incoming events without typing them.",
    )
    args = parser.parse_args()
    serve(args.host, args.port, print_only=args.print_only)


if __name__ == "__main__":
    main()
