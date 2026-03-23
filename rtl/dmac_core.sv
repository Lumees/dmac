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
// DMA Controller IP — Core integration
// =============================================================================
// Instantiates N_CH channels + 1 arbiter. Exposes per-channel register
// interface and a single muxed bus master port.
// =============================================================================

`timescale 1ns/1ps

import dmac_pkg::*;

module dmac_core #(
  parameter int NUM_CH = N_CH
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        global_enable,

  // ── Per-channel configuration (from register file) ────────────────────────
  input  logic [31:0] ch_ctrl   [NUM_CH],
  input  logic [31:0] ch_src    [NUM_CH],
  input  logic [31:0] ch_dst    [NUM_CH],
  input  logic [15:0] ch_count  [NUM_CH],
  input  logic [NUM_CH-1:0] ch_start,    // per-channel start pulse
  input  logic [NUM_CH-1:0] ch_abort,    // per-channel abort pulse

  // ── Per-channel status ────────────────────────────────────────────────────
  output logic [NUM_CH-1:0] ch_busy,
  output logic [NUM_CH-1:0] ch_tc,       // transfer complete pulse
  output logic [NUM_CH-1:0] ch_ht,       // half-transfer pulse
  output logic [NUM_CH-1:0] ch_te,       // transfer error pulse
  output logic [15:0]       ch_remain [NUM_CH],

  // ── Muxed bus master (to AXI4-Lite / Wishbone master FSM) ─────────────────
  output logic              bus_req,
  output logic              bus_we,
  output logic [31:0]       bus_addr,
  output logic [31:0]       bus_wdata,
  output logic [1:0]        bus_size,
  input  logic              bus_gnt,
  input  logic              bus_rvalid,
  input  logic [31:0]       bus_rdata,
  input  logic              bus_err,

  // ── DRQ/DACK ─────────────────────────────────────────────────────────────
  input  logic [NUM_CH-1:0] drq_i,
  output logic [NUM_CH-1:0] dack_o,

  // ── Combined IRQ ──────────────────────────────────────────────────────────
  output logic              irq_o,
  output logic [31:0]       version_o
);

  assign version_o = IP_VERSION;

  // ── Per-channel bus signals ───────────────────────────────────────────────
  logic [NUM_CH-1:0] per_ch_req;
  logic              per_ch_we     [NUM_CH];
  logic [31:0]       per_ch_addr   [NUM_CH];
  logic [31:0]       per_ch_wdata  [NUM_CH];
  logic [1:0]        per_ch_size   [NUM_CH];

  // ── Arbiter ───────────────────────────────────────────────────────────────
  logic [NUM_CH-1:0] ch_gnt;
  logic [$clog2(NUM_CH>1?NUM_CH:2)-1:0] winner;
  logic [1:0] ch_pri [NUM_CH];

  generate
    for (genvar c = 0; c < NUM_CH; c++)
      assign ch_pri[c] = ch_ctrl[c][CTRL_PRI_LO+1:CTRL_PRI_LO];
  endgenerate

  dmac_arbiter #(.NUM_CH(NUM_CH)) u_arb (
    .clk       (clk),
    .rst_n     (rst_n),
    .ch_req    (per_ch_req),
    .ch_pri    (ch_pri),
    .ch_gnt    (ch_gnt),
    .winner_id (winner)
  );

  // ── Channels ──────────────────────────────────────────────────────────────
  generate
    for (genvar c = 0; c < NUM_CH; c++) begin : gen_ch
      dmac_channel #(.BUF_DEPTH(FIFO_DEPTH)) u_ch (
        .clk          (clk),
        .rst_n        (rst_n),
        .ctrl_i       (ch_ctrl[c]),
        .src_addr_i   (ch_src[c]),
        .dst_addr_i   (ch_dst[c]),
        .xfer_count_i (ch_count[c]),
        .start_i      (ch_start[c] & global_enable),
        .abort_i      (ch_abort[c]),
        .busy_o       (ch_busy[c]),
        .tc_o         (ch_tc[c]),
        .ht_o         (ch_ht[c]),
        .te_o         (ch_te[c]),
        .remain_o     (ch_remain[c]),
        .bus_req_o    (per_ch_req[c]),
        .bus_gnt_i    (ch_gnt[c]),
        .bus_we_o     (per_ch_we[c]),
        .bus_addr_o   (per_ch_addr[c]),
        .bus_wdata_o  (per_ch_wdata[c]),
        .bus_size_o   (per_ch_size[c]),
        .bus_rvalid_i (bus_rvalid & ch_gnt[c]),
        .bus_rdata_i  (bus_rdata),
        .bus_err_i    (bus_err & ch_gnt[c]),
        .drq_i        (drq_i[c]),
        .dack_o       (dack_o[c])
      );
    end
  endgenerate

  // ── Bus master mux (winner channel drives the bus) ────────────────────────
  // Gate outputs to zero when no channel is requesting to prevent stale data
  always_comb begin
    bus_req   = |per_ch_req;
    bus_we    = bus_req ? per_ch_we[winner]    : 1'b0;
    bus_addr  = bus_req ? per_ch_addr[winner]  : '0;
    bus_wdata = bus_req ? per_ch_wdata[winner] : '0;
    bus_size  = bus_req ? per_ch_size[winner]  : 2'b00;
  end

  // ── Combined IRQ ──────────────────────────────────────────────────────────
  assign irq_o = |ch_tc | |ch_ht | |ch_te;

endmodule : dmac_core
