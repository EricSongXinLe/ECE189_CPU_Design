`timescale 1ns / 1ps
`include "riscv_types.svh"

module cpu_top(
    input clk,
    input rst
);
localparam int NUM_PREGS = (1 << PREG_IDX_WIDTH);
logic [NUM_PREGS-1:0] preg_busy_table;

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
    .flush(flush),
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
    .flush(flush),
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
    
    // --- Writeback (CDB) for RAT/FreeList Update ---
    // 加上这两行连接：
    .wb_valid(wb_valid),    // 连接顶层的 wb_valid 信号
    .wb_packet(wb_packet),  // 连接顶层的 wb_packet 信号
    
    // downstream (to DP)
    .rn_valid       (re_valid_in),
    .rn_instr_out   (re_data_in),
    .dp_ready       (dp_ready_out),
    .commit_valid     (rob_commit.valid),       
    
    // 2. 提交信息 (告诉 Rename 哪个旧物理寄存器可以释放了)
// ★ 用我们刚刚定义好的 commit_bus
    .commit_instr  (commit_bus), 

    // 3. 分支预测失败 (用于恢复 Map Table Checkpoint)
    // 你的 cpu_top 后面定义了 flush_from_rob，可以直接用
    .mispredict_valid (flush_from_rob),
    .preg_busy_table(preg_busy_table)
);

// ====== RE -> DP Pipe (Buffer) =========
rename_to_dispatch_t re_data_out;
logic re_valid_out;
logic dp_ready_in;

fifo_pipeline #(.T(rename_to_dispatch_t), .DEPTH(2))
u_buffer_fifo (
    .clk(clk),
    .reset(rst),
    .flush(flush),
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
logic [2:0] wb_valid;             // Packed: 正确，这是 3-bit 宽的向量
fu_to_prf_t [2:0] wb_packet;

logic flush;
fu_to_rob_t fu_wb;
rob_commit_t rob_commit;
commit_to_rename_t  commit_bus;
assign fu_wb.mispredict = mispredict || is_jalr; 
assign fu_wb.branch_target = target_pc;
assign fu_wb.rob_tag = br_rob_tag;
logic branch_update_en;
assign branch_update_en = issue_valid_br;
ROB u_rob (
    .clk(clk),
    .rst(rst),

    .dp_data_in(rob_instr),
    .dp_valid(rob_valid),

    .flush(flush),
    .wb_is_branch(branch_update_en),
    .fu_wb(fu_wb),

    .wb_valid (wb_valid),
    .wb_packet(wb_packet),

    .rob_full(rob_full),
    .rob_commit(rob_commit)
);

assign commit_bus.old_prd_addr = rob_commit.old_prd_addr;

// 如果你的 rob_commit 里真的有 rd_addr，就写：
// assign commit_bus.rd_addr      = rob_commit.rd_addr;
// 否则暂时全 0（rename 目前也没用 rd_addr）
assign commit_bus.rd_addr      = '0;

// RegWrite 我记得你在 ROB 里已经算过了：RegWrite = (old_prd_addr != 0)
assign commit_bus.RegWrite    = rob_commit.RegWrite;

// is_branch 现在 rename 也没用，但我们还是老老实实转发一下
assign commit_bus.is_branch   = rob_commit.is_branch;


// ====== RS_ALU =========
logic            issue_valid_alu;
dispatch_to_rs_t issue_instr_alu;
logic            fu_ready_alu; 

assign fu_ready_alu = 1'b1;
assign fu_ready_br  = 1'b1;
assign fu_ready_lsu = 1'b1;

RS u_alu (
    .clk(clk),
    .rst(rst),
    .flush(flush),
    .busy_table(preg_busy_table),

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
    .flush(flush),
    .busy_table(preg_busy_table),

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
RS_ORDERED u_lsu (
    .clk(clk),
    .rst(rst),
    .flush(flush),
    .busy_table(preg_busy_table),

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
// ✅ 替换为这段 Bypass 逻辑 ✅
// --- Operand Bypass / Forwarding Logic ---
// We need to check if the data currently being written back (on CDB) 
// is the data we need for the current issue stage.

logic [31:0] alu_op1_final, alu_op2_final;
logic [31:0] br_op1_final,  br_op2_final;
logic [31:0] lsu_op1_final, lsu_op2_final;

always_comb begin
    // ---------------------------------------------------------
    // 1. ALU Port Bypass
    // ---------------------------------------------------------
    // Operand 1
    alu_op1_final = read_data[0]; // Default: read from PRF
    for (int k = 0; k < 3; k++) begin
        // If WB is valid AND addresses match AND not x0/p0
        if (wb_valid[k] && wb_packet[k].prd_addr == issue_instr_alu.ps1_addr && issue_instr_alu.ps1_addr != '0) begin
            alu_op1_final = wb_packet[k].data;
        end
    end

    // Operand 2
    alu_op2_final = read_data[1];
    for (int k = 0; k < 3; k++) begin
        if (wb_valid[k] && wb_packet[k].prd_addr == issue_instr_alu.ps2_addr && issue_instr_alu.ps2_addr != '0) begin
            alu_op2_final = wb_packet[k].data;
        end
    end
    
    // ---------------------------------------------------------
    // 2. Branch Port Bypass
    // ---------------------------------------------------------
    // Operand 1
    br_op1_final = read_data[2];
    for (int k = 0; k < 3; k++) begin
        if (wb_valid[k] && wb_packet[k].prd_addr == issue_instr_br.ps1_addr && issue_instr_br.ps1_addr != '0) begin
            br_op1_final = wb_packet[k].data;
        end
    end

    // Operand 2
    br_op2_final = read_data[3];
    for (int k = 0; k < 3; k++) begin
        if (wb_valid[k] && wb_packet[k].prd_addr == issue_instr_br.ps2_addr && issue_instr_br.ps2_addr != '0) begin
            br_op2_final = wb_packet[k].data;
        end
    end

    // ---------------------------------------------------------
    // 3. LSU Port Bypass
    // ---------------------------------------------------------
    // Operand 1
    lsu_op1_final = read_data[4];
    for (int k = 0; k < 3; k++) begin
        if (wb_valid[k] && wb_packet[k].prd_addr == issue_instr_lsu.ps1_addr && issue_instr_lsu.ps1_addr != '0) begin
            lsu_op1_final = wb_packet[k].data;
        end
    end

    // Operand 2
    lsu_op2_final = read_data[5];
    for (int k = 0; k < 3; k++) begin
        if (wb_valid[k] && wb_packet[k].prd_addr == issue_instr_lsu.ps2_addr && issue_instr_lsu.ps2_addr != '0) begin
            lsu_op2_final = wb_packet[k].data;
        end
    end
end


// Execution signals
logic flush_from_rob;
logic        dmem_en;
logic [31:0] dmem_addr;
logic [31:0] dmem_rdata;
logic        dmem_we;
logic [31:0] dmem_wdata;
logic [3:0] dmem_wstrb;
//dMem instantiation
dmem u_dmem (
    .clk(clk),
    .en(dmem_en),
    .we(dmem_we),
    .wstrb (dmem_wstrb),
    .addr(dmem_addr),
    .wdata(dmem_wdata),
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
    .alu_val1(alu_op1_final),
    .alu_val2(alu_op2_final),

    .bru_issue_valid(issue_valid_br),
    .bru_issue_instr(issue_instr_br),
    .bru_val1(br_op1_final),
    .bru_val2(br_op2_final),

    .lsu_issue_valid(issue_valid_lsu),
    .lsu_issue_instr(issue_instr_lsu),
    .lsu_val1(lsu_op1_final),
    .lsu_val2(lsu_op2_final),

    // ---- Memory ----
    .dmem_en(dmem_en),
    .dmem_we(dmem_we),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_rdata(dmem_rdata),
    .dmem_wstrb (dmem_wstrb),

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
//assign redirect = branch_flush;
//assign redirect_pc = target_pc;
// FU->ROB
//assign flush = branch_flush;
// 1. 定义 Execute 阶段的 flush 仅用于通知 ROB (这部分保持不变，用于写回 ROB)
logic branch_exec_valid;
assign branch_exec_valid = issue_valid_br && (mispredict || is_jalr);
// FU->ROB: 告诉 ROB 这条指令是 Mispredict
assign fu_wb.mispredict = mispredict; 
assign fu_wb.branch_target = target_pc;

// 2. 全局 Flush/Redirect 逻辑 (全部移到 Commit 阶段)
// 当 ROB 提交一个 mispredict 的分支时，触发全局冲刷
assign flush_from_rob = rob_commit.mispredict; 

// Fetch 重定向：与 Rename 恢复同步
assign redirect    = flush_from_rob; 
assign redirect_pc = rob_commit.branch_target; // 确保 rob_commit 结构体里有这个字段

// Pipeline Buffer 冲刷：也使用 Commit 信号
// 注意：这会让错误路径的指令填满 ROB 后才被杀掉，但这最安全
assign flush       = flush_from_rob; 

assign fu_wb.rob_tag = br_rob_tag;
assign fu_wb.mispredict = mispredict;
assign fu_wb.branch_target = target_pc;


// ROB->FU
assign flush_from_rob = rob_commit.mispredict;

always_ff @(posedge clk) begin
    if (!rst) begin
        for (int k = 0; k < 3; k++) begin
            if (wb_valid[k]) begin
                `ifndef SYNTHESIS
                $display("[WB] t=%0t port=%0d prd=%0d data=%0d rob_tag=%0d",
                         $time, k, wb_packet[k].prd_addr, wb_packet[k].data, wb_packet[k].rob_tag);
                `endif
            end
        end
    end
end

always_ff @(posedge clk) begin
    if (!rst) begin
        if (branch_flush) begin
            $display("[CPU_TOP] t=%0t BRANCH_FLUSH redirect_pc=%h mispredict=%0d is_jalr=%0d br_rob_tag=%0d",
                     $time, target_pc, mispredict, is_jalr, br_rob_tag);
        end
    end
end


endmodule


//TO DO: execute step regfile read before execution
//TO DO; pipeline buffer implmentation
//TO DO: port connection


