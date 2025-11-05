`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/01/2025 04:02:03 PM
// Design Name: 
// Module Name: icache
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


module icache #(
    parameter BLOCK_SIZE = 1024
)(
    input  logic        clk,
    input  logic [31:0] pc,
    output logic [31:0] inst
);

    // Declare instruction memory
    logic [31:0] iMEM [0:BLOCK_SIZE-1];

    // Initialize instruction memory from file
    initial $readmemh("program.mem", iMEM);

    // Synchronous BRAM-style read (1-cycle latency)
    always_ff @(posedge clk) begin
        inst <= iMEM[pc[31:2]]; 
    end

endmodule
