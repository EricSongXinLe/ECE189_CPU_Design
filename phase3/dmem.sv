module dmem #(
    parameter BLOCK_SIZE = 1024
)(
    input  logic        clk,
    input logic         en,
    input  logic [31:0] addr,
    output logic [31:0] data
);

    logic [31:0] dmem[0:BLOCK_SIZE-1];

    initial $readmemh("program.mem", iMEM);

    always_ff @(posedge clk) begin
        if (en) inst <= dmem[pc[31:2]]; 
    end

endmodule
