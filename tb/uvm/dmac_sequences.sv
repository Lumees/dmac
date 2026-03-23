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
// DMAC UVM Testbench -- Sequences
// =============================================================================
// All sequences in one file. Each sequence:
//   1. Randomises (or hard-codes) a seq_item with source data
//   2. Starts it on the sequencer
//   3. Writes the full item to env.ap_context so the scoreboard reference
//      can compare destination memory against source data.
//
// Sequences access ap_context through a direct handle set in the test's
// build_phase.
// =============================================================================

`ifndef DMAC_SEQUENCES_SV
`define DMAC_SEQUENCES_SV

`include "uvm_macros.svh"

// ============================================================================
// Base sequence
// ============================================================================
class dmac_base_seq extends uvm_sequence #(dmac_seq_item);

  import dmac_pkg::*;

  `uvm_object_utils(dmac_base_seq)

  // Handle to the env's context analysis port -- set by test before starting
  uvm_analysis_port #(dmac_seq_item) ap_context;

  function new(string name = "dmac_base_seq");
    super.new(name);
  endfunction : new

  // Helper: send one item and publish context
  task send_item(dmac_seq_item item);
    start_item(item);
    if (!item.randomize())
      `uvm_fatal("SEQ_RAND", "Failed to randomise seq_item")
    // Post-randomize extracts config fields
    finish_item(item);

    // Publish full item so scoreboard can compare memory
    if (ap_context != null)
      ap_context.write(item);
    else
      `uvm_warning("SEQ_CTX", "ap_context handle is null -- scoreboard may not have config")
  endtask : send_item

  // Helper: send a pre-built (non-randomised) item directly
  task send_fixed_item(dmac_seq_item item);
    start_item(item);
    finish_item(item);
    if (ap_context != null)
      ap_context.write(item);
    else
      `uvm_warning("SEQ_CTX", "ap_context handle is null -- scoreboard may not have config")
  endtask : send_fixed_item

  virtual task body();
    `uvm_warning("SEQ", "dmac_base_seq::body() called -- override in derived class")
  endtask : body

endclass : dmac_base_seq


// ============================================================================
// Directed M2M sequence: 4-word and 8-word transfers on channel 0
// ============================================================================
class dmac_directed_seq extends dmac_base_seq;

  `uvm_object_utils(dmac_directed_seq)

  function new(string name = "dmac_directed_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    dmac_seq_item item;

    // ----------------------------------------------------------------
    // Test 1: 4-word M2M transfer, channel 0, INC/INC, WIDTH_32
    // ----------------------------------------------------------------
    item = dmac_seq_item::type_id::create("m2m_4word");
    item.channel    = 0;
    item.ctrl       = build_ctrl(XFER_M2M, WIDTH_32, ADDR_INC, ADDR_INC, 2'b00);
    item.src_addr   = 32'h0000_0000;
    item.dst_addr   = 32'h0000_0800;
    item.xfer_count = 4;
    item.src_data   = new[4];
    item.src_data[0] = 32'hDEAD_BEEF;
    item.src_data[1] = 32'hCAFE_BABE;
    item.src_data[2] = 32'h1234_5678;
    item.src_data[3] = 32'h9ABC_DEF0;
    item.post_randomize();  // extract config fields
    `uvm_info("SEQ_DIR", "Sending M2M 4-word transfer on channel 0", UVM_MEDIUM)
    send_fixed_item(item);

    // ----------------------------------------------------------------
    // Test 2: 8-word M2M transfer, channel 0, INC/INC, WIDTH_32
    // ----------------------------------------------------------------
    item = dmac_seq_item::type_id::create("m2m_8word");
    item.channel    = 0;
    item.ctrl       = build_ctrl(XFER_M2M, WIDTH_32, ADDR_INC, ADDR_INC, 2'b00);
    item.src_addr   = 32'h0000_0100;
    item.dst_addr   = 32'h0000_0900;
    item.xfer_count = 8;
    item.src_data   = new[8];
    for (int i = 0; i < 8; i++)
      item.src_data[i] = 32'hA000_0000 + i;
    item.post_randomize();
    `uvm_info("SEQ_DIR", "Sending M2M 8-word transfer on channel 0", UVM_MEDIUM)
    send_fixed_item(item);

    // ----------------------------------------------------------------
    // Test 3: 4-word M2M transfer on channel 1 (multi-channel coverage)
    // ----------------------------------------------------------------
    item = dmac_seq_item::type_id::create("m2m_ch1");
    item.channel    = 1;
    item.ctrl       = build_ctrl(XFER_M2M, WIDTH_32, ADDR_INC, ADDR_INC, 2'b01);
    item.src_addr   = 32'h0000_0200;
    item.dst_addr   = 32'h0000_0A00;
    item.xfer_count = 4;
    item.src_data   = new[4];
    item.src_data[0] = 32'hFF00_FF00;
    item.src_data[1] = 32'h00FF_00FF;
    item.src_data[2] = 32'hAAAA_5555;
    item.src_data[3] = 32'h5555_AAAA;
    item.post_randomize();
    `uvm_info("SEQ_DIR", "Sending M2M 4-word transfer on channel 1", UVM_MEDIUM)
    send_fixed_item(item);

  endtask : body

  // Helper: build a ctrl register value
  function logic [31:0] build_ctrl(
    xfer_type_t  xtype,
    xfer_width_t xwidth,
    addr_mode_t  src_mode,
    addr_mode_t  dst_mode,
    logic [1:0]  priority_val
  );
    logic [31:0] c;
    c = '0;
    c[CTRL_ENABLE]                       = 1'b1;
    c[CTRL_IRQ_TC]                       = 1'b1;
    c[CTRL_IRQ_ERR]                      = 1'b1;
    c[CTRL_XTYPE_LO+1  : CTRL_XTYPE_LO] = xtype;
    c[CTRL_XWIDTH_LO+1 : CTRL_XWIDTH_LO] = xwidth;
    c[CTRL_SRCM_LO+1   : CTRL_SRCM_LO]  = src_mode;
    c[CTRL_DSTM_LO+1   : CTRL_DSTM_LO]  = dst_mode;
    c[CTRL_PRI_LO+1    : CTRL_PRI_LO]    = priority_val;
    return c;
  endfunction : build_ctrl

endclass : dmac_directed_seq


// ============================================================================
// Random sequence
// ============================================================================
class dmac_random_seq extends dmac_base_seq;

  `uvm_object_utils(dmac_random_seq)

  int unsigned num_transactions = 20;

  function new(string name = "dmac_random_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    dmac_seq_item item;

    repeat (num_transactions) begin
      item = dmac_seq_item::type_id::create("rand_dmac");
      send_item(item);
    end

    `uvm_info("SEQ_RAND",
      $sformatf("Completed %0d random DMAC transactions", num_transactions),
      UVM_MEDIUM)
  endtask : body

endclass : dmac_random_seq


// ============================================================================
// Stress sequence (back-to-back short transfers)
// ============================================================================
class dmac_stress_seq extends dmac_base_seq;

  `uvm_object_utils(dmac_stress_seq)

  int unsigned num_transactions = 50;

  function new(string name = "dmac_stress_seq");
    super.new(name);
  endfunction : new

  virtual task body();
    dmac_seq_item item;

    repeat (num_transactions) begin
      item = dmac_seq_item::type_id::create("stress_dmac");
      start_item(item);
      // Constrain to short transfers for rapid back-to-back
      if (!item.randomize() with { xfer_count inside {[1:8]}; })
        `uvm_fatal("SEQ_RAND", "Failed to randomise stress seq_item")
      finish_item(item);
      if (ap_context != null) ap_context.write(item);
    end

    `uvm_info("SEQ_STRESS",
      $sformatf("Completed %0d back-to-back stress DMAC transactions", num_transactions),
      UVM_MEDIUM)
  endtask : body

endclass : dmac_stress_seq

`endif // DMAC_SEQUENCES_SV
