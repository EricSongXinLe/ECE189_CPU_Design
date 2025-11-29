typedef struct packed {
    logic valid; //this entry is occupied / contains an allocated instruction
    logic complete; //instruction has completed execution / writeback
    logic isBusy; //starts when instr is inserted into the rob; not when commited
    logic [6:0] prd_addr; 
    logic [6:0] old_prd_addr;
    logic [31:0] pc;
    logic is_branch;
    logic [3:0] recovery_ptr; //if isBranch, store the rob_idx at that point
    logic [3:0] rob_idx;
} rob_entry;

module ROB #(
    parameter ROB_SIZE = 16
)(
    input logic clk,
    input logic rst,

    input dispatch_to_rob_t rn_data_in,
    input logic re_valid,

    output logic rob_full,
    output rob_entry rob_head //TO DO: WB/commit
);

rob_entry ROB [0:ROB_SIZE-1];
logic [3:0] head, tail;
logic empty;

assign empty = (tail == head);
assign rob_full = ((tail + 4'd1) == head);
assign rob_head = ROB[head];

//signal prepare
rob_entry rob_entry_next;
always_comb begin
    rob_entry_next = '0;
    if(re_valid && !rob_full) begin
    rob_entry_next.valid = 1'b1;
    rob_entry_next.complete = 1'b0;
    rob_entry_next.isBusy = 1'b1;
    rob_entry_next.prd_addr = rn_data_in.prd_addr;
    rob_entry_next.old_prd_addr = rn_data_in.old_prd_addr;
    rob_entry_next.pc = rn_data_in.pc;
    rob_entry_next.is_branch = rn_data_in.is_branch;
    rob_entry_next.recovery_ptr = rn_data_in.is_branch ? tail : '0;
    rob_entry_next.rob_idx = tail;
    end
end

//ROB write in
integer i;
always_ff @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < ROB_SIZE; i = i+1)
            ROB[i] <= '0;
        head <= '0;
        tail <= '0;
    end

    else begin
        //fill in data from rename
        if(re_valid && !rob_full) begin
            ROB[tail] <= rob_entry_next;
            tail <= (tail==ROB_SIZE-1) ? 0 : tail + 4'd1;
        end
    end
end
endmodule