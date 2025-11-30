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
    output dispatch_to_rs_t rs_lsu_instr
);

//RS Entry
dispatch_to_rs_t new_rs_entry;
always_comb begin
    new_rs_entry = '0;
    if (buffer_valid_in) begin
        //rs
        new_rs_entry.immediate  = buffer_instr_in.immediate;
        new_rs_entry.ps1_addr   = buffer_instr_in.ps1_addr;
        new_rs_entry.ps1_ready  = buffer_instr_in.ps1_ready;
        new_rs_entry.ps2_addr   = buffer_instr_in.ps2_addr;
        new_rs_entry.ps2_ready  = buffer_instr_in.ps2_ready;
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
//ROB Entry
dispatch_to_rob_t new_rob_entry;
always_comb begin
    new_rob_entry = '0;
    if (buffer_valid_in) begin
        new_rob_entry.pc           = buffer_instr_in.pc;
        new_rob_entry.prd_addr     = buffer_instr_in.prd_addr;
        new_rob_entry.old_prd_addr = buffer_instr_in.old_prd_addr;
        new_rob_entry.rob_tag      = buffer_instr_in.rob_tag;
        new_rob_entry.is_branch  = buffer_instr_in.is_branch;
    end
end

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

assign dp_ready_out = rs_ready && rob_ready;

logic dispatch_fire;
assign dispatch_fire = buffer_valid_in && rs_ready && rob_ready;

assign rob_valid = dispatch_fire;
assign rob_instr = new_rob_entry;

assign rs_alu_valid = dispatch_fire && (buffer_instr_in.FU_type == 2'b00);
assign rs_br_valid = dispatch_fire && (buffer_instr_in.FU_type == 2'b01);
assign rs_lsu_valid = dispatch_fire && (buffer_instr_in.FU_type == 2'b10);

assign rs_alu_instr = new_rs_entry;
assign rs_br_instr = new_rs_entry;
assign rs_lsu_instr = new_rs_entry;

endmodule