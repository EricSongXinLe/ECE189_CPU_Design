`timescale 1ns / 1ps
`include "../phase2/riscv_types.svh"
module rename (
    input  logic clk,
    input  logic rst,

    // --- Upstream (from Decode) ---
    input  logic                de_valid,
    input  decode_to_rename_t   de_instr_in,
    output logic                rn_ready, // Ready to accept from Decode

    // --- Downstream (to Dispatch) ---
    output logic                rn_valid,
    output rename_to_dispatch_t rn_instr_out,
    input  logic                dp_ready,  // Dispatch is ready

    input logic commit_valid,
    input commit_to_rename_t commit_packet, //for freeing preg

    input rob_commit_t rob_flush //for misprediction
);

logic [ROB_IDX_WIDTH-1:0] rob_tag_counter;
logic [ROB_IDX_WIDTH-1:0] rob_tag_checkpoint;

    // --- 1. Map Table ---
    logic [PREG_IDX_WIDTH-1:0] map_table [ARCH_REGS-1:0];
    logic [PREG_IDX_WIDTH-1:0] map_table_copy [ARCH_REGS-1:0];
    logic map_table_copy_valid;

    always_comb begin
        rn_instr_out = '0;
        if (de_valid && rn_ready) begin
            if (de_instr_in.uses_rs1 && de_instr_in.rs1_addr != 0)
                rn_instr_out.ps1_addr = map_table[de_instr_in.rs1_addr];
            if (de_instr_in.uses_rs2 && de_instr_in.rs2_addr != 0)
                rn_instr_out.ps2_addr = map_table[de_instr_in.rs2_addr];
            if (de_instr_in.uses_rd && de_instr_in.rd_addr != 0) begin
                rn_instr_out.old_prd_addr = map_table[de_instr_in.rd_addr];
                rn_instr_out.prd_addr = fl_head;
            end

            rn_instr_out.rob_tag = rob_tag_counter;

            // --- Pass-through other signals ---
            rn_instr_out.pc         = de_instr_in.pc;
            rn_instr_out.immediate  = de_instr_in.immediate;
            rn_instr_out.uses_rd    = de_instr_in.uses_rd;
            rn_instr_out.RegWrite   = de_instr_in.RegWrite;
            rn_instr_out.MemRead    = de_instr_in.MemRead;
            rn_instr_out.MemWrite   = de_instr_in.MemWrite;
            rn_instr_out.MemToReg   = de_instr_in.MemToReg;
            rn_instr_out.ALUSrc     = de_instr_in.ALUSrc;
            rn_instr_out.is_branch  = de_instr_in.is_branch;
            rn_instr_out.is_jalr    = de_instr_in.is_jalr;
            rn_instr_out.is_store   = de_instr_in.is_store;
            rn_instr_out.ALUOp      = de_instr_in.ALUOp;
            rn_instr_out.funct7     = de_instr_in.funct7;
            rn_instr_out.funct3     = de_instr_in.funct3;
            rn_instr_out.opcode     = de_instr_in.opcode;
            rn_instr_out.FU_type    = de_instr_in.FU_type;
        end
    end

    //---- free list ----
    logic [PREG_IDX_WIDTH-1:0] fl_head;
    logic [PREG_IDX_WIDTH-1:0] fl_tail;
    logic no_free;
    logic all_free;
    logic [PREG_IDX_WIDTH-1:0] next_fl_head;
    logic [PREG_IDX_WIDTH-1:0] next_fl_tail;
    logic [FREE_CNT_W-1:0] free_count;
    logic [FREE_CNT_W-1:0] free_count_checkpoint;
    logic [PREG_IDX_WIDTH-1:0] fl_head_checkpoint;
    integer i;
    logic fl_allocate;
    logic fire;
    logic [FREE_CNT_W-1:0] delta_allocate;

    assign delta_allocate = (fl_head >= fl_head_checkpoint) ? (fl_head-fl_head_checkpoint) : (fl_head+FREE_MAX-fl_head_checkpoint);
    assign next_fl_head = (fl_head==PHYS_REGS-1)? ARCH_REGS : fl_head + 1;
    assign next_fl_tail = (fl_tail==PHYS_REGS-1)? ARCH_REGS : fl_tail + 1;

    assign all_free = (free_count == FREE_MAX);
    assign no_free = (free_count == 0);
    assign fl_allocate = de_valid && de_instr_in.uses_rd && (de_instr_in.rd_addr != 0);

    assign rn_ready = !(no_free && fl_allocate);
    assign rn_valid = de_valid && rn_ready;
    
    assign fire = rn_valid && dp_ready;

    assign write_en = commit_valid && commit_packet.uses_rd && (commit_packet.prd_addr != '0);
    assign read_en = fire&&fl_allocate;

    logic [FREE_CNT_W-1:0] free_count_next;
    always_comb begin
        free_count_next = free_count;
        if (read_en)  free_count_next = free_count_next - 1;
        if (write_en) free_count_next = free_count_next + 1;
    end

    always_ff @ (posedge clk) begin
        if (rst) begin
            free_count <= FREE_MAX;
            fl_head <= ARCH_REGS; //to avoid assigning p0, start assigning from p32
            fl_tail <= ARCH_REGS;
            for (i=0; i<ARCH_REGS; i=i+1)
                map_table[i] <= i;
            for (i=0; i<ARCH_REGS; i=i+1)
                map_table_copy[i] <= '0;
            map_table_copy_valid <= '0;
            rob_tag_counter <= '0;
        end
        else begin
            //misprediction has highest priority
            if (rob_flush.mispredict && map_table_copy_valid) begin
                //maptable restore
                for (i=1; i<ARCH_REGS; i=i+1) begin
                    map_table[i] <= map_table_copy[i];
                end
                map_table_copy_valid <= '0;
                //rob_tag recovery
                rob_tag_counter <= rob_tag_checkpoint + 1'b1;
                //freelist recovery
                free_count <= (free_count + delta_allocate > FREE_MAX) ? FREE_MAX : (free_count + delta_allocate);
                fl_head <= fl_head_checkpoint;
            end else begin
                free_count <= free_count_next;
                if (read_en) begin 
                    map_table[de_instr_in.rd_addr] <= fl_head;
                    fl_head <= next_fl_head;
                end
                if (write_en) begin
                    assert(commit_packet.prd_addr == fl_tail)
                    else $fatal("freelist order violated: got %0d expected %0d", commit_packet.prd_addr, fl_tail);
                    fl_tail <= next_fl_tail;
                end
                if(fire) //rn_valid&&dp_ready
                    rob_tag_counter <= rob_tag_counter + 1'b1;
                if (fire && (de_instr_in.is_branch || de_instr_in.is_jalr)) begin //recovery support
                    for (i=1; i<ARCH_REGS; i=i+1) begin 
                        if (read_en && (i == de_instr_in.rd_addr))
                            map_table_copy[i] <= fl_head;   // capture the *new* mapping
                        else
                        map_table_copy[i] <= map_table[i]; 
                    end 
                    map_table_copy_valid <= 1'b1;

                    fl_head_checkpoint <= read_en ? next_fl_head : fl_head; 
                    rob_tag_checkpoint <= rob_tag_counter;
                    free_count_checkpoint <= free_count_next;
                end
            end
        end
    end

endmodule