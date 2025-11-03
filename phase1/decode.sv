`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Yike Shi
// 
// Create Date: 11/01/2025 04:02:03 PM
// Design Name: RISC-V 5-Stage Pipeline
// Module Name: decode
// Project Name: ECE 189
// Target Devices: 
// Tool Versions: 
// Description: 
// This module implements the Decode (DE) stage of the pipeline.
// It decodes RISC-V instructions based on the provided C++ simulator logic
// and acts as a pipeline register with a full valid/ready handshake.
//
// Instructions Supported:
// R-type: ADD, SUB, SRA, AND
// I-type: ADDI, SLTIU, ORI, LW, LBU, JALR
// S-type: SW, SH
// B-type: BNE
// U-type: LUI
//
// Dependencies: None
// 
// Revision:
// Revision 0.01 - File Created
// Revision 1.00 - Implemented full decode logic and pipeline register
// Additional Comments:
// Based on C++ simulator from CPU.cpp and CPU.h I wrote in CA1
//
//////////////////////////////////////////////////////////////////////////////////

// This struct bundles all control signals and data
// that need to be passed from the Decode stage to the Execute stage.
typedef struct packed {
    // Primary Control Signals
    logic        RegWrite;   // Write result to register file
    logic        MemRead;    // Read from data memory
    logic        MemWrite;   // Write to data memory
    logic        MemToReg;   // Write data from memory (vs. ALU) to reg
    logic        ALUSrc;     // ALU operand 2 is immediate (vs. register)
    logic        Branch;     // This is a BNE instruction
    
    // ALUOp from mainControl in C++ code
    logic [1:0]  ALUOp;
    
    // Data for Execute Stage
    logic [31:0] pc;         // PC for branch/JALR calculations
    logic [4:0]  rs1_addr;   // Address of register operand 1
    logic [4:0]  rs2_addr;   // Address of register operand 2
    logic [4:0]  rd_addr;    // Address of destination register
    logic [31:0] immediate;  // Sign-extended immediate value
    
    // Pass-throughs for ALU Control and special ops
    logic [6:0]  funct7;
    logic [2:0]  funct3;
    logic [6:0]  opcode;     // For JALR/LUI special casing in execute
} control_signals_t;


module decode(
    input  logic        clk,
    input  logic        rst,

    // Upstream Interface (from Fetch)
    input  logic        fe_valid,       // Input is valid
    input  logic [31:0] fe_instr,     // Input instruction
    input  logic [31:0] fe_pc,        // Input PC
    output logic        de_ready,       // We are ready for input

    // Downstream Interface (to Execute)
    output logic        de_valid,       // Our output is valid
    input  logic        ex_ready,       // Next stage is ready for our output
    output control_signals_t de_signals_out // Our decoded output signals
);

    // --- Internal Registers ---
    // These registers hold the decoded instruction and control signals,
    // forming the pipeline register between Decode and Execute.
    logic de_valid_reg;
    control_signals_t de_signals_reg;

    // This signal holds the combinational-ly decoded signals
    // from the *current* instruction from Fetch.
    control_signals_t next_signals;

    always_comb begin
        // --- Instruction Field Extraction ---
        // Extract all possible fields from the incoming instruction
        logic [6:0]  opcode = fe_instr[6:0];
        logic [4:0]  rd     = fe_instr[11:7];
        logic [2:0]  funct3 = fe_instr[14:12];
        logic [4:0]  rs1    = fe_instr[19:15];
        logic [4:0]  rs2    = fe_instr[24:20];
        logic [6:0]  funct7 = fe_instr[31:25];

        // --- Default Control Signal Values (safe state) ---
        // This is crucial. Start every instruction decode by assuming
        // it does nothing, then set the bits that are required.
        next_signals = '0; // Set all fields in the struct to 0
        next_signals.pc = fe_pc;
        next_signals.rs1_addr = rs1;
        next_signals.rs2_addr = rs2;
        next_signals.rd_addr = rd;
        next_signals.funct3 = funct3;
        next_signals.funct7 = funct7;
        next_signals.opcode = opcode;
        
        // --- Main Control & Immediate Generation ---
        case (opcode)
            // R-type (ADD, SUB, SRA, AND)
            'h33: begin // 0b0110011
                next_signals.RegWrite = 1'b1;
                next_signals.ALUOp    = 2'b10;
                // immediate = 0 (default)
            end

            // I-type (ALU: ADDI, SLTIU, ORI)
            'h13: begin // 0b0010011
                next_signals.RegWrite = 1'b1;
                next_signals.ALUSrc   = 1'b1;
                next_signals.ALUOp    = 2'b11;
                // I-type immediate: sign-extend from bit 31
                next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:20]};
            end

            // I-type (Load: LW, LBU)
            'h03: begin // 0b0000011
                next_signals.RegWrite = 1'b1;
                next_signals.MemRead  = 1'b1;
                next_signals.MemToReg = 1'b1;
                next_signals.ALUSrc   = 1'b1;
                next_signals.ALUOp    = 2'b00;
                // I-type immediate: sign-extend from bit 31
                next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:20]};
            end

            // S-type (Store: SW, SH)
            'h23: begin // 0b0100011
                next_signals.MemWrite = 1'b1;
                next_signals.ALUSrc   = 1'b1;
                next_signals.ALUOp    = 2'b00;
                // S-type immediate: sign-extend from bit 31
                next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:25], fe_instr[11:7]};
            end

            // B-type (Branch: BNE)
            'h63: begin // 0b1100011
                next_signals.Branch = 1'b1;
                next_signals.ALUOp  = 2'b01;
                // B-type immediate: sign-extend from bit 31
                next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[7], fe_instr[30:25], fe_instr[11:8], 1'b0};
            end

            // I-type (JALR)
            'h67: begin // 0b1100111
                next_signals.RegWrite = 1'b1;
                next_signals.ALUSrc   = 1'b1;
                next_signals.ALUOp    = 2'b00;
                // I-type immediate: sign-extend from bit 31
                next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:20]};
            end

            // U-type (LUI)
            'h37: begin // 0b0110111
                next_signals.RegWrite = 1'b1;
                next_signals.ALUSrc   = 1'b1;
                // U-type immediate: 
                next_signals.immediate = {fe_instr[31:12], 12'h000};
            end
            
            default: begin
                // Default case: treat as NOP (all signals 0)
                // This is already handled by the default assignment
            end
        endcase
    end


    // --- Pipeline Register & Handshake Logic ---

    // `de_ready`: We are ready to accept a new instruction from Fetch if...
    // 1. Our pipeline register is currently empty (!de_valid_reg), OR
    // 2. The Execute stage is ready to take our current instruction (ex_ready)
    //    (This allows data to "flow through" combinational-ly)
    assign de_ready = !de_valid_reg || ex_ready;

    // `load_en`: We should load a new instruction into our register if...
    // 1. Fetch has a valid instruction for us (fe_valid), AND
    // 2. We are ready to accept it (de_ready)
    logic load_en = fe_valid && de_ready;

    // The output `de_valid` is simply the registered valid bit
    assign de_valid = de_valid_reg;
    
    // The output signals are the registered signals
    assign de_signals_out = de_signals_reg;

    // This is the pipeline register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // On reset, the pipeline stage is empty (invalid)
            de_valid_reg   <= 1'b0;
            de_signals_reg <= '0;
        end
        else if (load_en) begin
            // Load: A new valid instruction is coming from Fetch
            // and we are ready for it. Latch the combinational-ly
            // decoded signals and mark ourselves as 'valid'.
            de_valid_reg   <= 1'b1;
            de_signals_reg <= next_signals;
        end
        else if (de_valid_reg && ex_ready) begin
            // Clear: The Execute stage is taking our data, and no new
            // data is coming in. We become empty (invalid).
            de_valid_reg <= 1'b0;
        end
        // else:
        // Stall: (de_valid_reg && !ex_ready). We are holding a valid
        // instruction, but Execute is not ready. We hold our state.
        // `de_ready` becomes '0', stalling the Fetch stage.
    end

endmodule
