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
// DMAC UVM Testbench -- Virtual Interface
// =============================================================================
// Provides a SystemVerilog interface wrapping all dmac_top_tb ports.
// NUM_CH is fixed to the package default (4).
// =============================================================================

`timescale 1ns/1ps

interface dmac_if (input logic clk, input logic rst_n);

  import dmac_pkg::*;

  localparam int NUM_CH   = N_CH;
  localparam int MEM_SIZE = 1024;

  // ---------------------------------------------------------------------------
  // DUT ports (all driven/sampled here)
  // ---------------------------------------------------------------------------

  // Global
  logic              global_enable;

  // Per-channel configuration
  logic [31:0]       ch_ctrl   [NUM_CH];
  logic [31:0]       ch_src    [NUM_CH];
  logic [31:0]       ch_dst    [NUM_CH];
  logic [15:0]       ch_count  [NUM_CH];
  logic [NUM_CH-1:0] ch_start;
  logic [NUM_CH-1:0] ch_abort;

  // Per-channel status
  logic [NUM_CH-1:0] ch_busy;
  logic [NUM_CH-1:0] ch_tc;
  logic [NUM_CH-1:0] ch_ht;
  logic [NUM_CH-1:0] ch_te;
  logic [15:0]       ch_remain [NUM_CH];

  // DRQ/DACK
  logic [NUM_CH-1:0] drq_i;
  logic [NUM_CH-1:0] dack_o;

  // IRQ and version
  logic              irq_o;
  logic [31:0]       version_o;

  // Memory preload port (for test setup)
  logic              mem_we;
  logic [31:0]       mem_addr;
  logic [31:0]       mem_wdata;
  logic [31:0]       mem_rdata;

  // ---------------------------------------------------------------------------
  // Driver clocking block (active driving on posedge; sample 1-step before)
  // ---------------------------------------------------------------------------
  clocking driver_cb @(posedge clk);
    default input  #1step
            output #1step;

    // Global
    output global_enable;

    // Per-channel config -- driven by driver
    output ch_ctrl;
    output ch_src;
    output ch_dst;
    output ch_count;
    output ch_start;
    output ch_abort;

    // Per-channel status -- read back
    input  ch_busy;
    input  ch_tc;
    input  ch_ht;
    input  ch_te;
    input  ch_remain;

    // DRQ/DACK
    output drq_i;
    input  dack_o;

    // IRQ and version
    input  irq_o;
    input  version_o;

    // Memory preload
    output mem_we;
    output mem_addr;
    output mem_wdata;
    input  mem_rdata;
  endclocking : driver_cb

  // ---------------------------------------------------------------------------
  // Monitor clocking block (passive -- only inputs)
  // ---------------------------------------------------------------------------
  clocking monitor_cb @(posedge clk);
    default input #1step;

    input global_enable;

    input ch_ctrl;
    input ch_src;
    input ch_dst;
    input ch_count;
    input ch_start;
    input ch_abort;

    input ch_busy;
    input ch_tc;
    input ch_ht;
    input ch_te;
    input ch_remain;

    input drq_i;
    input dack_o;

    input irq_o;
    input version_o;

    input mem_we;
    input mem_addr;
    input mem_wdata;
    input mem_rdata;
  endclocking : monitor_cb

  // ---------------------------------------------------------------------------
  // Modports
  // ---------------------------------------------------------------------------
  modport driver_mp  (clocking driver_cb,  input clk, input rst_n);
  modport monitor_mp (clocking monitor_cb, input clk, input rst_n);

endinterface : dmac_if
