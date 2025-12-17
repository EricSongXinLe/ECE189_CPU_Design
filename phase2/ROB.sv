typedef struct packed {
    logic valid; //this entry is occupied / contains an allocated instruction
    logic complete; //instruction has completed execution / writeback
    logic isBusy; //starts when instr is inserted into the rob; not when commited
    logic [6:0] prd_addr; 
    logic [6:0] old_prd_addr;
    logic [31:0] pc;
    logic is_branch;
    logic [ROB_IDX_WIDTH-1:0] recovery_ptr; //if is_branch, store the rob_idx at that point
    logic [ROB_IDX_WIDTH-1:0] rob_idx;
    logic mispredict;
    logic [31:0] branch_target;
} rob_entry;



module ROB #(
    parameter ROB_SIZE = 16,
    parameter ROB_IDX_WIDTH = $clog2(ROB_SIZE)
)(
    input logic clk,
    input logic rst,

    input dispatch_to_rob_t dp_data_in,
    input logic dp_valid,

    input logic flush,
    input fu_to_rob_t fu_wb,

    input  logic wb_valid [3],
    input  fu_to_prf_t wb_packet[3],

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
        for (int i = 0; i < 3; i++) begin
            if (wb_valid[i]) begin
                ROB[ wb_packet[i].rob_tag ].complete <= 1'b1;
            end
        end
        if (flush) begin //flush
            ROB[fu_wb.rob_tag].complete <= 1'b1;
            ROB[fu_wb.rob_tag].mispredict <= fu_wb.mispredict;
            ROB[fu_wb.rob_tag].branch_target <= fu_wb.branch_target;

            for (i=0; i < ROB_SIZE; i=i+1) begin
                if (i > fu_wb.rob_tag) begin
                    ROB[i] <='0;
                end
            end
            
            tail <= fu_wb.rob_tag + 1'b1;
        end
        //fill in data from rename
        if(dp_valid && !rob_full) begin
            ROB[tail].valid <= 1'b1;
            ROB[tail].complete <= 1'b0;
            ROB[tail].isBusy <= 1'b1;
            ROB[tail].prd_addr <= dp_data_in.prd_addr;
            ROB[tail].old_prd_addr <= dp_data_in.old_prd_addr;
            ROB[tail].pc <= dp_data_in.pc;
            ROB[tail].is_branch <= dp_data_in.is_branch;
            ROB[tail].recovery_ptr <= dp_data_in.is_branch ? tail : '0;
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