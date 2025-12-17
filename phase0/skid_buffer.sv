module skid_buffer_struct #(
    parameter type T = logic
) (
    input  logic clk,
    input  logic reset,
    input  logic flush,
    // upstream (producer -> skid)
    input  logic valid_in,
    output logic ready_out,
    input  T     data_in,

    // downstream (skid -> consumer)
    output logic valid_out,
    input  logic ready_in,
    output T     data_out
);

    // One-entry register to hold a skidded beat
    logic skid_valid;
    T     skid_data;

    // Output select: pass-through when not holding; otherwise drive from skid reg
    assign valid_out = skid_valid ? 1'b1      : valid_in;
    assign data_out  = skid_valid ? skid_data : data_in;

    // Upstream can present a new beat if we're not holding,
    // or if downstream is ready (so we can forward/“swap” this cycle).
    assign ready_out = !skid_valid || ready_in;

    // Skid register control (synchronous active-high reset)
    always_ff @(posedge clk) begin
        if (reset || flush) begin
            skid_valid <= 1'b0;
            skid_data  <= '0;
        end else begin
            if (!skid_valid) begin
                // Empty: capture when a valid beat arrives but downstream stalls
                if (valid_in && !ready_in) begin
                    skid_valid <= 1'b1;
                    skid_data  <= data_in;
                end
            end else begin
                // Holding one beat
                if (ready_in) begin
                    if (valid_in) begin
                        // Downstream consumes; immediately refill with new input (swap)
                        skid_valid <= 1'b1;
                        skid_data  <= data_in;
                    end else begin
                        // Downstream consumes; no refill -> buffer becomes empty
                        skid_valid <= 1'b0;
                    end
                end
                // else: still stalled; keep holding
            end
        end
    end

endmodule
