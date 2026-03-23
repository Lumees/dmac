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
// DMAC UVM Testbench -- Scoreboard
// =============================================================================
// Self-checking scoreboard:
//   - Receives full-context items via ae_context (from sequence)
//   - Receives DUT output items via ae_out (from output monitor)
//   - After transfer complete, reads destination memory and compares
//     against source data from the context item
//   - Reports pass/fail counts in check_phase
// =============================================================================

`ifndef DMAC_SCOREBOARD_SV
`define DMAC_SCOREBOARD_SV

`include "uvm_macros.svh"

class dmac_scoreboard extends uvm_scoreboard;

  import dmac_pkg::*;

  `uvm_component_utils(dmac_scoreboard)

  // TLM FIFOs fed from the monitor / sequence analysis ports
  uvm_tlm_analysis_fifo #(dmac_seq_item) fifo_in;
  uvm_tlm_analysis_fifo #(dmac_seq_item) fifo_out;
  uvm_tlm_analysis_fifo #(dmac_seq_item) fifo_context;

  // Analysis exports (connected in env)
  uvm_analysis_export #(dmac_seq_item) ae_in;
  uvm_analysis_export #(dmac_seq_item) ae_out;
  uvm_analysis_export #(dmac_seq_item) ae_context;

  // Virtual interface handle (for reading destination memory)
  virtual dmac_if vif;

  // Counters
  int unsigned pass_count;
  int unsigned fail_count;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    pass_count = 0;
    fail_count = 0;
  endfunction : new

  // ---------------------------------------------------------------------------
  // build_phase
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    fifo_in      = new("fifo_in",      this);
    fifo_out     = new("fifo_out",     this);
    fifo_context = new("fifo_context", this);
    ae_in        = new("ae_in",        this);
    ae_out       = new("ae_out",       this);
    ae_context   = new("ae_context",   this);

    if (!uvm_config_db #(virtual dmac_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "dmac_scoreboard: cannot get virtual interface from config_db")
  endfunction : build_phase

  // ---------------------------------------------------------------------------
  // connect_phase: wire exports to FIFOs
  // ---------------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    ae_in.connect      (fifo_in.analysis_export);
    ae_out.connect     (fifo_out.analysis_export);
    ae_context.connect (fifo_context.analysis_export);
  endfunction : connect_phase

  // ---------------------------------------------------------------------------
  // run_phase: drain FIFOs and check
  // ---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    dmac_seq_item stim_item, resp_item, ctx_item;

    forever begin
      // Wait for a DUT output
      fifo_out.get(resp_item);

      // Get matching stimulus (in-order pipeline)
      fifo_in.get(stim_item);

      // Get full context (sent by the sequence)
      fifo_context.get(ctx_item);

      // Check transfer result
      if (resp_item.error) begin
        fail_count++;
        `uvm_error("SB_FAIL",
          $sformatf("FAIL | ch=%0d | Transfer error reported by DUT",
            resp_item.channel))
      end else if (resp_item.completed) begin
        // Compare destination memory contents against source data
        check_memory(ctx_item);
      end else begin
        fail_count++;
        `uvm_error("SB_FAIL",
          $sformatf("FAIL | ch=%0d | Neither TC nor TE asserted",
            resp_item.channel))
      end
    end
  endtask : run_phase

  // ---------------------------------------------------------------------------
  // check_memory: read destination memory and compare against source data
  // ---------------------------------------------------------------------------
  task check_memory(dmac_seq_item ctx_item);
    logic [31:0] dst_word;
    logic [31:0] exp_word;
    int errors;

    errors = 0;

    // Allow a couple of cycles for memory writes to settle
    @(posedge vif.clk);
    @(posedge vif.clk);

    for (int i = 0; i < ctx_item.xfer_count; i++) begin
      // Read destination memory via mem port
      @(posedge vif.clk);
      vif.mem_we   = 1'b0;
      vif.mem_addr = ctx_item.dst_addr + (i * 4);
      @(posedge vif.clk);
      dst_word = vif.mem_rdata;
      exp_word = ctx_item.src_data[i];

      if (dst_word !== exp_word) begin
        errors++;
        `uvm_error("SB_MEM",
          $sformatf("MISMATCH | ch=%0d word[%0d] | dst_addr=%h | exp=%h got=%h",
            ctx_item.channel, i, ctx_item.dst_addr + (i * 4),
            exp_word, dst_word))
      end
    end

    if (errors == 0) begin
      pass_count++;
      `uvm_info("SB_PASS",
        $sformatf("PASS | ch=%0d | %0d words verified: src=%h -> dst=%h",
          ctx_item.channel, ctx_item.xfer_count,
          ctx_item.src_addr, ctx_item.dst_addr),
        UVM_MEDIUM)
    end else begin
      fail_count++;
      `uvm_error("SB_FAIL",
        $sformatf("FAIL | ch=%0d | %0d/%0d words mismatched",
          ctx_item.channel, errors, ctx_item.xfer_count))
    end
  endtask : check_memory

  // ---------------------------------------------------------------------------
  // check_phase: summary report
  // ---------------------------------------------------------------------------
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    `uvm_info("SB_SUMMARY",
      $sformatf("Scoreboard results: PASS=%0d  FAIL=%0d",
        pass_count, fail_count),
      UVM_NONE)

    if (fail_count > 0)
      `uvm_error("SB_SUMMARY",
        $sformatf("%0d transaction(s) FAILED -- see above for details", fail_count))

    if (!fifo_in.is_empty())
      `uvm_warning("SB_LEFTOVERS",
        $sformatf("%0d input item(s) unmatched in fifo_in at end of test",
          fifo_in.used()))

    if (!fifo_out.is_empty())
      `uvm_warning("SB_LEFTOVERS",
        $sformatf("%0d output item(s) unmatched in fifo_out at end of test",
          fifo_out.used()))
  endfunction : check_phase

endclass : dmac_scoreboard

`endif // DMAC_SCOREBOARD_SV
