module re_dis_pipe (
    input  logic clk,
    input  logic rst
);
// Rename <-> Skid_RD wires
rename_to_dispatch_t re_data_in;
logic re_valid_in;
logic dp_ready_out;

// Skid_RD <-> Dispatch wires
control_signals_t de_signals_out;
logic de_valid_out;
logic re_ready_in;

// ------------ Rename ------------
    rename u_rename_downstream (
        .clk            (clk),
        .rst            (rst),

        // downstream (to DP)
        .rn_valid       (re_valid_in),
        .rn_instr_out   (re_data_in),
        .dp_ready       (dp_ready_out)
    );

// ------------ Skid Buffer (RE payload) ------------
    skid_buffer_struct #(.T(control_signals_t)) u_skidD (
        .clk        (clk),
        .reset      (rst),

        // upstream: decode <-> skid
        .valid_in   (de_valid_in),
        .ready_out   (re_ready_out),
        .data_in    (de_signals_in),

        // downstream: skid <-> decode
        .valid_out  (de_valid_out),
        .ready_in  (re_ready_in),
        .data_out   (de_signals_out)
    );

// ------------ Dispatch ------------
rename u_rename {
    .clk(clk),
    .rst(rst),

    // --- Upstream (from Decode) ---
    .de_valid(de_valid_out),
    .de_instr_in(de_signals_out),
    .rn_ready(re_ready_in)
}
endmodule