`timescale 1ns/1ps

`include "../phase2/riscv_types.svh"
`default_nettype none

module cpu_tb;
    logic clk, rst;

    // tie-offs for fetch
    logic stall, redirect;
    logic [31:0] redirect_pc;

    // ===== Fetch <-> Skid =====
    fe_bus_t fe_data_in, fe_data_out;
    logic fe_valid_in, fe_ready_out;
    logic fe_valid_out, de_ready_in;

    // Fetch outputs
    logic [31:0] pc_decode, inst_decode;

    // ===== Decode <-> Rename (stub) =====
    decode_to_rename_t de_data_in;
    logic de_valid_in;
    logic re_ready_out;
    
    decode_to_rename_t de_data_out;
    logic de_valid_out;
    logic re_ready_in;

    // Commit/flush stubs (if your rename has these ports)
    logic commit_valid;
    commit_to_rename_t commit_packet;
    rob_commit_t rob_flush;

    rename_to_dispatch_t re_data_in;
    logic re_valid_in;
    logic dp_ready_out;
    
    rename_to_dispatch_t re_data_out;
    logic re_valid_out;
    logic dp_ready_in;

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

    logic      wb_valid  [2:0];
    fu_to_prf_t wb_packet [2:0];


    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
    rst = 1;
    stall = 0;
    redirect = 0;
    redirect_pc = 32'h0;

    commit_valid  = 1'b0;
    commit_packet = '0;
    rob_flush     = '0;

    // ===== stubs to avoid X =====
    rob_full    = 1'b0;
    rs_alu_full = 1'b0;
    rs_br_full  = 1'b0;
    rs_lsu_full = 1'b0;

    wb_valid    = 3'b000;
    wb_packet   = '{default:'0};

    repeat (5) @(posedge clk);
    rst = 0;

    repeat (50) @(posedge clk);
    $finish;
    end


    // ===== Fetch =====
    fetch u_fetch(
    .clk(clk), .rst(rst),
    .stall(stall),
    .redirect(redirect),
    .redirect_pc(redirect_pc),

    // ready/valid handshake with skid
    .ready(fe_ready_out),
    .valid(fe_valid_in),

    .pc_decode(pc_decode),
    .inst_decode(inst_decode)
    );

    // pack into fe_bus_t for skid
    assign fe_data_in.pc    = pc_decode;
    assign fe_data_in.instr = inst_decode;

    // ===== Skid =====
    skid_buffer_struct #(.T(fe_bus_t)) u_fe_de(
    .clk(clk),
    .reset(rst),

    .valid_in(fe_valid_in),
    .ready_out(fe_ready_out),
    .data_in(fe_data_in),

    .valid_out(fe_valid_out),
    .ready_in(de_ready_in),
    .data_out(fe_data_out)
    );

    // ===== Decode =====
    decode u_decode(
    .clk(clk),
    .rst(rst),

    .fe_valid(fe_valid_out),
    .fe_instr(fe_data_out.instr),
    .fe_pc(fe_data_out.pc),
    .de_ready(de_ready_in),

    .de_valid(de_valid_in),
    .re_ready(re_ready_out),
    .de_signals_out(de_data_in)
    );

    // ====== DE -> RE Pipe =========

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

    rename u_rename (
    .clk(clk),
    .rst(rst),

    .de_valid(de_valid_out),
    .de_instr_in(de_data_out),
    .rn_ready(re_ready_in),

    .rn_valid(re_valid_in),
    .rn_instr_out(re_data_in),
    .dp_ready(dp_ready_out),

    .commit_valid(commit_valid),
    .commit_packet(commit_packet),
    .rob_flush(rob_flush)
    );

// ====== RE -> DP Pipe (Buffer) =========

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
        .rs_lsu_instr(rs_lsu_instr),

        .wb_valid(wb_valid),     
        .wb_packet(wb_packet)
    );

  int cyc;

    always_ff @(posedge clk) begin
    if (rst) cyc <= 0;
    else     cyc <= cyc + 1;
    end

    always_ff @(posedge clk) begin
    if (rst) begin
        rob_full    <= 1'b0;
        rs_alu_full <= 1'b0;
        rs_br_full  <= 1'b0;
        rs_lsu_full <= 1'b0;
    end else begin
        // 例如：C12~C14 让 ALU RS 满，看看 dp_ready_in 会不会拉低
        if (cyc == 12 || cyc == 13 || cyc == 14) rs_alu_full <= 1'b1;
        else rs_alu_full <= 1'b0;

        // 再来一次：C20~C21 让 ROB 满
        if (cyc == 20 || cyc == 21) rob_full <= 1'b1;
        else rob_full <= 1'b0;
    end
    end else begin
        // FE -> DE : skid output consumed by decode
        if (fe_valid_out && de_ready_in) begin
        $display("C%0d [FE->DE] pc=%08h inst=%08h", cyc, fe_data_out.pc, fe_data_out.instr);
        end

        // DE -> (skid in) : decode sends into DE->RE skid
        if (de_valid_in && re_ready_out) begin
        $display("C%0d [DE]     pc=%08h op=%02h rs1=%0d rs2=%0d rd=%0d imm=%0d branch=%0b jalr=%0b fu=%0d uses_rd=%0b",
            cyc,
            de_data_in.pc,
            de_data_in.opcode,
            de_data_in.rs1_addr,
            de_data_in.rs2_addr,
            de_data_in.rd_addr,
            $signed(de_data_in.immediate),
            de_data_in.is_branch,
            de_data_in.is_jalr,
            de_data_in.FU_type,
            de_data_in.uses_rd
        );
        end

        // DE->RE : skid output consumed by rename
        if (de_valid_out && re_ready_in) begin
        $display("C%0d [DE->RE] pc=%08h op=%02h rs1=%0d rs2=%0d rd=%0d",
            cyc,
            de_data_out.pc,
            de_data_out.opcode,
            de_data_out.rs1_addr,
            de_data_out.rs2_addr,
            de_data_out.rd_addr
        );
        end

        // RE -> DP : rename output (commit to downstream)
        if (re_valid_in && dp_ready_out) begin
        $display("C%0d [RE]     pc=%08h ps1=%0d ps2=%0d prd=%0d old=%0d rob=%0d",
            cyc,
            re_data_in.pc,
            re_data_in.ps1_addr,
            re_data_in.ps2_addr,
            re_data_in.prd_addr,
            re_data_in.old_prd_addr,
            re_data_in.rob_tag
        );
        end
        // BUF -> DP : fifo 输出给 dispatch
        if (re_valid_out) begin
        $display("C%0d [BUF->DP] pc=%08h fu=%0d ps1=%0d ps2=%0d prd=%0d uses_rd=%0b  dp_ready_in=%0b",
            cyc,
            re_data_out.pc,
            re_data_out.FU_type,
            re_data_out.ps1_addr,
            re_data_out.ps2_addr,
            re_data_out.prd_addr,
            re_data_out.uses_rd,
            dp_ready_in
        );
        end

        // DP stall reason（当 fifo 有东西但 dispatch 不收）
        if (re_valid_out && !dp_ready_in) begin
        $display("C%0d [DP] STALL rob_full=%0b alu_full=%0b br_full=%0b lsu_full=%0b fu=%0d",
            cyc, rob_full, rs_alu_full, rs_br_full, rs_lsu_full, re_data_out.FU_type);
        end

        // DP fire（等价于 dispatch_fire = re_valid_out && dp_ready_in）
        if (re_valid_out && dp_ready_in) begin
        $display("C%0d [DP] FIRE rob_v=%0b alu_v=%0b br_v=%0b lsu_v=%0b",
            cyc, rob_valid, rs_alu_valid, rs_br_valid, rs_lsu_valid);

        if (rob_valid) begin
            $display("C%0d [DP->ROB] pc=%08h prd=%0d old=%0d rob=%0d is_branch=%0b",
            cyc, rob_instr.pc, rob_instr.prd_addr, rob_instr.old_prd_addr, rob_instr.rob_tag, rob_instr.is_branch);
        end

        if (rs_alu_valid) begin
            $display("C%0d [DP->RS_ALU] rob=%0d prd=%0d ps1=%0d r1=%0b ps2=%0d r2=%0b",
            cyc, rs_alu_instr.rob_tag, rs_alu_instr.prd_addr,
            rs_alu_instr.ps1_addr, rs_alu_instr.ps1_ready,
            rs_alu_instr.ps2_addr, rs_alu_instr.ps2_ready);
        end
        if (rs_br_valid) begin
            $display("C%0d [DP->RS_BR ] rob=%0d prd=%0d ps1=%0d r1=%0b ps2=%0d r2=%0b",
            cyc, rs_br_instr.rob_tag, rs_br_instr.prd_addr,
            rs_br_instr.ps1_addr, rs_br_instr.ps1_ready,
            rs_br_instr.ps2_addr, rs_br_instr.ps2_ready);
        end
        if (rs_lsu_valid) begin
            $display("C%0d [DP->RS_LSU] rob=%0d prd=%0d ps1=%0d r1=%0b ps2=%0d r2=%0b MR=%0b MW=%0b",
            cyc, rs_lsu_instr.rob_tag, rs_lsu_instr.prd_addr,
            rs_lsu_instr.ps1_addr, rs_lsu_instr.ps1_ready,
            rs_lsu_instr.ps2_addr, rs_lsu_instr.ps2_ready,
            rs_lsu_instr.MemRead, rs_lsu_instr.MemWrite);
        end
    end
end
endmodule
