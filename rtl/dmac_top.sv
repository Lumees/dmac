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
// DMA Controller IP — Top-level wrapper
// =============================================================================

`timescale 1ns/1ps

import dmac_pkg::*;

module dmac_top #(
  parameter int NUM_CH = N_CH
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        global_enable,

  // Per-channel config
  input  logic [31:0] ch_ctrl   [NUM_CH],
  input  logic [31:0] ch_src    [NUM_CH],
  input  logic [31:0] ch_dst    [NUM_CH],
  input  logic [15:0] ch_count  [NUM_CH],
  input  logic [NUM_CH-1:0] ch_start,
  input  logic [NUM_CH-1:0] ch_abort,

  // Per-channel status
  output logic [NUM_CH-1:0] ch_busy,
  output logic [NUM_CH-1:0] ch_tc,
  output logic [NUM_CH-1:0] ch_ht,
  output logic [NUM_CH-1:0] ch_te,
  output logic [15:0]       ch_remain [NUM_CH],

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

  dmac_core #(.NUM_CH(NUM_CH)) u_core (
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

endmodule : dmac_top
