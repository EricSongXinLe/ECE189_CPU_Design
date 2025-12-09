`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Yike Shi
// 
// Create Date: 11/01/2025 04:02:03 PM
// Design Name: RISC-V 5-Stage Pipeline
// Module Name: decode
// Description: 
// This module implements the Decode (DE) stage of the pipeline.
//////////////////////////////////////////////////////////////////////////////////

module decode(
    input  logic        clk,
    input  logic        rst,

    // Upstream Interface (from Fetch)
    input  logic         fe_valid,       // Input is valid
    input  logic [31:0] fe_instr,     // Input instruction
    input  logic [31:0] fe_pc,        // Input PC
    output logic        de_ready,       // We are ready for input

    // Downstream Interface (to Rename)
    output logic        de_valid,        // Our output is valid
    input  logic        re_ready,       // Next stage is ready for our output
    output decode_to_rename_t de_signals_out // Our decoded output signals
);
    // --- Internal Registers ---
    logic de_valid_reg;
    decode_to_rename_t de_signals_reg;

    // This signal holds the combinational-ly decoded signals
    decode_to_rename_t next_signals;

    // --- Instruction Field Extraction (Moved outside always_comb to fix Warnings) ---
    logic [6:0]  opcode;
    logic [4:0]  rd;
    logic [2:0]  funct3;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [6:0]  funct7;

    assign opcode = fe_instr[6:0];
    assign rd     = fe_instr[11:7];
    assign funct3 = fe_instr[14:12];
    assign rs1    = fe_instr[19:15];
    assign rs2    = fe_instr[24:20];
    assign funct7 = fe_instr[31:25];

    always_comb begin
        // --- Default Control Signal Values (safe state) ---
        next_signals = '0; // Set all fields in the struct to 0
        next_signals.pc = fe_pc;
        next_signals.rs1_addr = rs1;
        next_signals.rs2_addr = rs2;
        next_signals.rd_addr = rd;
        next_signals.funct3 = funct3;
        next_signals.funct7 = funct7;
        next_signals.opcode = opcode;
        next_signals.FU_type = 2'b11; //no op
        
        // --- Main Control & Immediate Generation ---
        case (opcode)
            // R-type (ADD, SUB, SRA, AND)
            'h33: begin // 0b0110011
                next_signals.RegWrite = 1'b1;
                next_signals.ALUOp    = 2'b10;
                next_signals.FU_type = 2'b00;
                // immediate = 0 (default)
            end

            // I-type (ALU: ADDI, SLTIU, ORI)
            'h13: begin // 0b0010011
                next_signals.RegWrite = 1'b1;
                next_signals.ALUSrc   = 1'b1;
                next_signals.ALUOp    = 2'b11;
                next_signals.FU_type = 2'b00;
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
                next_signals.FU_type  = 2'b10;
                // I-type immediate: sign-extend from bit 31
                next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:20]};
            end

            // S-type (Store: SW, SH)
            'h23: begin // 0b0100011
                next_signals.MemWrite = 1'b1;
                next_signals.ALUSrc   = 1'b1;
                next_signals.ALUOp    = 2'b00;
                next_signals.FU_type  = 2'b10;
                // S-type immediate: sign-extend from bit 31
                next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:25], fe_instr[11:7]};
            end

            // B-type (Branch: BNE)
            'h63: begin // 0b1100011
                next_signals.is_branch = 1'b1;
                next_signals.ALUOp  = 2'b01;
                next_signals.FU_type  = 2'b01;
                // B-type immediate: sign-extend from bit 31
                next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[7], fe_instr[30:25], fe_instr[11:8], 1'b0};
            end

            // I-type (JALR)
            'h67: begin // 0b1100111
                next_signals.RegWrite = 1'b1;
                next_signals.ALUSrc   = 1'b1;
                next_signals.ALUOp    = 2'b00;
                next_signals.FU_type  = 2'b01;
                // I-type immediate: sign-extend from bit 31
                next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:20]};
            end

            // U-type (LUI)
            'h37: begin // 0b0110111
                next_signals.RegWrite = 1'b1;
                next_signals.ALUSrc   = 1'b1;
                next_signals.FU_type  = 2'b00;
                // U-type immediate: 
                next_signals.immediate = {fe_instr[31:12], 12'h000};
            end
            
            default: begin
                // Default case: treat as NOP
            end
        endcase
    end


    // --- Pipeline Register & Handshake Logic ---

    // `de_ready`: We are ready to accept a new instruction from Fetch if...
    // 1. Our pipeline register is currently empty (!de_valid_reg), OR
    // 2. The Next stage (Rename) is ready to take our current instruction (re_ready)
    
    // FIX: Changed ex_ready to re_ready
    assign de_ready = !de_valid_reg || re_ready;

    logic load_en = fe_valid && de_ready;
    
    assign de_valid = de_valid_reg;
    assign de_signals_out = de_signals_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            de_valid_reg   <= 1'b0;
            de_signals_reg <= '0;
        end
        else if (load_en) begin
            de_valid_reg   <= 1'b1;
            de_signals_reg <= next_signals;
        end
        // FIX: Changed ex_ready to re_ready
        else if (de_valid_reg && re_ready) begin
            de_valid_reg <= 1'b0;
        end
    end

endmodule