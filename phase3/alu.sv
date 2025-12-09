`timescale 1ns / 1ps
`include "riscv_types.svh"

module alu (
    input  logic                clk,
    input  logic                rst,
    input  logic                flush,

    // Issue Interface
    input  logic                valid_in,
    input  dispatch_to_rs_t     instr_in,
    input  logic [31:0]         val1,
    input  logic [31:0]         val2,

    // Writeback Interface
    output logic                valid_out,
    output fu_to_prf_t          wb_packet
);

    logic [31:0] result;
    
    // 🔥 关键修复 1: 定义第二个操作数 op2 🔥
    // 如果 ALUSrc 为 1，选立即数；否则选 val2 (寄存器值)
    logic [31:0] op2;
    assign op2 = instr_in.ALUSrc ? instr_in.immediate : val2;

    always_comb begin
        result = '0;
        // ALU Operation Decoder
        case (instr_in.funct3)
            3'b000: begin // ADD, SUB, ADDI
                // Check for SUB (R-type only, funct7[5]=1, AND ALUSrc=0)
                // 注意：ADDI 不需要检查 funct7，所以必须确保不是 I-type
                if (instr_in.ALUOp == 2'b10 && instr_in.funct7[5] && !instr_in.ALUSrc) 
                    result = val1 - op2; // 🔥 改为 op2
                else 
                    result = val1 + op2; // 🔥 改为 op2
            end
            
            // 🔥 下面的 val2 全部替换为 op2 🔥
            3'b001: result = val1 << op2[4:0];                          // SLL, SLLI
            3'b010: result = ($signed(val1) < $signed(op2)) ? 32'd1 : 32'd0; // SLT, SLTI
            3'b011: result = (val1 < op2) ? 32'd1 : 32'd0;              // SLTU, SLTIU
            3'b100: result = val1 ^ op2;                                // XOR, XORI
            
            3'b101: begin // SRL, SRA, SRLI, SRAI
                if (instr_in.funct7[5] && !instr_in.ALUSrc) // R-type SRA check
                    result = $signed(val1) >>> op2[4:0]; 
                else if (instr_in.funct7[5] && instr_in.ALUSrc) // I-type SRAI (funct7[5] is usually 1 for SRAI too, verify spec)
                     // RISC-V Spec: SRAI also has funct7[5]=1. 
                     // 简单写法：对于移位指令，通常 I-type 和 R-type 的 funct7 类似
                    result = $signed(val1) >>> op2[4:0];
                else                    
                    result = val1 >> op2[4:0];
            end
            
            3'b110: result = val1 | op2; // OR, ORI
            3'b111: result = val1 & op2; // AND, ANDI
            default: result = '0;
        endcase
        
        // Override for LUI (U-type)
        if (instr_in.opcode == 7'h37) begin
            result = instr_in.immediate;
        end
    end

    // Pipeline Register (1 Cycle Latency)
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            valid_out <= 1'b0;
            wb_packet <= '0;
        end else begin
            valid_out <= valid_in;
            // Always update data
            wb_packet.prd_addr <= instr_in.prd_addr;
            wb_packet.data     <= result;
            wb_packet.rob_tag  <= instr_in.rob_tag;
        end
    end

endmodule