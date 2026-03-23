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
// DMA Controller IP — Multi-channel Arbiter
// =============================================================================
// Priority-grouped round-robin arbitration for N_CH DMA channels.
// Highest priority wins; within same priority, round-robin for fairness.
// =============================================================================

`timescale 1ns/1ps

import dmac_pkg::*;

module dmac_arbiter #(
  parameter int NUM_CH = N_CH
) (
  input  logic                    clk,
  input  logic                    rst_n,

  // Per-channel requests
  input  logic [NUM_CH-1:0]       ch_req,
  input  logic [1:0]              ch_pri [NUM_CH],

  // Grant (one-hot)
  output logic [NUM_CH-1:0]       ch_gnt,
  output logic [$clog2(NUM_CH>1?NUM_CH:2)-1:0] winner_id
);

  localparam int ID_W = $clog2(NUM_CH > 1 ? NUM_CH : 2);

  // Round-robin last-served index
  logic [ID_W-1:0] last_served;

  // Find highest priority requesting channel, with round-robin tiebreak
  always_comb begin
    ch_gnt    = '0;
    winner_id = '0;

    // Scan from highest priority (3) to lowest (0)
    // Within each level, scan round-robin from last_served+1
    for (int p = 3; p >= 0; p--) begin
      if (ch_gnt == '0) begin  // no winner yet
        for (int i = 0; i < NUM_CH; i++) begin
          automatic int idx = (int'(last_served) + 1 + i) % NUM_CH;
          if (ch_gnt == '0 && ch_req[idx] && ch_pri[idx] == p[1:0]) begin
            ch_gnt[idx] = 1'b1;
            winner_id   = ID_W'(idx);
          end
        end
      end
    end
  end

  // Update last_served on grant
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      last_served <= '0;
    else if (ch_gnt != '0)
      last_served <= winner_id;
  end

endmodule : dmac_arbiter
