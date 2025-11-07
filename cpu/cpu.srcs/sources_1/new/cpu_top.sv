`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/05/2025 08:49:48 PM
// Design Name: 
// Module Name: cpu_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module cpu_top(
    input clk,
    input rst
);

logic stall, jalr, branch;
logic [31:0] offset, rs1_val;

// --- Fetch → Decode ---
  fe_de_pipe u_fe_de (
      .clk         (clk),
      .rst         (rst),
      .stall       (stall),
      .jalr        (jalr),
      .branch      (branch),
      .offset      (offset),
      .rs1_val     (rs1_val),
      // might also pass flush or branch redirect control later
  );

  // --- Decode → Rename ---
  de_ren_pipe u_de_re (
      .clk (clk),
      .rst (rst)
  );

endmodule



