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
from ctypes import wintypes


KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004
INPUT_KEYBOARD = 1

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
        ("dwExtraInfo", ctypes.POINTER(wintypes.ULONG)),
    ]


class INPUT_UNION(ctypes.Union):
    _fields_ = [("ki", KEYBDINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wintypes.DWORD), ("union", INPUT_UNION)]


def _send_input(*inputs: INPUT) -> None:
    sent = ctypes.windll.user32.SendInput(
        len(inputs), (INPUT * len(inputs))(*inputs), ctypes.sizeof(INPUT)
    )
    if sent != len(inputs):
        raise ctypes.WinError()


def _keyboard_input(vk: int = 0, scan: int = 0, flags: int = 0) -> INPUT:
    return INPUT(
        type=INPUT_KEYBOARD,
        union=INPUT_UNION(ki=KEYBDINPUT(vk, scan, flags, 0, None)),
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


def handle_event(event: dict[str, object]) -> None:
    event_type = event.get("type")
    if event_type == "text":
        type_text(str(event.get("value", "")))
    elif event_type == "key":
        press_key(str(event.get("key", "")))


def serve(host: str, port: int) -> None:
    if platform.system() != "Windows":
        print("This receiver currently injects keys on Windows only.")
        print("Incoming events will be printed instead of typed.")

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((host, port))
        server.listen(1)
        print(f"Remote keyboard receiver listening on {host}:{port}")

        while True:
            connection, address = server.accept()
            print(f"Connected by {address[0]}:{address[1]}")
            with connection, connection.makefile("r", encoding="utf-8") as lines:
                for line in lines:
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        print(f"Invalid event: {line.strip()}")
                        continue

                    print(event)
                    if platform.system() == "Windows":
                        handle_event(event)

            print("Disconnected")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5050)
    args = parser.parse_args()
    serve(args.host, args.port)


if __name__ == "__main__":
    main()
