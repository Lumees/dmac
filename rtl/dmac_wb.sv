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
// DMA Controller IP -- Wishbone B4 Classic Interface Wrapper
// =============================================================================
// Same register map as dmac_axil.sv.
//
//  Offset  Name            Access  Description
//  0x00    GLOBAL_CTRL     R/W     [0]=global_enable
//  0x04    GLOBAL_STATUS   RO      [N_CH-1:0]=ch_busy
//  0x08    GLOBAL_IRQ      R/W1C   Sticky TC/HT/TE per channel
//  0x0C    VERSION         RO      IP_VERSION from dmac_pkg
//
//  Per-channel at 0x40 + N * 0x20:
//  +0x00   CH_CTRL         R/W     Channel control register
//  +0x04   CH_STATUS       R/W1C   [0]=tc [1]=ht [2]=te [3]=busy(RO)
//  +0x08   CH_SRC          R/W     Source address
//  +0x0C   CH_DST          R/W     Destination address
//  +0x10   CH_COUNT        R/W     Transfer count [15:0]
//  +0x14   CH_NDESC        R/W     Next descriptor address
//  +0x18   CH_CDESC        RO      Current descriptor address
//  +0x1C   CH_REMAIN       RO      Remaining transfer count
// =============================================================================

`timescale 1ns/1ps

import dmac_pkg::*;

module dmac_wb #(
  parameter int NUM_CH = N_CH
) (
  // Wishbone system
  input  logic        CLK_I,
  input  logic        RST_I,

  // Wishbone slave
  input  logic [31:0] ADR_I,
  input  logic [31:0] DAT_I,
  output logic [31:0] DAT_O,
  input  logic        WE_I,
  input  logic [3:0]  SEL_I,
  input  logic        STB_I,
  input  logic        CYC_I,
  output logic        ACK_O,
  output logic        ERR_O,
  output logic        RTY_O,

  // Bus master (directly exposed from dmac_core)
  output logic              bus_req,
  output logic              bus_we,
  output logic [31:0]       bus_addr,
  output logic [31:0]       bus_wdata,
  output logic [1:0]        bus_size,
  input  logic              bus_gnt,
  input  logic              bus_rvalid,
  input  logic [31:0]       bus_rdata,
  input  logic              bus_err,

  // DRQ / DACK
  input  logic [NUM_CH-1:0] drq_i,
  output logic [NUM_CH-1:0] dack_o,

  // Interrupt
  output logic              irq
);

  assign ERR_O = 1'b0;
  assign RTY_O = 1'b0;

  // ── Configuration registers ────────────────────────────────────────────
  logic              reg_global_enable;
  logic [31:0]       reg_ch_ctrl  [NUM_CH];
  logic [31:0]       reg_ch_src   [NUM_CH];
  logic [31:0]       reg_ch_dst   [NUM_CH];
  logic [15:0]       reg_ch_count [NUM_CH];
  logic [31:0]       reg_ch_ndesc [NUM_CH];
  logic [31:0]       reg_irq_status;

  logic [NUM_CH-1:0] ch_start;
  logic [NUM_CH-1:0] ch_abort;

  // ── dmac_top status outputs ────────────────────────────────────────────
  logic [NUM_CH-1:0] ch_busy;
  logic [NUM_CH-1:0] ch_tc;
  logic [NUM_CH-1:0] ch_ht;
  logic [NUM_CH-1:0] ch_te;
  logic [15:0]       ch_remain [NUM_CH];
  logic              core_irq;
  logic [31:0]       core_version;

  // ── dmac_top instance ──────────────────────────────────────────────────
  dmac_top #(.NUM_CH(NUM_CH)) u_dmac (
    .clk           (CLK_I),
    .rst_n         (~RST_I),
    .global_enable (reg_global_enable),
    .ch_ctrl       (reg_ch_ctrl),
    .ch_src        (reg_ch_src),
    .ch_dst        (reg_ch_dst),
    .ch_count      (reg_ch_count),
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
    .irq_o         (core_irq),
    .version_o     (core_version)
  );

  // ── Sticky IRQ status ──────────────────────────────────────────────────
  always_ff @(posedge CLK_I) begin
    if (RST_I)
      reg_irq_status <= '0;
    else begin
      for (int i = 0; i < NUM_CH; i++) begin
        if (ch_tc[i]) reg_irq_status[i]      <= 1'b1;
        if (ch_ht[i]) reg_irq_status[8 + i]  <= 1'b1;
        if (ch_te[i]) reg_irq_status[16 + i] <= 1'b1;
      end
    end
  end

  assign irq = core_irq;

  // ── Bus logic ──────────────────────────────────────────────────────────
  always_ff @(posedge CLK_I) begin
    if (RST_I) begin
      ACK_O             <= 1'b0;
      DAT_O             <= '0;
      reg_global_enable <= 1'b0;
      ch_start          <= '0;
      ch_abort          <= '0;
      for (int i = 0; i < NUM_CH; i++) begin
        reg_ch_ctrl[i]  <= '0;
        reg_ch_src[i]   <= '0;
        reg_ch_dst[i]   <= '0;
        reg_ch_count[i] <= '0;
        reg_ch_ndesc[i] <= '0;
      end
    end else begin
      ACK_O    <= 1'b0;
      ch_start <= '0;
      ch_abort <= '0;

      if (CYC_I && STB_I && !ACK_O) begin
        ACK_O <= 1'b1;

        // Word address
        logic [7:0] waddr;
        waddr = ADR_I[9:2];

        if (WE_I) begin
          // ── Write ────────────────────────────────────────────────────
          if (waddr == 8'h00) begin  // GLOBAL_CTRL
            reg_global_enable <= DAT_I[0];
          end
          else if (waddr == 8'h02) begin  // GLOBAL_IRQ (W1C)
            reg_irq_status <= reg_irq_status & ~DAT_I;
          end
          else if (waddr >= 8'h10) begin  // Per-channel
            logic [7:0] ch_off;
            logic [2:0] ch_idx;
            ch_off = waddr - 8'h10;
            ch_idx = ch_off[5:3];
            if (int'(ch_idx) < NUM_CH) begin
              case (ch_off[2:0])
                3'h0: begin  // CH_CTRL
                  reg_ch_ctrl[ch_idx] <= DAT_I;
                  if (DAT_I[CTRL_ENABLE])
                    ch_start[ch_idx] <= 1'b1;
                end
                3'h1: ;  // CH_STATUS W1C (handled in irq_status)
                3'h2: reg_ch_src[ch_idx]   <= DAT_I;
                3'h3: reg_ch_dst[ch_idx]   <= DAT_I;
                3'h4: reg_ch_count[ch_idx] <= DAT_I[15:0];
                3'h5: reg_ch_ndesc[ch_idx] <= DAT_I;
                default: ;
              endcase
            end
          end
        end else begin
          // ── Read ─────────────────────────────────────────────────────
          if (waddr == 8'h00)
            DAT_O <= {31'b0, reg_global_enable};
          else if (waddr == 8'h01)
            DAT_O <= {{(32-NUM_CH){1'b0}}, ch_busy};
          else if (waddr == 8'h02)
            DAT_O <= reg_irq_status;
          else if (waddr == 8'h03)
            DAT_O <= core_version;
          else if (waddr >= 8'h10) begin
            logic [7:0] ch_off_r;
            logic [2:0] ch_idx_r;
            ch_off_r = waddr - 8'h10;
            ch_idx_r = ch_off_r[5:3];
            if (int'(ch_idx_r) < NUM_CH) begin
              case (ch_off_r[2:0])
                3'h0: DAT_O <= reg_ch_ctrl[ch_idx_r];
                3'h1: DAT_O <= {28'b0, ch_busy[ch_idx_r],
                                ch_te[ch_idx_r], ch_ht[ch_idx_r],
                                ch_tc[ch_idx_r]};
                3'h2: DAT_O <= reg_ch_src[ch_idx_r];
                3'h3: DAT_O <= reg_ch_dst[ch_idx_r];
                3'h4: DAT_O <= {16'b0, reg_ch_count[ch_idx_r]};
                3'h5: DAT_O <= reg_ch_ndesc[ch_idx_r];
                3'h6: DAT_O <= 32'h0;
                3'h7: DAT_O <= {16'b0, ch_remain[ch_idx_r]};
                default: DAT_O <= 32'hDEAD_BEEF;
              endcase
            end else begin
              DAT_O <= 32'hDEAD_BEEF;
            end
          end else begin
            DAT_O <= 32'hDEAD_BEEF;
          end
        end
      end
    end
  end

endmodule : dmac_wb
