`timescale 1ns / 1ps
`include "riscv_types.svh"  // <--- 修复1: 包含头文件，而不是重新定义 fe_bus_t

module fe_de_pipe (
    input  logic clk,
    input  logic rst,

    // Fetch-side control inputs
    input  logic        stall,
    input  logic        jalr,
    input  logic        branch,
    input  logic [31:0] offset,
    input  logic [31:0] rs1_val
);
    // Fetch <-> FE_DE_Skid wires
    fe_bus_t fe_data_in;
    logic fe_valid_in;
    logic fe_ready_out;

    // FE_DE_Skid <-> Decode wires
    fe_bus_t fe_data_out;
    logic fe_valid_out;
    logic de_ready_in;

    // ------------ Fetch Module ------------
    fetch u_fetch (
        .clk         (clk),
        .rst         (rst),
        .stall       (stall),
        .redirect    (jalr || branch), // 注意：这里可能需要根据你的逻辑确认 redirect 信号源
        .redirect_pc (offset),         // 注意：这里可能需要确认 redirect_pc 的逻辑
        // .jalr / .branch / .rs1_val 端口在 fetch.sv 中似乎没有直接对应，需确认 fetch 接口

        // handshake to skid
        .ready       (fe_ready_out),
        .valid       (fe_valid_in),

        // payload to skid
        .pc_decode   (fe_data_in.pc),
        .inst_decode (fe_data_in.instr)
    );

    // ------------ Skid Buffer (FE payload) ------------
    skid_buffer_struct #(.T(fe_bus_t)) u_skidF (
        .clk        (clk),
        .reset      (rst),

        // upstream: fetch <-> skid
        .valid_in   (fe_valid_in),
        .ready_out  (fe_ready_out),
        .data_in    (fe_data_in),

        // downstream: skid <-> decode
        .valid_out  (fe_valid_out),
        .ready_in   (de_ready_in),
        .data_out   (fe_data_out)
    );

    // ------------ Decode ------------
    decode u_decode_upstream (
        .clk            (clk),
        .rst            (rst),

        // upstream (from skid)
        .fe_valid       (fe_valid_out),
        .fe_instr       (fe_data_out.instr),
        .fe_pc          (fe_data_out.pc),
        .de_ready       (de_ready_in)   // <--- 修复2: 使用已声明的 de_ready_in 信号
    );

endmodule