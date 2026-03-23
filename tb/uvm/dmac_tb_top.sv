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
// DMAC UVM Testbench -- Top-level Module
// =============================================================================
// Instantiates:
//   - dmac_top_tb DUT (wrapper with built-in mock memory)
//   - Clock generator (10 ns period)
//   - Reset sequence (active-low, deassert after 10 cycles)
//   - dmac_if virtual interface
//   - UVM config_db registration
//   - run_test() kick-off
//
// Simulation plusargs:
//   +UVM_TESTNAME=<test>   (e.g., dmac_directed_test, dmac_random_test)
// =============================================================================

`timescale 1ns/1ps

`include "uvm_macros.svh"

import uvm_pkg::*;
import dmac_pkg::*;

// Include all testbench files in order of dependency
`include "dmac_seq_item.sv"
`include "dmac_if.sv"
`include "dmac_driver.sv"
`include "dmac_monitor.sv"
`include "dmac_scoreboard.sv"
`include "dmac_coverage.sv"
`include "dmac_agent.sv"
`include "dmac_env.sv"
`include "dmac_sequences.sv"
`include "dmac_tests.sv"

module dmac_tb_top;

  // ---------------------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  // 10 ns period -> 100 MHz
  initial clk = 1'b0;
  always #5ns clk = ~clk;

  // Reset: assert for 10 cycles, then release
  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    @(negedge clk);   // deassert on falling edge for clean setup
    rst_n = 1'b1;
    `uvm_info("TB_TOP", "Reset deasserted", UVM_MEDIUM)
  end

  // ---------------------------------------------------------------------------
  // Virtual interface instantiation
  // ---------------------------------------------------------------------------
  dmac_if dut_if (.clk(clk), .rst_n(rst_n));

  // ---------------------------------------------------------------------------
  // DUT instantiation (dmac_top_tb wrapper with built-in mock memory)
  // ---------------------------------------------------------------------------
  dmac_top_tb #(
    .NUM_CH   (dmac_pkg::N_CH),
    .MEM_SIZE (1024)
  ) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .global_enable  (dut_if.global_enable),

    // Per-channel config
    .ch_ctrl        (dut_if.ch_ctrl),
    .ch_src         (dut_if.ch_src),
    .ch_dst         (dut_if.ch_dst),
    .ch_count       (dut_if.ch_count),
    .ch_start       (dut_if.ch_start),
    .ch_abort       (dut_if.ch_abort),

    // Per-channel status
    .ch_busy        (dut_if.ch_busy),
    .ch_tc          (dut_if.ch_tc),
    .ch_ht          (dut_if.ch_ht),
    .ch_te          (dut_if.ch_te),
    .ch_remain      (dut_if.ch_remain),

    // DRQ/DACK
    .drq_i          (dut_if.drq_i),
    .dack_o         (dut_if.dack_o),

    // IRQ and version
    .irq_o          (dut_if.irq_o),
    .version_o      (dut_if.version_o),

    // Memory preload port
    .mem_we         (dut_if.mem_we),
    .mem_addr       (dut_if.mem_addr),
    .mem_wdata      (dut_if.mem_wdata),
    .mem_rdata      (dut_if.mem_rdata)
  );

  // ---------------------------------------------------------------------------
  // UVM config_db: register virtual interface
  // ---------------------------------------------------------------------------
  initial begin
    uvm_config_db #(virtual dmac_if)::set(
      null,          // from context (global)
      "uvm_test_top.*",
      "vif",
      dut_if
    );

    `uvm_info("TB_TOP",
      "DMAC DUT instantiated, vif registered in config_db",
      UVM_MEDIUM)
  end

  // ---------------------------------------------------------------------------
  // Simulation timeout watchdog (prevents infinite hang on protocol errors)
  // ---------------------------------------------------------------------------
  initial begin
    // Allow enough time for stress test (100 txns x ~500 cycles x 10 ns)
    #5ms;
    `uvm_fatal("WATCHDOG", "Simulation timeout -- check for protocol deadlock")
  end

  // ---------------------------------------------------------------------------
  // Waveform dump (uncomment for VCD/FSDB capture)
  // ---------------------------------------------------------------------------
  // initial begin
  //   $dumpfile("dmac_tb.vcd");
  //   $dumpvars(0, dmac_tb_top);
  // end

  // ---------------------------------------------------------------------------
  // Start UVM test
  // ---------------------------------------------------------------------------
  initial begin
    run_test();
  end

endmodule : dmac_tb_top
