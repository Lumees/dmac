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
// DMA Controller IP -- Flat-port wrapper for Migen/LiteX instantiation
// =============================================================================
// dmac_top uses SV unpacked arrays (ch_ctrl[NUM_CH], ch_src[NUM_CH], etc.)
// which Migen cannot connect to directly.  This wrapper presents flat packed
// ports and converts internally.
//
// For N channels, the flat ports are NUM_CH*32 bits wide for ctrl/src/dst,
// NUM_CH*16 for count/remain.
// =============================================================================

`timescale 1ns/1ps

import dmac_pkg::*;

module dmac_top_wrap #(
  parameter int NUM_CH = 1
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        global_enable,

  // Per-channel config (flat packed: ch0 in LSBs)
  input  logic [NUM_CH*32-1:0] ch_ctrl_flat,
  input  logic [NUM_CH*32-1:0] ch_src_flat,
  input  logic [NUM_CH*32-1:0] ch_dst_flat,
  input  logic [NUM_CH*16-1:0] ch_count_flat,
  input  logic [NUM_CH-1:0]    ch_start,
  input  logic [NUM_CH-1:0]    ch_abort,

  // Per-channel status
  output logic [NUM_CH-1:0]    ch_busy,
  output logic [NUM_CH-1:0]    ch_tc,
  output logic [NUM_CH-1:0]    ch_ht,
  output logic [NUM_CH-1:0]    ch_te,
  output logic [NUM_CH*16-1:0] ch_remain_flat,

  // Bus master
  output logic              bus_req,
  output logic              bus_we,
  output logic [31:0]       bus_addr,
  output logic [31:0]       bus_wdata,
  output logic [1:0]        bus_size,
  input  logic              bus_gnt,
  input  logic              bus_rvalid,
  input  logic [31:0]       bus_rdata,
  input  logic              bus_err,

  // DRQ/DACK
  input  logic [NUM_CH-1:0] drq_i,
  output logic [NUM_CH-1:0] dack_o,

  // IRQ and version
  output logic              irq_o,
  output logic [31:0]       version_o
);

  // ── Unpack flat ports into arrays ──────────────────────────────────────
  logic [31:0] ch_ctrl   [NUM_CH];
  logic [31:0] ch_src    [NUM_CH];
  logic [31:0] ch_dst    [NUM_CH];
  logic [15:0] ch_count  [NUM_CH];
  logic [15:0] ch_remain [NUM_CH];

  for (genvar g = 0; g < NUM_CH; g++) begin : gen_unpack
    assign ch_ctrl[g]  = ch_ctrl_flat[g*32 +: 32];
    assign ch_src[g]   = ch_src_flat[g*32 +: 32];
    assign ch_dst[g]   = ch_dst_flat[g*32 +: 32];
    assign ch_count[g] = ch_count_flat[g*16 +: 16];
    assign ch_remain_flat[g*16 +: 16] = ch_remain[g];
  end

  // ── Instantiate dmac_top ───────────────────────────────────────────────
  dmac_top #(.NUM_CH(NUM_CH)) u_dmac (
    .clk           (clk),
    .rst_n         (rst_n),
    .global_enable (global_enable),
    .ch_ctrl       (ch_ctrl),
    .ch_src        (ch_src),
    .ch_dst        (ch_dst),
    .ch_count      (ch_count),
    .ch_start      (ch_start),
    .ch_abort      (ch_abort),
    .ch_busy       (ch_busy),
    .ch_tc         (ch_tc),
    .ch_ht         (ch_ht),
    .ch_te         (ch_te),
    .ch_remain     (ch_remain),
    .bus_req       (bus_req),
    .bus_we        (bus_we),
    .bus_addr      (bus_addr),
    .bus_wdata     (bus_wdata),
    .bus_size      (bus_size),
    .bus_gnt       (bus_gnt),
    .bus_rvalid    (bus_rvalid),
    .bus_rdata     (bus_rdata),
    .bus_err       (bus_err),
    .drq_i         (drq_i),
    .dack_o        (dack_o),
    .irq_o         (irq_o),
    .version_o     (version_o)
  );

endmodule : dmac_top_wrap
