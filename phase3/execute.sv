`timescale 1ns / 1ps
`include "riscv_types.svh"

module execute (
    input  logic                clk,
    input  logic                rst,
    input  logic                flush,

    // --- Inputs from Issue Stage (RS + PRF) ---
    // Port 0: ALU
    input  logic                alu_issue_valid,
    input  dispatch_to_rs_t alu_issue_instr,
    input  logic [31:0]         alu_val1,
    input  logic [31:0]         alu_val2,

    // Port 1: BRU
    input  logic                bru_issue_valid,
    input  dispatch_to_rs_t bru_issue_instr,
    input  logic [31:0]         bru_val1,
    input  logic [31:0]         bru_val2,
    
    // Port 2: LSU
    input  logic                lsu_issue_valid,
    input  dispatch_to_rs_t lsu_issue_instr,
    input  logic [31:0]         lsu_val1,
    input  logic [31:0]         lsu_val2,
    
    // LSQ Interface
    input  logic                lsu_alloc_valid,      // 来自 Dispatch
    input  logic [SQ_IDX_WIDTH-1:0] lsu_alloc_sq_idx, // 来自 Dispatch
    input  logic                commit_valid,         // 来自 ROB
    input  logic                commit_mem_write,     // 来自 ROB
    output logic                lsu_busy,

    // --- Memory Interface ---
    output logic                dmem_en,
    output logic                dmem_we,
    output logic [31:0]         dmem_addr,
    output logic [31:0]         dmem_wdata,
    input  logic [31:0]         dmem_rdata,

    // --- Writeback Outputs (CDBs) ---
    // Port 0: ALU, Port 1: LSU, Port 2: BRU
    output logic [2:0]       wb_valid,

    output fu_to_prf_t [2:0] wb_packet,
    // --- Branch Outcome (To ROB/Fetch) ---
    output logic                is_jalr,
    output logic [31:0]         target_pc,
    output logic                mispredict,
    output logic [ROB_IDX_WIDTH-1:0] br_rob_tag
);

    // --- 1. ALU Instance ---
    alu u_alu (
        .clk        (clk),
        .rst        (rst),
        .flush      (flush),
        .valid_in   (alu_issue_valid),
        .instr_in   (alu_issue_instr),
        .val1       (alu_val1),
        .val2       (alu_val2),
        .valid_out  (wb_valid[0]),
        .wb_packet  (wb_packet[0])
    );

    // --- 2. LSU Instance ---
    lsu u_lsu (
        .clk        (clk),
        .rst        (rst),
        .flush      (flush),
        .alloc_valid (lsu_alloc_valid),
        .alloc_sq_idx(lsu_alloc_sq_idx),
        .valid_in   (lsu_issue_valid),
        .instr_in   (lsu_issue_instr),
        .val1       (lsu_val1),
        .val2       (lsu_val2),
        .commit_valid     (commit_valid),
        .commit_mem_write (commit_mem_write),
        .lsu_busy   (lsu_busy),
        .mem_en     (dmem_en),
        .mem_we     (dmem_we),
        .mem_addr   (dmem_addr),
        .mem_wdata  (dmem_wdata),
        .mem_rdata  (dmem_rdata),
        .valid_out  (wb_valid[1]),
        .wb_packet  (wb_packet[1])
    );

    // --- 3. Branch Unit Instance ---
    bru u_bru (
        .clk        (clk),
        .rst        (rst),
        .flush      (flush),
        .valid_in   (bru_issue_valid),
        .instr_in   (bru_issue_instr),
        .val1       (bru_val1),
        .val2       (bru_val2),
        .valid_out  (wb_valid[2]),
        .wb_packet  (wb_packet[2]),
        .is_jalr    (is_jalr),
        .target_pc  (target_pc),
        .mispredict (mispredict),
        .rob_tag    (br_rob_tag)
    );

endmodule