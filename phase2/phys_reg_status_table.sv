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
    input  logic [CDB_WIDTH-1:0]     wb_valid,
    input  logic [CDB_WIDTH-1:0][PREG_ID_WIDTH-1:0] wb_dest_preg,

    // --- Rename/Map Interface (Reader) ---
    input  logic [PREG_ID_WIDTH-1:0] src1_preg,
    input  logic [PREG_ID_WIDTH-1:0] src2_preg,

    // --- Outputs to Dispatch/RS ---
    output logic                     src1_ready,
    output logic [ROB_IDX_WIDTH-1:0] src1_wait_rob,
    
    output logic                     src2_ready,
    output logic [ROB_IDX_WIDTH-1:0] src2_wait_rob,

    // 新增：导出整个 busy_table 给顶层 / RS 使用
    output logic [(1<<PREG_ID_WIDTH)-1:0] busy_table_out
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
            busy_table <= '0;
            for (int i = 0; i < NUM_PREGS; i++)
                producer_rob_table[i] <= '0;
        end else begin
            // 1. Writeback 置 Ready
            for (int i = 0; i < CDB_WIDTH; i++) begin
                if (wb_valid[i] && (wb_dest_preg[i] != '0)) begin
                    $display("[SCOREBOARD] t=%0t WB preg=%0d => ready",
                             $time, wb_dest_preg[i]);
                    busy_table[wb_dest_preg[i]] <= 1'b0;
                end
            end

            // 2. Dispatch 置 Busy -- 只对 prd != 0
            if (dispatch_valid && (dispatch_dest_preg != '0)) begin
                $display("[SCOREBOARD] t=%0t DISPATCH dest_preg=%0d rob=%0d => busy",
                         $time, dispatch_dest_preg, dispatch_rob_idx);
                busy_table[dispatch_dest_preg]         <= 1'b1;
                producer_rob_table[dispatch_dest_preg] <= dispatch_rob_idx;
            end
        end
    end

    // 把 busy_table 导出去
    assign busy_table_out = busy_table;

    // 这个 debug block 原样可以留着
    always_comb begin
        if (src1_preg == 7'd33 || src1_preg == 7'd36) begin
            $display("[SCOREBOARD-READ] t=%0t src1_preg=%0d busy=%0d",
                     $time, src1_preg, busy_table[src1_preg]);
        end
    end

endmodule
