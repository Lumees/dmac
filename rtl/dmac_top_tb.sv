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

`timescale 1ns/1ps

import dmac_pkg::*;

module dmac_top_tb #(
  parameter int NUM_CH = N_CH,
  parameter int MEM_SIZE = 1024  // words
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

  // DRQ/DACK
  input  logic [NUM_CH-1:0] drq_i,
  output logic [NUM_CH-1:0] dack_o,

  output logic              irq_o,
  output logic [31:0]       version_o,

  // Memory preload port (for test setup)
  input  logic              mem_we,
  input  logic [31:0]       mem_addr,
  input  logic [31:0]       mem_wdata,
  output logic [31:0]       mem_rdata
);

  // ── Internal bus signals ──────────────────────────────────────────────────
  logic              bus_req, bus_we;
  logic [31:0]       bus_addr, bus_wdata, bus_rdata;
  logic [1:0]        bus_size;
  logic              bus_gnt, bus_rvalid, bus_err;

  // ── Simple mock memory ────────────────────────────────────────────────────
  logic [31:0] memory [MEM_SIZE];

  assign mem_rdata = memory[mem_addr[11:2]];

  // Bus response: 1-cycle grant, 1-cycle read data
  logic bus_req_d, bus_we_d;
  logic [31:0] bus_addr_d;

  /* verilator lint_off MULTIDRIVEN */
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bus_gnt    <= 1'b0;
      bus_rvalid <= 1'b0;
      bus_rdata  <= '0;
      bus_err    <= 1'b0;
      bus_req_d  <= 1'b0;
      bus_we_d   <= 1'b0;
      bus_addr_d <= '0;
    end else begin
      // Memory preload (test setup)
      if (mem_we)
        memory[mem_addr[11:2]] <= mem_wdata;

      bus_gnt    <= bus_req;
      bus_req_d  <= bus_req;
      bus_we_d   <= bus_we;
      bus_addr_d <= bus_addr;
      bus_err    <= 1'b0;

      // Write: capture on grant cycle
      if (bus_req_d && bus_we_d)
        memory[bus_addr_d[11:2]] <= bus_wdata;

      // Read: return data 1 cycle after grant
      bus_rvalid <= bus_req_d && !bus_we_d;
      bus_rdata  <= memory[bus_addr_d[11:2]];
    end
  end
  /* verilator lint_on MULTIDRIVEN */

  // ── DUT ───────────────────────────────────────────────────────────────────
  dmac_top #(.NUM_CH(NUM_CH)) u_dut (
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

endmodule : dmac_top_tb
