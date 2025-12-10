`timescale 1ns / 1ps
`include "riscv_types.svh"

module RS #(
    parameter RS_SIZE       = 8,
    parameter RS_IDX_WIDTH  = $clog2(RS_SIZE),
    parameter CDB_WIDTH     = 3,          // Number of writeback ports to snoop (ALU+LSU+BRU)
    parameter PREG_ID_WIDTH = 7          // 和 PREG_IDX_WIDTH 保持一致
)(
    input logic clk,
    input logic rst,

    // --- 来自全局 scoreboard 的 busy_table ---
    // busy_table[preg_id] == 1 表示这个物理寄存器还在等待写回
    input  logic [(1<<PREG_ID_WIDTH)-1:0] busy_table,

    // --- Dispatch Interface (Allocate) ---
    input  logic                dp_valid,       // Dispatch is trying to write an instr
    input  dispatch_to_rs_t     dp_instr,       // Instruction payload
    output logic                rs_full,        // RS is full, stall Dispatch

    // --- Writeback/CDB Interface (Wakeup) ---
    input  logic [CDB_WIDTH-1:0]       wb_valid,
    input  fu_to_prf_t [CDB_WIDTH-1:0] wb_packet,

    // --- Issue Interface (Select) ---
    output logic                issue_valid,
    output dispatch_to_rs_t     issue_instr,
    input  logic                fu_ready
);

    localparam int NUM_PREGS = (1 << PREG_ID_WIDTH);

    // --- Internal Data Structures ---
    typedef struct packed {
        logic                valid;      // Slot is occupied
        dispatch_to_rs_t     instr;      // Payload
    } rs_entry_t;

    rs_entry_t rs_array [RS_SIZE];

    // --- 1. Allocation Logic (Find Free Slot) ---
    logic [RS_SIZE-1:0]      free_slots_bv;   // Bitvector of free slots
    logic [RS_IDX_WIDTH-1:0] alloc_idx;       // Index to write to
    logic                    alloc_possible;  // At least one slot is free

    // Invert 'valid' bits to find 'free' slots
    always_comb begin
        for (int i = 0; i < RS_SIZE; i++) begin
            free_slots_bv[i] = !rs_array[i].valid;
        end
    end

    // Priority Decoder 1: Find first free slot
    priority_decoder #(.WIDTH(RS_SIZE)) u_alloc_pd (
        .in     (free_slots_bv),
        .out    (alloc_idx),
        .valid  (alloc_possible)
    );

    assign rs_full = !alloc_possible; // If no free slots, we are full

    // --- 2. Wakeup Logic (Combinational) ---
    // next_op*_ready = 当前 ready 状态
    //  + scoreboard 看 busy_table
    //  + CDB 同周期唤醒
    logic [RS_SIZE-1:0] next_op1_ready;
    logic [RS_SIZE-1:0] next_op2_ready;

    always_comb begin
        for (int i = 0; i < RS_SIZE; i++) begin
            // 默认先保留当前存的 ready bit
            next_op1_ready[i] = rs_array[i].instr.ps1_ready;
            next_op2_ready[i] = rs_array[i].instr.ps2_ready;

            if (!rs_array[i].valid) begin
                continue;
            end

            // ---- 源操作数 1：x0 或 scoreboard 不 busy => ready ----
            if (rs_array[i].instr.ps1_addr == '0) begin
                next_op1_ready[i] = 1'b1;
            end else if (!busy_table[ rs_array[i].instr.ps1_addr ]) begin
                next_op1_ready[i] = 1'b1;
            end

            // ---- 源操作数 2：ALUSrc(立即数) / x0 / scoreboard 不 busy => ready ----
            if (rs_array[i].instr.ALUSrc || rs_array[i].instr.ps2_addr == '0) begin
                next_op2_ready[i] = 1'b1;
            end else if (!busy_table[ rs_array[i].instr.ps2_addr ]) begin
                next_op2_ready[i] = 1'b1;
            end

            // ---- 再用 CDB 做一个"同周期"唤醒 ----
            for (int k = 0; k < CDB_WIDTH; k++) begin
                if (wb_valid[k] && wb_packet[k].prd_addr != '0) begin
                    if (rs_array[i].instr.ps1_addr == wb_packet[k].prd_addr)
                        next_op1_ready[i] = 1'b1;
                    if (!rs_array[i].instr.ALUSrc &&
                        rs_array[i].instr.ps2_addr == wb_packet[k].prd_addr)
                        next_op2_ready[i] = 1'b1;
                end
            end
        end
    end

    // --- 3. Selection Logic (Find Ready Instruction) ---
    logic [RS_SIZE-1:0]      ready_instr_bv; // Bitvector of ready-to-issue instructions
    logic [RS_IDX_WIDTH-1:0] issue_idx;      // Index to issue
    logic                    issue_possible; // Found a candidate

    always_comb begin
        for (int i = 0; i < RS_SIZE; i++) begin
            ready_instr_bv[i] = rs_array[i].valid && next_op1_ready[i] && next_op2_ready[i];
        end
    end

    // Priority Decoder 2: Find first ready instruction
    priority_decoder #(.WIDTH(RS_SIZE)) u_issue_pd (
        .in     (ready_instr_bv),
        .out    (issue_idx),
        .valid  (issue_possible)
    );

    // --- Output Assignment ---
    assign issue_valid = issue_possible && fu_ready;
    assign issue_instr = rs_array[issue_idx].instr;

    // --- 4. State Update (Sequential) ---

    logic op1_alloc_ready, op2_alloc_ready;

    // 分配新条目时的初始 ready 状态，同样结合 scoreboard + CDB
    always_comb begin
        // 默认：根据 scoreboard/x0/ALUSrc 来判断
        if (dp_instr.ps1_addr == '0)
            op1_alloc_ready = 1'b1;
        else
            op1_alloc_ready = !busy_table[ dp_instr.ps1_addr ];

        if (dp_instr.ALUSrc || dp_instr.ps2_addr == '0)
            op2_alloc_ready = 1'b1;
        else
            op2_alloc_ready = !busy_table[ dp_instr.ps2_addr ];

        // 再考虑"刚好这周期写回"的情况，用 CDB 做 bypass 唤醒
        for (int k = 0; k < CDB_WIDTH; k++) begin
            if (wb_valid[k] && wb_packet[k].prd_addr != '0) begin
                if (dp_instr.ps1_addr == wb_packet[k].prd_addr)
                    op1_alloc_ready = 1'b1;
                if (!dp_instr.ALUSrc && dp_instr.ps2_addr == wb_packet[k].prd_addr)
                    op2_alloc_ready = 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < RS_SIZE; i++) begin
                rs_array[i].valid              <= 1'b0;
                rs_array[i].instr              <= '0;
                rs_array[i].instr.ps1_ready    <= 1'b0;
                rs_array[i].instr.ps2_ready    <= 1'b0;
            end
        end else begin
            // --- A. 用 next_op*_ready 更新条目中的 ready bit（仅用于 debug 展示） ---
            for (int i = 0; i < RS_SIZE; i++) begin
                if (rs_array[i].valid) begin
                    rs_array[i].instr.ps1_ready <= next_op1_ready[i];
                    rs_array[i].instr.ps2_ready <= next_op2_ready[i];
                end
            end

            // --- B. Issue (Clear Slot) ---
            if (issue_possible && fu_ready) begin
                rs_array[issue_idx].valid <= 1'b0; // Free the slot
            end

            // --- C. Allocate (Fill Slot) ---
            if (dp_valid && !rs_full) begin
                rs_array[alloc_idx].valid <= 1'b1;
                rs_array[alloc_idx].instr <= dp_instr;

                rs_array[alloc_idx].instr.ps1_ready <= op1_alloc_ready;
                rs_array[alloc_idx].instr.ps2_ready <= op2_alloc_ready;
            end
        end
    end

    // ===== Debug：保持你原来的打印 =====
    always_ff @(posedge clk) begin
        if (!rst) begin
            if (dp_valid && !rs_full) begin
                $display("[RS_BR] t=%0t ALLOC FU=%0d pc=%h ps1=%0d rdy1=%0d ps2=%0d rdy2=%0d prd=%0d rob=%0d",
                         $time,
                         dp_instr.FU_type,
                         dp_instr.pc,
                         dp_instr.ps1_addr, op1_alloc_ready,
                         dp_instr.ps2_addr, op2_alloc_ready,
                         dp_instr.prd_addr,
                         dp_instr.rob_tag);
            end
        end
    end

always_ff @(posedge clk) begin
    if (!rst) begin
        if (issue_valid && fu_ready) begin
            $display("[RS_BR] t=%0t ISSUE pc=%h ps1_rdy=%0d ps2_rdy=%0d rob=%0d",
                     $time,
                     issue_instr.pc,
                     next_op1_ready[issue_idx],  // ✅ 用本周期"真实 ready"信号
                     next_op2_ready[issue_idx],
                     issue_instr.rob_tag);
        end
    end
end


always_ff @(posedge clk) begin
    if (!rst) begin
        for (int i = 0; i < RS_SIZE; i++) begin
            if (rs_array[i].valid && rs_array[i].instr.pc == 32'h00000010) begin
                $display("[RS_BR-STATE] t=%0t idx=%0d pc=%h ps1=%0d rdy1=%0d ps2=%0d rdy2=%0d | ready_vec=%b issue_possible=%0d fu_ready=%0d",
                         $time,
                         i,
                         rs_array[i].instr.pc,
                         rs_array[i].instr.ps1_addr,
                         next_op1_ready[i],       // ✅ 用组合 ready
                         rs_array[i].instr.ps2_addr,
                         next_op2_ready[i],       // ✅ 用组合 ready
                         ready_instr_bv,
                         issue_possible,
                         fu_ready);
            end
        end
    end
end


endmodule
