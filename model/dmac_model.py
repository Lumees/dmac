#!/usr/bin/env python3
# =============================================================================
# Copyright (c) 2026 Lumees Lab / Hasan Kurşun
# SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
#
# Free for non-commercial use (academic, research, hobby, education).
# Commercial use requires a Lumees Lab license: info@lumeeslab.com
# =============================================================================
"""
DMA Controller — Golden Model
================================
Models single-channel M2M transfers for cocotb comparison.
"""

from __future__ import annotations


class DMAChannel:
    """Model of a single DMA channel."""

    def __init__(self):
        self.src_addr = 0
        self.dst_addr = 0
        self.count = 0
        self.src_inc = True
        self.dst_inc = True
        self.width = 4  # bytes per transfer (1/2/4)

    def configure(self, src, dst, count, width=4, src_inc=True, dst_inc=True):
        self.src_addr = src
        self.dst_addr = dst
        self.count = count
        self.width = width
        self.src_inc = src_inc
        self.dst_inc = dst_inc

    def run(self, memory: dict) -> dict:
        """Execute the DMA transfer on a dict-based memory model.
        Returns dict of {dst_addr: value} for verification."""
        results = {}
        src = self.src_addr
        dst = self.dst_addr

        for i in range(self.count):
            val = memory.get(src, 0)
            results[dst] = val
            memory[dst] = val

            if self.src_inc:
                src += self.width
            if self.dst_inc:
                dst += self.width

        return results


def _self_test():
    """Basic sanity checks."""
    mem = {}
    # Fill source
    for i in range(8):
        mem[0x1000 + i * 4] = 0xAA + i

    ch = DMAChannel()
    ch.configure(src=0x1000, dst=0x2000, count=8, width=4)
    results = ch.run(mem)

    assert len(results) == 8
    assert results[0x2000] == 0xAA
    assert results[0x201C] == 0xAA + 7
    assert mem[0x2000] == 0xAA
    print("  [PASS] M2M 8-word transfer")

    # Fixed source (FIFO mode)
    mem2 = {0x3000: 0x42}
    ch2 = DMAChannel()
    ch2.configure(src=0x3000, dst=0x4000, count=4, width=4, src_inc=False)
    results2 = ch2.run(mem2)
    assert all(v == 0x42 for v in results2.values())
    print("  [PASS] Fixed-source 4-word fill")

    print("\n  2/2 self-tests passed")
    return True


if __name__ == "__main__":
    print("DMAC Model Self-Test")
    print("=" * 40)
    ok = _self_test()
    exit(0 if ok else 1)
