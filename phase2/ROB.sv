typedef struct packed {
    logic valid; //this entry is occupied / contains an allocated instruction
    logic complete; //instruction has completed execution / writeback
    logic isBusy; //starts when instr is inserted into the rob; not when commited
    logic [6:0] prd_addr; 
    logic [6:0] old_prd_addr;
    logic [31:0] pc;
    logic is_branch;
    logic [ROB_IDX_WIDTH-1:0] recovery_ptr; //if isBranch, store the rob_idx at that point
    logic [ROB_IDX_WIDTH-1:0] rob_idx;
    logic mispredict;
    logic [31:0] branch_target;
} rob_entry;

typedef struct packed {
    logic commit_valid;
    logic [ROB_IDX_WIDTH-1:0] commit_idx;
    logic mispredict;
    logic [31:0] branch_target;
}
rob_commit_t;

module ROB #(
    parameter ROB_SIZE = 16,
    parameter ROB_IDX_WIDTH = $clog2(ROB_SIZE)
)(
    input logic clk,
    input logic rst,

    input dispatch_to_rob_t rn_data_in,
    input logic re_valid,

    input logic fu_valid,
    input fu_to_rob_t fu_wb,

    output logic rob_full,
    output rob_commit_t rob_commit
);

rob_entry ROB [0:ROB_SIZE-1];
logic [ROB_IDX_WIDTH-1:0] head, tail;
logic empty;
rob_commit_t rob_head_in;

assign empty = (tail == head);
assign rob_full = ((tail + 4'd1) == head);

integer i;
always_ff @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < ROB_SIZE; i = i+1)
            ROB[i] <= '0;
        head <= '0;
        tail <= '0;
        rob_head_in <= '0;
    end

    else begin
        rob_head_in.commit_valid <= 1'b0;
        if (fu_valid) begin
            ROB[fu_wb.rob_tag].complete <= 1'b1;
            ROB[fu_wb.rob_tag].mispredict <= fu_wb.mispredict;
            ROB[fu_wb.rob_tag].branch_target <= fu_wb.branch_target;
        end
        //fill in data from rename
        if(re_valid && !rob_full) begin
            ROB[tail].valid <= 1'b1;
            ROB[tail].complete <= 1'b0;
            ROB[tail].isBusy <= 1'b1;
            ROB[tail].prd_addr <= rn_data_in.prd_addr;
            ROB[tail].old_prd_addr <= rn_data_in.old_prd_addr;
            ROB[tail].pc <= rn_data_in.pc;
            ROB[tail].is_branch <= rn_data_in.is_branch;
            ROB[tail].recovery_ptr <= rn_data_in.is_branch ? tail : '0;
            ROB[tail].rob_idx <= tail;
            tail <= (tail==ROB_SIZE-1) ? 0 : tail + 4'd1;
        end
        if (ROB[head].valid && ROB[head].complete) begin
            rob_head_in.commit_valid <= 1'b1;
            rob_head_in.commit_idx <= head;
            rob_head_in.mispredict <= ROB[head].mispredict;
            rob_head_in.branch_target <= ROB[head].branch_target;
            ROB[head] <= '0;
            head <= (head == ROB_SIZE-1) ? '0 : head + 4'd1;
        end
    end
end

assign rob_commit = rob_head_in;

endmodule