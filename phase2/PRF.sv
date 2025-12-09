`include "riscv_types.svh"

/**
 * Physical Register File (PRF)
 *
 * A large, multi-ported register file.
 * - Synchronous (clocked) writes
 * - Combinational (asynchronous) reads
 *
 * p0 is hardwired to zero.
 */
module prf (
    input  logic clk,
    input  logic rst,

    // --- Read Ports (from Reservation Stations) ---
    // Read addresses are provided, data is read out combinationally
    input  logic [PREG_IDX_WIDTH-1:0] read_addr [PRF_READ_PORTS],
    output logic [31:0]               read_data [PRF_READ_PORTS],

    // --- Write Ports (from Functional Units) ---
    // When a FU completes, it provides its result, dest PRF, and write enable
    input  logic [PRF_WRITE_PORTS-1:0]       write_en,
    input  fu_to_prf_t [PRF_WRITE_PORTS-1:0] write_port_data
);

    // The core register file storage
    logic [31:0] register_file [PHYS_REGS];

    // --- Read Logic (Combinational) ---
    // Generate loop for all read ports
    genvar i_read;
    generate
        for (i_read = 0; i_read < PRF_READ_PORTS; i_read = i_read + 1) begin : read_port_gen
            // p0 is hardwired to 0
            assign read_data[i_read] = (read_addr[i_read] == '0) ? 32'b0 : register_file[read_addr[i_read]];
        end
    endgenerate

    // --- Write Logic (Synchronous) ---
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset all registers to zero
            for (int i = 0; i < PHYS_REGS; i++) begin
                register_file[i] <= 32'b0;
            end
        end else begin
            // p0 is always zero, so writes to it are ignored
            register_file[0] <= 32'b0;
            
            // Generate loop for all write ports
            for (int i = 0; i < PRF_WRITE_PORTS; i = i + 1) begin
                if (write_en[i] && write_port_data[i].prd_addr != '0) begin
                    register_file[write_port_data[i].prd_addr] <= write_port_data[i].data;
                end
            end
        end
    end

endmodule