// =============================================================================
// Copyright (c) 2026 Lumees Lab / Hasan Kurşun
// SPDX-License-Identifier: Apache-2.0 WITH Commons-Clause
//
// Licensed under the Apache License 2.0 with Commons Clause restriction.
// You may use this file freely for non-commercial purposes (academic,
// research, hobby, education, personal projects).
//
// COMMERCIAL USE requires a separate license from Lumees Lab.
// Contact: info@lumeeslab.com · https://lumeeslab.com
// =============================================================================
// DMA Controller IP — Package
// =============================================================================

`timescale 1ns/1ps

package dmac_pkg;

  localparam int IP_VERSION = 32'h0001_0000;

  // ── Compile-time parameters ───────────────────────────────────────────────
`ifdef DMAC_PKG_N_CH
  localparam int N_CH = `DMAC_PKG_N_CH;
`else
  localparam int N_CH = 4;
`endif

  localparam int ADDR_W     = 32;
  localparam int DATA_W     = 32;
  localparam int FIFO_DEPTH = 4;

  // ── Transfer type ─────────────────────────────────────────────────────────
  typedef enum logic [1:0] {
    XFER_M2M  = 2'b00,   // memory-to-memory
    XFER_M2P  = 2'b01,   // memory-to-peripheral
    XFER_P2M  = 2'b10,   // peripheral-to-memory
    XFER_RSVD = 2'b11
  } xfer_type_t;

  // ── Address mode ──────────────────────────────────────────────────────────
  typedef enum logic [1:0] {
    ADDR_INC  = 2'b00,
    ADDR_DEC  = 2'b01,
    ADDR_FIX  = 2'b10,
    ADDR_RSVD = 2'b11
  } addr_mode_t;

  // ── Transfer width ────────────────────────────────────────────────────────
  typedef enum logic [1:0] {
    WIDTH_8   = 2'b00,
    WIDTH_16  = 2'b01,
    WIDTH_32  = 2'b10,
    WIDTH_RSVD= 2'b11
  } xfer_width_t;

  // ── Channel control register (packed) ─────────────────────────────────────
  // Bit layout (32-bit register):
  //   [0]     enable
  //   [1]     irq_tc (interrupt on transfer complete)
  //   [2]     irq_ht (interrupt on half-transfer)
  //   [3]     irq_err (interrupt on error)
  //   [5:4]   xfer_type
  //   [7:6]   xfer_width
  //   [9:8]   src_mode
  //   [11:10] dst_mode
  //   [13:12] priority (0=low, 3=high)
  //   [14]    sg_enable (scatter-gather)
  //   [15]    circ (circular mode)
  localparam int CTRL_ENABLE     = 0;
  localparam int CTRL_IRQ_TC     = 1;
  localparam int CTRL_IRQ_HT     = 2;
  localparam int CTRL_IRQ_ERR    = 3;
  localparam int CTRL_XTYPE_LO   = 4;
  localparam int CTRL_XWIDTH_LO  = 6;
  localparam int CTRL_SRCM_LO    = 8;
  localparam int CTRL_DSTM_LO    = 10;
  localparam int CTRL_PRI_LO     = 12;
  localparam int CTRL_SG         = 14;
  localparam int CTRL_CIRC       = 15;

  // ── Channel status bits ───────────────────────────────────────────────────
  localparam int STAT_TC   = 0;   // transfer complete
  localparam int STAT_HT   = 1;   // half-transfer
  localparam int STAT_TE   = 2;   // transfer error
  localparam int STAT_BUSY = 3;   // channel active

  // ── Channel FSM states ────────────────────────────────────────────────────
  typedef enum logic [2:0] {
    CH_IDLE,
    CH_FETCH_DESC,
    CH_READ_REQ,
    CH_READ_WAIT,
    CH_WRITE_REQ,
    CH_WRITE_WAIT,
    CH_DONE
  } ch_state_t;

  // ── Global register offsets ───────────────────────────────────────────────
  localparam int REG_GLOBAL_CTRL   = 8'h00;
  localparam int REG_GLOBAL_STATUS = 8'h04;
  localparam int REG_GLOBAL_IRQ    = 8'h08;
  localparam int REG_VERSION       = 8'h0C;

  // ── Per-channel register offsets (relative to channel base) ───────────────
  localparam int CH_BASE   = 8'h40;
  localparam int CH_STRIDE = 8'h20;

  localparam int CH_CTRL   = 5'h00;
  localparam int CH_STATUS = 5'h04;
  localparam int CH_SRC    = 5'h08;
  localparam int CH_DST    = 5'h0C;
  localparam int CH_COUNT  = 5'h10;
  localparam int CH_NDESC  = 5'h14;
  localparam int CH_CDESC  = 5'h18;
  localparam int CH_REMAIN = 5'h1C;

endpackage : dmac_pkg
