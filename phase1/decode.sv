`include "../phase2/riscv_types.svh"

module decode(
    input  logic        clk,
    input  logic        rst,

    // Upstream Interface (from Fetch)
    input  logic        fe_valid,       // Input is valid
    input  logic [31:0] fe_instr,     // Input instruction
    input  logic [31:0] fe_pc,        // Input PC
    output logic        de_ready,       // We are ready for input

    // Downstream Interface (to Rename)
    output logic        de_valid,       // Our output is valid
    input  logic        re_ready,       // Next stage is ready for our output
    output decode_to_rename_t de_signals_out // Our decoded output signals
);

    decode_to_rename_t next_signals;

    always_comb begin
        // --- Instruction Field Extraction ---
        // Extract all possible fields from the incoming instruction
        logic [6:0]  opcode = fe_instr[6:0];
        logic [4:0]  rd     = fe_instr[11:7];
        logic [2:0]  funct3 = fe_instr[14:12];
        logic [4:0]  rs1    = fe_instr[19:15];
        logic [4:0]  rs2    = fe_instr[24:20];
        logic [6:0]  funct7 = fe_instr[31:25];

        // --- Default Control Signal Values (safe state) ---
        // This is crucial. Start every instruction decode by assuming
        // it does nothing, then set the bits that are required.
        next_signals = '0; // Set all fields in the struct to 0
        next_signals.pc = fe_pc;
        next_signals.rs1_addr = rs1;
        next_signals.rs2_addr = rs2;
        next_signals.rd_addr = rd;

        next_signals.uses_rs1 = 1'b0;
        next_signals.uses_rs2 = 1'b0;
        next_signals.uses_rd  = 1'b0;

        next_signals.funct3 = funct3;
        next_signals.funct7 = funct7;
        next_signals.opcode = opcode;
        next_signals.FU_type = 2'b11; //no op
        
        // --- Main Control & Immediate Generation ---
        case (opcode)
        'h33: begin // R-type
            next_signals.RegWrite = 1'b1;
            next_signals.ALUOp    = 2'b10;
            next_signals.FU_type  = 2'b00;

            next_signals.uses_rs1 = 1'b1;
            next_signals.uses_rs2 = 1'b1;
            next_signals.uses_rd  = (rd != 5'd0);
        end

        'h13: begin // I-type ALU (ADDI/SLTIU/ORI)
            next_signals.RegWrite = 1'b1;
            next_signals.ALUSrc   = 1'b1;
            next_signals.ALUOp    = 2'b11;
            next_signals.FU_type  = 2'b00;
            next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:20]};

            next_signals.uses_rs1 = 1'b1;
            next_signals.uses_rs2 = 1'b0;
            next_signals.uses_rd  = (rd != 5'd0);
        end

        'h03: begin // Load (LW/LBU)
            next_signals.RegWrite = 1'b1;
            next_signals.MemRead  = 1'b1;
            next_signals.MemToReg = 1'b1;
            next_signals.ALUSrc   = 1'b1;
            next_signals.ALUOp    = 2'b00;
            next_signals.FU_type  = 2'b10;
            next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:20]};

            next_signals.uses_rs1 = 1'b1;      // base
            next_signals.uses_rs2 = 1'b0;
            next_signals.uses_rd  = (rd != 5'd0);
        end

        'h23: begin // Store (SW/SH)
            next_signals.MemWrite = 1'b1;
            next_signals.ALUSrc   = 1'b1;
            next_signals.ALUOp    = 2'b00;
            next_signals.FU_type  = 2'b10;
            next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:25], fe_instr[11:7]};

            next_signals.uses_rs1 = 1'b1;      // base
            next_signals.uses_rs2 = 1'b1;      // store data
            next_signals.uses_rd  = 1'b0;
        end

        'h63: begin // Branch (BNE)
            next_signals.is_branch = 1'b1;
            next_signals.ALUOp     = 2'b01;
            next_signals.FU_type   = 2'b01;
            next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[7], fe_instr[30:25], fe_instr[11:8], 1'b0};

            next_signals.uses_rs1 = 1'b1;
            next_signals.uses_rs2 = 1'b1;
            next_signals.uses_rd  = 1'b0;
        end

        'h67: begin // JALR
            next_signals.is_jalr   = 1'b1;
            next_signals.RegWrite = 1'b1;
            next_signals.ALUSrc   = 1'b1;
            next_signals.ALUOp    = 2'b00;
            next_signals.FU_type  = 2'b01;
            next_signals.immediate = {{20{fe_instr[31]}}, fe_instr[31:20]};

            next_signals.uses_rs1 = 1'b1;      // base (rs1)
            next_signals.uses_rs2 = 1'b0;
            next_signals.uses_rd  = (rd != 5'd0); // writes link unless rd=x0
        end

        'h37: begin // LUI
            next_signals.RegWrite = 1'b1;
            next_signals.ALUSrc   = 1'b1;
            next_signals.FU_type  = 2'b00;
            next_signals.immediate = {fe_instr[31:12]};

            next_signals.uses_rs1 = 1'b0;
            next_signals.uses_rs2 = 1'b0;
            next_signals.uses_rd  = (rd != 5'd0);
        end

        default: begin end
        endcase

    end

    assign de_valid = fe_valid;
    assign de_ready = re_ready;
    assign de_signals_out = fe_valid? next_signals : '0;

endmodule