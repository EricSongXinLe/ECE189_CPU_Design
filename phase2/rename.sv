`include "riscv_types.svh"

/**
 * Register Rename Stage (RN)
 *
 * This module performs register renaming to eliminate false dependencies.
 * It contains:
 * 1. Map Table (AREG -> PREG)
 * 2. Map Table Checkpoint (for branch recovery)
 * 3. Free List (FIFO of free PREGs)
 * 4. ROB Tag Counter
 *
 * It is a fully-pipelined stage with valid/ready handshaking.
 *
 * --- FIXES APPLIED ---
 * 1. `rn_ready` logic fixed to not stall on x0 writes when free list is empty.
 * 2. Checkpoint/Recovery logic expanded to save/restore fl_tail and fl_count
 * for robust mispredict recovery.
 */
module rename (
    input  logic clk,
    input  logic rst,

    input logic [2:0] wb_valid,     
    input fu_to_prf_t [2:0] wb_packet,

    // --- Upstream (from Decode) ---
    input  logic                de_valid,
    input  decode_to_rename_t   de_instr_in,
    output logic                rn_ready, // Ready to accept from Decode

    // --- Downstream (to Dispatch) ---
    output logic                rn_valid,
    output rename_to_dispatch_t rn_instr_out,
    input  logic                dp_ready,  // Dispatch is ready

    // --- From Commit (ROB) ---
    input  logic                commit_valid,
    input  commit_to_rename_t   commit_instr,

    // --- From Branch Unit (Mispredict) ---
    input  logic                mispredict_valid
);

    // --- 1. Map Table ---
    // Maps ARCH_REGS -> PHYS_REGS
    logic [PREG_IDX_WIDTH-1:0] map_table [ARCH_REGS];
    logic [PREG_IDX_WIDTH-1:0] map_table_checkpoint [ARCH_REGS];

    // --- 2. Free List (FIFO implementation) ---
    logic [PREG_IDX_WIDTH-1:0] free_list_q [PHYS_REGS];
    logic [PREG_IDX_WIDTH-1:0] fl_head; // Points to next *free* PREG
    logic [PREG_IDX_WIDTH-1:0] fl_tail; // Points to where *committed* PREGs are added
    
    // Checkpointing: Save all pointers and the count
    logic [PREG_IDX_WIDTH-1:0] fl_head_checkpoint;
    logic [PREG_IDX_WIDTH-1:0] fl_tail_checkpoint; // <-- FIX: Added
    
    // We need a counter to know if the FIFO is full/empty
    logic [PREG_IDX_WIDTH:0]   fl_count; // Needs +1 bit for full
    logic [PREG_IDX_WIDTH:0]   fl_count_checkpoint; // <-- FIX: Added
    
    logic fl_empty;
    logic fl_full;

    // --- 3. ROB Tag Counter ---
    logic [ROB_IDX_WIDTH-1:0] rob_tag_counter;
    logic [ROB_IDX_WIDTH-1:0] rob_tag_checkpoint;
    
    // --- 4. Pipeline Register (Skid Buffer logic) ---
    logic                rn_valid_reg;
    rename_to_dispatch_t rn_instr_reg; // Holds the renamed instruction


    // --- Combinational Logic ---
    
    // Free List status
    assign fl_empty = (fl_count == 0);
    assign fl_full = (fl_count == PHYS_REGS); // Should never happen if 32 are always mapped

    // We need a free register if the instr writes to a *non-zero* dest reg
    logic need_free_reg = de_instr_in.RegWrite && (de_instr_in.rd_addr != '0);

    // Ready to accept from Decode?
    // We are ready if:
    // 1. Our output skid buffer is empty OR Dispatch is ready to take it.
    // 2. We are NOT stalling for a resource.
    // We stall for a resource if we NEED a free register but the list is empty.
    logic resource_stall = need_free_reg && fl_empty;
    
    assign rn_ready = (!rn_valid_reg || dp_ready) && !resource_stall;
                      
    // This is the instruction currently at the *output* of our stage
    assign rn_valid = rn_valid_reg;
    assign rn_instr_out = rn_instr_reg;

    // Combinational rename logic for the *incoming* instruction
    rename_to_dispatch_t rn_instr_comb;

    // 1. (Unpack PRD Addresses)
    logic [PREG_IDX_WIDTH-1:0] wb_dest_addrs [3];
    always_comb begin
        for (int i = 0; i < 3; i++) begin
            wb_dest_addrs[i] = wb_packet[i].prd_addr;
        end
    end

    // 2. Lookup Table
    logic src1_rdy_out, src2_rdy_out;

    phys_reg_status_table #(
        .PREG_ID_WIDTH(PREG_IDX_WIDTH),
        .ROB_IDX_WIDTH(ROB_IDX_WIDTH),
        .CDB_WIDTH(3)
    ) u_scoreboard (
        .clk            (clk),
        .rst_n          (!rst), 

        // Writer 1: Dispatch
        .dispatch_valid     (do_rename && need_free_reg), 
        .dispatch_dest_preg (rn_instr_comb.prd_addr),
        .dispatch_rob_idx   (rn_instr_comb.rob_tag),

        // Writer 2: Writeback (3 Ports)
        .wb_valid           (wb_valid),      
        .wb_dest_preg       (wb_dest_addrs),  

        // Reader: Map Lookup
        .src1_preg          (rn_instr_comb.ps1_addr),
        .src2_preg          (rn_instr_comb.ps2_addr),

        // Outputs
        .src1_ready         (src1_rdy_out),
        .src1_wait_rob      (), 
        .src2_ready         (src2_rdy_out),
        .src2_wait_rob      ()
    );
    
    always_comb begin
        // --- 1. Look up source registers ---
        // p0 is always p0.
        rn_instr_comb.ps1_addr = (de_instr_in.rs1_addr == '0) ? '0 : map_table[de_instr_in.rs1_addr];
        rn_instr_comb.ps2_addr = (de_instr_in.rs2_addr == '0) ? '0 : map_table[de_instr_in.rs2_addr];
        
        // --- Fix: Assign Ready Bits ---
        // Source 1
        if (de_instr_in.rs1_addr == '0) 
            rn_instr_comb.ps1_ready = 1'b1;
        else 
            rn_instr_comb.ps1_ready = src1_rdy_out;

        // Source 2
        if (de_instr_in.rs2_addr == '0 || de_instr_in.ALUSrc) 
            //x0, immediate(ALUSrc = 1)
            rn_instr_comb.ps2_ready = 1'b1;
        else 
            rn_instr_comb.ps2_ready = src2_rdy_out;
        
        // --- 2. Allocate destination register ---
        if (need_free_reg) begin
            // Get new PREG from Free List
            rn_instr_comb.prd_addr = free_list_q[fl_head];
            // Get old PREG from Map Table (for commit)
            rn_instr_comb.old_prd_addr = map_table[de_instr_in.rd_addr];
        end else begin
            // Not writing or writing to x0
            rn_instr_comb.prd_addr = '0;
            rn_instr_comb.old_prd_addr = '0;
        end
        
        // --- 3. Assign ROB Tag ---
        rn_instr_comb.rob_tag = rob_tag_counter;

        // --- 4. Pass-through other signals ---
        rn_instr_comb.pc         = de_instr_in.pc;
        rn_instr_comb.immediate  = de_instr_in.immediate;
        rn_instr_comb.RegWrite   = de_instr_in.RegWrite;
        rn_instr_comb.MemRead    = de_instr_in.MemRead;
        rn_instr_comb.MemWrite   = de_instr_in.MemWrite;
        rn_instr_comb.MemToReg   = de_instr_in.MemToReg;
        rn_instr_comb.ALUSrc     = de_instr_in.ALUSrc;
        rn_instr_comb.is_branch  = de_instr_in.is_branch;
        rn_instr_comb.ALUOp      = de_instr_in.ALUOp;
        rn_instr_comb.funct7     = de_instr_in.funct7;
        rn_instr_comb.funct3     = de_instr_in.funct3;
        rn_instr_comb.opcode     = de_instr_in.opcode;
        rn_instr_comb.FU_type    = de_instr_in.FU_type;
    end

    
    // --- Sequential Logic (State Updates) ---
    
    logic do_rename;   // Latch new instruction from Decode
    logic do_dispatch; // Send current instruction to Dispatch
    logic do_alloc;    // Allocate from Free List
    logic do_free;     // Free to Free List
    
    assign do_rename = de_valid && rn_ready;
    assign do_dispatch = rn_valid_reg && dp_ready;
    assign do_alloc = do_rename && need_free_reg; // Use the corrected signal
    assign do_free = commit_valid && commit_instr.RegWrite && (commit_instr.old_prd_addr != '0);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            // --- Reset Pipeline Register ---
            rn_valid_reg <= 1'b0;
            
            // --- Reset Map Table ---
            // Initial map: x0->p0, x1->p1, ..., x31->p31
            map_table[0] <= '0;
            for (int i = 1; i < ARCH_REGS; i++) begin
                map_table[i] <= i;
            end
            
            // --- Reset Free List ---
            // Contains p32 through p127
            fl_head <= '0;
            fl_tail <= PHYS_REGS - ARCH_REGS; // e.g., 128-32 = 96
            fl_count <= PHYS_REGS - ARCH_REGS;   // e.g., 96 registers
            for (int i = 0; i < (PHYS_REGS - ARCH_REGS); i++) begin
                free_list_q[i] <= i + ARCH_REGS; // p32, p33, ...
            end
            // Note: fl_tail points to the *next empty slot* (96),
            // which is correct. The loop goes from 0 to 95.

            // --- Reset ROB Tag ---
            rob_tag_counter <= '0;
            
            // (Checkpoints are undefined on reset)
            
        end else if (mispredict_valid) begin
            // --- Mispredict Recovery (Highest Priority) ---
            
            // Restore state from checkpoint
            map_table       <= map_table_checkpoint;
            fl_head         <= fl_head_checkpoint;
            fl_tail         <= fl_tail_checkpoint;  // <-- FIX: Restore tail
            fl_count        <= fl_count_checkpoint; // <-- FIX: Restore count
            rob_tag_counter <= rob_tag_checkpoint;
            
            // Flush the pipeline stage
            rn_valid_reg <= 1'b0;

        end else begin
            // --- Normal Operation ---
            
            // --- 1. State Updates (Map Table, Free List, ROB Tag) ---
            
            if (do_rename) begin
                // A new instruction is being renamed and latched
                
                // Update Map Table
                if (need_free_reg) begin
                    map_table[de_instr_in.rd_addr] <= rn_instr_comb.prd_addr;
                end
                
                // Update ROB Tag Counter
                rob_tag_counter <= rob_tag_counter + 1;
                
                // Checkpoint if this is a branch
                if (de_instr_in.is_branch) begin
                    // Take snapshot *before* we update for this branch
                    map_table_checkpoint  <= map_table;
                    fl_head_checkpoint    <= fl_head;
                    fl_tail_checkpoint    <= fl_tail;  // <-- FIX: Save tail
                    fl_count_checkpoint   <= fl_count; // <-- FIX: Save count
                    rob_tag_checkpoint    <= rob_tag_counter;
                end
            end
            
            // --- 2. Free List Counter Update (handles alloc/free) ---
            if (do_alloc && !do_free) begin
                fl_count <= fl_count - 1; // Consumed one
            end else if (!do_alloc && do_free) begin
                fl_count <= fl_count + 1; // Freed one
            end
            // if (do_alloc && do_free) or (!do_alloc && !do_free), count is stable
            
            // --- 3. Free List Pointer Updates ---
            if (do_alloc) begin
                fl_head <= fl_head + 1; // Wrap-around handled by % PHYS_REGS
            end
            
            if (do_free) begin
                // Add the committed *old* register back to the tail
                free_list_q[fl_tail] <= commit_instr.old_prd_addr;
                fl_tail <= fl_tail + 1;
            end

            // --- 4. Pipeline Register Update (Skid logic) ---
            if (do_rename) begin
                // New instruction latched
                rn_valid_reg <= 1'b1;
                rn_instr_reg <= rn_instr_comb;
            end else if (do_dispatch) begin
                // Current instruction consumed
                rn_valid_reg <= 1'b0;
            end
            // else (stall or bubble), rn_valid_reg keeps its state
        end
    end

endmodule