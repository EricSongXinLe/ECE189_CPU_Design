module de_re_pipe (
    input  logic clk,
    input  logic rst
);
// Decode <-> Skid_DR wires
control_signals_t de_signals_in;
logic de_valid_in;
logic re_ready_out;

// Skid_DR <-> Rename wires
control_signals_t de_signals_out;
logic de_valid_out;
logic re_ready_in;

// ------------ Decode ------------
    decode u_decode (
        .clk            (clk),
        .rst            (rst),

        // downstream (to RE)
        .de_valid       (de_valid_in),
        .re_ready       (re_ready_out),
        .de_signals_out (de_signals_in)
    );

// ------------ Skid Buffer (DE payload) ------------
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

// ------------ Rename ------------
//TO DO

endmodule