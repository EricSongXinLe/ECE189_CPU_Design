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
    input logic stall, jalr, branch, //JALR is unconditional, branch is conditional
    input logic [31:0] offset,
    input logic [31:0] rs1_val,
    
    input logic ready,
    output logic valid,
    
    output logic [31:0] pc_decode,
    output logic [31:0] inst_decode
    );
logic [31:0] pc;
logic [31:0] nextpc;

logic [31:0] inst;

logic hold;
assign hold = stall || (valid && !ready);

logic [31:0] icache [0:1023];


always_comb begin   
    nextpc = pc + 32'd4;
    if (branch) nextpc = pc + offset;
    if (jalr) nextpc = (rs1_val + offset) & 32'hFFFF_FFFE;
end

always @(posedge clk) begin
    if(rst)begin
        pc <= 32'b0;
    end else if (!hold) begin
        pc <= nextpc;
    end
end

  
assign inst = icache[pc[31:2]];

always_ff @(posedge clk) begin
    if (rst) begin
      valid       <= 1'b0;
      pc_decode   <= '0;
      inst_decode <= '0;
    end else if (hold) begin
      // Hold outputs while sink is not ready
      /*
      valid       <= valid;
      pc_decode   <= pc_decode;
      inst_decode <= inst_decode; 
      */
    end else begin
        valid <= 1'b1;
        pc_decode <= pc;
        inst_decode <= inst;
    end
    
end

endmodule
