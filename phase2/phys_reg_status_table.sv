/* * Module: phys_reg_status_table
 * Description: 
 * Tracks the status (Busy/Ready) and the Producer ROB Index for every Physical Register.
 * This is used during the Rename/Dispatch stage to inform the Reservation Stations 
 * whether the source operands are already available in the PRF or if they need to 
 * wait for a specific ROB entry to complete.
 *
 * Inputs:
 * - Dispatch Signals: Mark a destination physical register as BUSY (waiting for computation).
 * - Writeback Signals: Mark a destination physical register as READY (computation finished).
 * - Source Lookups: Query the status of source physical registers.
 *
 * Outputs:
 * - Ready bits for source operands (to be sent to RS).
 * - ROB Tags for source operands (to be sent to RS for wakeup monitoring).
 */

/*
 * Updated to support multiple Writeback (CDB) ports.
 */

module phys_reg_status_table #(
    parameter PREG_ID_WIDTH = 7,  // 128 Physical Registers
    parameter ROB_IDX_WIDTH = 4,  // 16 ROB entries
    parameter CDB_WIDTH     = 3   // 3 Writeback Ports (ALU, LSU, BRU)
) (
    input  logic                     clk,
    input  logic                     rst_n,

    // --- Dispatch Stage Interface (Writer 1: Set Busy) ---
    input  logic                     dispatch_valid,
    input  logic [PREG_ID_WIDTH-1:0] dispatch_dest_preg,
    input  logic [ROB_IDX_WIDTH-1:0] dispatch_rob_idx,

    // --- Writeback/CDB Interface (Writer 2: Set Ready) ---
    // Now supports arrays for multiple ports
    input  logic                     wb_valid [CDB_WIDTH],
    input  logic [PREG_ID_WIDTH-1:0] wb_dest_preg [CDB_WIDTH],

    // --- Rename/Map Interface (Reader) ---
    input  logic [PREG_ID_WIDTH-1:0] src1_preg,
    input  logic [PREG_ID_WIDTH-1:0] src2_preg,

    // --- Outputs to Dispatch/RS ---
    output logic                     src1_ready,
    output logic [ROB_IDX_WIDTH-1:0] src1_wait_rob,
    
    output logic                     src2_ready,
    output logic [ROB_IDX_WIDTH-1:0] src2_wait_rob
);

    localparam NUM_PREGS = 1 << PREG_ID_WIDTH;

    // Internal Storage
    logic [NUM_PREGS-1:0] busy_table;
    logic [ROB_IDX_WIDTH-1:0] producer_rob_table [0:NUM_PREGS-1];

    // --- Read Logic (Combinational) ---
    always_comb begin
        // Source 1
        if (busy_table[src1_preg] == 1'b1) begin
            src1_ready    = 1'b0;
            src1_wait_rob = producer_rob_table[src1_preg];
        end else begin
            src1_ready    = 1'b1;
            src1_wait_rob = '0; 
        end

        // Source 2
        if (busy_table[src2_preg] == 1'b1) begin
            src2_ready    = 1'b0;
            src2_wait_rob = producer_rob_table[src2_preg];
        end else begin
            src2_ready    = 1'b1;
            src2_wait_rob = '0; 
        end
    end

    // --- Write Logic (Sequential) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_table <= '0; // Reset all to Ready
            for (int i = 0; i < NUM_PREGS; i++) begin
                producer_rob_table[i] <= '0;
            end
        end else begin
            
            // 1. Handle Writeback (Completion) -> Set Ready
            // Iterate through all CDB ports
            for (int i = 0; i < CDB_WIDTH; i++) begin
                if (wb_valid[i]) begin
                    busy_table[wb_dest_preg[i]] <= 1'b0;
                end
            end

            // 2. Handle Dispatch (Allocation) -> Set Busy
            // Priority: Dispatch overrides Writeback if they target the same register.
            // (Scenario: Old instr finishes using Px, New instr allocates Px immediately)
            if (dispatch_valid) begin
                busy_table[dispatch_dest_preg] <= 1'b1;
                producer_rob_table[dispatch_dest_preg] <= dispatch_rob_idx;
            end
        end
    end

endmodule