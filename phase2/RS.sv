`timescale 1ns / 1ps
`include "riscv_types.svh"

module reservation_station #(
    parameter RS_SIZE = 8,
    parameter RS_IDX_WIDTH = $clog2(RS_SIZE),
    parameter CDB_WIDTH = 3 // Number of writeback ports to snoop (ALU+LSU+BRU)
)(
    input logic clk,
    input logic rst,

    // --- Dispatch Interface (Allocate) ---
    input  logic                dp_valid,       // Dispatch is trying to write an instr
    input  rename_to_dispatch_t dp_instr,       // Instruction payload
    input  logic                op1_ready_in,   // Is PS1 ready in PRF right now? (From Scoreboard/BusyTable)
    input  logic                op2_ready_in,   // Is PS2 ready in PRF right now?
    output logic                rs_full,        // RS is full, stall Dispatch

    // --- Writeback/CDB Interface (Wakeup) ---
    // We snoop these signals to update op1_ready/op2_ready
    input  logic                wb_valid [CDB_WIDTH],
    input  fu_to_prf_t          wb_packet [CDB_WIDTH],

    // --- Issue Interface (Select) ---
    // Sent to Functional Unit / PRF Read Ports
    output logic                issue_valid,
    output rename_to_dispatch_t issue_instr,
    input  logic                fu_ready        // Functional Unit is ready to accept
);

    // --- Internal Data Structures ---
    typedef struct packed {
        logic                valid;      // Slot is occupied
        logic                op1_ready;  // Operand 1 is physically ready
        logic                op2_ready;  // Operand 2 is physically ready
        rename_to_dispatch_t instr;      // Payload
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
    // Determine the "Next State" for operand readiness based on WB snooping
    
    logic [RS_SIZE-1:0] next_op1_ready;
    logic [RS_SIZE-1:0] next_op2_ready;

    always_comb begin
        for (int i = 0; i < RS_SIZE; i++) begin
            // Default: keep current state
            next_op1_ready[i] = rs_array[i].op1_ready;
            next_op2_ready[i] = rs_array[i].op2_ready;

            // Check all Writeback ports
            for (int k = 0; k < CDB_WIDTH; k++) begin
                if (wb_valid[k] && wb_packet[k].prd_addr != '0) begin
                    // If waiting for this register, wake up!
                    if (rs_array[i].valid && rs_array[i].instr.ps1_addr == wb_packet[k].prd_addr)
                        next_op1_ready[i] = 1'b1;
                    if (rs_array[i].valid && rs_array[i].instr.ps2_addr == wb_packet[k].prd_addr)
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
            // Ready if: Valid AND Op1 Ready AND Op2 Ready
            // Note: We use next_op1_ready to allow "Forwarding" (issue same cycle as wakeup)
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
    
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < RS_SIZE; i++) begin
                rs_array[i].valid <= 1'b0;
                rs_array[i].op1_ready <= 1'b0;
                rs_array[i].op2_ready <= 1'b0;
                rs_array[i].instr <= '0;
            end
        end else begin
            // --- A. Wakeup Updates ---
            // Apply the snooped wakeup results calculated above
            for (int i = 0; i < RS_SIZE; i++) begin
                if (rs_array[i].valid) begin
                    rs_array[i].op1_ready <= next_op1_ready[i];
                    rs_array[i].op2_ready <= next_op2_ready[i];
                end
            end

            // --- B. Issue (Clear Slot) ---
            if (issue_possible && fu_ready) begin
                rs_array[issue_idx].valid <= 1'b0; // Free the slot
                // NOTE: In a more complex design, you might keep it valid until 
                // execution confirms no replay is needed, but for this project, 
                // issuing clears the RS entry.
            end

            // --- C. Allocate (Fill Slot) ---
            if (dp_valid && !rs_full) begin
                // If we are issuing from this slot same cycle, Dispatch takes priority 
                // (Reuse the slot immediately or just use a different one)
                // The PriorityDecoder for allocation ensures we pick a free one.
                // If the issue logic just freed slot X, alloc logic sees it as valid 
                // (old state) so it won't double allocate in one cycle unless forwarded.
                // Simple approach: Use the combinational alloc_idx.
                
                rs_array[alloc_idx].valid <= 1'b1;
                rs_array[alloc_idx].instr <= dp_instr;
                
                // Determine Initial Readiness
                // Ready if: Dispatch says it's ready OR it is being broadcast on WB bus RIGHT NOW
                
                logic op1_now, op2_now;
                op1_now = op1_ready_in;
                op2_now = op2_ready_in;

                // Check matches against concurrent Writebacks (Forwarding to Dispatch)
                for (int k = 0; k < CDB_WIDTH; k++) begin
                    if (wb_valid[k] && wb_packet[k].prd_addr == dp_instr.ps1_addr && dp_instr.ps1_addr != '0)
                        op1_now = 1'b1;
                    if (wb_valid[k] && wb_packet[k].prd_addr == dp_instr.ps2_addr && dp_instr.ps2_addr != '0)
                        op2_now = 1'b1;
                end

                // PS0 is always ready
                if (dp_instr.ps1_addr == '0) op1_now = 1'b1;
                if (dp_instr.ps2_addr == '0) op2_now = 1'b1;

                rs_array[alloc_idx].op1_ready <= op1_now;
                rs_array[alloc_idx].op2_ready <= op2_now;
            end
        end
    end

endmodule