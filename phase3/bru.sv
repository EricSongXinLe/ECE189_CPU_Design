`timescale 1ns / 1ps
`include "riscv_types.svh"

module bru (
    input  logic                clk,
    input  logic                rst,
    input  logic                flush,

    // Issue Interface
    input  logic                valid_in,
    input  dispatch_to_rs_t instr_in,
    input  logic [31:0]         val1,
    input  logic [31:0]         val2,

    // Writeback Interface (For Link Registers)
    output logic                valid_out,
    output fu_to_prf_t          wb_packet,

    // Branch Outcome Interface (Combinational for fast flush)
    output logic                is_jalr,
    output logic [31:0]         target_pc,
    output logic                mispredict,
    output logic [ROB_IDX_WIDTH-1:0] rob_tag
);

    logic taken;
    logic [31:0] calc_target;
    logic is_branch;
    
    // Opcode Decoding
    assign is_branch = (instr_in.opcode == 7'h63); // BNE
    assign is_jalr   = (instr_in.opcode == 7'h67); // JALR

    // 1. Direction Logic
    always_comb begin
        taken = 1'b0;
        if (is_branch) begin
            taken = (val1 != val2);
        end else if (is_jalr) begin
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
    assign target_pc  = calc_target;
    assign rob_tag    = instr_in.rob_tag;
    
    // Misprediction Logic:
    // Simple Model: Predict-Not-Taken. If branch is Taken, it's a mispredict.
    assign mispredict = valid_in && is_branch && taken; 

    // 4. Pipeline Register (Writeback for Link Address)
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            valid_out <= 1'b0;
            wb_packet <= '0;
        end else begin
            valid_out <= valid_in;
            
            // Writeback logic
            wb_packet.prd_addr <= instr_in.prd_addr;
            wb_packet.rob_tag <= instr_in.rob_tag;
            
            // For JAL/JALR, write PC+4. For Branches, result is irrelevant (rd=0)
            if (is_jalr) begin
                wb_packet.data <= instr_in.pc + 32'd4;
            end else
                wb_packet.data <= '0;
        end
    end

endmodule