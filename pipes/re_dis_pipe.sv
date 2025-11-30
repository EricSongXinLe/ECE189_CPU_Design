module re_dis_pipe (
    input  logic clk,
    input  logic rst
);
// Rename <-> buffer_RD wires
rename_to_dispatch_t re_data_in;
logic re_valid_in;
logic dp_ready_out;

// buffer_RD <-> Dispatch wires
rename_to_dispatch_t re_data_out;
logic re_valid_out;
logic dp_ready_in;

// ------------ Rename ------------
    rename u_rename_downstream (
        .clk            (clk),
        .rst            (rst),

        // downstream (to DP)
        .rn_valid       (re_valid_in),
        .rn_instr_out   (re_data_in),
        .dp_ready       (dp_ready_out)
    );

fifo_pipeline #(.T(rename_to_dispatch_t), .DEPTH(2))
u_buffer_fifo (
    .clk(clk),
    .reset(rst),

    .valid_in(re_valid_in),
    .ready_out(dp_ready_out),
    .write_data(re_data_in),
    .valid_out(re_valid_out),
    .ready_in(dp_ready_in),
    .read_data(re_data_out)
);

// ------------ Dispatch ------------
dispatch u_dispatch (
    .clk(clk),
    .rst(rst),

    // --- Upstream (from Decode) ---
    .rn_valid(re_valid_out),
    .rn_instr_in(re_data_out),
    .rn_ready(dp_ready_in)
);
endmodule