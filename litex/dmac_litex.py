# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
DMAC LiteX Module
==================
Instantiates dmac_top_wrap.sv (flat-port wrapper around dmac_top) and wires
it to LiteX CSR registers.  Supports 1 channel (NUM_CH=1) for simplicity.

CSR registers:
  ctrl        [0]=global_enable
  ch_ctrl     Channel 0 control word
  ch_src      Channel 0 source address
  ch_dst      Channel 0 destination address
  ch_count    Channel 0 transfer count [15:0]
  ch_start    Write [0]=1 to trigger channel 0 start (self-clearing)
  status      [0]=ch0_busy [1]=ch0_tc [2]=ch0_ht [3]=ch0_te
  version     IP version (RO)

The bus master port is connected to a small loopback SRAM (256 words)
for self-contained M2M testing.
"""

from migen import *
from litex.soc.interconnect.csr import *

import os

DMAC_RTL_DIR = os.path.join(os.path.dirname(__file__), '../rtl')

LOOPBACK_DEPTH = 256  # 256 x 32-bit words = 1 KiB


class DMAC(Module, AutoCSR):
    def __init__(self, platform):
        # ── Platform sources ──────────────────────────────────────────────
        for f in ['dmac_pkg.sv', 'dmac_channel.sv', 'dmac_arbiter.sv',
                   'dmac_core.sv', 'dmac_top.sv', 'dmac_top_wrap.sv']:
            platform.add_source(os.path.join(DMAC_RTL_DIR, f))

        # ── CSR registers (RW) ────────────────────────────────────────────
        self.ctrl     = CSRStorage(8,  name="ctrl",
                                   description="[0]=global_enable")
        self.ch_ctrl  = CSRStorage(32, name="ch_ctrl",
                                   description="Channel 0 control word")
        self.ch_src   = CSRStorage(32, name="ch_src",
                                   description="Channel 0 source address")
        self.ch_dst   = CSRStorage(32, name="ch_dst",
                                   description="Channel 0 destination address")
        self.ch_count = CSRStorage(16, name="ch_count",
                                   description="Channel 0 transfer count")
        self.ch_start = CSRStorage(8,  name="ch_start",
                                   description="[0]=start (write triggers pulse)")

        # ── CSR registers (RO) ────────────────────────────────────────────
        self.status  = CSRStatus(8,  name="status",
                                 description="[0]=busy [1]=tc [2]=ht [3]=te")
        self.version = CSRStatus(32, name="version", description="IP version")

        # ── Loopback memory (CSR-accessible for test setup/readback) ──────
        self.mem_addr = CSRStorage(32, name="mem_addr",
                                   description="Loopback memory address for CPU access")
        self.mem_wdata = CSRStorage(32, name="mem_wdata",
                                    description="Loopback memory write data")
        self.mem_we    = CSRStorage(8,  name="mem_we",
                                    description="[0]=write enable (self-clearing)")
        self.mem_rdata = CSRStatus(32, name="mem_rdata",
                                   description="Loopback memory read data")

        # ── Core signals ──────────────────────────────────────────────────
        ch_busy    = Signal()
        ch_tc      = Signal()
        ch_ht      = Signal()
        ch_te      = Signal()
        ch_remain  = Signal(16)
        version_sig = Signal(32)
        core_irq   = Signal()

        # Bus master signals
        bus_req    = Signal()
        bus_we     = Signal()
        bus_addr   = Signal(32)
        bus_wdata  = Signal(32)
        bus_size   = Signal(2)
        bus_gnt    = Signal()
        bus_rvalid = Signal()
        bus_rdata  = Signal(32)
        bus_err    = Signal()

        # Start pulse: fires one cycle after ch_start is written with bit[0]=1
        # Register to avoid comb race between re and storage update
        start_pulse = Signal()
        start_pending = Signal()
        self.sync += [
            start_pulse.eq(0),
            If(self.ch_start.re & self.ch_start.storage[0],
                start_pending.eq(1),
            ),
            If(start_pending,
                start_pulse.eq(1),
                start_pending.eq(0),
            ),
        ]

        # Status — latch TC/HT/TE pulses into sticky flags (cleared on start)
        tc_sticky = Signal(reset=0)
        ht_sticky = Signal(reset=0)
        te_sticky = Signal(reset=0)
        self.sync += [
            If(start_pulse,
                tc_sticky.eq(0),
                ht_sticky.eq(0),
                te_sticky.eq(0),
            ).Else(
                If(ch_tc, tc_sticky.eq(1)),
                If(ch_ht, ht_sticky.eq(1)),
                If(ch_te, te_sticky.eq(1)),
            ),
        ]
        self.comb += [
            self.status.status[0].eq(ch_busy),
            self.status.status[1].eq(tc_sticky),
            self.status.status[2].eq(ht_sticky),
            self.status.status[3].eq(te_sticky),
        ]

        # IRQ
        self.irq = Signal()
        irq_prev = Signal()
        self.sync += irq_prev.eq(core_irq)
        self.comb += self.irq.eq(core_irq & ~irq_prev)

        # ── Loopback SRAM ─────────────────────────────────────────────────
        mem = Memory(32, LOOPBACK_DEPTH)
        self.specials += mem

        # Port A: bus master (DMA engine)
        dma_port = mem.get_port(write_capable=True, has_re=True)
        self.specials += dma_port

        # Port B: CPU access via CSR (READ-ONLY to avoid dual-write-port)
        cpu_port = mem.get_port(write_capable=False, has_re=True)
        self.specials += cpu_port

        # CPU read port wiring
        self.comb += [
            cpu_port.adr.eq(self.mem_addr.storage[:len(cpu_port.adr)]),
            cpu_port.re.eq(1),
        ]
        self.sync += self.mem_rdata.status.eq(cpu_port.dat_r)

        # CPU writes go through the DMA port when DMA is idle
        # (mux the DMA port between DMA engine and CPU writes)
        cpu_we_pulse = Signal()
        self.comb += cpu_we_pulse.eq(self.mem_we.re & self.mem_we.storage[0])

        # ── DMA bus master to SRAM bridge ─────────────────────────────────
        # Mux DMA port: DMA engine has priority; CPU writes when DMA idle
        self.comb += [
            bus_gnt.eq(bus_req),
            bus_err.eq(0),
        ]
        self.comb += [
            If(bus_req,
                dma_port.adr.eq(bus_addr[2:2 + len(dma_port.adr)]),
                dma_port.dat_w.eq(bus_wdata),
                dma_port.we.eq(bus_we),
                dma_port.re.eq(~bus_we),
            ).Elif(cpu_we_pulse,
                dma_port.adr.eq(self.mem_addr.storage[:len(dma_port.adr)]),
                dma_port.dat_w.eq(self.mem_wdata.storage),
                dma_port.we.eq(1),
                dma_port.re.eq(0),
            ).Else(
                dma_port.adr.eq(0),
                dma_port.dat_w.eq(0),
                dma_port.we.eq(0),
                dma_port.re.eq(0),
            ),
        ]
        # rvalid and rdata arrive one cycle after request (synchronous RAM)
        self.sync += [
            bus_rvalid.eq(bus_req & ~bus_we),
            bus_rdata.eq(dma_port.dat_r),
        ]

        # ── Reset stretcher: ensure rst_n has a clean negedge after power-up ──
        rst_cnt = Signal(4, reset=0)
        rst_n_stretched = Signal(reset=0)
        self.sync += [
            If(rst_cnt < 15,
                rst_cnt.eq(rst_cnt + 1),
                rst_n_stretched.eq(0),
            ).Else(
                rst_n_stretched.eq(1),
            ),
        ]

        # ── DMAC top wrapper instance (flat ports, no unpacked arrays) ────
        self.specials += Instance("dmac_top_wrap",
            p_NUM_CH        = 1,
            i_clk           = ClockSignal(),
            i_rst_n         = rst_n_stretched & ~ResetSignal(),
            i_global_enable = self.ctrl.storage[0],

            # Per-channel config (flat packed, 1 channel = 32/16 bits)
            i_ch_ctrl_flat  = self.ch_ctrl.storage,
            i_ch_src_flat   = self.ch_src.storage,
            i_ch_dst_flat   = self.ch_dst.storage,
            i_ch_count_flat = self.ch_count.storage,
            i_ch_start      = start_pulse,
            i_ch_abort      = Signal(1, reset=0),

            # Status
            o_ch_busy       = ch_busy,
            o_ch_tc         = ch_tc,
            o_ch_ht         = ch_ht,
            o_ch_te         = ch_te,
            o_ch_remain_flat = ch_remain,

            # Bus master
            o_bus_req       = bus_req,
            o_bus_we        = bus_we,
            o_bus_addr      = bus_addr,
            o_bus_wdata     = bus_wdata,
            o_bus_size      = bus_size,
            i_bus_gnt       = bus_gnt,
            i_bus_rvalid    = bus_rvalid,
            i_bus_rdata     = bus_rdata,
            i_bus_err       = bus_err,

            # DRQ/DACK (unused, tie off)
            i_drq_i         = Signal(1, reset=0),
            o_dack_o        = Signal(1),

            # IRQ / version
            o_irq_o         = core_irq,
            o_version_o     = version_sig,
        )

        self.comb += self.version.status.eq(version_sig)
