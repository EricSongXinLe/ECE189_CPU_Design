`timescale 1ns / 1ps
`include "../phase2/riscv_types.svh"

module dispatch (
    input logic clk, rst,

    //rename <-> dispatch
    output logic dp_ready_out,
    input  logic buffer_valid_in,
    input  rename_to_dispatch_t buffer_instr_in,

    //dispatch <-> ROB
    input  logic rob_full,
    output logic rob_valid,
    output dispatch_to_rob_t rob_instr,

    //dispatch <-> RS (3)
    input  logic rs_alu_full,
    output logic rs_alu_valid,
    output dispatch_to_rs_t rs_alu_instr,

    input  logic rs_br_full,
    output logic rs_br_valid,
    output dispatch_to_rs_t rs_br_instr,

    input  logic rs_lsu_full,
    output logic rs_lsu_valid,
    output dispatch_to_rs_t rs_lsu_instr,

    input  logic       wb_valid  [2:0],
    input  fu_to_prf_t wb_packet [2:0]
);

    // -----------------------------
    // Local helpers
    // -----------------------------
    logic is_store;
    assign is_store = buffer_instr_in.is_store;

    // -----------------------------
    // Store Queue (SQ)
    // -----------------------------
    logic [ROB_IDX_WIDTH-1:0] sq_head, sq_tail, next_sq_tail;
    logic sq_full;

    sq_t sq_entry [ROB_SIZE-1:0];
    integer i;

    assign next_sq_tail = (sq_tail == ROB_SIZE-1) ? '0 : (sq_tail + 1'b1);
    assign sq_full      = (next_sq_tail == sq_head);

    // -----------------------------
    // RS/ROB availability
    // -----------------------------
    logic rs_ready, rob_ready;

    always_comb begin
        rs_ready = 1'b0;
        if (buffer_valid_in) begin
            unique case (buffer_instr_in.FU_type)
                2'b00: rs_ready = !rs_alu_full; // ALU
                2'b01: rs_ready = !rs_br_full;  // BRU
                2'b10: rs_ready = !rs_lsu_full; // LSU
                default: rs_ready = 1'b0;
            endcase
        end
    end

    assign rob_ready = !rob_full;

    logic sq_ready;
    assign sq_ready = (!is_store) || (!sq_full);

    logic dispatch_fire;
    assign dispatch_fire = buffer_valid_in && rs_ready && rob_ready && sq_ready;

    assign dp_ready_out = (!buffer_valid_in) ? 1'b1 : (rs_ready && rob_ready && sq_ready);

    // -----------------------------
    // Scoreboard lookup (src ready)
    // -----------------------------
    logic src1_rdy, src2_rdy;
    logic [PREG_IDX_WIDTH-1:0] wb_dest_addrs [2:0];

    always_comb begin
        for (int j = 0; j < 3; j++) begin
            wb_dest_addrs[j] = wb_packet[j].prd_addr;
        end
    end

    phys_reg_status_table #(.CDB_WIDTH(3)) u_scoreboard (
        .clk (clk),
        .rst (rst),

        .dispatch_valid     (dispatch_fire && buffer_instr_in.uses_rd && (buffer_instr_in.prd_addr != '0)),
        .dispatch_dest_preg (buffer_instr_in.prd_addr),

        .wb_valid           (wb_valid),
        .wb_dest_preg       (wb_dest_addrs),

        .src1_preg          (buffer_instr_in.ps1_addr),
        .src2_preg          (buffer_instr_in.ps2_addr),

        .src1_ready         (src1_rdy),
        .src2_ready         (src2_rdy)
    );

    // -----------------------------
    // RS entry
    // -----------------------------
    dispatch_to_rs_t new_rs_entry;

    always_comb begin
        new_rs_entry = '0;

        if (buffer_valid_in) begin
            new_rs_entry.immediate  = buffer_instr_in.immediate;
            new_rs_entry.ps1_addr   = buffer_instr_in.ps1_addr;
            new_rs_entry.ps2_addr   = buffer_instr_in.ps2_addr;
            new_rs_entry.ps1_ready  = src1_rdy;
            new_rs_entry.ps2_ready  = src2_rdy;

            new_rs_entry.uses_rd    = buffer_instr_in.uses_rd;
            new_rs_entry.prd_addr   = buffer_instr_in.prd_addr;
            new_rs_entry.rob_tag    = buffer_instr_in.rob_tag;

            new_rs_entry.is_branch  = buffer_instr_in.is_branch;
            new_rs_entry.is_jalr    = buffer_instr_in.is_jalr;
            new_rs_entry.is_store   = buffer_instr_in.is_store;

            new_rs_entry.MemRead    = buffer_instr_in.MemRead;
            new_rs_entry.MemWrite   = buffer_instr_in.MemWrite;
            new_rs_entry.ALUSrc     = buffer_instr_in.ALUSrc;
            new_rs_entry.ALUOp      = buffer_instr_in.ALUOp;
            new_rs_entry.funct3     = buffer_instr_in.funct3;
            new_rs_entry.funct7     = buffer_instr_in.funct7;
            new_rs_entry.opcode     = buffer_instr_in.opcode;
            new_rs_entry.FU_type    = buffer_instr_in.FU_type;

            // SQ index only meaningful for stores, and only when we will actually fire
            if (dispatch_fire && is_store) begin
                new_rs_entry.sq_idx = sq_tail;
                new_rob_entry.sq_idx = sq_tail;
            end else begin
                new_rs_entry.sq_idx = '0;
                new_rob_entry.sq_idx = '0;
            end
        end
    end

    assign rs_alu_instr = new_rs_entry;
    assign rs_br_instr  = new_rs_entry;
    assign rs_lsu_instr = new_rs_entry;

    // RS valids
    assign rs_alu_valid = dispatch_fire && (buffer_instr_in.FU_type == 2'b00);
    assign rs_br_valid  = dispatch_fire && (buffer_instr_in.FU_type == 2'b01);
    assign rs_lsu_valid = dispatch_fire && (buffer_instr_in.FU_type == 2'b10);

    // -----------------------------
    // ROB entry
    // -----------------------------
    dispatch_to_rob_t new_rob_entry;

    always_comb begin
        new_rob_entry = '0;
        if (buffer_valid_in) begin
            new_rob_entry.pc           = buffer_instr_in.pc;
            new_rob_entry.prd_addr     = buffer_instr_in.prd_addr;
            new_rob_entry.old_prd_addr = buffer_instr_in.old_prd_addr;
            new_rob_entry.rob_tag      = buffer_instr_in.rob_tag;
            new_rob_entry.is_branch    = buffer_instr_in.is_branch;
            new_rob_entry.is_jalr      = buffer_instr_in.is_jalr;
            new_rob_entry.is_store     = buffer_instr_in.is_store;
        end
    end

    assign rob_instr  = new_rob_entry;
    assign rob_valid  = dispatch_fire;

    // -----------------------------
    // SQ enqueue
    // -----------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            sq_head <= '0;
            sq_tail <= '0;
            for (i = 0; i < ROB_SIZE; i = i + 1) begin
                sq_entry[i] <= '0;
            end
        end else begin
            if (dispatch_fire && is_store) begin
                sq_entry[sq_tail].valid   <= 1'b1;
                sq_entry[sq_tail].rob_tag <= buffer_instr_in.rob_tag;
                sq_entry[sq_tail].funct3  <= buffer_instr_in.funct3;
                sq_tail <= next_sq_tail;
            end
        end
    end

endmodule
