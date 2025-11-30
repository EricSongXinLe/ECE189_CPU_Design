module dispatch (
    input logic clk, rst,

    //rename <-> dispatch
    output logic rn_ready, //dispatch/buffer has space to take in new instr
    input logic rn_valid, //rename has new instr
    input rename_to_dispatch_t rn_instr_in,

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

rename_to_dispatch_t buffer_instr_in;
logic buffer_valid; //will inplement in the pipeline buffer module, later connect ports w/ buffer

dispatch_to_rs_t new_rs_entry;
dispatch_to_rob_t new_rob_entry;

always_comb begin
    new_rs_entry = '0;
    new_rob_entry = '0;
    if (buffer_valid) begin
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

        //rob
        new_rob_entry.pc           = buffer_instr_in.pc;
        new_rob_entry.prd_addr     = buffer_instr_in.prd_addr;
        new_rob_entry.old_prd_addr = buffer_instr_in.old_prd_addr;
        new_rob_entry.rob_tag      = buffer_instr_in.rob_tag;
        new_rob_entry.is_branch  = buffer_instr_in.is_branch;
    end
end

//Determine RS readiness
logic rs_ready;
always_comb begin
    rs_ready = 0;
    if (buffer_valid) begin
        case (buffer_instr_in.FU_type)
            2'b00: rs_ready = !rs_alu_full; //ALU
            2'b01: rs_ready = !rs_br_full; //BR
            2'b10: rs_ready = !rs_lsu_full; //LSU
            default: rs_ready = 0;
        endcase
    end
end

//Determine ROB readiness
logic rob_ready;
assign rob_ready = !rob_full;

always_ff @(posedge clk) begin
    rob_valid <=0;
    rs_alu_valid<=0;
    rs_br_valid<=0;
    rs_lsu_valid<=0;
    if (rst) begin
        buffer_valid<=0;
        buffer_instr_in <='0;
        rn_ready<=1'b1; //empty buffer -> ready after reset
    end
    else if (!buffer_valid) begin //if pipeline buffer has no instructions
        rn_ready <= 1'b1;
        if (rn_valid) begin //if rename holds an instr -> fill in buffer
            buffer_instr_in <= rn_instr_in;
            buffer_valid <= 1'b1;
            rn_ready <= 0; //rename can't accept any intructions anymore
        end
    end
    else begin //if buffer has instructions
        rn_ready <= 0; //cannot accept instructions
        if (rs_ready&&rob_ready) begin //pass instructions from buffer to RS&ROB
            rob_instr <= new_rob_entry;
            rob_valid <= 1'b1;
            case (buffer_instr_in.FU_type)
            2'b00: begin
                rs_alu_valid <= 1'b1;
                rs_alu_instr <= new_rs_entry; //ALU
            end
            2'b01: begin
                rs_br_valid <= 1'b1;
                rs_br_instr <= new_rs_entry; //BR
            end
            2'b10: begin
                rs_lsu_valid <= 1'b1;
                rs_lsu_instr <= new_rs_entry; //LSU
            end
            default: ;
            endcase

            buffer_valid <= 0; //buffer gets empty next cycle
            rn_ready <= 1; //ready for next instruction
        end
        else begin //if either RS/ROB not ready
            buffer_valid<=1; //buffer holds instr
        end
    end
end

endmodule