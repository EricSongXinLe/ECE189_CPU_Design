`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/15/2025 10:50:38 AM
// Design Name: 
// Module Name: fetch_icache_tb
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


module fetch_icache_tb;

    logic clk, rst;
    
    //tie-offs
    logic stall, redirect, ready;
    logic [31:0] redirect_pc;
    
    //DUT outputs
    logic valid;
    logic [31:0] pc_decode, inst_decode;
    
    //clock
    initial clk=0;
    always #5 clk = ~clk;
    
    //reset+stimulus
    initial begin
        rst = 1;
        stall = 0;
        redirect = 0;
        redirect_pc = 32'h0;
        ready = 1;
        
        repeat (5) @(posedge clk);
        rst = 0;
        
        repeat (10) @(posedge clk);
        
        //test stall
        stall = 1;
        repeat (5) @(posedge clk);
        stall = 0;
        
        //test redirect
          redirect_pc = 32'h00000004;
          redirect = 1;
          @(negedge clk)
          redirect = 0;
        
        repeat (10) @(posedge clk);
        $finish;
    end
    
    fetch dut(
        .clk(clk), .rst(rst),
        .stall(stall),
        .redirect(redirect),
        .redirect_pc(redirect_pc),
            .ready(ready),
            .valid(valid),
            .pc_decode(pc_decode),
            .inst_decode(inst_decode)
    );
    always @(posedge clk) begin
        if (!rst && valid && ready) begin
            $display("pc=%08h inst=%08h", pc_decode, inst_decode);
        end
    end    
endmodule
