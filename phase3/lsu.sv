`timescale 1ns / 1ps
`include "riscv_types.svh"

module lsu (
    input  logic                clk,
    input  logic                rst,
    input  logic                flush,

    // Issue Interface
    input  logic                valid_in,
    input  dispatch_to_rs_t instr_in,
    input  logic [31:0]         val1,
    input  logic [31:0]         val2, // Store data (unused in Phase 3)

    // Data Memory Interface (BRAM)
    output logic                mem_en,
    output logic                mem_we,
    output logic [31:0]         mem_addr,
    output logic [31:0]         mem_wdata,
    input  logic [31:0]         mem_rdata, // Valid 1 or 2 cycles after request

    // Writeback Interface
    output logic                valid_out,
    output fu_to_prf_t          wb_packet
);

    // --- Stage 1: Address Generation & Request ---
    logic [31:0] agu_addr;
    assign agu_addr = val1 + instr_in.immediate;

    assign mem_en   = valid_in;
    assign mem_addr = agu_addr;

    assign mem_we    = valid_in && instr_in.MemWrite;
    always_comb begin
        mem_wdata = val2; // 默认
        case (agu_addr[1:0])
            2'b00: mem_wdata = val2;
            2'b01: mem_wdata = val2 << 8;
            2'b10: mem_wdata = val2 << 16;
            2'b11: mem_wdata = val2 << 24;
        endcase
    end
    // --- Pipeline Registers for Latency ---
    // We need to keep track of the instruction as it moves through the memory latency
    
    logic valid_s1;
    rename_to_dispatch_t instr_s1;
    logic [1:0] addr_low_s1;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            valid_s1 <= 1'b0;
            instr_s1 <= '0;
            addr_low_s1 <= 2'b0; // reset
        end else begin
            valid_s1 <= valid_in;
            instr_s1 <= instr_in;
            addr_low_s1 <= agu_addr[1:0];
        end
    end

    // --- Stage 2: Writeback ---
    // Logic: If BRAM takes 2 cycles (Request at T0, Data at T2), 
    // we need one register stage (S1).
    // T0: valid_in=1, mem_addr=X
    // T1: valid_s1=1 (BRAM is working)
    // T2: valid_out=1, mem_rdata is valid NOW.
    
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            valid_out <= 1'b0;
        end else begin
            valid_out <= valid_s1;
        end
    end

    // Combinational Data Path (Crucial Fix)
    // We do NOT register the data again, or we would miss the BRAM valid window.
    // We take mem_rdata directly as it arrives from BRAM.
    /*
    always_comb begin
        wb_packet.prd_addr = instr_s1.prd_addr;
        wb_packet.data     = mem_rdata; 
        wb_packet.rob_tag = instr_s1.rob_tag;
    end
    */

    //logic [1:0] byte_offset;
    //assign byte_offset = instr_s1.immediate[1:0] + val1[1:0]; // 简化的地址低位计算

    always_comb begin
        wb_packet.prd_addr = instr_s1.prd_addr;
        wb_packet.rob_tag  = instr_s1.rob_tag;
        wb_packet.data     = '0; // 默认清零

        // 仅当是 Load 指令 (opcode 7'h03) 时进行处理
        if (instr_s1.opcode == 7'h03) begin
            unique case (instr_s1.funct3)
                // --- LB: Load Byte (Signed Extension) ---
                3'b000: begin
                    case (addr_low_s1)
                        2'b00: wb_packet.data = {{24{mem_rdata[7]}},  mem_rdata[7:0]};
                        2'b01: wb_packet.data = {{24{mem_rdata[15]}}, mem_rdata[15:8]};
                        2'b10: wb_packet.data = {{24{mem_rdata[23]}}, mem_rdata[23:16]};
                        2'b11: wb_packet.data = {{24{mem_rdata[31]}}, mem_rdata[31:24]};
                    endcase
                end
                
                // --- LH: Load Halfword (Signed Extension) ---
                3'b001: begin
                    case (addr_low_s1[1]) // 0 or 2
                        1'b0: wb_packet.data = {{16{mem_rdata[15]}}, mem_rdata[15:0]};
                        1'b1: wb_packet.data = {{16{mem_rdata[31]}}, mem_rdata[31:16]};
                    endcase
                end

                // --- LW: Load Word ---
                3'b010: begin
                    wb_packet.data = mem_rdata;
                end

                // --- LBU: Load Byte (Unsigned / Zero Extension) ---
                3'b100: begin
                    case (addr_low_s1)
                        2'b00: wb_packet.data = {24'b0, mem_rdata[7:0]};
                        2'b01: wb_packet.data = {24'b0, mem_rdata[15:8]};
                        2'b10: wb_packet.data = {24'b0, mem_rdata[23:16]};
                        2'b11: wb_packet.data = {24'b0, mem_rdata[31:24]};
                    endcase
                end

                // --- LHU: Load Halfword (Unsigned / Zero Extension) ---
                3'b101: begin
                    case (addr_low_s1[1])
                        1'b0: wb_packet.data = {16'b0, mem_rdata[15:0]};
                        1'b1: wb_packet.data = {16'b0, mem_rdata[31:16]};
                    endcase
                end

                default: wb_packet.data = mem_rdata;
            endcase
        end 
        else begin
            // 非 Load 指令 (理论上 LSU 不会有其他写回，但也可能是 Store 的 ack)
            // wb_packet.data = mem_rdata;
            wb_packet.data = 0;
        end
    end

endmodule