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

    );
endmodule

// ---------- FE <-> DE bus payload ----------
typedef struct packed {
  logic [31:0] pc;
  logic [31:0] instr;
} fe_bus_t;

// ---------- Top: Fetch + Skid + Decode ----------
module fe_de_pipe (
    input  logic clk,
    input  logic rst,

    // Fetch-side control inputs
    input  logic        stall,
    input  logic        jalr,
    input  logic        branch,
    input  logic [31:0] offset,
    input  logic [31:0] rs1_val,

    // Execute-stage handshake (downstream of Decode)
    input  logic        ex_ready,

    // Decode -> Execute payload
    output logic                     de_valid,
    output control_signals_t         de_signals_out
    );
    // Fetch <-> Skid_FD wires
    fe_bus_t fe_data_in;
    logic    fe_valid_in;
    logic    fe_ready_in;

    // Skid_FD <-> Decode wires
    fe_bus_t fe_data_out;
    logic    fe_valid_out;
    logic    de_ready;       // from decode

    // ------------ Fetch ------------
    fetch u_fetch (
        .clk         (clk),
        .rst         (rst),
        .stall       (stall),
        .jalr        (jalr),
        .branch      (branch),
        .offset      (offset),
        .rs1_val     (rs1_val),

        // handshake to skid
        .ready       (fe_ready_in),
        .valid       (fe_valid_in),

        // payload to skid
        .pc_decode   (fe_data_in.pc),
        .inst_decode (fe_data_in.instr)
    );

    // ------------ Skid Buffer (FE payload) ------------
    skid_buffer_struct #(.T(fe_bus_t)) u_skid (
        .clk        (clk),
        .reset      (rst),

        // upstream: fetch -> skid
        .valid_in   (fe_valid_in),
        .ready_in   (fe_ready_in),
        .data_in    (fe_data_in),

        // downstream: skid -> decode
        .valid_out  (fe_valid_out),
        .ready_out  (de_ready),
        .data_out   (fe_data_out)
    );

    // ------------ Decode ------------
    decode u_decode (
        .clk            (clk),
        .rst            (rst),

        // upstream (from skid)
        .fe_valid       (fe_valid_out),
        .fe_instr       (fe_data_out.instr),
        .fe_pc          (fe_data_out.pc),
        .de_ready       (de_ready),      // decode advertises readiness to skid

        // downstream (to EX)
        .de_valid       (de_valid),
        .ex_ready       (ex_ready),
        .de_signals_out (de_signals_out)
    );

endmodule


