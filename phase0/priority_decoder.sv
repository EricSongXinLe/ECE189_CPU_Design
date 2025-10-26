/**
 * Priority Decoder
 *
 * Takes a [WIDTH-1:0] input vector and outputs the binary index
 * of the highest-priority bit that is set to '1'.
 *
 * Priority is given to the Most Significant Bit (MSB).
 * For example, if in = 4'b0110, the highest priority '1' is at index 2.
 *
 * PARAMETERS:
 * WIDTH: The number of input bits.
 *
 * INPUTS:
 * in: The [WIDTH-1:0] input vector.
 *
 * OUTPUTS:
 * out: The [$clog2(WIDTH)-1:0] binary index of the highest-priority '1'.
 * valid: '1' if any bit in 'in' is '1', '0' otherwise.
 * 
 * Written by Yike Shi with help of Gemini
 */
module priority_decoder #(
    parameter WIDTH = 4
)(
    input  wire [WIDTH-1: 0]          in,    
    output logic [$clog2(WIDTH)-1:0]  out,  
    output logic                      valid
);

    //combinational block.
    always_comb begin
        // By default, assume no bits are set.
        valid = 1'b0; 
        out = '0;     // Output 0 when not valid.
        // Iterate from the highest priority bit (MSB) down to the LSB.
        for (int i = WIDTH - 1; i >= 0; i--) begin
            if (in[i]) begin
                // Found the first '1' (which is the highest priority one).
                out = i;       // Assign its index to the output.
                valid = 1'b1;  // Signal that the output is valid.
                break;         // Stop searching.
            end
        end
    end

endmodule