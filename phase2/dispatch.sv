`timescale 1ns / 1ps
`include "../phase2/riscv_types.svh"
module dispatch (
    input logic clk, rst,

    //rename <-> dispatch
    output logic dp_ready_out, //dispatch/buffer has space to take in new instr
    input logic buffer_valid_in, //buffer has new instr
    input rename_to_dispatch_t buffer_instr_in,

    //dispatch <-> ROB
    input logic rob_full,
    output logic rob_valid,
    output dispatch_to_rob_t rob_instr,

    //dispatch <-> RS (3)
    input logic rs_alu_full,
    output logic rs_alu_valid,
    output dispatch_to_rs_t rs_alu_instr,

    input logic rs_br_full, 
    output logic rs_br_valid,
    output dispatch_to_rs_t rs_br_instr,
    
    input logic rs_lsu_full,
    output logic rs_lsu_valid,
    output dispatch_to_rs_t rs_lsu_instr,

    input logic      wb_valid  [2:0],
    input fu_to_prf_t wb_packet [2:0]

);

//Determine RS/ROB Availability
logic rs_ready, rob_ready;
always_comb begin
    case (buffer_instr_in.FU_type)
        2'b00: rs_ready = !rs_alu_full; //ALU
        2'b01: rs_ready = !rs_br_full; //BR
        2'b10: rs_ready = !rs_lsu_full; //LSU
        default: rs_ready = 0;
    endcase
end

assign rob_ready = !rob_full;

assign dp_ready_out = (!buffer_valid_in) ? 1'b1 : (rs_ready && rob_ready);

logic dispatch_fire;
assign dispatch_fire = buffer_valid_in && rs_ready && rob_ready;

assign rob_valid = dispatch_fire;

assign rs_alu_valid = dispatch_fire && (buffer_instr_in.FU_type == 2'b00);
assign rs_br_valid = dispatch_fire && (buffer_instr_in.FU_type == 2'b01);
assign rs_lsu_valid = dispatch_fire && (buffer_instr_in.FU_type == 2'b10);


//src ready bit lookup
logic src1_rdy, src2_rdy;
    logic [PREG_IDX_WIDTH-1:0] wb_dest_addrs [2:0];
    always_comb begin
        for (int i = 0; i < 3; i++) begin
            wb_dest_addrs[i] = wb_packet[i].prd_addr;
        end
    end

    phys_reg_status_table #(
        .CDB_WIDTH(3)
    ) u_scoreboard (
        .clk (clk),
        .rst (rst), 
        // Writer 1: Dispatch
        .dispatch_valid     (dispatch_fire && buffer_instr_in.uses_rd && (buffer_instr_in.prd_addr != 0)), 
        .dispatch_dest_preg (buffer_instr_in.prd_addr),
        // Writer 2: Writeback (3 Ports)
        .wb_valid           (wb_valid),      
        .wb_dest_preg       (wb_dest_addrs),  
        // Reader: Map Lookup
        .src1_preg          (buffer_instr_in.ps1_addr),
        .src2_preg          (buffer_instr_in.ps2_addr),
        // Outputs
        .src1_ready         (src1_rdy),
        .src2_ready         (src2_rdy)
    );

//RS Entry
dispatch_to_rs_t new_rs_entry;
always_comb begin
    new_rs_entry = '0;
    if (buffer_valid_in) begin
        //rs
        new_rs_entry.immediate  = buffer_instr_in.immediate;
        new_rs_entry.ps1_addr   = buffer_instr_in.ps1_addr;
        new_rs_entry.ps2_addr   = buffer_instr_in.ps2_addr;
        new_rs_entry.ps1_ready  = src1_rdy;
        new_rs_entry.ps2_ready  = src2_rdy;
        new_rs_entry.uses_rd    = buffer_instr_in.uses_rd;
        new_rs_entry.prd_addr   = buffer_instr_in.prd_addr;
        new_rs_entry.rob_tag    = buffer_instr_in.rob_tag;

        new_rs_entry.MemRead    = buffer_instr_in.MemRead;
        new_rs_entry.MemWrite   = buffer_instr_in.MemWrite;
        new_rs_entry.ALUSrc     = buffer_instr_in.ALUSrc;
        new_rs_entry.ALUOp      = buffer_instr_in.ALUOp;
        new_rs_entry.funct3     = buffer_instr_in.funct3;
        new_rs_entry.funct7     = buffer_instr_in.funct7;
        new_rs_entry.opcode     = buffer_instr_in.opcode;
        new_rs_entry.FU_type    = buffer_instr_in.FU_type;
    end
end
assign rs_alu_instr = new_rs_entry;
assign rs_br_instr = new_rs_entry;
assign rs_lsu_instr = new_rs_entry;

//ROB Entry
dispatch_to_rob_t new_rob_entry;
always_comb begin
    new_rob_entry = '0;
    if (buffer_valid_in) begin
        new_rob_entry.pc           = buffer_instr_in.pc;
        new_rob_entry.prd_addr     = buffer_instr_in.prd_addr;
        new_rob_entry.old_prd_addr = buffer_instr_in.old_prd_addr;
        new_rob_entry.rob_tag      = buffer_instr_in.rob_tag;
        new_rob_entry.is_branch    = buffer_instr_in.is_branch;
    end
end

assign rob_instr = new_rob_entry;


endmodule