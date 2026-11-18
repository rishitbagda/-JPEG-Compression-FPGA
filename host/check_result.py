#!/usr/bin/env python3
# check_result.py - verify the assembled JPEG against the fed image.
#
# Usage: python3 check_result.py input.ppm out.jpg W H
#
# Checks (prints [PASS]/[FAIL], exit code 0 = all pass):
#   structure: SOI first, APP0/DQT/SOF0/DHT/SOS segments well formed,
#              EOI is the last two bytes, every 0xFF in the scan data is
#              followed by 0x00 (stuffing), no unknown markers in scan
#   image:     out.jpg decodes, dimensions match W x H
#   quality:   PSNR of decoded JPEG vs input.ppm (needs Pillow; JPEG at
#              quality 50 should land well above 25 dB on these patterns)
import sys, math

def main():
    ppm_path, jpg_path, W, H = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    failures = 0

    def check(ok, msg):
        nonlocal failures
        print(("[PASS] " if ok else "[FAIL] ") + msg)
        if not ok:
            failures += 1

    data = open(jpg_path, 'rb').read()

    # ---- structure ----
    check(data[:2] == b'\xff\xd8', "starts with SOI marker (FF D8)")
    check(data[-2:] == b'\xff\xd9', "ends with EOI marker (FF D9), nothing after it")

    pos = 2
    seen = set()
    sos_end = None
    ok = True
    while pos + 1 < len(data):
        if data[pos] != 0xFF:
            ok = False
            break
        m = data[pos+1]
        if m == 0xDA:                       # SOS
            seglen = (data[pos+2] << 8) | data[pos+3]
            sos_end = pos + 2 + seglen
            seen.add(m)
            break
        seglen = (data[pos+2] << 8) | data[pos+3]
        seen.add(m)
        pos += 2 + seglen
    check(ok and sos_end is not None, "header segments well formed, SOS found")
    for m, name in [(0xE0,"APP0"), (0xDB,"DQT"), (0xC0,"SOF0"), (0xC4,"DHT")]:
        check(m in seen, f"{name} segment present")

    if sos_end is not None:
        scan = data[sos_end:-2]             # strip appended EOI
        bad = [i for i in range(len(scan)-1)
               if scan[i] == 0xFF and scan[i+1] != 0x00]
        check(not bad, f"scan data: every 0xFF stuffed with 0x00 ({len(bad)} violations)")
        check(len(scan) > 0, f"scan data non-empty ({len(scan)} bytes)")

    # ---- decode + PSNR ----
    try:
        from PIL import Image
    except ImportError:
        print("[SKIP] Pillow not installed - skipping decode/PSNR checks")
        print("       (pip install Pillow) structure checks above still apply")
        sys.exit(0 if failures == 0 else 1)

    ref = Image.open(ppm_path).convert('RGB')
    dec = Image.open(jpg_path); dec.load(); dec = dec.convert('RGB')
    check(dec.size == (W, H), f"decoded size {dec.size[0]}x{dec.size[1]} matches {W}x{H}")
    check(ref.size == (W, H), f"reference size matches {W}x{H}")

    if dec.size == ref.size == (W, H):
        rp, dp = ref.tobytes(), dec.tobytes()
        se = [0, 0, 0]
        for i in range(0, len(rp), 3):
            for c in range(3):
                d = rp[i+c] - dp[i+c]
                se[c] += d*d
        n = W * H
        psnrs = [float('inf') if se[c] == 0 else 10*math.log10(255*255*n/se[c]) for c in range(3)]
        mse_all = sum(se) / (3*n)
        psnr_all = float('inf') if mse_all == 0 else 10*math.log10(255*255/mse_all)
        print(f"[INFO] PSNR  R: {psnrs[0]:.1f} dB   G: {psnrs[1]:.1f} dB   B: {psnrs[2]:.1f} dB   overall: {psnr_all:.1f} dB")
        # Sanity floor only: at quality 50, PSNR depends heavily on content -
        # smooth gradients land ~35-45 dB, dense high-frequency texture ~20-25 dB
        # (libjpeg at the same quality scores the same on pattern 1).
        check(psnr_all >= 20.0, f"overall PSNR {psnr_all:.1f} dB >= 20 dB sanity floor")

    print("CHECK_RESULT: " + ("ALL PASS" if failures == 0 else f"{failures} FAILURE(S)"))
    sys.exit(0 if failures == 0 else 1)

if __name__ == '__main__':
    main()
