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
// DMAC UVM Testbench -- Sequence Item
// =============================================================================
// Represents one complete DMA transfer (stimulus + response).
// =============================================================================

`ifndef DMAC_SEQ_ITEM_SV
`define DMAC_SEQ_ITEM_SV

`include "uvm_macros.svh"

class dmac_seq_item extends uvm_sequence_item;

  import dmac_pkg::*;

  `uvm_object_utils_begin(dmac_seq_item)
    `uvm_field_int        (channel,       UVM_ALL_ON | UVM_DEC)
    `uvm_field_int        (ctrl,          UVM_ALL_ON | UVM_HEX)
    `uvm_field_int        (src_addr,      UVM_ALL_ON | UVM_HEX)
    `uvm_field_int        (dst_addr,      UVM_ALL_ON | UVM_HEX)
    `uvm_field_int        (xfer_count,    UVM_ALL_ON | UVM_DEC)
    `uvm_field_array_int  (src_data,      UVM_ALL_ON | UVM_HEX)
    `uvm_field_int        (completed,     UVM_ALL_ON | UVM_BIN)
    `uvm_field_int        (error,         UVM_ALL_ON | UVM_BIN)
  `uvm_object_utils_end

  // -------------------------------------------------------------------------
  // Stimulus fields (randomised)
  // -------------------------------------------------------------------------
  rand int unsigned     channel;         // channel index (0..NUM_CH-1)
  rand logic [31:0]     ctrl;            // channel control register value
  rand logic [31:0]     src_addr;        // source address (word-aligned)
  rand logic [31:0]     dst_addr;        // destination address (word-aligned)
  rand logic [15:0]     xfer_count;      // number of transfers
  rand logic [31:0]     src_data [];     // source data to preload into memory

  // -------------------------------------------------------------------------
  // Response fields
  // -------------------------------------------------------------------------
  logic                 completed;       // ch_tc asserted
  logic                 error;           // ch_te asserted

  // -------------------------------------------------------------------------
  // Derived config fields (extracted from ctrl)
  // -------------------------------------------------------------------------
  xfer_type_t           xfer_type;
  xfer_width_t          xfer_width;
  addr_mode_t           src_mode;
  addr_mode_t           dst_mode;

  // -------------------------------------------------------------------------
  // Constraints
  // -------------------------------------------------------------------------

  // Channel: valid range
  constraint c_channel {
    channel inside {[0 : N_CH-1]};
  }

  // Transfer count: 1 to 64 words
  constraint c_xfer_count {
    xfer_count inside {[1:64]};
    xfer_count dist { [1:4] := 30, [5:16] := 40, [17:32] := 20, [33:64] := 10 };
  }

  // Source data size matches transfer count
  constraint c_src_data_size {
    src_data.size() == xfer_count;
  }

  // Addresses: word-aligned, within mock memory range (1024 words = 4096 bytes)
  // Source and destination regions must not overlap
  constraint c_src_addr {
    src_addr[1:0] == 2'b00;
    src_addr inside {[32'h0000_0000 : 32'h0000_07FF]};
  }

  constraint c_dst_addr {
    dst_addr[1:0] == 2'b00;
    dst_addr inside {[32'h0000_0800 : 32'h0000_0FFF]};
  }

  // Control register: enable=1, M2M transfer, WIDTH_32, INC/INC, no SG/CIRC
  constraint c_ctrl_default {
    ctrl[CTRL_ENABLE]   == 1'b1;
    ctrl[CTRL_IRQ_TC]   == 1'b1;
    ctrl[CTRL_IRQ_HT]   == 1'b0;
    ctrl[CTRL_IRQ_ERR]  == 1'b1;
    ctrl[CTRL_XTYPE_LO+1 : CTRL_XTYPE_LO] dist {
      XFER_M2M := 60, XFER_M2P := 15, XFER_P2M := 15, XFER_RSVD := 0
    };
    ctrl[CTRL_XWIDTH_LO+1 : CTRL_XWIDTH_LO] dist {
      WIDTH_32 := 60, WIDTH_16 := 20, WIDTH_8 := 20, WIDTH_RSVD := 0
    };
    ctrl[CTRL_SRCM_LO+1 : CTRL_SRCM_LO] dist {
      ADDR_INC := 70, ADDR_DEC := 10, ADDR_FIX := 20, ADDR_RSVD := 0
    };
    ctrl[CTRL_DSTM_LO+1 : CTRL_DSTM_LO] dist {
      ADDR_INC := 70, ADDR_DEC := 10, ADDR_FIX := 20, ADDR_RSVD := 0
    };
    ctrl[CTRL_PRI_LO+1 : CTRL_PRI_LO] inside {[0:3]};
    ctrl[CTRL_SG]   == 1'b0;
    ctrl[CTRL_CIRC] == 1'b0;
    ctrl[31:16]     == 16'h0000;
  }

  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------
  function new(string name = "dmac_seq_item");
    super.new(name);
    completed = 1'b0;
    error     = 1'b0;
  endfunction : new

  // -------------------------------------------------------------------------
  // Post-randomize: extract config fields from ctrl
  // -------------------------------------------------------------------------
  function void post_randomize();
    xfer_type  = xfer_type_t'(ctrl[CTRL_XTYPE_LO+1  : CTRL_XTYPE_LO]);
    xfer_width = xfer_width_t'(ctrl[CTRL_XWIDTH_LO+1 : CTRL_XWIDTH_LO]);
    src_mode   = addr_mode_t'(ctrl[CTRL_SRCM_LO+1   : CTRL_SRCM_LO]);
    dst_mode   = addr_mode_t'(ctrl[CTRL_DSTM_LO+1   : CTRL_DSTM_LO]);
  endfunction : post_randomize

  // Short printable summary
  function string convert2string();
    return $sformatf(
      "DMAC | ch=%0d xtype=%s width=%s src=%h dst=%h cnt=%0d | tc=%0b te=%0b",
      channel,
      xfer_type.name(),
      xfer_width.name(),
      src_addr,
      dst_addr,
      xfer_count,
      completed,
      error
    );
  endfunction : convert2string

endclass : dmac_seq_item

`endif // DMAC_SEQ_ITEM_SV
