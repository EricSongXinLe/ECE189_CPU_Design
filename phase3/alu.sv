`timescale 1ns / 1ps
`include "riscv_types.svh"

module alu (
    input  logic                clk,
    input  logic                rst,
    input  logic                flush,

    // Issue Interface
    input  logic                valid_in,
    input  rename_to_dispatch_t instr_in,
    input  logic [31:0]         val1,
    input  logic [31:0]         val2,

    // Writeback Interface
    output logic                valid_out,
    output fu_to_prf_t          wb_packet
);

    logic [31:0] result;

    always_comb begin
        result = '0;
        // ALU Operation Decoder
        // ALUOp: 00=Add(L/S), 01=Sub(Br), 10=R-type, 11=I-type
        case (instr_in.funct3)
            3'b000: begin // ADD, SUB, ADDI
                // Check for SUB (R-type only, funct7[5]=1)
                if (instr_in.ALUOp == 2'b10 && instr_in.funct7[5]) 
                    result = val1 - val2;
                else 
                    result = val1 + val2; // ADD, ADDI, Memory Offset
            end
            3'b001: result = val1 << val2[4:0]; // SLL, SLLI
            3'b010: result = ($signed(val1) < $signed(val2)) ? 32'd1 : 32'd0; // SLT, SLTI
            3'b011: result = (val1 < val2) ? 32'd1 : 32'd0; // SLTU, SLTIU
            3'b100: result = val1 ^ val2; // XOR, XORI
            3'b101: begin // SRL, SRA, SRLI, SRAI
                if (instr_in.funct7[5]) result = $signed(val1) >>> val2[4:0]; // SRA
                else                    result = val1 >> val2[4:0];           // SRL
            end
            3'b110: result = val1 | val2; // OR, ORI
            3'b111: result = val1 & val2; // AND, ANDI
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
            // Always update data, valid bit controls usage
            wb_packet.prd_addr <= instr_in.prd_addr;
            wb_packet.data     <= result;
        end
    end

endmodule