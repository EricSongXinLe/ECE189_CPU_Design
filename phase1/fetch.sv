`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/01/2025 04:02:03 PM
// Design Name: 
// Module Name: fetch
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


module fetch(
    input logic clk,
    input logic rst,
    input logic stall, 
    input logic redirect, //JALR is unconditional, branch is conditional
    input logic [31:0] redirect_pc,
    
    input logic ready,
    output logic valid,
    
    output logic [31:0] pc_decode, //to decode
    output logic [31:0] inst_decode //to decode
    );

logic [31:0] pc; //to icache
logic [31:0] nextpc;
logic [31:0] inst; //from icache
logic hold;

assign hold = stall || (valid && !ready);

always_comb begin   
    if (redirect) nextpc = redirect_pc;
    else nextpc = pc + 32'd4;
end

always @(posedge clk) begin
    if(rst)begin
        pc <= 32'b0;
    end else if (!hold) begin
        pc <= nextpc;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
      valid       <= 1'b0;
      pc_decode   <= '0;
      inst_decode <= '0;
    end else if (!hold) begin
        valid <= 1'b1;
        pc_decode <= pc;
        inst_decode <= inst;
    end
    //else hold: do nothing, automatically retains previous values
end

icache u_icache( //I/O with icache
    //Output
    .inst(inst),
    //Input
    .pc(pc),
    .clk(clk)
);

endmodule
