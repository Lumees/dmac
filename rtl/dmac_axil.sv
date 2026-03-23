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
// DMA Controller IP -- AXI4-Lite + Bus Master Interface Wrapper
// =============================================================================
// DUAL-interface wrapper:
//   1. AXI4-Lite SLAVE for CPU register access (configuration)
//   2. Simple bus master for data movement (driven by dmac_core)
//
// Register map (32-bit word, 4-byte aligned):
//
//  Offset  Name            Access  Description
//  0x00    GLOBAL_CTRL     R/W     [0]=global_enable
//  0x04    GLOBAL_STATUS   RO      [N_CH-1:0]=ch_busy
//  0x08    GLOBAL_IRQ      RO      IRQ status (sticky TC/HT/TE per channel)
//  0x0C    VERSION         RO      IP_VERSION from dmac_pkg
//
//  Per-channel at 0x40 + N * 0x20:
//  +0x00   CH_CTRL         R/W     Channel control (see dmac_pkg bit layout)
//  +0x04   CH_STATUS       R/W1C   [0]=tc [1]=ht [2]=te [3]=busy(RO)
//  +0x08   CH_SRC          R/W     Source address
//  +0x0C   CH_DST          R/W     Destination address
//  +0x10   CH_COUNT        R/W     Transfer count [15:0]
//  +0x14   CH_NDESC        R/W     Next descriptor address (scatter-gather)
//  +0x18   CH_CDESC        RO      Current descriptor address
//  +0x1C   CH_REMAIN       RO      Remaining transfer count
// =============================================================================

`timescale 1ns/1ps

import dmac_pkg::*;

module dmac_axil #(
  parameter int NUM_CH = N_CH
) (
  input  logic        clk,
  input  logic        rst_n,

  // ── AXI4-Lite Slave (CPU register access) ──────────────────────────────
  input  logic [31:0] s_axil_awaddr,
  input  logic        s_axil_awvalid,
  output logic        s_axil_awready,
  input  logic [31:0] s_axil_wdata,
  input  logic [3:0]  s_axil_wstrb,
  input  logic        s_axil_wvalid,
  output logic        s_axil_wready,
  output logic [1:0]  s_axil_bresp,
  output logic        s_axil_bvalid,
  input  logic        s_axil_bready,
  input  logic [31:0] s_axil_araddr,
  input  logic        s_axil_arvalid,
  output logic        s_axil_arready,
  output logic [31:0] s_axil_rdata,
  output logic [1:0]  s_axil_rresp,
  output logic        s_axil_rvalid,
  input  logic        s_axil_rready,

  // ── Bus master (directly exposed from dmac_core) ───────────────────────
  output logic              bus_req,
  output logic              bus_we,
  output logic [31:0]       bus_addr,
  output logic [31:0]       bus_wdata,
  output logic [1:0]        bus_size,
  input  logic              bus_gnt,
  input  logic              bus_rvalid,
  input  logic [31:0]       bus_rdata,
  input  logic              bus_err,

  // ── DRQ / DACK ─────────────────────────────────────────────────────────
  input  logic [NUM_CH-1:0] drq_i,
  output logic [NUM_CH-1:0] dack_o,

  // ── Interrupt ──────────────────────────────────────────────────────────
  output logic              irq
);

  // ── Constant responses ─────────────────────────────────────────────────
  assign s_axil_bresp = 2'b00;
  assign s_axil_rresp = 2'b00;

  // ── Configuration registers ────────────────────────────────────────────
  logic              reg_global_enable;
  logic [31:0]       reg_ch_ctrl  [NUM_CH];
  logic [31:0]       reg_ch_src   [NUM_CH];
  logic [31:0]       reg_ch_dst   [NUM_CH];
  logic [15:0]       reg_ch_count [NUM_CH];
  logic [31:0]       reg_ch_ndesc [NUM_CH];
  logic [31:0]       reg_irq_status;

  // ── Per-channel start/abort ────────────────────────────────────────────
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
    .clk           (clk),
    .rst_n         (rst_n),
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
  // Bits [N-1:0]=TC, [N+7:8]=HT, [N+15:16]=TE  (for up to 8 channels)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
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

  // ── AXI4-Lite write path ───────────────────────────────────────────────
  logic [7:0]  wr_addr;
  logic [31:0] wdata_lat;
  logic        aw_active, w_active;

  assign s_axil_awready = !aw_active;
  assign s_axil_wready  = !w_active;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_active         <= 1'b0;
      w_active          <= 1'b0;
      wr_addr           <= '0;
      wdata_lat         <= '0;
      s_axil_bvalid     <= 1'b0;
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
      // Default: clear single-cycle pulses
      ch_start <= '0;
      ch_abort <= '0;

      // AW handshake
      if (s_axil_awvalid && s_axil_awready) begin
        wr_addr   <= s_axil_awaddr[9:2];
        aw_active <= 1'b1;
      end
      // W handshake
      if (s_axil_wvalid && s_axil_wready) begin
        wdata_lat <= s_axil_wdata;
        w_active  <= 1'b1;
      end
      // B handshake
      if (s_axil_bvalid && s_axil_bready)
        s_axil_bvalid <= 1'b0;

      // Perform write when both AW and W captured
      if (aw_active && w_active) begin
        aw_active     <= 1'b0;
        w_active      <= 1'b0;
        s_axil_bvalid <= 1'b1;

        // Global registers
        if (wr_addr == 8'h00) begin  // GLOBAL_CTRL
          reg_global_enable <= wdata_lat[0];
        end
        // 0x04 GLOBAL_STATUS: read-only
        // 0x08 GLOBAL_IRQ: W1C
        else if (wr_addr == 8'h02) begin
          reg_irq_status <= reg_irq_status & ~wdata_lat;
        end
        // 0x0C VERSION: read-only
        // Per-channel registers
        else if (wr_addr >= 8'h10) begin
          // Channel index = (wr_addr - 0x10) / 0x08
          // Byte offset 0x40 => word offset 0x10, stride 0x20 => word stride 0x08
          logic [7:0] ch_offset;
          logic [2:0] ch_idx;
          ch_offset = wr_addr - 8'h10;
          ch_idx    = ch_offset[5:3];
          if (int'(ch_idx) < NUM_CH) begin
            case (ch_offset[2:0])
              3'h0: begin  // CH_CTRL
                reg_ch_ctrl[ch_idx] <= wdata_lat;
                // Writing enable bit triggers start pulse
                if (wdata_lat[CTRL_ENABLE])
                  ch_start[ch_idx] <= 1'b1;
              end
              3'h1: begin  // CH_STATUS (W1C for tc/ht/te bits)
                // Clear sticky bits (handled in irq_status)
              end
              3'h2: reg_ch_src[ch_idx]   <= wdata_lat;       // CH_SRC
              3'h3: reg_ch_dst[ch_idx]   <= wdata_lat;       // CH_DST
              3'h4: reg_ch_count[ch_idx] <= wdata_lat[15:0]; // CH_COUNT
              3'h5: reg_ch_ndesc[ch_idx] <= wdata_lat;       // CH_NDESC
              // 3'h6: CH_CDESC read-only
              // 3'h7: CH_REMAIN read-only
              default: ;
            endcase
          end
        end
      end
    end
  end

  // ── AXI4-Lite read path ────────────────────────────────────────────────
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axil_arready <= 1'b1;
      s_axil_rvalid  <= 1'b0;
      s_axil_rdata   <= '0;
    end else begin
      if (s_axil_arvalid && s_axil_arready) begin
        s_axil_arready <= 1'b0;
        s_axil_rvalid  <= 1'b1;

        // Decode word address
        case (s_axil_araddr[9:2])
          8'h00: s_axil_rdata <= {31'b0, reg_global_enable};
          8'h01: s_axil_rdata <= {{(32-NUM_CH){1'b0}}, ch_busy};
          8'h02: s_axil_rdata <= reg_irq_status;
          8'h03: s_axil_rdata <= core_version;
          default: begin
            if (s_axil_araddr[9:2] >= 8'h10) begin
              logic [7:0] rd_ch_off;
              logic [2:0] rd_ch_idx;
              rd_ch_off = s_axil_araddr[9:2] - 8'h10;
              rd_ch_idx = rd_ch_off[5:3];
              if (int'(rd_ch_idx) < NUM_CH) begin
                case (rd_ch_off[2:0])
                  3'h0: s_axil_rdata <= reg_ch_ctrl[rd_ch_idx];
                  3'h1: s_axil_rdata <= {28'b0, ch_busy[rd_ch_idx],
                                         ch_te[rd_ch_idx], ch_ht[rd_ch_idx],
                                         ch_tc[rd_ch_idx]};
                  3'h2: s_axil_rdata <= reg_ch_src[rd_ch_idx];
                  3'h3: s_axil_rdata <= reg_ch_dst[rd_ch_idx];
                  3'h4: s_axil_rdata <= {16'b0, reg_ch_count[rd_ch_idx]};
                  3'h5: s_axil_rdata <= reg_ch_ndesc[rd_ch_idx];
                  3'h6: s_axil_rdata <= 32'h0;  // CH_CDESC placeholder
                  3'h7: s_axil_rdata <= {16'b0, ch_remain[rd_ch_idx]};
                  default: s_axil_rdata <= 32'hDEAD_BEEF;
                endcase
              end else begin
                s_axil_rdata <= 32'hDEAD_BEEF;
              end
            end else begin
              s_axil_rdata <= 32'hDEAD_BEEF;
            end
          end
        endcase
      end
      if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid  <= 1'b0;
        s_axil_arready <= 1'b1;
      end
    end
  end

endmodule : dmac_axil
