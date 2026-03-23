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
// DMAC UVM Testbench -- Monitor
// =============================================================================
// Passive monitor with two logical sub-monitors:
//
//   Input sub-monitor  : captures ch_start pulse and channel configuration
//   Output sub-monitor : captures ch_tc/ch_te completion pulses
//
// The input analysis port emits items when a channel is started; the output
// port emits items when a channel completes. The scoreboard correlates them
// via FIFO ordering (channels are started and complete in order for single-
// channel tests; multi-channel tests use the context path).
// =============================================================================

`ifndef DMAC_MONITOR_SV
`define DMAC_MONITOR_SV

`include "uvm_macros.svh"

class dmac_monitor extends uvm_monitor;

  import dmac_pkg::*;

  `uvm_component_utils(dmac_monitor)

  // Analysis ports
  uvm_analysis_port #(dmac_seq_item) ap_in;    // stimuli accepted by DUT
  uvm_analysis_port #(dmac_seq_item) ap_out;   // results produced by DUT

  // Virtual interface (read-only via monitor_cb)
  virtual dmac_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction : new

  // ---------------------------------------------------------------------------
  // build_phase
  // ---------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap_in  = new("ap_in",  this);
    ap_out = new("ap_out", this);

    if (!uvm_config_db #(virtual dmac_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "dmac_monitor: cannot get virtual interface from config_db")
  endfunction : build_phase

  // ---------------------------------------------------------------------------
  // run_phase: fork both sub-monitors
  // ---------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    fork
      monitor_input();
      monitor_output();
    join
  endtask : run_phase

  // ---------------------------------------------------------------------------
  // monitor_input: watch for ch_start pulses and capture channel config
  // ---------------------------------------------------------------------------
  task monitor_input();
    dmac_seq_item item;
    forever begin
      @(vif.monitor_cb);
      for (int ch = 0; ch < N_CH; ch++) begin
        if (vif.monitor_cb.ch_start[ch] === 1'b1) begin
          item = dmac_seq_item::type_id::create("mon_in_item");
          item.channel    = ch;
          item.ctrl       = vif.monitor_cb.ch_ctrl[ch];
          item.src_addr   = vif.monitor_cb.ch_src[ch];
          item.dst_addr   = vif.monitor_cb.ch_dst[ch];
          item.xfer_count = vif.monitor_cb.ch_count[ch];

          // Extract config fields
          item.xfer_type  = xfer_type_t'(item.ctrl[CTRL_XTYPE_LO+1  : CTRL_XTYPE_LO]);
          item.xfer_width = xfer_width_t'(item.ctrl[CTRL_XWIDTH_LO+1 : CTRL_XWIDTH_LO]);
          item.src_mode   = addr_mode_t'(item.ctrl[CTRL_SRCM_LO+1   : CTRL_SRCM_LO]);
          item.dst_mode   = addr_mode_t'(item.ctrl[CTRL_DSTM_LO+1   : CTRL_DSTM_LO]);

          `uvm_info("MON_IN",
            $sformatf("Channel %0d started: ctrl=%h src=%h dst=%h cnt=%0d",
              ch, item.ctrl, item.src_addr, item.dst_addr, item.xfer_count),
            UVM_HIGH)
          ap_in.write(item);
        end
      end
    end
  endtask : monitor_input

  // ---------------------------------------------------------------------------
  // monitor_output: watch for ch_tc / ch_te assertion
  // ---------------------------------------------------------------------------
  task monitor_output();
    dmac_seq_item item;
    forever begin
      @(vif.monitor_cb);
      for (int ch = 0; ch < N_CH; ch++) begin
        if (vif.monitor_cb.ch_tc[ch] === 1'b1 ||
            vif.monitor_cb.ch_te[ch] === 1'b1) begin
          item = dmac_seq_item::type_id::create("mon_out_item");
          item.channel   = ch;
          item.completed = vif.monitor_cb.ch_tc[ch];
          item.error     = vif.monitor_cb.ch_te[ch];

          `uvm_info("MON_OUT",
            $sformatf("Channel %0d done: tc=%0b te=%0b",
              ch, item.completed, item.error),
            UVM_HIGH)
          ap_out.write(item);
        end
      end
    end
  endtask : monitor_output

endclass : dmac_monitor

`endif // DMAC_MONITOR_SV
