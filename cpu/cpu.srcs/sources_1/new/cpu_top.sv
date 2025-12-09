`timescale 1ns / 1ps
`include "riscv_types.svh"

module cpu_top(
    input clk,
    input rst
);

// ====== Fetch =========
fe_bus_t fe_data_in;
logic fe_valid_in;
logic fe_ready_out;

logic stall;
logic redirect;
logic [31:0] redirect_pc;

fetch u_fetch (
    .clk         (clk),
    .rst         (rst),

    //later from ROB/fu_br
    .stall        (stall),
    .redirect     (redirect),
    .redirect_pc  (redirect_pc),

    //handshake to skid
    .ready       (fe_ready_out),
    .valid       (fe_valid_in),

    // payload to skid
    .pc_decode   (fe_data_in.pc),
    .inst_decode (fe_data_in.instr)
);


// ====== FE -> DE pipe =========
fe_bus_t fe_data_out;
logic fe_valid_out;
logic de_ready_in;

skid_buffer_struct #(.T(fe_bus_t)) 
u_fe_de (
    .clk        (clk),
    .reset      (rst),
    // upstream: fetch <-> skid
    .valid_in   (fe_valid_in),
    .ready_out   (fe_ready_out),
    .data_in    (fe_data_in),
    // downstream: skid <-> decode
    .valid_out  (fe_valid_out),
    .ready_in  (de_ready_in),
    .data_out   (fe_data_out)
);

// ====== Decode =========
decode_to_rename_t de_data_in;
logic de_valid_in;
logic re_ready_out;

decode u_decode (
    .clk            (clk),
    .rst            (rst),
    // upstream (from skid)
    .fe_valid       (fe_valid_out),
    .fe_instr       (fe_data_out.instr),
    .fe_pc          (fe_data_out.pc),
    .de_ready       (de_ready_in),      // decode advertises readiness to skid
    // downstream (to RE)
    .de_valid       (de_valid_in),
    .re_ready       (re_ready_out),
    .de_signals_out (de_data_in)
);

// ====== DE -> RE Pipe =========
decode_to_rename_t de_data_out;
logic de_valid_out;
logic re_ready_in;

skid_buffer_struct #(.T(decode_to_rename_t)) 
u_de_re (
    .clk        (clk),
    .reset      (rst),
    // upstream: decode <-> skid
    .valid_in   (de_valid_in),
    .ready_out   (re_ready_out),
    .data_in    (de_data_in),
    // downstream: skid <-> decode
    .valid_out  (de_valid_out),
    .ready_in  (re_ready_in),
    .data_out   (de_data_out)
);

// ====== Rename =========
rename_to_dispatch_t re_data_in;
logic re_valid_in;
logic dp_ready_out;

rename u_rename (
    .clk(clk),
    .rst(rst),

    // --- Upstream (from Decode) ---
    .de_valid(de_valid_out),
    .de_instr_in(de_data_out),
    .rn_ready(re_ready_in),

    // downstream (to DP)
    .rn_valid       (re_valid_in),
    .rn_instr_out   (re_data_in),
    .dp_ready       (dp_ready_out)
);

// ====== RE -> DP Pipe (Buffer) =========
rename_to_dispatch_t re_data_out;
logic re_valid_out;
logic dp_ready_in;

fifo_pipeline #(.T(rename_to_dispatch_t), .DEPTH(2))
u_buffer_fifo (
    .clk(clk),
    .reset(rst),

    .valid_in(re_valid_in),
    .ready_out(dp_ready_out),
    .write_data(re_data_in),
    .valid_out(re_valid_out),
    .ready_in(dp_ready_in),
    .read_data(re_data_out)
);

// ====== Dispatch =========
logic rob_full;
logic rob_valid;
dispatch_to_rob_t rob_instr;

logic rs_alu_full;
logic rs_alu_valid;
dispatch_to_rs_t rs_alu_instr;

logic rs_br_full; 
logic rs_br_valid;
dispatch_to_rs_t rs_br_instr;

logic rs_lsu_full;
logic rs_lsu_valid;
dispatch_to_rs_t rs_lsu_instr;

dispatch u_dispatch (
    .clk(clk),
    .rst(rst),

    // --- Upstream (from Rename) ---
    .buffer_valid_in(re_valid_out),
    .buffer_instr_in(re_data_out),
    .dp_ready_out(dp_ready_in),

    // --- Downstream (to ROB) ---
    .rob_full(rob_full),
    .rob_valid(rob_valid),
    .rob_instr(rob_instr),
    // --- Downstream (to RS) --- 
    .rs_alu_full(rs_alu_full),
    .rs_alu_valid(rs_alu_valid),
    .rs_alu_instr(rs_alu_instr),

    .rs_br_full(rs_br_full),
    .rs_br_valid(rs_br_valid),
    .rs_br_instr(rs_br_instr),

    .rs_lsu_full(rs_lsu_full),
    .rs_lsu_valid(rs_lsu_valid),
    .rs_lsu_instr(rs_lsu_instr)
);

// ====== ROB =========
logic  wb_valid [3];
fu_to_prf_t wb_packet [3];
logic flush;
fu_to_rob_t fu_wb;
rob_commit_t rob_commit;

ROB u_rob (
    .clk(clk),
    .rst(rst),

    .dp_data_in(rob_instr),
    .dp_valid(rob_valid),

    .flush(flush),
    .fu_wb(fu_wb),

    .wb_valid (wb_valid),
    .wb_packet(wb_packet),

    .rob_full(rob_full),
    .rob_commit(rob_commit)
);

// ====== RS_ALU =========
logic            issue_valid_alu;
dispatch_to_rs_t issue_instr_alu;
logic            fu_ready_alu; 

RS u_alu (
    .clk(clk),
    .rst(rst),

    .dp_valid(rs_alu_valid),
    .dp_instr(rs_alu_instr),
    .rs_full(rs_alu_full),

    .wb_valid(wb_valid),
    .wb_packet(wb_packet),

    .issue_valid(issue_valid_alu),
    .issue_instr(issue_instr_alu),
    .fu_ready(fu_ready_alu)  
);

// ====== RS_BR =========
logic            issue_valid_br;
dispatch_to_rs_t issue_instr_br;
logic            fu_ready_br; 
RS u_br (
    .clk(clk),
    .rst(rst),

    .dp_valid(rs_br_valid),
    .dp_instr(rs_br_instr),
    .rs_full(rs_br_full),

    .wb_valid(wb_valid),
    .wb_packet(wb_packet),

    .issue_valid(issue_valid_br),
    .issue_instr(issue_instr_br),
    .fu_ready(fu_ready_br)  
);

// ====== RS_LSU =========
logic            issue_valid_lsu;
dispatch_to_rs_t issue_instr_lsu;
logic            fu_ready_lsu; 
RS u_lsu (
    .clk(clk),
    .rst(rst),

    .dp_valid(rs_lsu_valid),
    .dp_instr(rs_lsu_instr),
    .rs_full(rs_lsu_full),

    .wb_valid(wb_valid),
    .wb_packet(wb_packet),

    .issue_valid(issue_valid_lsu),
    .issue_instr(issue_instr_lsu),
    .fu_ready(fu_ready_lsu)  
);


// ====== Execution =========
logic [31:0] prf_val1_alu;
logic [31:0] prf_val2_alu;

logic [31:0] prf_val1_br;
logic [31:0] prf_val2_br;

logic [31:0] prf_val1_lsu;
logic [31:0] prf_val2_lsu;

// ====== PRF =========
logic [PREG_IDX_WIDTH-1:0] read_addr [PRF_READ_PORTS];
logic [31:0]               read_data [PRF_READ_PORTS];
logic                      write_en [PRF_WRITE_PORTS];
fu_to_prf_t                write_port_data [PRF_WRITE_PORTS];

prf u_prf (
    .clk(clk),
    .rst(rst),

    .read_addr(read_addr),
    .read_data(read_data),

    .write_en(wb_valid),
    .write_port_data(wb_packet)    
);

// PRF Read Port Mapping
assign read_addr[0] = issue_instr_alu.ps1_addr;
assign read_addr[1] = issue_instr_alu.ps2_addr;

assign read_addr[2] = issue_instr_br.ps1_addr;
assign read_addr[3] = issue_instr_br.ps2_addr;

assign read_addr[4] = issue_instr_lsu.ps1_addr;
assign read_addr[5] = issue_instr_lsu.ps2_addr;

// PRF Read Data Mapping
assign prf_val1_alu = read_data[0];
assign prf_val2_alu = read_data[1];

assign prf_val1_br  = read_data[2];
assign prf_val2_br  = read_data[3];

assign prf_val1_lsu = read_data[4];
assign prf_val2_lsu = read_data[5];


// Execution signals
logic flush_from_rob;
logic        dmem_en;
logic [31:0] dmem_addr;
logic [31:0] dmem_rdata;

//dMem instantiation
dmem u_dmem (
    .clk(clk),
    .en(dmem_en),
    .addr(dmem_addr),

    .data(dmem_rdata)
);

logic        is_jalr;
logic [31:0] target_pc;
logic        mispredict;
logic [ROB_IDX_WIDTH-1:0] br_rob_tag;

execute u_execute (
    .clk(clk),
    .rst(rst),
    .flush(flush_from_rob),

    // ---- Issue from RS ----
    .alu_issue_valid(issue_valid_alu),
    .alu_issue_instr(issue_instr_alu),
    .alu_val1(prf_val1_alu),
    .alu_val2(prf_val2_alu),

    .bru_issue_valid(issue_valid_br),
    .bru_issue_instr(issue_instr_br),
    .bru_val1(prf_val1_br),
    .bru_val2(prf_val2_br),

    .lsu_issue_valid(issue_valid_lsu),
    .lsu_issue_instr(issue_instr_lsu),
    .lsu_val1(prf_val1_lsu),
    .lsu_val2(prf_val2_lsu),

    // ---- Memory ----
    .dmem_en(dmem_en),
    .dmem_addr(dmem_addr),
    .dmem_rdata(dmem_rdata),

    // ---- CDB outputs ----
    .wb_valid(wb_valid),
    .wb_packet(wb_packet),

    // ---- Branch outcome ----
    .is_jalr(is_jalr),
    .target_pc(target_pc),
    .mispredict(mispredict),
    .br_rob_tag(br_rob_tag)
);

logic branch_flush;
assign branch_flush = issue_valid_br && (mispredict || is_jalr);
//FE wireback
assign stall = rob_full || rs_alu_full || rs_br_full || rs_lsu_full; //TO DO
assign redirect = branch_flush;
assign redirect_pc = target_pc;
// FU->ROB
assign flush = branch_flush;
assign fu_wb.rob_tag = br_rob_tag;
assign fu_wb.mispredict = mispredict;
assign fu_wb.branch_target = target_pc;


// ROB->FU
assign flush_from_rob = rob_commit.mispredict;


endmodule


//TO DO: execute step regfile read before execution
//TO DO; pipeline buffer implmentation
//TO DO: port connection


