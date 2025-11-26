`timescale 1ns / 1ps
`include "riscv_types.svh"

module lsu (
    input  logic                clk,
    input  logic                rst,
    input  logic                flush,

    // Issue Interface
    input  logic                valid_in,
    input  rename_to_dispatch_t instr_in,
    input  logic [31:0]         val1,
    input  logic [31:0]         val2, // Store data (unused in Phase 3)

    // Data Memory Interface (BRAM)
    output logic                mem_en,
    output logic [31:0]         mem_addr,
    input  logic [31:0]         mem_rdata, // Valid 1 or 2 cycles after request

    // Writeback Interface
    output logic                valid_out,
    output fu_to_prf_t          wb_packet
);

    // --- Stage 1: Address Generation & Request ---
    logic [31:0] agu_addr;
    assign agu_addr = val1 + instr_in.immediate;

    assign mem_en   = valid_in;
    assign mem_addr = agu_addr;

    // --- Pipeline Registers for Latency ---
    // We need to keep track of the instruction as it moves through the memory latency
    
    logic valid_s1;
    rename_to_dispatch_t instr_s1;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            valid_s1 <= 1'b0;
            instr_s1 <= '0;
        end else begin
            valid_s1 <= valid_in;
            instr_s1 <= instr_in;
        end
    end

    // --- Stage 2: Writeback ---
    // Logic: If BRAM takes 2 cycles (Request at T0, Data at T2), 
    // we need one register stage (S1).
    // T0: valid_in=1, mem_addr=X
    // T1: valid_s1=1 (BRAM is working)
    // T2: valid_out=1, mem_rdata is valid NOW.
    
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_s1;
        end
    end

    // Combinational Data Path (Crucial Fix)
    // We do NOT register the data again, or we would miss the BRAM valid window.
    // We take mem_rdata directly as it arrives from BRAM.
    always_comb begin
        wb_packet.prd_addr = instr_s1.prd_addr;
        wb_packet.data     = mem_rdata; 
    end

endmodule