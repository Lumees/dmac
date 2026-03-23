# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
DMAC IP — Directed cocotb tests for dmac_axil (AXI4-Lite wrapper)
==================================================================
Tests global register readback and per-channel register write/read.

Register map:
  0x00  GLOBAL_CTRL     R/W  [0]=global_enable
  0x04  GLOBAL_STATUS   RO   [N_CH-1:0]=ch_busy
  0x08  GLOBAL_IRQ      RO   Sticky TC/HT/TE per channel
  0x0C  VERSION         RO   IP_VERSION (0x00010000)

  Per-channel at 0x40 + N * 0x20:
  +0x00  CH_CTRL    R/W  Channel control
  +0x04  CH_STATUS  R/W1C [0]=tc [1]=ht [2]=te [3]=busy(RO)
  +0x08  CH_SRC     R/W  Source address
  +0x0C  CH_DST     R/W  Destination address
  +0x10  CH_COUNT   R/W  Transfer count [15:0]
  +0x14  CH_NDESC   R/W  Next descriptor address
  +0x18  CH_CDESC   RO   Current descriptor address
  +0x1C  CH_REMAIN  RO   Remaining transfer count
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import os

N_CH   = int(os.environ.get("DMAC_N_CH", "4"))
CLK_NS = 10

# Global register offsets
REG_GLOBAL_CTRL   = 0x00
REG_GLOBAL_STATUS = 0x04
REG_GLOBAL_IRQ    = 0x08
REG_VERSION       = 0x0C

# Per-channel base and stride (byte addresses)
CH_BASE   = 0x40
CH_STRIDE = 0x20


def ch_reg(ch, offset):
    """Byte address for per-channel register."""
    return CH_BASE + ch * CH_STRIDE + offset


# Per-channel register offsets within a channel block
CH_CTRL    = 0x00
CH_STATUS  = 0x04
CH_SRC     = 0x08
CH_DST     = 0x0C
CH_COUNT   = 0x10
CH_NDESC   = 0x14
CH_CDESC   = 0x18
CH_REMAIN  = 0x1C


# ---------------------------------------------------------------------------
# AXI4-Lite bus helpers
# ---------------------------------------------------------------------------
async def axil_write(dut, addr, data):
    """Single AXI4-Lite write transaction."""
    dut.s_axil_awaddr.value  = addr
    dut.s_axil_awvalid.value = 1
    dut.s_axil_wdata.value   = data & 0xFFFFFFFF
    dut.s_axil_wstrb.value   = 0xF
    dut.s_axil_wvalid.value  = 1
    dut.s_axil_bready.value  = 1

    while True:
        await RisingEdge(dut.clk)
        aw_done = int(dut.s_axil_awready.value) == 1
        w_done  = int(dut.s_axil_wready.value)  == 1
        if aw_done:
            dut.s_axil_awvalid.value = 0
        if w_done:
            dut.s_axil_wvalid.value = 0
        if aw_done and w_done:
            break

    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_bvalid.value) == 1:
            dut.s_axil_bready.value = 0
            return
    raise TimeoutError(f"axil_write timeout at addr=0x{addr:04X}")


async def axil_read(dut, addr) -> int:
    """Single AXI4-Lite read transaction, returns 32-bit data."""
    dut.s_axil_araddr.value  = addr
    dut.s_axil_arvalid.value = 1
    dut.s_axil_rready.value  = 1

    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_arready.value) == 1:
            dut.s_axil_arvalid.value = 0
            break
    else:
        raise TimeoutError(f"axil_read AR timeout at addr=0x{addr:04X}")

    for _ in range(20):
        await RisingEdge(dut.clk)
        if int(dut.s_axil_rvalid.value) == 1:
            data = int(dut.s_axil_rdata.value)
            dut.s_axil_rready.value = 0
            return data
    raise TimeoutError(f"axil_read R timeout at addr=0x{addr:04X}")


# ---------------------------------------------------------------------------
# Reset
# ---------------------------------------------------------------------------
async def hw_reset(dut):
    """Assert reset and initialize all AXI4-Lite and bus master inputs to idle."""
    dut.s_axil_awvalid.value = 0
    dut.s_axil_wvalid.value  = 0
    dut.s_axil_bready.value  = 0
    dut.s_axil_arvalid.value = 0
    dut.s_axil_rready.value  = 0
    dut.s_axil_awaddr.value  = 0
    dut.s_axil_wdata.value   = 0
    dut.s_axil_wstrb.value   = 0xF
    dut.s_axil_araddr.value  = 0
    dut.bus_gnt.value    = 0
    dut.bus_rvalid.value = 0
    dut.bus_rdata.value  = 0
    dut.bus_err.value    = 0
    dut.drq_i.value      = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 8)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 4)


# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_t01_version(dut):
    """T01: Read VERSION register (offset 0x0C) == 0x00010000."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    ver = await axil_read(dut, REG_VERSION)
    dut._log.info(f"[T01] VERSION = 0x{ver:08X}")
    assert ver == 0x00010000, f"VERSION mismatch: 0x{ver:08X} != 0x00010000"


@cocotb.test()
async def test_t02_global_register_readback(dut):
    """T02: Global register readback — CTRL, STATUS, IRQ after reset."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    # GLOBAL_CTRL: global_enable should be 0 after reset
    ctrl = await axil_read(dut, REG_GLOBAL_CTRL)
    dut._log.info(f"[T02] GLOBAL_CTRL = 0x{ctrl:08X}")
    assert (ctrl & 0x1) == 0, f"GLOBAL_CTRL.enable should be 0, got 0x{ctrl:08X}"

    # Write global_enable = 1
    await axil_write(dut, REG_GLOBAL_CTRL, 0x01)
    ctrl = await axil_read(dut, REG_GLOBAL_CTRL)
    dut._log.info(f"[T02] GLOBAL_CTRL after enable = 0x{ctrl:08X}")
    assert (ctrl & 0x1) == 1, f"GLOBAL_CTRL.enable should be 1, got 0x{ctrl:08X}"

    # GLOBAL_STATUS: no channels busy after reset
    status = await axil_read(dut, REG_GLOBAL_STATUS)
    dut._log.info(f"[T02] GLOBAL_STATUS = 0x{status:08X}")
    assert status == 0, f"GLOBAL_STATUS should be 0 (no busy channels), got 0x{status:08X}"

    # GLOBAL_IRQ: no interrupts pending
    irq_status = await axil_read(dut, REG_GLOBAL_IRQ)
    dut._log.info(f"[T02] GLOBAL_IRQ = 0x{irq_status:08X}")
    assert irq_status == 0, f"GLOBAL_IRQ should be 0, got 0x{irq_status:08X}"

    dut._log.info("[T02] Global register readback verified")


@cocotb.test()
async def test_t03_per_channel_registers(dut):
    """T03: Per-channel register write/read for all channels."""
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    await hw_reset(dut)

    for ch in range(N_CH):
        # Write CH_SRC
        src_val = 0x1000_0000 + ch * 0x100
        await axil_write(dut, ch_reg(ch, CH_SRC), src_val)
        rd = await axil_read(dut, ch_reg(ch, CH_SRC))
        dut._log.info(f"[T03] CH{ch} SRC: wrote 0x{src_val:08X}, read 0x{rd:08X}")
        assert rd == src_val, f"CH{ch} SRC mismatch: 0x{rd:08X} != 0x{src_val:08X}"

        # Write CH_DST
        dst_val = 0x2000_0000 + ch * 0x100
        await axil_write(dut, ch_reg(ch, CH_DST), dst_val)
        rd = await axil_read(dut, ch_reg(ch, CH_DST))
        dut._log.info(f"[T03] CH{ch} DST: wrote 0x{dst_val:08X}, read 0x{rd:08X}")
        assert rd == dst_val, f"CH{ch} DST mismatch: 0x{rd:08X} != 0x{dst_val:08X}"

        # Write CH_COUNT
        count_val = 64 + ch * 16
        await axil_write(dut, ch_reg(ch, CH_COUNT), count_val)
        rd = await axil_read(dut, ch_reg(ch, CH_COUNT))
        got_count = rd & 0xFFFF
        dut._log.info(f"[T03] CH{ch} COUNT: wrote {count_val}, read {got_count}")
        assert got_count == count_val, (
            f"CH{ch} COUNT mismatch: {got_count} != {count_val}")

        # Write CH_NDESC
        ndesc_val = 0x3000_0000 + ch * 0x10
        await axil_write(dut, ch_reg(ch, CH_NDESC), ndesc_val)
        rd = await axil_read(dut, ch_reg(ch, CH_NDESC))
        dut._log.info(f"[T03] CH{ch} NDESC: wrote 0x{ndesc_val:08X}, read 0x{rd:08X}")
        assert rd == ndesc_val, (
            f"CH{ch} NDESC mismatch: 0x{rd:08X} != 0x{ndesc_val:08X}")

        # CH_STATUS: should show not busy (bit 3), no flags
        st = await axil_read(dut, ch_reg(ch, CH_STATUS))
        dut._log.info(f"[T03] CH{ch} STATUS = 0x{st:08X}")
        assert (st & 0x08) == 0, f"CH{ch} should not be busy, STATUS=0x{st:08X}"

    dut._log.info(f"[T03] Per-channel register write/read verified for {N_CH} channels")
