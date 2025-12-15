module dmem #(
    parameter BLOCK_SIZE = 1024
)(
    input  logic        clk,
    input  logic        en,
    input  logic        we, // Write Enable
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
            if (we) begin
                // 写操作 (简化版：只支持按字写入，如果需要支持 SH/SB 需要掩码)
                // 25swr.txt 里的 SH/SB 可能需要更复杂的逻辑，但先跑通 SW
                dmem[addr[11:2]] <= wdata;
            end else begin
                // 读操作
                // data <= dmem[addr[31:2]];
                dmem[addr[11:2]] <= dmem[addr[11:2]]; // 读保持/读出
                data <= dmem[addr[11:2]];
            end
        end
    end

endmodule