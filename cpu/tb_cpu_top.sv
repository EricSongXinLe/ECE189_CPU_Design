`timescale 1ns / 1ps

module tb_cpu_top;

    // 1. 声明信号
    logic clk;
    logic rst;

    // 2. 实例化你的 CPU (Device Under Test)
    cpu_top u_cpu (
        .clk(clk),
        .rst(rst)
    );

    // 3. 产生时钟 (周期 10ns -> 100MHz)
    always #5 clk = ~clk;

    // 4. 测试流程
    initial begin
        // 初始化信号
        clk = 0;
        rst = 1; // 保持复位状态

        // 打印开始信息
        $display("=== Simulation Start ===");

        // 复位 20ns 后释放
        #20;
        rst = 0; 
        $display("=== Reset Released ===");

        // 让仿真跑一段时间 (比如 500ns)
        // 这个时间足够跑完我们那 3 条指令了
        #500;

        // 结束仿真
        $display("=== Simulation Finished ===");
        $stop; // 暂停仿真
    end

endmodule