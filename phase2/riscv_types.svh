`ifndef RISCV_TYPES_SVH
`define RISCV_TYPES_SVH

// --- Architectural Parameters ---
parameter ARCH_REGS = 32;
parameter AREG_IDX_WIDTH = $clog2(ARCH_REGS); // 5

// --- Physical Register File Parameters ---
parameter PHYS_REGS = 128;
parameter PREG_IDX_WIDTH = $clog2(PHYS_REGS); // 7

parameter FREE_MAX = PHYS_REGS-ARCH_REGS;
parameter FREE_CNT_W = $clog2(FREE_MAX + 1);

// --- Reorder Buffer Parameters ---
parameter ROB_SIZE = 16;
parameter ROB_IDX_WIDTH = $clog2(ROB_SIZE); // 4

// --- Functional Unit Parameters ---
// Used by PRF for write ports
parameter FU_ALU_COUNT = 1;
parameter FU_LSU_COUNT = 1;
parameter FU_BRU_COUNT = 1; // Branch Unit
parameter PRF_WRITE_PORTS = FU_ALU_COUNT + FU_LSU_COUNT + FU_BRU_COUNT; // Total 3

// Used by PRF for read ports (2 operands per RS)
parameter RS_ALU_READ_PORTS = 2;
parameter RS_LSU_READ_PORTS = 2;
parameter RS_BRU_READ_PORTS = 2;
parameter PRF_READ_PORTS = RS_ALU_READ_PORTS + RS_LSU_READ_PORTS + RS_BRU_READ_PORTS; // Total 6


// --- Data Structures ---
// ---------- FE <-> DE bus payload ----------
typedef struct packed {
  logic [31:0] pc;
  logic [31:0] instr;
} fe_bus_t;

// Data from Decode (Phase 1) to Rename
// We assume 'decode' has already identified instruction type.
typedef struct packed {
    logic [31:0] pc;
    logic [31:0] immediate;
    
    logic [AREG_IDX_WIDTH-1:0] rs1_addr;
    logic [AREG_IDX_WIDTH-1:0] rs2_addr;
    logic [AREG_IDX_WIDTH-1:0] rd_addr;
    
    logic uses_rs1;
    logic uses_rs2;
    logic uses_rd;

    // Control Signals
    logic        RegWrite;   // This instruction writes to a register
    logic        MemRead;
    logic        MemWrite;
    logic        MemToReg;
    logic        ALUSrc;
    logic        is_branch;  // This is a branch (for checkpointing)
    logic        is_jalr;
    logic [1:0]  ALUOp;
    
    // Pass-throughs
    logic [6:0]  funct7;
    logic [2:0]  funct3;
    logic [6:0]  opcode;
    logic [1:0]  FU_type; //00:ALU, 01:BR, 10: LSU, 11:NOP
} decode_to_rename_t;


// Data from Rename to Dispatch
typedef struct packed {
    logic [31:0] pc;
    logic [31:0] immediate;
    
    // Physical register addresses
    logic [PREG_IDX_WIDTH-1:0] ps1_addr;
    logic ps1_ready;
    logic [PREG_IDX_WIDTH-1:0] ps2_addr;
    logic ps2_ready;
    logic [PREG_IDX_WIDTH-1:0] prd_addr;     // New destination
    
    // For commit: what was the *previous* mapping for our dest?
    logic [PREG_IDX_WIDTH-1:0] old_prd_addr; 
    
    // ROB tag for this instruction
    logic [ROB_IDX_WIDTH-1:0] rob_tag;
    
    // Pass-through all other control signals
    logic uses_rd;
    logic        RegWrite;
    logic        MemRead;
    logic        MemWrite;
    logic        MemToReg;
    logic        ALUSrc;
    logic        is_branch;
    logic        is_jalr;
    logic [1:0]  ALUOp;
    logic [6:0]  funct7;
    logic [2:0]  funct3;
    logic [6:0]  opcode;
    logic [1:0]  FU_type; //00:ALU, 01:BR, 10: LSU, 11:NOP
} rename_to_dispatch_t;


// Data from Execute/Memory to PRF
typedef struct packed {
    logic [PREG_IDX_WIDTH-1:0] prd_addr; // Physical dest reg
    logic [31:0]               data;     // Data to write
    logic [ROB_IDX_WIDTH-1:0]  rob_tag;
} fu_to_prf_t;


// Data from ROB (Commit) to Rename (for freeing registers)
typedef struct packed {
    logic [PREG_IDX_WIDTH-1:0] prd_addr; // Physical *dest* reg to be freed
    logic uses_rd;
    logic [AREG_IDX_WIDTH-1:0] rd_addr;        // Architectural dest reg
    logic                      RegWrite;
    logic                      is_branch;      // To free checkpoints
} commit_to_rename_t;

//Data from Dispatch to RS
typedef struct packed {
    logic [31:0] immediate;
    
    // Physical register addresses
    logic [PREG_IDX_WIDTH-1:0] ps1_addr;
    logic ps1_ready;
    logic [PREG_IDX_WIDTH-1:0] ps2_addr;
    logic ps2_ready;
    logic [PREG_IDX_WIDTH-1:0] prd_addr;     // New destination
    
    // ROB tag for this instruction
    logic [ROB_IDX_WIDTH-1:0] rob_tag;
    
    // Pass-through all other control signals
    logic uses_rd;
    logic        MemRead;
    logic        MemWrite;
    logic        ALUSrc;
    logic [1:0]  ALUOp;
    logic [6:0]  funct7;
    logic [2:0]  funct3;
    logic [6:0]  opcode;
    logic [1:0]  FU_type; //00:ALU, 01:BR, 10: LSU, 11:NOP
} dispatch_to_rs_t;

//Data from Dispatch to ROB
typedef struct packed {
    logic [31:0] pc;
    
    // Physical register addresses
    logic [PREG_IDX_WIDTH-1:0] prd_addr;     // New destination
    
    // For commit: what was the *previous* mapping for our dest?
    logic [PREG_IDX_WIDTH-1:0] old_prd_addr; 
    
    // ROB tag for this instruction
    logic [ROB_IDX_WIDTH-1:0] rob_tag;
    
    logic        is_branch;
} dispatch_to_rob_t;

typedef struct packed {
    logic [ROB_IDX_WIDTH-1:0] rob_tag;
    logic mispredict;
    logic [31:0] branch_target;
} fu_to_rob_t;
 
typedef struct packed {
    logic commit_valid;
    logic [ROB_IDX_WIDTH-1:0] commit_idx;
    logic mispredict;
    logic [31:0] branch_target;
}
rob_commit_t;

`endif