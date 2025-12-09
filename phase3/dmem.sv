module dmem #(
    parameter BLOCK_SIZE = 1024
)(
    input  logic        clk,
    input  logic        en,
    input  logic [31:0] addr,
    output logic [31:0] data
);
    // 定义内存数组
    logic [31:0] dmem[0:BLOCK_SIZE-1];

    // 初始化内存
    // 注意：如果你有单独的数据文件，请将 "program.mem" 改为 "data.mem"
    // 修复：这里必须使用上面定义的 dmem 数组，而不是 iMEM
    initial $readmemh("program.mem", dmem);

    // 同步读取 (BRAM 行为)
    always_ff @(posedge clk) begin
        if (en) begin
            // 修复：输出给 data，地址来自 addr (按字寻址)
            data <= dmem[addr[31:2]];
        end
    end

endmodule