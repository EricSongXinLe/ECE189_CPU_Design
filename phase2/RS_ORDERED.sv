`timescale 1ns / 1ps
`include "riscv_types.svh"

module RS_ORDERED #(
    parameter RS_SIZE       = 8,
    parameter RS_IDX_WIDTH  = $clog2(RS_SIZE),
    parameter CDB_WIDTH     = 3,
    parameter PREG_ID_WIDTH = 7
)(
    input logic clk,
    input logic rst,
    input logic flush,
    input  logic [(1<<PREG_ID_WIDTH)-1:0] busy_table,

    // --- Dispatch Interface ---
    input  logic                dp_valid,
    input  dispatch_to_rs_t     dp_instr,
    output logic                rs_full, 

    // --- Writeback Interface ---
    input  logic [CDB_WIDTH-1:0]       wb_valid,
    input  fu_to_prf_t [CDB_WIDTH-1:0] wb_packet,

    // --- Issue Interface ---
    output logic                issue_valid,
    output dispatch_to_rs_t     issue_instr,
    input  logic                fu_ready
);

    // --- FIFO Pointers ---
    logic [RS_IDX_WIDTH-1:0] head;
    logic [RS_IDX_WIDTH-1:0] tail;
    logic [RS_IDX_WIDTH:0]   count; // Extra bit to distinguish full/empty

    // --- Storage ---
    typedef struct packed {
        logic                valid;
        dispatch_to_rs_t     instr;
    } rs_entry_t;

    rs_entry_t rs_array [RS_SIZE];

    // --- 1. Allocation Logic (FIFO Tail) ---
    // Full condition for FIFO
    assign rs_full = (count == RS_SIZE);

    // --- 2. Wakeup Logic (Combinational) ---
    // We strictly need to check if HEAD is ready, but we update all for simplicity/debug
    logic [RS_SIZE-1:0] next_op1_ready;
    logic [RS_SIZE-1:0] next_op2_ready;

    always_comb begin
        for (int i = 0; i < RS_SIZE; i++) begin
            // Inherit current state
            next_op1_ready[i] = rs_array[i].instr.ps1_ready;
            next_op2_ready[i] = rs_array[i].instr.ps2_ready;

            if (!rs_array[i].valid) continue;

            // Check OP1
            if (rs_array[i].instr.ps1_addr == '0)
                next_op1_ready[i] = 1'b1;
            else if (!busy_table[ rs_array[i].instr.ps1_addr ])
                next_op1_ready[i] = 1'b1;

            // Check OP2
            if ((rs_array[i].instr.ALUSrc && !rs_array[i].instr.MemWrite) || rs_array[i].instr.ps2_addr == '0)
                next_op2_ready[i] = 1'b1;
            else if (!busy_table[ rs_array[i].instr.ps2_addr ])
                next_op2_ready[i] = 1'b1;

            // CDB Wakeup
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

    // --- 3. Selection Logic (FIFO Head) ---
    // Issue only if not empty AND Head is ready
    logic head_ready;
    assign head_ready = (count > 0) && next_op1_ready[head] && next_op2_ready[head];
    
    assign issue_valid = head_ready && fu_ready;
    assign issue_instr = rs_array[head].instr;

    // --- 4. State Update & FIFO Management ---
    // Calculate initial ready bits for incoming instruction
    logic op1_alloc_ready, op2_alloc_ready;
    always_comb begin
        if (dp_instr.ps1_addr == '0) op1_alloc_ready = 1'b1;
        else op1_alloc_ready = !busy_table[ dp_instr.ps1_addr ];

        if ((dp_instr.ALUSrc && !dp_instr.MemWrite) || dp_instr.ps2_addr == '0) op2_alloc_ready = 1'b1;
        else op2_alloc_ready = !busy_table[ dp_instr.ps2_addr ];

        for (int k = 0; k < CDB_WIDTH; k++) begin
            if (wb_valid[k] && wb_packet[k].prd_addr != '0) begin
                if (dp_instr.ps1_addr == wb_packet[k].prd_addr)
                    op1_alloc_ready = 1'b1;
                if ((!dp_instr.ALUSrc || dp_instr.MemWrite) && dp_instr.ps2_addr == wb_packet[k].prd_addr)
                    op2_alloc_ready = 1'b1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            head  <= '0;
            tail  <= '0;
            count <= '0;
            for (int i = 0; i < RS_SIZE; i++) begin
                rs_array[i].valid <= 1'b0;
                rs_array[i].instr <= '0;
            end
        end else begin
            // Update Ready Bits for all entries
            for (int i = 0; i < RS_SIZE; i++) begin
                if (rs_array[i].valid) begin
                    rs_array[i].instr.ps1_ready <= next_op1_ready[i];
                    rs_array[i].instr.ps2_ready <= next_op2_ready[i];
                end
            end

            // FIFO Logic
            case ({ (dp_valid && !rs_full), (issue_valid) })
                2'b01: begin // Issue only
                    rs_array[head].valid <= 1'b0; // Optional clear
                    head  <= head + 1'b1;
                    count <= count - 1'b1;
                end
                2'b10: begin // Dispatch only
                    rs_array[tail].valid <= 1'b1;
                    rs_array[tail].instr <= dp_instr;
                    rs_array[tail].instr.ps1_ready <= op1_alloc_ready;
                    rs_array[tail].instr.ps2_ready <= op2_alloc_ready;
                    tail  <= tail + 1'b1;
                    count <= count + 1'b1;
                end
                2'b11: begin // Both
                    // Issue Head
                    rs_array[head].valid <= 1'b0;
                    head <= head + 1'b1;
                    
                    // Dispatch Tail
                    rs_array[tail].valid <= 1'b1;
                    rs_array[tail].instr <= dp_instr;
                    rs_array[tail].instr.ps1_ready <= op1_alloc_ready;
                    rs_array[tail].instr.ps2_ready <= op2_alloc_ready;
                    tail <= tail + 1'b1;
                    // Count stays same
                end
            endcase
        end
    end
    
    // --- Debug ---
    always_ff @(posedge clk) begin
        if (!rst && dp_valid && !rs_full)
            $display("[RS_LSU_ORD] t=%0t ENQ idx=%0d pc=%h", $time, tail, dp_instr.pc);
        if (!rst && issue_valid)
            $display("[RS_LSU_ORD] t=%0t DEQ idx=%0d pc=%h", $time, head, issue_instr.pc);
    end

endmodule