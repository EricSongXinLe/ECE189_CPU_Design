module icache #(
    parameter BLOCK_SIZE = 1024
)(
    input  logic        clk,
    input  logic [31:0] pc,
    output logic [31:0] inst
);

    // Declare instruction memory
    logic [31:0] iMEM [0:BLOCK_SIZE-1];

    // Initialize instruction memory from file
    initial $readmemh("program.mem", iMEM);

    assign inst = iMEM[pc[31:2]];

endmodule
