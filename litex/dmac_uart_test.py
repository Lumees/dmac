#!/usr/bin/env python3
# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
DMAC UART Hardware Regression Test
=====================================
Runs on Arty A7-100T via litex_server + RemoteClient.
Requires: litex_server --uart --uart-port /dev/ttyUSB1 --uart-baudrate 115200

Tests:
  T01 - Version register readback
  T02 - Status idle on reset
  T03 - Program a 4-word M2M transfer and verify
  T04 - Back-to-back M2M transfers
"""

import os
import sys
import time

from litex.tools.litex_client import RemoteClient

PASS_COUNT = 0
FAIL_COUNT = 0


class DMACClient:
    def __init__(self, host='localhost', tcp_port=1234, csr_csv=None):
        self.client = RemoteClient(host=host, port=tcp_port, csr_csv=csr_csv)
        self.client.open()

    def close(self):
        self.client.close()

    def _w(self, reg: str, val: int):
        getattr(self.client.regs, f"dmac_{reg}").write(val & 0xFFFFFFFF)

    def _r(self, reg: str) -> int:
        return int(getattr(self.client.regs, f"dmac_{reg}").read())

    # ── Register helpers ──────────────────────────────────────────────────
    def version(self) -> int:
        return self._r("version")

    def status(self) -> dict:
        s = self._r("status")
        return {
            "busy": bool(s & 0x01),
            "tc":   bool(s & 0x02),
            "ht":   bool(s & 0x04),
            "te":   bool(s & 0x08),
        }

    def set_global_enable(self, en: bool):
        self._w("ctrl", 1 if en else 0)

    def program_channel(self, src: int, dst: int, count: int, ctrl: int = 0x01):
        """Program channel 0 for a transfer.
        ctrl default 0x01 = enable, M2M, 32-bit, increment, priority 0."""
        self._w("ch_src", src)
        self._w("ch_dst", dst)
        self._w("ch_count", count)
        self._w("ch_ctrl", ctrl)

    def start_channel(self):
        self._w("ch_start", 0x01)

    def wait_done(self, timeout: float = 5.0) -> bool:
        t0 = time.time()
        while time.time() - t0 < timeout:
            s = self.status()
            if s["tc"]:
                return True
            if not s["busy"]:
                return True
            time.sleep(0.01)
        return False

    # ── Loopback memory access ────────────────────────────────────────────
    def mem_write(self, word_addr: int, value: int):
        """Write a 32-bit word to the loopback SRAM at word_addr."""
        self._w("mem_addr", word_addr)
        self._w("mem_wdata", value)
        self._w("mem_we", 0x01)
        time.sleep(0.001)

    def mem_read(self, word_addr: int) -> int:
        """Read a 32-bit word from the loopback SRAM at word_addr."""
        self._w("mem_addr", word_addr)
        time.sleep(0.001)
        return self._r("mem_rdata")


def check(name, condition, detail=""):
    global PASS_COUNT, FAIL_COUNT
    if condition:
        print(f"  [PASS] {name}")
        PASS_COUNT += 1
    else:
        print(f"  [FAIL] {name}  {detail}")
        FAIL_COUNT += 1


# ── Tests ────────────────────────────────────────────────────────────────────

def test_version(dut: DMACClient):
    """T01: Read VERSION register, expect 0x00010000."""
    print("\n[T01] Version register")
    # Reset all CSRs to known state
    dut.set_global_enable(False)
    dut._w("ch_start", 0)
    dut._w("ch_ctrl", 0)
    dut._w("ch_src", 0)
    dut._w("ch_dst", 0)
    dut._w("ch_count", 0)
    import time; time.sleep(0.05)
    ver = dut.version()
    check("VERSION == 0x00010000", ver == 0x00010000, f"got 0x{ver:08X}")


def test_status_idle(dut: DMACClient):
    """T02: After reset, status should show idle (not busy, no flags)."""
    print("\n[T02] Status idle on reset")
    s = dut.status()
    check("busy == False", not s["busy"], f"got busy={s['busy']}")
    check("tc == False",   not s["tc"],   f"got tc={s['tc']}")
    check("ht == False",   not s["ht"],   f"got ht={s['ht']}")
    check("te == False",   not s["te"],   f"got te={s['te']}")


def test_m2m_4word(dut: DMACClient):
    """T03: Program a 4-word memory-to-memory transfer and verify data."""
    print("\n[T03] 4-word M2M transfer")

    # Source data at word addresses 0..3, destination at 64..67
    src_base = 0
    dst_base = 64
    test_data = [0xDEADBEEF, 0xCAFEBABE, 0x12345678, 0xA5A5A5A5]

    # Write source data into loopback memory
    for i, val in enumerate(test_data):
        dut.mem_write(src_base + i, val)

    # Clear destination
    for i in range(len(test_data)):
        dut.mem_write(dst_base + i, 0x00000000)

    # Verify source was written
    for i, val in enumerate(test_data):
        rd = dut.mem_read(src_base + i)
        check(f"src[{i}] written", rd == val,
              f"expected 0x{val:08X}, got 0x{rd:08X}")

    # Program DMA: src byte address = src_base*4, dst byte address = dst_base*4
    # ctrl = 0x01: enable=1, M2M, WIDTH_32, ADDR_INC, priority=0
    # xfer_width = WIDTH_32 = 2'b10 at bits [7:6] => 0x80
    ch_ctrl = 0x01 | (0b10 << 6)  # enable + WIDTH_32
    dut.set_global_enable(True)
    dut.program_channel(src=src_base * 4, dst=dst_base * 4,
                        count=len(test_data), ctrl=ch_ctrl)
    dut.start_channel()

    # Wait for completion
    done = dut.wait_done(timeout=5.0)
    check("Transfer completed", done)

    # Read back destination and verify
    for i, val in enumerate(test_data):
        rd = dut.mem_read(dst_base + i)
        check(f"dst[{i}] == 0x{val:08X}", rd == val,
              f"got 0x{rd:08X}")


def test_back_to_back(dut: DMACClient):
    """T04: Two back-to-back 4-word M2M transfers."""
    print("\n[T04] Back-to-back M2M transfers")

    src_base_1 = 0
    dst_base_1 = 64
    src_base_2 = 128
    dst_base_2 = 192

    data_1 = [0x11111111, 0x22222222, 0x33333333, 0x44444444]
    data_2 = [0xAAAAAAAA, 0xBBBBBBBB, 0xCCCCCCCC, 0xDDDDDDDD]

    # Write source data
    for i, val in enumerate(data_1):
        dut.mem_write(src_base_1 + i, val)
    for i, val in enumerate(data_2):
        dut.mem_write(src_base_2 + i, val)

    ch_ctrl = 0x01 | (0b10 << 6)  # enable + WIDTH_32

    # Transfer 1
    dut.set_global_enable(True)
    dut.program_channel(src=src_base_1 * 4, dst=dst_base_1 * 4,
                        count=len(data_1), ctrl=ch_ctrl)
    dut.start_channel()
    done1 = dut.wait_done(timeout=5.0)
    check("Transfer 1 completed", done1)

    for i, val in enumerate(data_1):
        rd = dut.mem_read(dst_base_1 + i)
        check(f"xfer1 dst[{i}] == 0x{val:08X}", rd == val,
              f"got 0x{rd:08X}")

    # Transfer 2
    dut.program_channel(src=src_base_2 * 4, dst=dst_base_2 * 4,
                        count=len(data_2), ctrl=ch_ctrl)
    dut.start_channel()
    done2 = dut.wait_done(timeout=5.0)
    check("Transfer 2 completed", done2)

    for i, val in enumerate(data_2):
        rd = dut.mem_read(dst_base_2 + i)
        check(f"xfer2 dst[{i}] == 0x{val:08X}", rd == val,
              f"got 0x{rd:08X}")


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    csr_csv = os.path.join(os.path.dirname(__file__),
                           'build/digilent_arty/csr.csv')
    if not os.path.exists(csr_csv):
        csr_csv = None

    dut = DMACClient(csr_csv=csr_csv)

    try:
        print("=" * 60)
        print("DMAC UART Hardware Regression")
        print("  1 channel, loopback SRAM")
        print("=" * 60)

        test_version(dut)
        test_status_idle(dut)
        test_m2m_4word(dut)
        test_back_to_back(dut)

        print("\n" + "=" * 60)
        total = PASS_COUNT + FAIL_COUNT
        print(f"Result: {PASS_COUNT}/{total} PASS  {FAIL_COUNT}/{total} FAIL")
        print("=" * 60)
        sys.exit(0 if FAIL_COUNT == 0 else 1)

    finally:
        dut.close()


if __name__ == "__main__":
    main()
