# Validation

## Hardware validation

The project team reports successful deployment and testing on the Nexys 4 DDR, including source images with different dimensions through the host uploader. This hardware validation is separate from the fresh RTL simulation checks below.

## Checked examples

The bundled color and grayscale images are 240 x 240. Both were fed through the complete `jpeg_encoder_jfif_top` testbench during repository preparation.

For each example, the supplied testbench reported `TB_CHECKS ALL PASS`, including completion, scan-byte accounting, JFIF byte count and FIFO error checks. The Python checker accepted the JPEG markers, byte stuffing, dimensions and decoded output.

| Example | JPEG bytes | Overall RGB PSNR |
|---|---:|---:|
| Color | 24,448 | 26.90 dB |
| Grayscale | 19,716 | 31.48 dB |

The freshly simulated color JPEG matches the original bundled `fpga_out.jpg` byte for byte. `examples/output/grayscale.jpg` is the freshly simulated grayscale result.

## Reproduce with Icarus Verilog

Install Icarus Verilog (`iverilog` and `vvp`) and the Python dependencies, then run from the repository root:

```bash
python3 scripts/run_sim.py examples/input/color.png --output-dir build/sim-color
python3 scripts/run_sim.py examples/input/grayscale.png --output-dir build/sim-grayscale
```

The helper makes simulation-only copies replacing `always_comb` with `always @*` to accommodate Icarus 11 sensitivity scheduling. The original files in `rtl/` remain unchanged. Outputs, compatibility copies and logs stay under the chosen build directory.

For Vivado simulation, use the original RTL directly and select `tb_jpeg_jfif_top` from `sim/tb_jpeg_jfif_top_240x240_custom.sv`. Generate `image.hex` with `host/img2hex.py` and put it in the simulator working directory before running.

## Independent non-240 photograph frame

A public-domain NASA photograph from scikit-image was cropped from 512 x 512 to 512 x 448, then prepared as a 320 x 280 frame. The full encoder was compiled with `W=320`, `H=280` and produced a 31,253-byte JPEG decoding at 320 x 280. Overall RGB PSNR is 31.5 dB. All supplied testbench checks and JPEG checker tests passed. The test summary is included in `astronaut-simulation.txt`.

```bash
python3 scripts/run_sim.py examples/input/astronaut-source-512x448.png --width 320 --height 280 --output-dir build/sim-photo
```

An earlier independent 320 x 192 test also passed. During that test, the actual `host/send_image.py` function was exercised with a serial test double. Its upload exactly matched `IMG` plus 320/192 big-endian dimensions plus the expected 184,320 resized RGB bytes. It received and preserved the simulated JPEG byte for byte. This checks host protocol behavior without representing it as a physical UART or board test.

## Setup checks

The documented simulation helper was executed from the organized project with both default and non-default dimensions. Python files passed syntax checks. All README local links and image paths resolve. The Vivado Tcl scripts use repository-relative paths, the correct part, board top, constraints and source sets, with matching frame parameters in synthesis and simulation. Their Tcl control flow was checked with command stubs; an actual Vivado synthesis/build remains a separate hardware-tool step.

## Integrity and build provenance

- All 25 SystemVerilog design files, the board constraints and the supplied bitstream were copied byte for byte from the final project archive.
- Testbenches and host utilities were moved into dedicated folders. The host upload utility's baud-divider help text was updated to agree with the 50 MHz board RTL; its serial protocol is unchanged.
- New Tcl scripts create a portable project without absolute workstation paths.
- The supplied bitstream header identifies Vivado 2026.1 and the Artix-7 `7a100tcsg324` device.
- The new project-creation/build Tcl scripts were inspected for paths and source selection. Rebuilding and hardware programming are separate from the image simulations recorded above.

No open-source license was added during organization. Existing notices in retained source are preserved.
