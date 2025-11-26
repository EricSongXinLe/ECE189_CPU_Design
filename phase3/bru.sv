`timescale 1ns / 1ps
`include "riscv_types.svh"

module bru (
    input  logic                clk,
    input  logic                rst,
    input  logic                flush,

    // Issue Interface
    input  logic                valid_in,
    input  rename_to_dispatch_t instr_in,
    input  logic [31:0]         val1,
    input  logic [31:0]         val2,

    // Writeback Interface (For Link Registers)
    output logic                valid_out,
    output fu_to_prf_t          wb_packet,

    // Branch Outcome Interface (Combinational for fast flush)
    output logic                br_taken,
    output logic [31:0]         target_pc,
    output logic                mispredict,
    output logic [ROB_IDX_WIDTH-1:0] rob_tag
);

    logic taken;
    logic [31:0] calc_target;
    logic is_jal, is_jalr, is_branch;

    // Opcode Decoding
    assign is_branch = (instr_in.opcode == 7'h63); // BNE, BEQ...
    assign is_jal    = (instr_in.opcode == 7'h6f); // JAL
    assign is_jalr   = (instr_in.opcode == 7'h67); // JALR

    // 1. Direction Logic
    always_comb begin
        taken = 1'b0;
        if (is_branch) begin
            case (instr_in.funct3)
                3'b000: taken = (val1 == val2);                         // BEQ
                3'b001: taken = (val1 != val2);                         // BNE
                3'b100: taken = ($signed(val1) < $signed(val2));        // BLT
                3'b101: taken = ($signed(val1) >= $signed(val2));       // BGE
                3'b110: taken = (val1 < val2);                          // BLTU
                3'b111: taken = (val1 >= val2);                         // BGEU
                default: taken = 1'b0;
            endcase
        end else if (is_jal || is_jalr) begin
            taken = 1'b1; // Unconditional jumps are always taken
        end
    end

    // 2. Target Calculation
    always_comb begin
        if (is_jalr) 
            // JALR: (rs1 + offset) & ~1
            calc_target = (val1 + instr_in.immediate) & ~32'd1;
        else 
            // B-type and JAL: PC + offset
            calc_target = instr_in.pc + instr_in.immediate;
    end

    // 3. Output Logic (Combinational)
    // We output these immediately so the Fetch Unit/ROB sees them in the same cycle as Execute
    assign br_taken   = valid_in && taken;
    assign target_pc  = calc_target;
    assign rob_tag    = instr_in.rob_tag;
    
    // Misprediction Logic:
    // Simple Model: Predict-Not-Taken. If branch is Taken, it's a mispredict.
    assign mispredict = valid_in && taken; 

    // 4. Pipeline Register (Writeback for Link Address)
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            valid_out <= 1'b0;
            wb_packet <= '0;
        end else begin
            valid_out <= valid_in;
            
            // Writeback logic
            wb_packet.prd_addr <= instr_in.prd_addr;
            
            // For JAL/JALR, write PC+4. For Branches, result is irrelevant (rd=0)
            if (is_jal || is_jalr)
                wb_packet.data <= instr_in.pc + 32'd4;
            else
                wb_packet.data <= '0;
        end
    end

endmodule