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

module phys_reg_status_table #(
    [cite_start]parameter PREG_ID_WIDTH = 7,  // e.g., 128 Physical Registers -> 7 bits [cite: 133]
    [cite_start]parameter ROB_IDX_WIDTH = 4   // e.g., 16 ROB entries -> 4 bits [cite: 103]
) (
    input  logic                     clk,
    input  logic                     rst_n,

    // --- Dispatch Stage Interface (Writer 1) ---
    // When an instruction is dispatched, its Destination PREG becomes BUSY.
    input  logic                     dispatch_valid,
    input  logic [PREG_ID_WIDTH-1:0] dispatch_dest_preg,
    input  logic [ROB_IDX_WIDTH-1:0] dispatch_rob_idx,

    // --- Writeback/CDB Interface (Writer 2) ---
    // When an instruction completes, its Destination PREG becomes READY.
    input  logic                     wb_valid,
    input  logic [PREG_ID_WIDTH-1:0] wb_dest_preg,

    // --- Rename/Map Interface (Reader) ---
    // Check status of Source PREGs obtained from the Map Table.
    input  logic [PREG_ID_WIDTH-1:0] src1_preg,
    input  logic [PREG_ID_WIDTH-1:0] src2_preg,

    // --- Outputs to Dispatch/RS ---
    output logic                     src1_ready,      // 1 = Data in PRF, 0 = Wait for ROB
    output logic [ROB_IDX_WIDTH-1:0] src1_wait_rob,   // The ROB index src1 is waiting for
    
    output logic                     src2_ready,      // 1 = Data in PRF, 0 = Wait for ROB
    output logic [ROB_IDX_WIDTH-1:0] src2_wait_rob    // The ROB index src2 is waiting for
);

    // Number of physical registers
    localparam NUM_PREGS = 1 << PREG_ID_WIDTH;

    // --- Internal Storage ---
    // bit [0]: Busy Bit (1 = Busy/Pending, 0 = Ready/In-PRF)
    logic [NUM_PREGS-1:0] busy_table;
    
    // Stores the ROB Index that will produce the value for this physical register
    logic [ROB_IDX_WIDTH-1:0] producer_rob_table [0:NUM_PREGS-1];

    // --- Read Logic (Combinational) ---
    // Determine if sources are ready based on the busy table.
    // If Busy is 1, Ready is 0.
    always_comb begin
        // Source 1 Lookup
        if (busy_table[src1_preg] == 1'b1) begin
            src1_ready    = 1'b0;
            src1_wait_rob = producer_rob_table[src1_preg];
        end else begin
            src1_ready    = 1'b1;
            src1_wait_rob = '0; // Don't care, but keep clean
        end

        // Source 2 Lookup
        if (busy_table[src2_preg] == 1'b1) begin
            src2_ready    = 1'b0;
            src2_wait_rob = producer_rob_table[src2_preg];
        end else begin
            src2_ready    = 1'b1;
            src2_wait_rob = '0; // Don't care, but keep clean
        end
    end

    // --- Write Logic (Sequential) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset: All physical registers are considered READY (Busy = 0) initially.
            // This assumes initial PRF values are valid (or don't matter).
            busy_table <= '0;
            for (int i = 0; i < NUM_PREGS; i++) begin
                producer_rob_table[i] <= '0;
            end
        end else begin
            
            // 1. Handle Writeback (Completion)
            // If an instruction finishes, it broadcasts the tag/preg on the CDB.
            // We mark the corresponding Physical Register as READY (Busy = 0).
            if (wb_valid) begin
                busy_table[wb_dest_preg] <= 1'b0;
            end

            // 2. Handle Dispatch (Allocation)
            // A new instruction overwrites the status of its destination register.
            // It marks it as BUSY (waiting for this new instruction's ROB idx).
            // NOTE: Dispatch logic overrides Writeback if they target the same reg 
            // in the same cycle (rare, requires empty free list or zero-latency reuse).
            if (dispatch_valid) begin
                busy_table[dispatch_dest_preg] <= 1'b1;
                producer_rob_table[dispatch_dest_preg] <= dispatch_rob_idx;
            end
        end
    end

endmodule