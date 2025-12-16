`include "riscv_types.svh"

module phys_reg_status_table #(
    parameter CDB_WIDTH     = 3   // 3 Writeback Ports (ALU, LSU, BRU)
) (
    input  logic                     clk,
    input  logic                     rst,
    // --- Dispatch Stage Interface (Writer 1: Set Busy) ---
    input  logic                     dispatch_valid,
    input  logic [PREG_IDX_WIDTH-1:0] dispatch_dest_preg,

    // --- Writeback/CDB Interface (Writer 2: Set Ready) ---
    // Now supports arrays for multiple ports
    input  logic                     wb_valid [CDB_WIDTH-1:0],
    input  logic [PREG_IDX_WIDTH-1:0] wb_dest_preg [CDB_WIDTH-1:0],

    // --- Rename/Map Interface (Reader) ---
    input  logic [PREG_IDX_WIDTH-1:0] src1_preg,
    input  logic [PREG_IDX_WIDTH-1:0] src2_preg,

    // --- Outputs to Dispatch/RS ---
    output logic                     src1_ready,
    
    output logic                     src2_ready
);
    // Internal Storage
    logic [PHYS_REGS-1:0] busy_table;
    // --- Read Logic (Combinational) ---
    always_comb begin
        src1_ready = (src1_preg == '0) ? 1'b1 : ~busy_table[src1_preg];
        src2_ready = (src2_preg == '0) ? 1'b1 : ~busy_table[src2_preg];
    end
    // --- Write Logic (Sequential) ---
    always_ff @(posedge clk) begin
        if (rst) begin
            busy_table <= '0;
        end else begin
            // 1. Handle Writeback (Completion) -> Set Ready
            // Iterate through all CDB ports
            for (int i = 0; i < CDB_WIDTH; i++) begin
                if (wb_valid[i] && wb_dest_preg[i] != '0) begin
                    busy_table[wb_dest_preg[i]] <= 1'b0;
                end
            end
            // 2. Handle Dispatch (Allocation) -> Set Busy
            // Priority: Dispatch overrides Writeback if they target the same register.
            // (Scenario: Old instr finishes using Px, New instr allocates Px immediately)
            if (dispatch_valid && dispatch_dest_preg != '0)
                busy_table[dispatch_dest_preg] <= 1'b1;
        end
    end
endmodule