#!/usr/bin/env python3
"""Run the complete encoder testbench with Icarus Verilog (iverilog + vvp)."""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('image', type=Path, help='input image')
p.add_argument('--width', type=int, default=240)
p.add_argument('--height', type=int, default=240)
p.add_argument('--output-dir', type=Path, default=root / 'build' / 'sim')
a = p.parse_args()
if a.width <= 0 or a.height <= 0 or a.width % 8 or a.height % 8:
    p.error('width and height must be positive multiples of 8')
image = a.image.resolve()
work = a.output_dir.resolve()
work.mkdir(parents=True, exist_ok=True)
for command in ('iverilog', 'vvp'):
    if not shutil.which(command):
        p.error(f'{command} must be installed and available on PATH')
subprocess.run([sys.executable, str(root/'host/img2hex.py'), str(image),
                str(a.width), str(a.height), 'image.hex'], cwd=work, check=True)
# Icarus 11 can enter a zero-time scheduling loop with this design's
# always_comb sensitivity handling. Use a separate simulation-only copy.
compat = work / 'icarus_compat'
compat.mkdir(exist_ok=True)
sources = []
for source in sorted((root/'rtl').glob('*.sv')):
    target = compat/source.name
    target.write_text(source.read_text().replace('always_comb', 'always @*'))
    sources.append(str(target))
print('Icarus compatibility copies use always @*; rtl/ files are unchanged.', flush=True)
subprocess.run(['iverilog','-g2012','-s','tb_jpeg_jfif_top',
                f'-Ptb_jpeg_jfif_top.W={a.width}',f'-Ptb_jpeg_jfif_top.H={a.height}','-o',str(work/'sim.vvp'),
                *sources,str(root/'sim/tb_jpeg_jfif_top_240x240_custom.sv')],
               cwd=work,check=True)
result = subprocess.run(['vvp',str(work/'sim.vvp')],cwd=work,check=True,
                        text=True,stdout=subprocess.PIPE,timeout=180)
print(result.stdout)
(work/'simulation.log').write_text(result.stdout)
if 'TB_CHECKS ALL PASS' not in result.stdout:
    raise SystemExit('Testbench did not report ALL PASS')
subprocess.run([sys.executable,str(root/'host/check_result.py'),
                'input.ppm','fpga.jpg',str(a.width),str(a.height)],cwd=work,check=True)
