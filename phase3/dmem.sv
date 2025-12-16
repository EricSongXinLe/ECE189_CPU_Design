module dmem #(
    parameter BLOCK_SIZE = 1024
)(
    input  logic        clk,
    input  logic        en,
    input  logic        we, // Write Enable
    input  logic [3:0]  wstrb,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    output logic [31:0] data
);
    // 定义内存数组
    logic [31:0] dmem[0:BLOCK_SIZE-1];
    initial begin
    for (int i = 0; i < BLOCK_SIZE; i++) begin
        dmem[i] = 32'b0;
    end
    // 初始化内存
    // 注意：如果你有单独的数据文件，请将 "program.mem" 改为 "data.mem"
    // 修复：这里必须使用上面定义的 dmem 数组，而不是 iMEM
    $readmemh("program.mem", dmem);
    end

    // 同步读取 (BRAM 行为)
    always_ff @(posedge clk) begin
        if (en) begin
            int unsigned idx;
            logic [31:0] merged;

            idx    = addr[11:2];
            merged = dmem[idx];

            if (we) begin
                if (wstrb[0]) merged[7:0]   = wdata[7:0];
                if (wstrb[1]) merged[15:8]  = wdata[15:8];
                if (wstrb[2]) merged[23:16] = wdata[23:16];
                if (wstrb[3]) merged[31:24] = wdata[31:24];

                dmem[idx] <= merged;
                data      <= merged; // write-first
                $display("[DMEM] WRITE addr=%h (idx=%0d) wstrb=%b val=%h", addr, idx, wstrb, merged);
            end else begin
                data <= dmem[idx];
            end
        end
    end

endmodule