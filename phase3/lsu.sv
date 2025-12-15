`timescale 1ns / 1ps
`include "riscv_types.svh"

module lsu (
    input  logic                clk,
    input  logic                rst,
    input  logic                flush,

    // Issue Interface
    input  logic                valid_in,
    input  dispatch_to_rs_t     instr_in,
    input  logic [31:0]         val1,
    input  logic [31:0]         val2,

    // Data Memory Interface (BRAM)
    output logic                mem_en,
    output logic                mem_we,    
    output logic [31:0]         mem_addr,
    output logic [31:0]         mem_wdata,
    input  logic [31:0]         mem_rdata,

    // Writeback Interface
    output logic                valid_out,
    output fu_to_prf_t          wb_packet
);
    // --- Stage 1: Address Generation & Request ---
    logic [31:0] agu_addr;
    assign agu_addr = val1 + instr_in.immediate;

    assign mem_en   = valid_in;
    assign mem_addr = agu_addr;
    assign mem_we   = valid_in && instr_in.MemWrite;
    
    initial $display("!!! LSU FIXED VERSION COMPILED !!!");

    // --- Shift Logic for Stores ---
    always_comb begin
        mem_wdata = val2; 
        case (agu_addr[1:0])
            2'b00: mem_wdata = val2;
            2'b01: mem_wdata = val2 << 8;
            2'b10: mem_wdata = val2 << 16;
            2'b11: mem_wdata = val2 << 24;
        endcase
    end

    // --- Pipeline Registers ---
    logic valid_s1;
    dispatch_to_rs_t instr_s1; 
    logic [1:0] addr_low_s1;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            valid_s1    <= 1'b0;
            instr_s1    <= '0;
            addr_low_s1 <= 2'b0; 
        end else begin
            valid_s1    <= valid_in;
            // Capture all instruction info for Stage 2
            instr_s1.pc         <= instr_in.pc;
            instr_s1.immediate  <= instr_in.immediate;
            instr_s1.prd_addr   <= instr_in.prd_addr;  
            instr_s1.rob_tag    <= instr_in.rob_tag;
            instr_s1.MemRead    <= instr_in.MemRead;
            instr_s1.MemWrite   <= instr_in.MemWrite;
            instr_s1.ALUSrc     <= instr_in.ALUSrc;
            instr_s1.ALUOp      <= instr_in.ALUOp;
            instr_s1.funct7     <= instr_in.funct7;
            instr_s1.funct3     <= instr_in.funct3;
            instr_s1.opcode     <= instr_in.opcode;    
            instr_s1.FU_type    <= instr_in.FU_type;
            addr_low_s1 <= agu_addr[1:0];
        end
    end

    // --- Stage 2: Writeback ---
    // FIX: Removed always_ff for valid_out. 
    // valid_out now aligns with instr_s1 and mem_rdata (1 cycle latency).
    assign valid_out = valid_s1;

    // --- Output Logic ---
    always_comb begin
        // The warning below might trigger for rob=0, which is normal. 
        // You can ignore it if your system uses rob=0 as a valid tag.
        // if (instr_s1.rob_tag == 0 && instr_s1.opcode != 0) 
        //    $display("!!! WARNING: LSU processing instr with rob_tag=0 !!!");

        wb_packet.prd_addr = instr_s1.prd_addr;
        wb_packet.rob_tag  = instr_s1.rob_tag;
        wb_packet.data     = '0;

        // Load Logic
        if (instr_s1.opcode == 7'h03) begin
            unique case (instr_s1.funct3)
                // --- LB ---
                3'b000: begin
                    case (addr_low_s1)
                        2'b00: wb_packet.data = {{24{mem_rdata[7]}},  mem_rdata[7:0]};
                        2'b01: wb_packet.data = {{24{mem_rdata[15]}}, mem_rdata[15:8]};
                        2'b10: wb_packet.data = {{24{mem_rdata[23]}}, mem_rdata[23:16]};
                        2'b11: wb_packet.data = {{24{mem_rdata[31]}}, mem_rdata[31:24]};
                    endcase
                end
                // --- LH ---
                3'b001: begin
                    case (addr_low_s1[1])
                        1'b0: wb_packet.data = {{16{mem_rdata[15]}}, mem_rdata[15:0]};
                        1'b1: wb_packet.data = {{16{mem_rdata[31]}}, mem_rdata[31:16]};
                    endcase
                end
                // --- LW ---
                3'b010: begin
                    wb_packet.data = mem_rdata;
                end
                // --- LBU ---
                3'b100: begin
                    case (addr_low_s1)
                        2'b00: wb_packet.data = {24'b0, mem_rdata[7:0]};
                        2'b01: wb_packet.data = {24'b0, mem_rdata[15:8]};
                        2'b10: wb_packet.data = {24'b0, mem_rdata[23:16]};
                        2'b11: wb_packet.data = {24'b0, mem_rdata[31:24]};
                    endcase
                end
                // --- LHU ---
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
            wb_packet.data = '0;
        end
    end
    
    // Debug Print
    always_ff @(posedge clk) begin
        if (valid_in && !rst) begin
             $display("[LSU_DBG] t=%0t valid_in=1 rob=%0d prd=%0d op=%h", 
                      $time, instr_in.rob_tag, instr_in.prd_addr, instr_in.opcode);
        end
    end

endmodule