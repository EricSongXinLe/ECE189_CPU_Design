`timescale 1ns / 1ps
`include "riscv_types.svh"

module execute (
    input  logic                clk,
    input  logic                rst,
    input  logic                flush,

    // --- Inputs from Issue Stage (RS + PRF) ---
    // Port 0: ALU
    input  logic                alu_issue_valid,
    input  rename_to_dispatch_t alu_issue_instr,
    input  logic [31:0]         alu_val1,
    input  logic [31:0]         alu_val2,

    // Port 1: BRU
    input  logic                bru_issue_valid,
    input  rename_to_dispatch_t bru_issue_instr,
    input  logic [31:0]         bru_val1,
    input  logic [31:0]         bru_val2,

    // Port 2: LSU
    input  logic                lsu_issue_valid,
    input  rename_to_dispatch_t lsu_issue_instr,
    input  logic [31:0]         lsu_val1,
    input  logic [31:0]         lsu_val2,

    // --- Memory Interface ---
    output logic                dmem_en,
    output logic [31:0]         dmem_addr,
    input  logic [31:0]         dmem_rdata,

    // --- Writeback Outputs (CDBs) ---
    // Port 0: ALU, Port 1: LSU, Port 2: BRU
    output logic                wb_valid [3],
    output fu_to_prf_t          wb_packet [3],

    // --- Branch Outcome (To ROB/Fetch) ---
    output logic                br_taken,
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
        .valid_in   (lsu_issue_valid),
        .instr_in   (lsu_issue_instr),
        .val1       (lsu_val1),
        .val2       (lsu_val2),
        .mem_en     (dmem_en),
        .mem_addr   (dmem_addr),
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
        .br_taken   (br_taken),
        .target_pc  (target_pc),
        .mispredict (mispredict),
        .rob_tag    (br_rob_tag)
    );

endmodule