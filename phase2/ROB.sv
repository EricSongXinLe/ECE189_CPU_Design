typedef struct packed {
    logic valid; //this entry is occupied / contains an allocated instruction
    logic ready; //instruction has completed execution / writeback
    logic isBusy; //starts when instr is inserted into the rob; not when commited
    logic [6:0] dest_preg; 
    logic [6:0] old_dest_preg;
    logic [31:0] pc;
    logic isBranch;
    logic [3:0] recovery_ptr; //if isBranch, store the rob_idx at that point
    logic isStore; //doesn't have dest_preg or old_dest_preg
    logic [3:0] rob_idx;
} rob_entry;

module ROB #(
    parameter ROB_SIZE = 16
)(
    input logic clk,
    input logic rst,

    input rename_data re_data_in,
    input logic re_valid,

    output logic rob_full,
    output rob_entry rob_head //TO DO: WB/commit
);

rob_entry ROB [0:ROB_SIZE-1];
logic [3:0] head, tail;
logic empty;

assign empty = (tail == head);
assign rob_full = ((tail + 3'd1) == head);
assign rob_head = ROB[head];

//signal prepare
rob_entry rob_entry_next;
always_comb begin
    rob_entry_next = '0;
    if(re_valid && !rob_full) begin
    rob_entry_next.valid = 1'b1;
    rob_entry_next.ready = 1'b0;
    rob_entry_next.isBusy = 1'b1;
    rob_entry_next.dest_preg = re_data_in.dest_preg;
    rob_entry_next.old_dest_preg = re_data_in.old_dest_preg;
    rob_entry_next.pc = re_data_in.pc;
    rob_entry_next.isBranch = re_data_in.isBranch;
    rob_entry_next.isStore = re_data_in.isStore;
    rob_entry_next.recovery_ptr = tail;
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