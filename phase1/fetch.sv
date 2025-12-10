`timescale 1ns / 1ps

module fetch(
    input  logic        clk,
    input  logic        rst,

    // 流控 & 分支
    input  logic        stall,        // 下游 / 结构冲突，暂停取指
    input  logic        redirect,     // 来自 BRU/ROB 的重定向（JALR/branch mispredict）
    input  logic [31:0] redirect_pc,  // 跳转目标 PC

    // 与下游（skid/decode）的 ready/valid 握手
    input  logic        ready,        // 下游能接受新一条指令
    output logic        valid,        // 本周期输出有效

    // 输出到 Decode
    output logic [31:0] pc_decode,
    output logic [31:0] inst_decode
);

    // F1：发给 icache 的 PC
    logic [31:0] pc;

    // F2：和 icache 输出 inst 对齐的 PC
    logic [31:0] pc_f2;

    // 顺序执行时的 "下一条 PC"
    logic [31:0] nextpc;

    // 从 icache 读出的指令
    logic [31:0] inst;

    // 是否需要保持当前输出不变（下游没 ready 或上游 stall）
    logic hold;

    // ready/valid + stall 组合成 hold
    assign hold = stall || (valid && !ready);

    // 顺序执行情况下的 nextpc（不含 redirect）
    always_comb begin
        nextpc = pc + 32'd4;
    end

    // --------- F1：PC 更新逻辑（驱动 icache） ---------
    always_ff @(posedge clk) begin
        if (rst) begin
            pc <= 32'b0;
        end
        // ★ redirect 优先级最高，不能被 hold 掉
        else if (redirect) begin
            pc <= redirect_pc;
        end
        // 正常顺序执行，只有在不 hold 时才推进
        else if (!hold) begin
            pc <= nextpc;
        end
        // else: hold=1 且没有 redirect，pc 保持不变
    end

    // --------- F2：PC 打一拍，与 inst 对齐 ---------
    always_ff @(posedge clk) begin
        if (rst) begin
            pc_f2 <= 32'b0;
        end
        else if (redirect) begin
            // 和 F1 一致：redirect 发生时，直接把 pc_f2 调整到跳转目标
            pc_f2 <= redirect_pc;
        end
        else if (!hold) begin
            // 正常情况下，F2 拿到的是 F1 的 PC
            pc_f2 <= pc;
        end
        // else: hold，保持 pc_f2 不变
    end

    // --------- F2 输出：送往 Decode 的 valid/pc/instr ---------
    always_ff @(posedge clk) begin
        if (rst) begin
            valid       <= 1'b0;
            pc_decode   <= 32'b0;
            inst_decode <= 32'b0;
        end
        else if (!hold) begin
            // 只有在不 hold 的时候才更新输出
            valid       <= 1'b1;
            pc_decode   <= pc_f2;  // ★ 和 inst 对齐后的 PC
            inst_decode <= inst;   // 来自 icache 的指令
        end
        // else: hold=1，保持上一拍的 valid/pc_decode/inst_decode
    end

    // --------- 指令存储 / icache ---------
    icache u_icache(
        .clk (clk),
        .pc  (pc),   // 用 F1 的 PC 作为地址
        .inst(inst)
    );
    
    always_ff @(posedge clk) begin
    if (!rst) begin
        $display("[FETCH] t=%0t pc=%h hold=%0d redirect=%0d redirect_pc=%h valid=%0d ready=%0d",
                 $time, pc, hold, redirect, redirect_pc, valid, ready);
    end
end


endmodule
