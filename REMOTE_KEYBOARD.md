# Remote Keyboard

This app turns a tablet into a full-screen keyboard that sends key events to a
device on the same network.

## Controlled Device

Run the receiver on the device you want to type into:

```powershell
python tools\remote_keyboard_receiver.py --host 0.0.0.0 --port 5050
```

On Windows, the receiver types into whichever app currently has keyboard focus.
Allow the port through Windows Firewall if prompted.

## Tablet App

1. Build or run the Flutter app on the tablet.
2. Enter the controlled device's IP address.
3. Use port `5050`, unless you changed it in the receiver command.
4. Tap `Connect`.
5. Focus a text field on the controlled device, then type from the tablet.

The app sends newline-delimited JSON over TCP:

```json
{"type":"text","value":"hello"}
{"type":"key","key":"backspace"}
```

Supported special keys are `backspace`, `enter`, `tab`, and `escape`.
