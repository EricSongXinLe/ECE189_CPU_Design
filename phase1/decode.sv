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

// 在 decode 模块的 always_comb 中
always_comb begin
    // --- Default Control Signal Values (Safe State) ---
    next_signals = '0;
    next_signals.pc = fe_pc;
    // 默认连接指令中的 rs1/rs2/rd 字段
    next_signals.rs1_addr = rs1; 
    next_signals.rs2_addr = rs2;
    next_signals.rd_addr  = rd; 
    next_signals.funct3 = funct3;
    next_signals.funct7 = funct7;
    next_signals.opcode = opcode;
    next_signals.FU_type = 2'b11; // 默认 invalid/nop

    case (opcode)
        // R-type (ADD, SUB, etc.)
        'h33: begin 
            next_signals.RegWrite = 1'b1;
            next_signals.ALUOp    = 2'b10;
            next_signals.FU_type  = 2'b00; // ALU
        end

        // I-type (ADDI, etc.)
        'h13: begin 
            next_signals.RegWrite = 1'b1;
            next_signals.ALUSrc   = 1'b1;
            next_signals.ALUOp    = 2'b11; 
            next_signals.FU_type  = 2'b00; // ALU
            next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:20]};
        end

        // I-type (Load)
        'h03: begin 
            next_signals.RegWrite = 1'b1;
            next_signals.MemRead  = 1'b1;
            next_signals.MemToReg = 1'b1;
            next_signals.ALUSrc   = 1'b1;
            next_signals.ALUOp    = 2'b00; // ADD (base + offset)
            next_signals.FU_type  = 2'b10; // LSU
            next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:20]};
        end

        // S-type (Store)
        'h23: begin 
            next_signals.MemWrite = 1'b1;
            next_signals.ALUSrc   = 1'b1;
            next_signals.ALUOp    = 2'b00; // ADD (base + offset)
            next_signals.FU_type  = 2'b10; // LSU
            next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:25], fe_instr[11:7]};
            
            // 安全强制：Store 不写回寄存器
            next_signals.RegWrite = 1'b0; 
            next_signals.rd_addr  = 5'b0; 
        end

        // B-type (Branch)
        'h63: begin 
            next_signals.is_branch = 1'b1;
            next_signals.ALUOp     = 2'b01;
            next_signals.FU_type   = 2'b01; // BRU
            next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[7], fe_instr[30:25], fe_instr[11:8], 1'b0};
            
            // 安全强制：Branch 不写回寄存器
            next_signals.RegWrite = 1'b0;
            next_signals.rd_addr  = 5'b0; 
        end

        // I-type (JALR)
        'h67: begin 
            next_signals.RegWrite  = 1'b1;
            next_signals.ALUSrc    = 1'b1; // Use Imm
            next_signals.ALUOp     = 2'b00; // ADD (rs1 + imm)
            next_signals.FU_type   = 2'b01; // BRU handles jumps
            next_signals.is_branch = 1'b1;
            next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:20]};
        end

        // J-type (JAL) - ★ 你缺失的部分 ★
        'h6f: begin 
            next_signals.RegWrite  = 1'b1;
            next_signals.ALUSrc    = 1'b1; // PC + 4 (handled in BRU/Execute)
            next_signals.FU_type   = 2'b01; // BRU
            next_signals.is_branch = 1'b1;
            // J-immediate decoding
            next_signals.immediate = {{12{fe_instr[31]}}, fe_instr[19:12], fe_instr[20], fe_instr[30:21], 1'b0};
        end

        // U-type (LUI)
        'h37: begin 
            next_signals.RegWrite = 1'b1;
            next_signals.ALUSrc   = 1'b1;
            next_signals.ALUOp    = 2'b00; // ADD
            next_signals.FU_type  = 2'b00; // ALU
            next_signals.immediate = {fe_instr[31:12], 12'h000};
            
            // ★ 关键修复：强制 rs1 为 x0，确保 ALU 计算 0 + imm ★
            next_signals.rs1_addr = 5'b0; 
            next_signals.rs1_addr = 5'b0; // NEWLY ADDED
        end
        
        // U-type (AUIPC) - 建议加上
        'h17: begin
            next_signals.RegWrite = 1'b1;
            next_signals.ALUSrc   = 1'b1;
            next_signals.FU_type  = 2'b00;
            next_signals.immediate = {fe_instr[31:12], 12'h000};
            // AUIPC 需要 PC + Imm。如果你的 ALU 不支持直接读 PC，这需要特殊处理。
            // 暂时假设你的 ALUOp=ADD 可以处理，或者你后续有 PC 通路。
        end

        default: begin
            next_signals.rd_addr = 5'b0;
            next_signals.RegWrite = 1'b0;
        end
    endcase
end


    // --- Pipeline Register & Handshake Logic ---

    // `de_ready`: We are ready to accept a new instruction from Fetch if...
    // 1. Our pipeline register is currently empty (!de_valid_reg), OR
    // 2. The Next stage (Rename) is ready to take our current instruction (re_ready)
    
    // FIX: Changed ex_ready to re_ready
    assign de_ready = !de_valid_reg || re_ready;

    logic load_en;
    assign load_en = fe_valid && de_ready;
    
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
            
            `ifndef SYNTHESIS
        $display("[DECODE] t=%0t pc=%h inst=%h opcode=%h rd=%0d rs1=%0d rs2=%0d imm=%0d FU=%0d RegWrite=%0d is_branch=%0d ALUSrc=%0d",
                 $time,
                 fe_pc,
                 fe_instr,
                 opcode,
                 rd,
                 rs1,
                 rs2,
                 next_signals.immediate,
                 next_signals.FU_type,
                 next_signals.RegWrite,
                 next_signals.is_branch,
                 next_signals.ALUSrc);
        `endif
        
        end
        // FIX: Changed ex_ready to re_ready
        else if (de_valid_reg && re_ready) begin
            de_valid_reg <= 1'b0;
        end
    end

endmodule