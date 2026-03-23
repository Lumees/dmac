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
// DMAC UVM Testbench -- Driver
// =============================================================================
// Drives dmac_top_tb via the virtual interface clocking block.
// Protocol per DUT spec:
//   1. Preload source data into mock memory via mem_we port.
//   2. Program channel registers (ctrl, src, dst, count).
//   3. Assert global_enable, pulse ch_start for one cycle.
//   4. Wait for ch_tc or ch_te, capture completion status.
// =============================================================================

`ifndef DMAC_DRIVER_SV
`define DMAC_DRIVER_SV

`include "uvm_macros.svh"

class dmac_driver extends uvm_driver #(dmac_seq_item);

  import dmac_pkg::*;

  `uvm_component_utils(dmac_driver)

  // Virtual interface handle
  virtual dmac_if vif;

  // Max cycles to wait for transfer completion
  localparam int DONE_TIMEOUT = 10000;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  // ---------------------------------------------------------------------------
  // build_phase: retrieve virtual interface from config_db
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual dmac_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "dmac_driver: cannot get virtual interface from config_db")
  endfunction : build_phase

  // ---------------------------------------------------------------------------
  // run_phase: main driver loop
  // ---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    dmac_seq_item req, rsp;

    // Initialise all driven signals to safe defaults
    init_signals();

    // Wait for reset to deassert
    @(posedge vif.clk);
    wait (vif.rst_n === 1'b1);
    @(posedge vif.clk);

    forever begin
      // Get next item from sequencer
      seq_item_port.get_next_item(req);
      `uvm_info("DRV", $sformatf("Driving: %s", req.convert2string()), UVM_HIGH)

      // Clone for response
      rsp = dmac_seq_item::type_id::create("rsp");
      rsp.copy(req);

      // ------------------------------------------------------------------
      // Step 1: Preload source data into mock memory
      // ------------------------------------------------------------------
      preload_memory(req);

      // ------------------------------------------------------------------
      // Step 2: Program channel registers and pulse start
      // ------------------------------------------------------------------
      drive_channel(req);

      // ------------------------------------------------------------------
      // Step 3: Wait for completion and capture status
      // ------------------------------------------------------------------
      capture_completion(req.channel, rsp);

      // Return response to sequence
      seq_item_port.item_done(rsp);
    end
  endtask : run_phase

  // ---------------------------------------------------------------------------
  // init_signals: set all driven signals to safe defaults
  // ---------------------------------------------------------------------------
  task init_signals();
    vif.driver_cb.global_enable <= 1'b0;
    vif.driver_cb.ch_start      <= '0;
    vif.driver_cb.ch_abort      <= '0;
    vif.driver_cb.drq_i         <= '0;
    vif.driver_cb.mem_we        <= 1'b0;
    vif.driver_cb.mem_addr      <= '0;
    vif.driver_cb.mem_wdata     <= '0;
    for (int i = 0; i < N_CH; i++) begin
      vif.driver_cb.ch_ctrl[i]  <= '0;
      vif.driver_cb.ch_src[i]   <= '0;
      vif.driver_cb.ch_dst[i]   <= '0;
      vif.driver_cb.ch_count[i] <= '0;
    end
  endtask : init_signals

  // ---------------------------------------------------------------------------
  // preload_memory: write source data into mock memory via mem_we port
  // ---------------------------------------------------------------------------
  task preload_memory(dmac_seq_item item);
    for (int i = 0; i < item.src_data.size(); i++) begin
      @(vif.driver_cb);
      vif.driver_cb.mem_we    <= 1'b1;
      vif.driver_cb.mem_addr  <= item.src_addr + (i * 4);
      vif.driver_cb.mem_wdata <= item.src_data[i];
    end
    @(vif.driver_cb);
    vif.driver_cb.mem_we <= 1'b0;

    `uvm_info("DRV",
      $sformatf("Preloaded %0d words at src_addr=%h",
        item.src_data.size(), item.src_addr),
      UVM_HIGH)
  endtask : preload_memory

  // ---------------------------------------------------------------------------
  // drive_channel: program registers, assert global_enable, pulse ch_start
  // ---------------------------------------------------------------------------
  task drive_channel(dmac_seq_item item);
    int ch;
    ch = item.channel;

    @(vif.driver_cb);
    vif.driver_cb.ch_ctrl[ch]  <= item.ctrl;
    vif.driver_cb.ch_src[ch]   <= item.src_addr;
    vif.driver_cb.ch_dst[ch]   <= item.dst_addr;
    vif.driver_cb.ch_count[ch] <= item.xfer_count;
    vif.driver_cb.global_enable <= 1'b1;

    @(vif.driver_cb);
    vif.driver_cb.ch_start[ch] <= 1'b1;

    @(vif.driver_cb);
    vif.driver_cb.ch_start[ch] <= 1'b0;

    `uvm_info("DRV",
      $sformatf("Channel %0d started: ctrl=%h src=%h dst=%h cnt=%0d",
        ch, item.ctrl, item.src_addr, item.dst_addr, item.xfer_count),
      UVM_HIGH)
  endtask : drive_channel

  // ---------------------------------------------------------------------------
  // capture_completion: wait for ch_tc or ch_te on the given channel
  // ---------------------------------------------------------------------------
  task capture_completion(int ch, dmac_seq_item rsp);
    int timeout;

    timeout = 0;
    forever begin
      @(vif.driver_cb);
      if (vif.driver_cb.ch_tc[ch] === 1'b1) begin
        rsp.completed = 1'b1;
        rsp.error     = 1'b0;
        `uvm_info("DRV",
          $sformatf("Channel %0d transfer complete (TC)", ch),
          UVM_HIGH)
        return;
      end
      if (vif.driver_cb.ch_te[ch] === 1'b1) begin
        rsp.completed = 1'b0;
        rsp.error     = 1'b1;
        `uvm_info("DRV",
          $sformatf("Channel %0d transfer error (TE)", ch),
          UVM_HIGH)
        return;
      end
      timeout++;
      if (timeout >= DONE_TIMEOUT)
        `uvm_fatal("DRV_TIMEOUT",
          $sformatf("Channel %0d: neither ch_tc nor ch_te asserted after %0d cycles",
            ch, DONE_TIMEOUT))
    end
  endtask : capture_completion

endclass : dmac_driver

`endif // DMAC_DRIVER_SV
