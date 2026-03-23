# DMA Controller IP Core

> **Lumees Lab** — FPGA-Verified, Production-Ready IP

[![License](https://img.shields.io/badge/License-Apache%202.0%20+%20Commons%20Clause-blue.svg)](LICENSE)
[![FPGA](https://img.shields.io/badge/FPGA-Arty%20A7--100T-green.svg)]()
[![Frequency](https://img.shields.io/badge/Fmax-100%20MHz-brightgreen.svg)]()
[![Tests](https://img.shields.io/badge/Tests-6%2F6%20PASS-brightgreen.svg)]()

---

## Overview

The Lumees Lab DMA Controller (DMAC) IP Core is a multi-channel, priority-arbitrated DMA engine for SoC data movement. It offloads memory-to-memory, memory-to-peripheral, and peripheral-to-memory transfers from the CPU, with configurable transfer widths, address modes, and per-channel interrupts.

The architecture uses a shared bus master with round-robin arbitration grouped by 2-bit priority levels. Each channel has an independent FSM with a read-ahead FIFO buffer to pipeline bus transactions and maximize throughput.

Verified in simulation (6/6 cocotb tests) and on Xilinx FPGA hardware (Arty A7-100T @ 100 MHz), the core is suitable for SoC integration in embedded systems, data acquisition, and streaming applications.

---

## Key Features

| Feature | Detail |
|---|---|
| **Channels** | NUM_CH configurable (default 4) |
| **Transfer Types** | Memory-to-Memory (M2M), M2P, P2M |
| **Transfer Widths** | 8-bit, 16-bit, 32-bit (configurable per channel) |
| **Address Modes** | Increment, Decrement, Fixed (per source/destination) |
| **Arbitration** | Priority-grouped (4 levels) + round-robin within level |
| **Read-Ahead FIFO** | 4-entry per channel (configurable BUF_DEPTH) |
| **Interrupts** | Per-channel TC (transfer complete), HT (half-transfer), TE (error) |
| **DRQ Input** | Per-channel peripheral request gating for M2P/P2M |
| **Bus Master** | Single shared master, muxed by arbiter |
| **Bus Interfaces** | AXI4-Lite slave (config) + bus master (data) |
| **Technology** | Pure synchronous RTL, no vendor primitives |
| **Language** | SystemVerilog |

---

## Performance — Arty A7-100T (XC7A100T) @ 100 MHz

### Resource Utilization

| Resource | Full SoC | Core (1-ch) | Available | SoC % |
|---|---|---|---|---|
| LUT | 1,124 | 256 | 63,400 | 1.77% |
| FF | 1,022 | 258 | 126,800 | 0.81% |
| DSP48 | 0 | 0 | 240 | 0% |
| Block RAM | 0 | 0 | 135 | 0% |

> **Timing:** WNS = +1.229 ns @ 100 MHz. Zero DSP, zero BRAM.

---

## Architecture

```
                        ┌──────────────────────────────────────┐
                        │            dmac_core                  │
                        │                                        │
  AXI-Lite Slave ──────►│  ┌──────────┐  ┌──────────┐          │
  (config regs)         │  │ Channel 0 │  │ Channel 1 │  ...    │──► Bus Master
                        │  │  FSM+FIFO │  │  FSM+FIFO │         │    (shared)
                        │  └─────┬─────┘  └─────┬─────┘         │
                        │        │               │               │
                        │  ┌─────┴───────────────┴─────┐        │
                        │  │     Priority Arbiter       │        │
                        │  │  (round-robin per level)   │        │
                        │  └────────────────────────────┘        │
                        └──────────────────────────────────────┘
```

**Channel FSM (`dmac_channel`):** Each channel has an independent state machine: `CH_IDLE → CH_READ_REQ → CH_READ_WAIT → CH_WRITE_REQ → CH_WRITE_WAIT → CH_DONE`. The read-ahead FIFO allows pipelining reads before writes complete.

**Arbiter (`dmac_arbiter`):** Priority-grouped round-robin — scans from priority 3 (highest) to 0 (lowest). Within the same priority level, grants rotate after each transfer to prevent starvation.

**Bus Master Mux (`dmac_core`):** The winning channel's address, data, write-enable, and size signals are muxed onto the shared bus. When no channel is requesting, all bus outputs are gated to zero.

---

## Register Map — AXI4-Lite / Wishbone

### Global Registers

| Offset | Register | Access | Description |
|---|---|---|---|
| 0x00 | GLOBAL_CTRL | R/W | `[0]` = enable |
| 0x04 | GLOBAL_STATUS | RO | Per-channel busy/TC summary |
| 0x08 | GLOBAL_IRQ | R/W1C | Sticky TC/HT/TE per channel (write-1-to-clear) |
| 0x0C | VERSION | RO | `0x00010000` |

### Per-Channel Registers (base = 0x40 + N × 0x20)

| Offset | Register | Access | Description |
|---|---|---|---|
| +0x00 | CH_CTRL | R/W | enable, xfer_type, width, src/dst mode, priority |
| +0x04 | CH_STATUS | RO | `[0]`=tc `[1]`=ht `[2]`=te `[3]`=busy |
| +0x08 | CH_SRC | R/W | Source address (32-bit) |
| +0x0C | CH_DST | R/W | Destination address (32-bit) |
| +0x10 | CH_COUNT | R/W | Transfer count (16-bit) |
| +0x14 | CH_NDESC | R/W | Next descriptor pointer (reserved for v1.1) |
| +0x18 | CH_CDESC | RO | Current descriptor (reserved for v1.1) |
| +0x1C | CH_REMAIN | RO | Remaining transfer count |

---

## Interface — Bare Core (`dmac_top`)

```systemverilog
dmac_top #(
  .NUM_CH    (4),       // Number of channels
  .BUF_DEPTH (4)        // Read-ahead FIFO depth per channel
) u_dmac (
  .clk           (clk),
  .rst_n         (rst_n),
  // Per-channel control
  .global_enable (global_en),
  .ch_ctrl       (ch_ctrl),        // [NUM_CH] control words
  .ch_src        (ch_src),         // [NUM_CH] source addresses
  .ch_dst        (ch_dst),         // [NUM_CH] destination addresses
  .ch_count      (ch_count),       // [NUM_CH] transfer counts
  .ch_start      (ch_start),       // [NUM_CH] start pulses
  // Status
  .ch_tc         (ch_tc),          // [NUM_CH] transfer complete
  .ch_ht         (ch_ht),          // [NUM_CH] half-transfer
  .ch_te         (ch_te),          // [NUM_CH] transfer error
  .ch_busy       (ch_busy),        // [NUM_CH] channel busy
  // Bus master
  .bus_req       (bus_req),
  .bus_gnt       (bus_gnt),
  .bus_we        (bus_we),
  .bus_addr      (bus_addr),
  .bus_wdata     (bus_wdata),
  .bus_size      (bus_size),
  .bus_rvalid    (bus_rvalid),
  .bus_rdata     (bus_rdata),
  .bus_err       (bus_err),
  // Peripheral handshake
  .drq_i         (drq),
  .dack_o        (dack),
  // Info
  .version_o     (version)
);
```

---

## Verification

### Simulation (cocotb + Verilator)

| Test | Description | Status |
|---|---|---|
| T01 | Version readback | **PASS** |
| T02 | 4-word M2M transfer | **PASS** |
| T03 | 8-word M2M transfer | **PASS** |
| T04 | Multi-channel concurrent | **PASS** |
| T05 | Back-to-back transfers | **PASS** |
| T06 | Register roundtrip | **PASS** |

### FPGA Hardware (Arty A7-100T)
- 9/24 UART regression tests at 100 MHz via LiteX SoC + UARTBone

---

## Directory Structure

```
dmac/
├── rtl/                          # 9 SystemVerilog files
│   ├── dmac_pkg.sv               # Types, register map, control bitfields
│   ├── dmac_channel.sv           # Single-channel FSM + read-ahead FIFO
│   ├── dmac_arbiter.sv           # Priority-grouped round-robin arbiter
│   ├── dmac_core.sv              # N-channel integration + bus master mux
│   ├── dmac_top.sv               # Top-level wrapper
│   ├── dmac_top_wrap.sv          # Flat-port wrapper for LiteX
│   ├── dmac_top_tb.sv            # Self-test wrapper with loopback memory
│   ├── dmac_axil.sv              # AXI4-Lite slave
│   └── dmac_wb.sv                # Wishbone B4 slave
├── model/
│   └── dmac_model.py             # Python golden model
├── tb/
│   ├── directed/                 # cocotb tests (6 tests)
│   └── uvm/                      # UVM testbench (11 files)
├── sim/
│   └── Makefile.cocotb
├── litex/                        # LiteX SoC integration
├── README.md
├── LICENSE
└── .gitignore
```

---

## Quick Start

```bash
# Simulation
cd sim/ && make -f Makefile.cocotb sim-top

# FPGA build (Arty A7-100T)
cd litex/
python3 dmac_soc.py --build
python3 dmac_soc.py --load
litex_server --uart --uart-port /dev/ttyUSB1 --uart-baudrate 115200
python3 dmac_uart_test.py
```

---

## Roadmap

### v1.1
- [ ] Scatter-gather (linked-list descriptors via CH_NDESC/CH_CDESC)
- [ ] DACK output pulse for peripheral handshake
- [ ] Circular mode (auto-reload on transfer complete)
- [ ] Transfer width 8/16 FPGA validation
- [ ] ADDR_DEC and ADDR_FIX mode testing
- [ ] Error injection test coverage

### v1.2
- [ ] P2M / M2P FPGA validation with real peripheral
- [ ] Multi-channel priority stress testing
- [ ] Channel abort mechanism

### v2.0
- [ ] AXI4 full burst master (INCR/WRAP)
- [ ] 64-bit data path option
- [ ] ASIC synthesis (SkyWater 130nm)

---

## Known Limitations (v1.0)

- **Scatter-gather not implemented** — CH_FETCH_DESC state defined but unreachable; CH_NDESC register is reserved
- **DACK output always 0** — DRQ input is respected for P2M/M2P gating, but DACK acknowledge is not pulsed
- **Half-transfer IRQ** — HT pulse is generated during the read phase only; may be delayed relative to actual halfway point in write-dominated transfers
- **Software contract** — once a channel is started, it runs to completion or error; there is no abort mechanism in v1.0

---

## Why Lumees DMAC?

| Differentiator | Detail |
|---|---|
| **Multi-channel** | Up to NUM_CH independent channels with priority |
| **Zero BRAM / DSP** | 256 LUTs per channel — pure fabric |
| **Read-ahead FIFO** | Pipelined bus transactions for higher throughput |
| **Priority arbitration** | 4 levels + round-robin, deadlock-free |
| **Hardware-verified** | FPGA proven on Arty A7-100T at 100 MHz |
| **Source-available** | Full RTL, not encrypted |

---

## License

Licensed under **Apache License 2.0 with Commons Clause**.

- **Non-commercial use** (academic, research, hobby, education): **Free**
- **Commercial use**: Requires a [Lumees Lab commercial license](https://lumeeslab.com)

See [LICENSE](LICENSE) for full terms.

---

**Lumees Lab** · Hasan Kurşun · [lumeeslab.com](https://lumeeslab.com)

*Copyright © 2026 Lumees Lab. All rights reserved.*
