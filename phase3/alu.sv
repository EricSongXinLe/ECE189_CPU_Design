module alu (
    input  logic                clk,
    input  logic                rst,
    input  logic                flush,

    input  logic                valid_in,
    input  dispatch_to_rs_t     instr_in,
    input  logic [31:0]         val1,
    input  logic [31:0]         val2,

    output logic                valid_out,
    output fu_to_prf_t          wb_packet
);

    logic [31:0] result;
    logic [31:0] op2;
    assign op2 = instr_in.ALUSrc ? instr_in.immediate : val2;

    // 组合逻辑：只负责算 result
    always_comb begin
        result = '0;
        unique case (instr_in.funct3)
            3'b000: begin
                if (instr_in.ALUOp == 2'b10 && instr_in.funct7[5] && !instr_in.ALUSrc)
                    result = val1 - op2;
                else
                    result = val1 + op2;
            end
            3'b001: result = val1 << op2[4:0];
            3'b010: result = ($signed(val1) < $signed(op2)) ? 32'd1 : 32'd0;
            3'b011: result = (val1 < op2) ? 32'd1 : 32'd0;
            3'b100: result = val1 ^ op2;
            3'b101: begin
                if (instr_in.funct7[5])
                    result = $signed(val1) >>> op2[4:0];
                else
                    result = val1 >> op2[4:0];
            end
            3'b110: result = val1 | op2;
            3'b111: result = val1 & op2;
            default: result = '0;
        endcase

        if (instr_in.opcode == 7'h37) begin
            result = instr_in.immediate; // LUI
        end
    end

    // 🔑 打拍保存「上一条指令」的信息
    dispatch_to_rs_t instr_q;
    logic [31:0]     result_q;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            valid_out <= 1'b0;
            instr_q   <= '0;
            result_q  <= '0;
        end else begin
            valid_out <= valid_in;
            instr_q   <= instr_in;
            result_q  <= result;
        end
    end

    // 输出 wb_packet：完全使用打拍后的 instr_q / result_q
    always_comb begin
        wb_packet.prd_addr = instr_q.prd_addr;
        wb_packet.rob_tag  = instr_q.rob_tag;
        wb_packet.data     = result_q;
    end

    // Debug：也用 instr_q，而不是 instr_in
    always_ff @(posedge clk) begin
        if (!rst && valid_out) begin
            $display("[ALU_WB] t=%0t pc=%h prd=%0d rob=%0d data=%0d",
                     $time,
                     instr_q.pc,
                     wb_packet.prd_addr,
                     wb_packet.rob_tag,
                     wb_packet.data);
        end
    end

    // 你想保留的 ALU_IN 打印可以继续放在 valid_in 时：
    always_ff @(posedge clk) begin
        if (!rst && valid_in) begin
            $display("[ALU_IN] t=%0t pc=%h ALUSrc=%0d val1=%0d val2=%0d imm=%0d op2=%0d funct3=%0b funct7=%0b",
                     $time,
                     instr_in.pc,
                     instr_in.ALUSrc,
                     val1,
                     val2,
                     instr_in.immediate,
                     op2,
                     instr_in.funct3,
                     instr_in.funct7);
        end
    end

endmodule
