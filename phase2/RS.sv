`timescale 1ns / 1ps
`include "riscv_types.svh"

module RS #(
    parameter RS_SIZE       = 8,
    parameter RS_IDX_WIDTH  = $clog2(RS_SIZE),
    parameter CDB_WIDTH     = 3,
    parameter PREG_ID_WIDTH = 7
)(
    input logic clk,
    input logic rst,
    input logic [(1<<PREG_ID_WIDTH)-1:0] busy_table,

    input  logic                dp_valid,
    input  dispatch_to_rs_t     dp_instr,
    output logic                rs_full,

    input  logic [CDB_WIDTH-1:0]       wb_valid,
    input  fu_to_prf_t [CDB_WIDTH-1:0] wb_packet,

    output logic                issue_valid,
    output dispatch_to_rs_t     issue_instr,
    input  logic                fu_ready,
    
    // ★ 新增端口：ROB 头部指针，用于计算年龄
    input logic [ROB_IDX_WIDTH-1:0] rob_head
);

    localparam int NUM_PREGS = (1 << PREG_ID_WIDTH);

    typedef struct packed {
        logic                valid;
        dispatch_to_rs_t     instr;
    } rs_entry_t;

    rs_entry_t rs_array [RS_SIZE];

    // --- Allocation Logic ---
    logic [RS_SIZE-1:0]      free_slots_bv;
    logic [RS_IDX_WIDTH-1:0] alloc_idx;
    logic                    alloc_possible;

    always_comb begin
        for (int i = 0; i < RS_SIZE; i++) begin
            free_slots_bv[i] = !rs_array[i].valid;
        end
    end

    priority_decoder #(.WIDTH(RS_SIZE)) u_alloc_pd (
        .in     (free_slots_bv),
        .out    (alloc_idx),
        .valid  (alloc_possible)
    );
    assign rs_full = !alloc_possible;

    // --- Wakeup Logic ---
    logic [RS_SIZE-1:0] next_op1_ready;
    logic [RS_SIZE-1:0] next_op2_ready;

    always_comb begin
        for (int i = 0; i < RS_SIZE; i++) begin
            next_op1_ready[i] = rs_array[i].instr.ps1_ready;
            next_op2_ready[i] = rs_array[i].instr.ps2_ready;

            if (!rs_array[i].valid) continue;

            // Op1
            if (rs_array[i].instr.ps1_addr == '0) next_op1_ready[i] = 1'b1;
            else if (!busy_table[ rs_array[i].instr.ps1_addr ]) next_op1_ready[i] = 1'b1;

            // Op2 (Store logic included)
            if ((rs_array[i].instr.ALUSrc && !rs_array[i].instr.MemWrite) || rs_array[i].instr.ps2_addr == '0)
                next_op2_ready[i] = 1'b1;
            else if (!busy_table[ rs_array[i].instr.ps2_addr ])
                next_op2_ready[i] = 1'b1;

            // Bypass
            for (int k = 0; k < CDB_WIDTH; k++) begin
                if (wb_valid[k] && wb_packet[k].prd_addr != '0) begin
                    if (rs_array[i].instr.ps1_addr == wb_packet[k].prd_addr)
                        next_op1_ready[i] = 1'b1;
                    if ((!rs_array[i].instr.ALUSrc || rs_array[i].instr.MemWrite) &&
                        rs_array[i].instr.ps2_addr == wb_packet[k].prd_addr)
                        next_op2_ready[i] = 1'b1;
                end
            end
        end
    end

    // --- Selection Logic (Fixing the Load/Store Hazard) ---
    logic [RS_SIZE-1:0]      ready_instr_bv;
    logic [RS_IDX_WIDTH-1:0] issue_idx;
    logic                    issue_possible;

    // 辅助函数：计算指令年龄 (距离 ROB Head 的距离)
    // 距离越小，指令越老。
    function logic [ROB_IDX_WIDTH-1:0] get_age(input [ROB_IDX_WIDTH-1:0] tag, input [ROB_IDX_WIDTH-1:0] head);
        return tag - head; // 利用溢出特性，直接相减即可得到环形缓冲区的距离
    endfunction

    always_comb begin
        for (int i = 0; i < RS_SIZE; i++) begin
            // 1. 基本 Ready 条件
            ready_instr_bv[i] = rs_array[i].valid && next_op1_ready[i] && next_op2_ready[i];

            // 2. ★ 内存指令顺序强制检查 ★
            // 如果我是内存指令 (Load 或 Store)
            if (ready_instr_bv[i] && (rs_array[i].instr.MemRead || rs_array[i].instr.MemWrite)) begin
                for (int j = 0; j < RS_SIZE; j++) begin
                    // 检查是否存在另一条有效的内存指令 j
                    if (i != j && rs_array[j].valid && (rs_array[j].instr.MemRead || rs_array[j].instr.MemWrite)) begin
                        // 如果 j 比 i 老 (age_j < age_i)，那么 i 必须等待 j 发射
                        if (get_age(rs_array[j].instr.rob_tag, rob_head) < get_age(rs_array[i].instr.rob_tag, rob_head)) begin
                            ready_instr_bv[i] = 1'b0; // 屏蔽 i，防止乱序发射
                        end
                    end
                end
            end
        end
    end

    priority_decoder #(.WIDTH(RS_SIZE)) u_issue_pd (
        .in     (ready_instr_bv),
        .out    (issue_idx),
        .valid  (issue_possible)
    );

    assign issue_valid = issue_possible && fu_ready;
    assign issue_instr = rs_array[issue_idx].instr;


    // --- State Update ---
    logic op1_alloc_ready, op2_alloc_ready;

    always_comb begin
        if (dp_instr.ps1_addr == '0) op1_alloc_ready = 1'b1;
        else op1_alloc_ready = !busy_table[ dp_instr.ps1_addr ];

        if ((dp_instr.ALUSrc && !dp_instr.MemWrite) || dp_instr.ps2_addr == '0)
            op2_alloc_ready = 1'b1;
        else op2_alloc_ready = !busy_table[ dp_instr.ps2_addr ];

        for (int k = 0; k < CDB_WIDTH; k++) begin
            if (wb_valid[k] && wb_packet[k].prd_addr != '0) begin
                if (dp_instr.ps1_addr == wb_packet[k].prd_addr) op1_alloc_ready = 1'b1;
                if ((!dp_instr.ALUSrc || dp_instr.MemWrite) && dp_instr.ps2_addr == wb_packet[k].prd_addr)
                    op2_alloc_ready = 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < RS_SIZE; i++) begin
                rs_array[i].valid           <= 1'b0;
                rs_array[i].instr           <= '0;
                rs_array[i].instr.ps1_ready <= 1'b0;
                rs_array[i].instr.ps2_ready <= 1'b0;
            end
        end else begin
            for (int i = 0; i < RS_SIZE; i++) begin
                if (rs_array[i].valid) begin
                    rs_array[i].instr.ps1_ready <= next_op1_ready[i];
                    rs_array[i].instr.ps2_ready <= next_op2_ready[i];
                end
            end

            if (issue_possible && fu_ready) begin
                rs_array[issue_idx].valid <= 1'b0;
            end

            if (dp_valid && !rs_full) begin
                rs_array[alloc_idx].valid <= 1'b1;
                rs_array[alloc_idx].instr <= dp_instr;
                rs_array[alloc_idx].instr.ps1_ready <= op1_alloc_ready;
                rs_array[alloc_idx].instr.ps2_ready <= op2_alloc_ready;
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
