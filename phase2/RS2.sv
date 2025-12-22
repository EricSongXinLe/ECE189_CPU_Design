`timescale 1ns / 1ps
`include "riscv_types.svh"

module RS (
    input logic clk,
    input logic rst,

    input logic dp_valid,
    input dispatch_to_rs_t dp_instr,
    output logic rs_full,

    input logic wb_valid [2:0],
    input fu_to_prf_t wb_packet [2:0], 

    output logic issue_valid,
    output dispatch_to_rs_t issue_instr,
    input logic fu_ready 
);

typedef struct packed {
    logic valid;
    dispatch_to_rs_t instr;
} rs_entry;

rs_entry rs_array [RS_SIZE];
logic [RS_SIZE-1:0] free_slot;
logic [RS_IDX_WIDTH-1:0] alloc_idx;
logic alloc_possible;


logic [RS_SIZE-1:0] ready_slot;
logic [RS_IDX_WIDTH-1:0] issue_idx;
logic issue_possible;

logic [RS_IDX_WIDTH-1:0] alloc_idx_eff;

integer i, j;

// --- Combinational Logic (what happens every cycle) ---
//check free slots (priority decoder) to put in instructions
// free = ~valid
always_comb begin
    free_slot = '0;
    for (i=0; i<RS_SIZE; i=i+1) begin
        free_slot[i] = ~rs_array[i].valid;
    end
end

//output free slot idx
priority_decoder u_free #(.WIDTH(RS_SIZE)) (
    .in(free_slot),
    .out(alloc_idx),
    .valid(alloc_possible)
);

assign rs_full = !alloc_possible;

//can issue if: ps1_ready && ps2_ready && fu_ready
always_comb begin
    ready_slot = '0;
    for (i=0; i<RS_SIZE; i=i+1) begin
        ready_slot[i] = rs_array[i].valid && rs_array[i].instr.ps1_ready && rs_array[i].instr.ps2_ready;
    end
end

priority_decoder u_issue #(.WIDTH(RS_SIZE)) (
    .in(ready_slot),
    .out(issue_idx),
    .valid(issue_possible)
);

// --- Sequential Logic (what needs to be stored: allocate, prepare ready, issue) ---
logic do_allocate;
logic do_issue;

assign alloc_idx_eff = alloc_possible ? alloc_idx : issue_idx; //to take care of the situation where rs is full and a slot is issued and then allocated.
assign do_issue = fu_ready && issue_possible;
assign do_allocate = dp_valid && (alloc_possible || do_issue);

//allocate instr into free slot
always_ff @(posedge clk) begin
    if (rst) begin
        for (i=0; i<RS_SIZE; i=i+1) begin
            rs_array[i] <= '0;
        end
        issue_valid <= '0;
        issue_instr <= '0;
    end else begin
        issue_valid <= '0;
        for (i=0; i<RS_SIZE; i=i+1) begin
            if (rs_array[i].valid) begin
                for (j=0; j<CDB_WIDTH; j=j+1) begin
                    if (wb_valid[j]) begin
                        if (wb_packet[j].prd_addr != 0 && (wb_packet[j].prd_addr == rs_array[i].instr.ps1_addr))
                            rs_array[i].instr.ps1_ready <= 1'b1;
                        if (wb_packet[j].prd_addr != 0 && wb_packet[j].prd_addr == rs_array[i].instr.ps2_addr)
                            rs_array[i].instr.ps2_ready <= 1'b1;
                    end
                end
            end
        end
        if (do_issue) begin
            issue_valid <= 1'b1;
            issue_instr <= rs_array[issue_idx].instr;
            rs_array[issue_idx].valid <= '0;

        end
        if (do_allocate) begin
            rs_array[alloc_idx_eff].valid <= 1'b1;
            rs_array[alloc_idx_eff].instr <= dp_instr;
        end 
    end
end

endmodule