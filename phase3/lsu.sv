`timescale 1ns / 1ps
`include "riscv_types.svh"

module lsu (
    input  logic                clk,
    input  logic                rst,
    input  logic                flush,

    // Issue Interface
    input  logic                valid_in,
    input  dispatch_to_rs_t     instr_in,
    input  logic [31:0]         val1,
    input  logic [31:0]         val2, // Store data (unused in Phase 3)

    // Data Memory Interface (BRAM)
    output logic                mem_en,
    output logic [31:0]         mem_addr,
    input  logic [31:0]         mem_rdata, // Valid 1 or 2 cycles after request

    // SQ update (store only)
    output logic                sq_upd_valid,
    output logic [ROB_IDX_WIDTH-1:0] sq_upd_idx,
    output logic [31:0]         sq_upd_addr,
    output logic [31:0]         sq_upd_data,

    // Writeback (load only)
    output logic                valid_out,
    output fu_to_prf_t          wb_packet
);

    // --- Stage 1: Address Generation & Request ---
    logic [31:0] agu_addr, w, load_data;
    logic [7:0] b;
    logic [15:0] h;
    assign agu_addr = val1 + instr_in.immediate;

    assign w = mem_rdata;

    always_comb begin
        case(agu_addr[1:0])
            2'b00: b=w[7:0];
            2'b01: b=w[15:8];
            2'b10: b=w[23:16];
            2'b11: b=w[31:24];
        endcase
    
        h = agu_addr[1]? w[31:16] : w[15:0];

        case(instr_in.funct3)
            3'b001: load_data={{16{h[15]}},h}; //half-word
            3'b010: load_data= w;
            3'b100: load_data={24'b0,b}; //byte
        endcase
    end

    always_ff @(posedge clk) begin
        if (valid_in && instr_in.is_store) begin
            sq_entry[instr_in.sq_idx].addr       <= agu_addr;
            sq_entry[instr_in.sq_idx].addr_ready <= 1'b1;

            sq_entry[instr_in.sq_idx].data       <= val2;
            sq_entry[instr_in.sq_idx].data_ready <= 1'b1;
        end
    end

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
        wb_packet.rob_tag = instr_s1.rob_tag;
    end

endmodule