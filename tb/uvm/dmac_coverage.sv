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
// DMAC UVM Testbench -- Functional Coverage Collector
// =============================================================================
// Subscribes to the context analysis port.
// Covergroups:
//   cg_dmac : xfer_type x width x src_mode x dst_mode x channel_count (with cross)
// =============================================================================

`ifndef DMAC_COVERAGE_SV
`define DMAC_COVERAGE_SV

`include "uvm_macros.svh"

class dmac_coverage extends uvm_subscriber #(dmac_seq_item);

  import dmac_pkg::*;

  `uvm_component_utils(dmac_coverage)

  // Current sampled item fields (written in write() before sampling)
  xfer_type_t    cov_xfer_type;
  xfer_width_t   cov_xfer_width;
  addr_mode_t    cov_src_mode;
  addr_mode_t    cov_dst_mode;
  int unsigned   cov_channel;
  int unsigned   cov_xfer_count;

  // ---------------------------------------------------------------------------
  // Covergroup: DMAC configuration space
  // ---------------------------------------------------------------------------
  covergroup cg_dmac;
    option.per_instance = 1;
    option.name         = "cg_dmac";
    option.comment      = "DMAC transfer type, width, address mode, and channel coverage";

    cp_xfer_type: coverpoint cov_xfer_type {
      bins m2m  = {XFER_M2M};
      bins m2p  = {XFER_M2P};
      bins p2m  = {XFER_P2M};
    }

    cp_xfer_width: coverpoint cov_xfer_width {
      bins w8   = {WIDTH_8};
      bins w16  = {WIDTH_16};
      bins w32  = {WIDTH_32};
    }

    cp_src_mode: coverpoint cov_src_mode {
      bins inc  = {ADDR_INC};
      bins dec  = {ADDR_DEC};
      bins fix  = {ADDR_FIX};
    }

    cp_dst_mode: coverpoint cov_dst_mode {
      bins inc  = {ADDR_INC};
      bins dec  = {ADDR_DEC};
      bins fix  = {ADDR_FIX};
    }

    cp_channel: coverpoint cov_channel {
      bins ch[] = {[0 : N_CH-1]};
    }

    cp_xfer_count: coverpoint cov_xfer_count {
      bins single   = {1};
      bins small    = {[2:4]};
      bins medium   = {[5:16]};
      bins large    = {[17:64]};
    }

    // Cross: xfer_type x width x src_mode x dst_mode x channel
    cx_type_width: cross cp_xfer_type, cp_xfer_width;

    cx_type_width_src_dst: cross cp_xfer_type, cp_xfer_width, cp_src_mode, cp_dst_mode;

    cx_type_channel: cross cp_xfer_type, cp_channel;

    cx_full: cross cp_xfer_type, cp_xfer_width, cp_src_mode, cp_dst_mode, cp_channel;
  endgroup : cg_dmac

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_dmac = new();
  endfunction : new

  // ---------------------------------------------------------------------------
  // write(): called by analysis port on each context transaction
  // ---------------------------------------------------------------------------
  function void write(dmac_seq_item t);
    cov_xfer_type  = t.xfer_type;
    cov_xfer_width = t.xfer_width;
    cov_src_mode   = t.src_mode;
    cov_dst_mode   = t.dst_mode;
    cov_channel    = t.channel;
    cov_xfer_count = t.xfer_count;

    cg_dmac.sample();

    `uvm_info("COV",
      $sformatf("Sampled: ch=%0d type=%s width=%s src=%s dst=%s cnt=%0d",
        cov_channel, cov_xfer_type.name(), cov_xfer_width.name(),
        cov_src_mode.name(), cov_dst_mode.name(), cov_xfer_count),
      UVM_DEBUG)
  endfunction : write

  // ---------------------------------------------------------------------------
  // report_phase: print coverage summary
  // ---------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    `uvm_info("COV_REPORT",
      $sformatf("cg_dmac coverage: %.2f%%", cg_dmac.get_coverage()),
      UVM_NONE)
  endfunction : report_phase

endclass : dmac_coverage

`endif // DMAC_COVERAGE_SV
