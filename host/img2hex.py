#!/usr/bin/env python3
# img2hex.py - convert any image (jpg/png/...) into the hex file the
# testbench's custom-image mode (PATTERN = 2) loads with $readmemh.
#
# Usage:
#   python3 img2hex.py photo.jpg            -> auto size: image resized UP to
#                                              the next multiple of 8 in each
#                                              dimension; prints the W/H to set
#   python3 img2hex.py photo.jpg 64 48      -> resize to exactly 64x48
#   python3 img2hex.py photo.jpg 64 48 my.hex
#
# Behaviour (simplest predictable rule): the image is RESIZED to exactly
# W x H. If the aspect ratios differ it will be stretched - crop your image
# to the right shape first if you don't want that.
#
# Outputs (always in the current directory):
#   <out.hex>  one 24-bit RGB pixel per line as 6 hex digits (RRGGBB),
#              raster order (row 0 left-to-right, then row 1, ...) - exactly
#              the order the testbench feeds the DUT. W*H lines total.
#   input.ppm  the same resized image as binary P6 PPM, the reference for
#              check_result.py's PSNR comparison. (The testbench also writes
#              its own input.ppm in the sim directory with identical content;
#              this copy is for reference/eyeballing.)
#
# Needs Pillow:  pip install Pillow
import sys, os

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__.strip().splitlines()[0] +
                 "\nusage: python3 img2hex.py IMAGE [W H] [out.hex]")
    src = sys.argv[1]
    try:
        from PIL import Image
    except ImportError:
        sys.exit("Pillow not installed - run: pip install Pillow")

    img = Image.open(src).convert('RGB')
    w0, h0 = img.size

    if len(sys.argv) >= 4:
        W, H = int(sys.argv[2]), int(sys.argv[3])
    else:
        W = (w0 + 7) // 8 * 8
        H = (h0 + 7) // 8 * 8
    out_hex = sys.argv[4] if len(sys.argv) >= 5 else "image.hex"

    if W <= 0 or H <= 0 or W % 8 or H % 8:
        sys.exit(f"W and H must be positive multiples of 8 (got {W}x{H})")

    if (W, H) != (w0, h0):
        img = img.resize((W, H), Image.LANCZOS)

    px = img.tobytes()  # RGBRGB... raster order
    with open(out_hex, 'w') as f:
        for i in range(0, len(px), 3):
            f.write(f"{px[i]:02x}{px[i+1]:02x}{px[i+2]:02x}\n")

    img.save("input.ppm")

    print(f"wrote {out_hex}: {W}x{H} = {W*H} pixels "
          f"(source {os.path.basename(src)} was {w0}x{h0})")
    print(f"wrote input.ppm (reference for check_result.py)")
    print(f"-> set in tb_jpeg_encoder_top.sv:  W = {W}, H = {H}, "
          f"PATTERN = 2, IMAGE_FILE = \"{out_hex}\"")

if __name__ == '__main__':
    main()
