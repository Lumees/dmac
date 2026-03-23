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
// DMA Controller IP — Single Channel Engine
// =============================================================================
// Implements one DMA channel with:
//   - Read-ahead FIFO (FIFO_DEPTH entries)
//   - Source/destination address generation (inc/dec/fixed)
//   - Transfer width steering (8/16/32-bit)
//   - DRQ/DACK peripheral handshake
//   - IRQ on transfer complete / half-transfer / error
// =============================================================================

`timescale 1ns/1ps

import dmac_pkg::*;

module dmac_channel #(
  parameter int BUF_DEPTH = FIFO_DEPTH
) (
  input  logic        clk,
  input  logic        rst_n,

  // ── Configuration (from register file) ────────────────────────────────────
  input  logic [31:0] ctrl_i,         // ch_ctrl packed
  input  logic [31:0] src_addr_i,
  input  logic [31:0] dst_addr_i,
  input  logic [15:0] xfer_count_i,
  input  logic        start_i,        // pulse: begin transfer
  input  logic        abort_i,        // pulse: cancel transfer

  // ── Status ────────────────────────────────────────────────────────────────
  output logic        busy_o,
  output logic        tc_o,           // pulse: transfer complete
  output logic        ht_o,           // pulse: half-transfer reached
  output logic        te_o,           // pulse: transfer error
  output logic [15:0] remain_o,

  // ── Bus master request (to arbiter) ───────────────────────────────────────
  output logic        bus_req_o,
  input  logic        bus_gnt_i,
  output logic        bus_we_o,
  output logic [31:0] bus_addr_o,
  output logic [31:0] bus_wdata_o,
  output logic [1:0]  bus_size_o,
  input  logic        bus_rvalid_i,
  input  logic [31:0] bus_rdata_i,
  input  logic        bus_err_i,

  // ── Peripheral handshake ──────────────────────────────────────────────────
  input  logic        drq_i,
  output logic        dack_o
);

  // ── Internal state ────────────────────────────────────────────────────────
  ch_state_t state;
  logic [31:0] src_ptr, dst_ptr;
  logic [15:0] total_count, remain_cnt;
  logic [15:0] rd_count;   // reads issued
  logic [31:0] ctrl_lat;

  // Extract control fields
  logic        ch_enable;
  xfer_type_t  xfer_type;
  xfer_width_t xfer_width;
  addr_mode_t  src_mode, dst_mode;

  assign ch_enable  = ctrl_lat[CTRL_ENABLE];
  assign xfer_type  = xfer_type_t'(ctrl_lat[CTRL_XTYPE_LO+1:CTRL_XTYPE_LO]);
  assign xfer_width = xfer_width_t'(ctrl_lat[CTRL_XWIDTH_LO+1:CTRL_XWIDTH_LO]);
  assign src_mode   = addr_mode_t'(ctrl_lat[CTRL_SRCM_LO+1:CTRL_SRCM_LO]);
  assign dst_mode   = addr_mode_t'(ctrl_lat[CTRL_DSTM_LO+1:CTRL_DSTM_LO]);

  // Address increment based on width
  logic [2:0] addr_step;
  always_comb begin
    unique case (xfer_width)
      WIDTH_8:  addr_step = 3'd1;
      WIDTH_16: addr_step = 3'd2;
      WIDTH_32: addr_step = 3'd4;
      default:  addr_step = 3'd4;
    endcase
  end

  // ── Read-ahead FIFO ───────────────────────────────────────────────────────
  logic [31:0] fifo [BUF_DEPTH];
  logic [$clog2(BUF_DEPTH):0] fifo_wptr, fifo_rptr;
  logic [$clog2(BUF_DEPTH):0] fifo_count;

  assign fifo_count = fifo_wptr - fifo_rptr;
  wire fifo_full  = (fifo_count == BUF_DEPTH[$clog2(BUF_DEPTH):0]);
  wire fifo_empty = (fifo_count == 0);

  // ── Outputs ───────────────────────────────────────────────────────────────
  assign busy_o   = (state != CH_IDLE && state != CH_DONE);
  assign remain_o = remain_cnt;
  assign bus_size_o = ctrl_lat[CTRL_XWIDTH_LO+1:CTRL_XWIDTH_LO];
  assign dack_o = 1'b0;  // simplified: no explicit DACK pulse in v1.0

  // ── DRQ gating ────────────────────────────────────────────────────────────
  logic drq_ok;
  always_comb begin
    unique case (xfer_type)
      XFER_M2P: drq_ok = drq_i;      // wait for peripheral ready before write
      XFER_P2M: drq_ok = drq_i;      // wait for peripheral ready before read
      default:  drq_ok = 1'b1;        // M2M: no handshake needed
    endcase
  end

  // ── Main FSM ──────────────────────────────────────────────────────────────
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= CH_IDLE;
      src_ptr     <= '0;
      dst_ptr     <= '0;
      total_count <= '0;
      remain_cnt  <= '0;
      rd_count    <= '0;
      ctrl_lat    <= '0;
      fifo_wptr   <= '0;
      fifo_rptr   <= '0;
      bus_req_o   <= 1'b0;
      bus_we_o    <= 1'b0;
      bus_addr_o  <= '0;
      bus_wdata_o <= '0;
      tc_o        <= 1'b0;
      ht_o        <= 1'b0;
      te_o        <= 1'b0;
    end else begin
      tc_o <= 1'b0;
      ht_o <= 1'b0;
      te_o <= 1'b0;

      if (abort_i) begin
        state     <= CH_IDLE;
        bus_req_o <= 1'b0;
      end else unique case (state)

        CH_IDLE: begin
          bus_req_o <= 1'b0;
          if (start_i) begin
            ctrl_lat    <= ctrl_i;
            src_ptr     <= src_addr_i;
            dst_ptr     <= dst_addr_i;
            total_count <= xfer_count_i;
            remain_cnt  <= xfer_count_i;
            rd_count    <= '0;
            fifo_wptr   <= '0;
            fifo_rptr   <= '0;
            state       <= CH_READ_REQ;
          end
        end

        // ── Read phase: fill FIFO from source ───────────────────────────
        CH_READ_REQ: begin
          if (rd_count < total_count && !fifo_full && drq_ok) begin
            bus_req_o  <= 1'b1;
            bus_we_o   <= 1'b0;
            bus_addr_o <= src_ptr;
            state      <= CH_READ_WAIT;
          end else if (!fifo_empty) begin
            // FIFO has data — switch to write phase
            bus_req_o <= 1'b0;
            state     <= CH_WRITE_REQ;
          end else if (remain_cnt == 0) begin
            state <= CH_DONE;
          end
        end

        CH_READ_WAIT: begin
          // Deassert req after grant (address was accepted)
          if (bus_gnt_i)
            bus_req_o <= 1'b0;
          // Wait for read data
          if (bus_rvalid_i) begin
            if (bus_err_i) begin
              te_o  <= 1'b1;
              state <= CH_DONE;
            end else begin
              fifo[fifo_wptr[$clog2(BUF_DEPTH)-1:0]] <= bus_rdata_i;
              fifo_wptr <= fifo_wptr + 1;
              rd_count  <= rd_count + 1;
              // Advance source pointer
              unique case (src_mode)
                ADDR_INC: src_ptr <= src_ptr + {29'd0, addr_step};
                ADDR_DEC: src_ptr <= src_ptr - {29'd0, addr_step};
                default:  ; // ADDR_FIX: no change
              endcase
              // Check half-transfer
              if (rd_count + 1 == {1'b0, total_count[15:1]})
                ht_o <= ctrl_lat[CTRL_IRQ_HT];
              // Continue: try to fill more or switch to write
              if (!fifo_full && rd_count + 1 < total_count)
                state <= CH_READ_REQ;
              else
                state <= CH_WRITE_REQ;
            end
          end
        end

        // ── Write phase: drain FIFO to destination ──────────────────────
        CH_WRITE_REQ: begin
          if (!fifo_empty && drq_ok) begin
            bus_req_o   <= 1'b1;
            bus_we_o    <= 1'b1;
            bus_addr_o  <= dst_ptr;
            bus_wdata_o <= fifo[fifo_rptr[$clog2(BUF_DEPTH)-1:0]];
            state       <= CH_WRITE_WAIT;
          end else if (fifo_empty && rd_count < total_count) begin
            // More reads needed
            state <= CH_READ_REQ;
          end else if (fifo_empty && remain_cnt == 0) begin
            state <= CH_DONE;
          end
        end

        CH_WRITE_WAIT: begin
          if (bus_gnt_i) begin
            bus_req_o <= 1'b0;
            // Write accepted — advance FIFO and destination
            fifo_rptr  <= fifo_rptr + 1;
            remain_cnt <= remain_cnt - 1;
            unique case (dst_mode)
              ADDR_INC: dst_ptr <= dst_ptr + {29'd0, addr_step};
              ADDR_DEC: dst_ptr <= dst_ptr - {29'd0, addr_step};
              default:  ; // ADDR_FIX
            endcase
            // Continue draining or switch back to read
            if (remain_cnt - 1 == 0)
              state <= CH_DONE;
            else if (!fifo_empty)
              state <= CH_WRITE_REQ;  // more in FIFO
            else
              state <= CH_READ_REQ;   // need more reads
          end else if (bus_err_i) begin
            // Error takes priority — don't decrement remain_cnt
            te_o      <= 1'b1;
            bus_req_o <= 1'b0;
            state     <= CH_DONE;
          end
        end

        CH_DONE: begin
          tc_o      <= 1'b1;
          bus_req_o <= 1'b0;
          state     <= CH_IDLE;
        end

        default: state <= CH_IDLE;
      endcase
    end
  end

endmodule : dmac_channel
