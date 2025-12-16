module fetch(
    input logic clk,
    input logic rst,
    input logic stall, 
    input logic redirect, //JALR is unconditional, branch is conditional
    input logic [31:0] redirect_pc,
    
    input logic ready, // ready to fetch another instruction
    output logic valid, // fetch has a valid instruction
    
    output logic [31:0] pc_decode, //to decode
    output logic [31:0] inst_decode //to decode
    );

logic [31:0] pc; //to icache
logic [31:0] inst; //from icache
logic hold;

assign hold = stall || !ready;

always_ff @(posedge clk) begin
    if(rst)begin
        valid <= 0;
        pc <= 32'b0;
    end else if (redirect) begin
        valid <= 1'b1;
        pc <= redirect_pc;
    end else if (!hold) begin
        valid <= 1'b1;
        pc <= pc + 32'd4;
    end
end

assign pc_decode = pc;
assign inst_decode = inst;


icache u_icache( //I/O with icache
    //Output
    .inst(inst),
    //Input
    .pc(pc),
    .clk(clk)
);

endmodule
