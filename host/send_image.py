#!/usr/bin/env python3
# send_image.py - send an image to the Nexys 4 DDR running jpeg_board_top
# and save the JPEG the FPGA encodes and returns.
#
# Protocol (8N1 over the FT2232 USB-UART):
#   host -> FPGA: "IMG" + W(2B BE) + H(2B BE) + W*H*3 RGB bytes (raster order)
#   FPGA -> host: LEN(4B BE) + LEN jpg bytes
#
# Usage:
#   python3 send_image.py photo.jpg
#   python3 send_image.py photo.jpg --port /dev/ttyUSB1 --baud 921600 --out out.jpg
#
# The FPGA design is compiled for a fixed IMG_W x IMG_H (default 240x240);
# the image is resized to that size before sending. On Linux the Nexys 4
# DDR's FT2232 shows up as two ports: ttyUSB0 is JTAG, ttyUSB1 is the UART
# (check with: dmesg | grep ttyUSB after plugging in).
#
# Deps: pip install pyserial Pillow
import argparse
import struct
import sys
import time


def main():
    p = argparse.ArgumentParser(description="Send an image to the FPGA JPEG encoder and save the returned .jpg")
    p.add_argument("image", help="input image file (jpg/png/...)")
    p.add_argument("--port", default="/dev/ttyUSB1", help="serial port (default /dev/ttyUSB1)")
    p.add_argument("--baud", type=int, default=921600, help="baud rate (default 921600; must match CLKS_PER_BIT: 921600<->54, 115200<->434 at 50 MHz)")
    p.add_argument("--width", type=int, default=240, help="compiled IMG_W (default 240)")
    p.add_argument("--height", type=int, default=240, help="compiled IMG_H (default 240)")
    p.add_argument("--out", default="fpga_out.jpg", help="output file (default fpga_out.jpg)")
    args = p.parse_args()

    try:
        import serial
    except ImportError:
        sys.exit("pyserial not installed - run: pip install pyserial")
    try:
        from PIL import Image
    except ImportError:
        sys.exit("Pillow not installed - run: pip install Pillow")

    W, H = args.width, args.height

    img = Image.open(args.image).convert("RGB")
    if img.size != (W, H):
        img = img.resize((W, H), Image.LANCZOS)
    payload = img.tobytes()  # RGBRGB... raster order
    assert len(payload) == W * H * 3

    ser = serial.Serial(args.port, args.baud, bytesize=8, parity="N",
                        stopbits=1, timeout=30)
    ser.reset_input_buffer()

    t0 = time.time()
    ser.write(b"IMG" + struct.pack(">HH", W, H) + payload)
    ser.flush()
    t_tx = time.time() - t0
    print(f"sent {7 + len(payload)} bytes ({W}x{H} RGB) in {t_tx:.1f}s - FPGA is encoding...")

    hdr = ser.read(4)
    if len(hdr) != 4:
        sys.exit(f"timed out waiting for the FPGA (got {len(hdr)} of 4 length bytes). "
                 "Is the board programmed and the design running? LED1 should be on while encoding.")
    jpg_len = struct.unpack(">I", hdr)[0]
    print(f"FPGA reports {jpg_len} jpg bytes, receiving...")

    t0 = time.time()
    data = bytearray()
    while len(data) < jpg_len:
        chunk = ser.read(jpg_len - len(data))
        if not chunk:
            sys.exit(f"timed out after {len(data)} of {jpg_len} bytes")
        data += chunk
    t_rx = time.time() - t0

    with open(args.out, "wb") as f:
        f.write(data)
    print(f"saved {args.out}: {jpg_len} bytes received in {t_rx:.1f}s")

    # sanity check
    try:
        dec = Image.open(args.out)
        dec.load()
        print(f"decodes OK: {dec.size[0]}x{dec.size[1]} {dec.mode}")
    except Exception as e:
        print(f"WARNING: received data does not decode as a JPEG: {e}")
    ser.close()


if __name__ == "__main__":
    main()
