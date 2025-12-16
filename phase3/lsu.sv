`timescale 1ns / 1ps
`include "riscv_types.svh"

module lsu (
    input  logic                clk,
    input  logic                rst,
    input  logic                flush,

    // --- Dispatch Allocation Interface (Store) ---
    input  logic                alloc_valid,
    input  logic [SQ_IDX_WIDTH-1:0] alloc_sq_idx,

    // --- Issue Interface (from RS) ---
    input  logic                valid_in,
    input  dispatch_to_rs_t     instr_in,
    input  logic [31:0]         val1, // Base Addr
    input  logic [31:0]         val2, // Store Data

    // --- Commit Interface (from ROB) ---
    input  logic                commit_valid,
    input  logic                commit_mem_write, // ROB 提交的是否是 Store

    // --- Data Memory Interface ---
    output logic                mem_en,
    output logic                mem_we,    
    output logic [31:0]         mem_addr,
    output logic [31:0]         mem_wdata,
    input  logic [31:0]         mem_rdata,

    // --- Writeback Interface ---
    output logic                valid_out,
    output fu_to_prf_t          wb_packet,

    // --- Flow Control ---
    output logic                lsu_busy // 冲突时置高，阻止 RS 发新指令
);

    // --- Store Queue Definition ---
    typedef struct packed {
        logic        valid;
        logic [31:0] addr;
        logic [31:0] data;
        logic        addr_ready;
        logic [1:0]  funct3; // 用于 SB/SH/SW
    } sq_entry_t;

    sq_entry_t SQ [SQ_SIZE];
    logic [SQ_IDX_WIDTH-1:0] sq_head;

    // --- AGU (Address Generation) ---
    logic [31:0] agu_addr;
    assign agu_addr = val1 + instr_in.immediate;

    // --- Conflict Detection (Combinational) ---
    logic conflict;
    
    always_comb begin
        conflict = 1'b0;
        if (valid_in && instr_in.MemRead) begin // 如果是 Load
            // 遍历 SQ，检查所有有效且比我老（Age < My_SQ_Idx）的 Store
            // 这里的 sq_idx 来自 Dispatch 阶段的快照
            // 我们检查从 sq_head 到 instr_in.sq_idx (不包含) 的所有条目
            
            for (int i = 0; i < SQ_SIZE; i++) begin
                if (SQ[i].valid) begin
                    // 判断 i 是否在 [sq_head, instr_in.sq_idx) 区间内 (处理回绕)
                    logic is_older;
                    if (sq_head <= instr_in.sq_idx)
                        is_older = (i >= sq_head && i < instr_in.sq_idx);
                    else
                        is_older = (i >= sq_head || i < instr_in.sq_idx);
                    
                    if (is_older) begin
                        // 1. 如果老 Store 地址还没算出来 -> 不敢读 -> 冲突
                        if (!SQ[i].addr_ready) begin
                            conflict = 1'b1;
                        end 
                        // 2. 如果地址算出来了且相等 -> RAW 冒险 -> 冲突 (因为不做转发)
                        else if (SQ[i].addr[31:2] == agu_addr[31:2]) begin
                            conflict = 1'b1;
                        end
                    end
                end
            end
        end
    end

    // --- Retry Logic / Stall Control ---
    // 如果发生冲突，我们要“锁住”这条 Load 指令，在 LSU 内部重试，
    // 同时拉高 lsu_busy 让 RS 别发新指令来捣乱。
    
    // 内部状态机
    typedef enum logic {IDLE, RETRY} state_t;
    state_t state, next_state;
    
    // 锁存冲突的 Load 信息
    dispatch_to_rs_t latched_instr;
    logic [31:0]     latched_addr;
    
    // 决定当前真正处理的是谁：新来的 valid_in 还是 latched 的
    logic            processing_valid;
    dispatch_to_rs_t processing_instr;
    logic [31:0]     processing_addr;
    logic            processing_conflict;

    // 组合逻辑：选择处理对象并检测冲突
    always_comb begin
        // 默认用新来的
        processing_valid = valid_in;
        processing_instr = instr_in;
        processing_addr  = agu_addr;
        
        // 如果处于 RETRY 状态，优先处理 latched
        if (state == RETRY) begin
            processing_valid = 1'b1;
            processing_instr = latched_instr;
            processing_addr  = latched_addr;
        end
        
        // 再次进行冲突检测 (复用上面的逻辑，只需把输入换成 processing_*)
        processing_conflict = 0;
        if (processing_valid && processing_instr.MemRead) begin
            for (int i = 0; i < SQ_SIZE; i++) begin
                if (SQ[i].valid) begin
                    logic is_older;
                    if (sq_head <= processing_instr.sq_idx)
                        is_older = (i >= sq_head && i < processing_instr.sq_idx);
                    else
                        is_older = (i >= sq_head || i < processing_instr.sq_idx);
                    
                    if (is_older) begin
                        if (!SQ[i].addr_ready) processing_conflict = 1'b1;
                        else if (SQ[i].addr[31:2] == processing_addr[31:2]) processing_conflict = 1'b1;
                    end
                end
            end
        end
    end

    // 状态机更新
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (valid_in && instr_in.MemRead && conflict) begin
                        state <= RETRY;
                        latched_instr <= instr_in;
                        latched_addr  <= agu_addr;
                    end
                end
                RETRY: begin
                    if (!processing_conflict) begin
                        state <= IDLE; // 冲突解决，去读内存
                    end
                    // 否则保持 RETRY
                end
            endcase
        end
    end

    assign lsu_busy = (state == RETRY) || (valid_in && instr_in.MemRead && conflict);

    // --- Pipeline Registers (Stage 1 -> 2) ---
    // 保存那些 "成功发射且无冲突" 的指令到下一级
    logic            s1_valid;
    dispatch_to_rs_t s1_instr;
    logic [1:0]      s1_addr_low;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            s1_valid <= 1'b0;
            s1_instr <= '0;
            s1_addr_low <= '0;
            
            // SQ Reset
            sq_head <= '0;
            for(int k=0; k<SQ_SIZE; k++) SQ[k].valid <= 0;
        end else begin
            // 1. SQ Allocation (Dispatch)
            if (alloc_valid) begin
                SQ[alloc_sq_idx].valid <= 1'b1;
                SQ[alloc_sq_idx].addr_ready <= 1'b0;
                `ifndef SYNTHESIS
                $display("[LSQ_ALLOC] t=%0t sq_idx=%0d", $time, alloc_sq_idx);
                `endif
            end

            // 2. Store Update (Execute)
            if (valid_in && instr_in.MemWrite) begin
                SQ[instr_in.sq_idx].addr       <= agu_addr;
                SQ[instr_in.sq_idx].data       <= val2; 
                SQ[instr_in.sq_idx].addr_ready <= 1'b1;
                SQ[instr_in.sq_idx].funct3     <= instr_in.funct3;
                
                // Store 执行完就可以 Complete
                s1_valid <= 1'b1;
                s1_instr <= instr_in;
                
                `ifndef SYNTHESIS
                $display("[LSQ_STORE_UPDATE] t=%0t sq_idx=%0d addr=%h data=%h", $time, instr_in.sq_idx, agu_addr, val2);
                `endif
            end
            
            // 3. Load Handling
            else if (processing_valid && processing_instr.MemRead) begin
                if (processing_conflict) begin
                    // 冲突：不传给下一级，在内部空转
                    s1_valid <= 1'b0;
                    `ifndef SYNTHESIS
                    $display("[LSQ_CONFLICT] t=%0t load_pc=%h stalled by older store", $time, processing_instr.pc);
                    `endif
                end else begin
                    // 无冲突：传给下一级（Stage 2 Writeback）
                    s1_valid <= 1'b1;
                    s1_instr <= processing_instr;
                    s1_addr_low <= processing_addr[1:0];
                    `ifndef SYNTHESIS
                    $display("[LSQ_LOAD_GO] t=%0t load_pc=%h addr=%h", $time, processing_instr.pc, processing_addr);
                    `endif
                end
            end 
            else begin
                s1_valid <= 1'b0;
            end

            // 4. Commit (Store Retire)
            if (commit_valid && commit_mem_write) begin
                SQ[sq_head].valid <= 1'b0;
                sq_head <= sq_head + 1;
                `ifndef SYNTHESIS
                $display("[LSQ_COMMIT] t=%0t sq_head=%0d writing mem", $time, sq_head);
                `endif
            end
        end
    end

    // --- D-Mem Interface ---
    // 只有在 Commit 时才写，只有在 Load 无冲突时才读
    assign mem_we = (commit_valid && commit_mem_write);
    
    // 写数据/地址来自 SQ Head (Commit)，读地址来自 Processing Logic (Execute)
    always_comb begin
        if (mem_we) begin
            mem_addr  = SQ[sq_head].addr;
            // Store Data Formatting
            case (SQ[sq_head].funct3[1:0]) // funct3
                2'b00: mem_wdata = SQ[sq_head].data;       // SB (简化)
                2'b01: mem_wdata = SQ[sq_head].data << 8;  // SH (简化)
                default: mem_wdata = SQ[sq_head].data;     // SW
            endcase
            // 注意：这里需要更完善的 Store Data 处理，类似你之前的 switch case
            // 但为了简洁先这样，之前的 dmem.sv 似乎只处理字写入
        end else begin
            mem_addr  = processing_addr;
            mem_wdata = '0;
        end
    end

    // Load Enable: 只有在无冲突且有效时读
    assign mem_en = mem_we || (processing_valid && processing_instr.MemRead && !processing_conflict);

    // --- Writeback Stage (Stage 2) ---
    // 处理 Load 数据格式化 (LB, LH, LW...)
    assign valid_out = s1_valid;

    // --- Output Logic ---
    always_comb begin
        // The warning below might trigger for rob=0, which is normal. 
        // You can ignore it if your system uses rob=0 as a valid tag.
        // if (instr_s1.rob_tag == 0 && instr_s1.opcode != 0) 
        //    $display("!!! WARNING: LSU processing instr with rob_tag=0 !!!");

        wb_packet.prd_addr = instr_s1.prd_addr;
        wb_packet.rob_tag  = instr_s1.rob_tag;
        wb_packet.data     = '0;

        // Load Logic
        if (instr_s1.opcode == 7'h03) begin
            unique case (instr_s1.funct3)
                // --- LB ---
                3'b000: begin
                    case (addr_low_s1)
                        2'b00: wb_packet.data = {{24{mem_rdata[7]}},  mem_rdata[7:0]};
                        2'b01: wb_packet.data = {{24{mem_rdata[15]}}, mem_rdata[15:8]};
                        2'b10: wb_packet.data = {{24{mem_rdata[23]}}, mem_rdata[23:16]};
                        2'b11: wb_packet.data = {{24{mem_rdata[31]}}, mem_rdata[31:24]};
                    endcase
                end
                // --- LH ---
                3'b001: begin
                    case (addr_low_s1[1])
                        1'b0: wb_packet.data = {{16{mem_rdata[15]}}, mem_rdata[15:0]};
                        1'b1: wb_packet.data = {{16{mem_rdata[31]}}, mem_rdata[31:16]};
                    endcase
                end
                // --- LW ---
                3'b010: begin
                    wb_packet.data = mem_rdata;
                end
                // --- LBU ---
                3'b100: begin
                    case (addr_low_s1)
                        2'b00: wb_packet.data = {24'b0, mem_rdata[7:0]};
                        2'b01: wb_packet.data = {24'b0, mem_rdata[15:8]};
                        2'b10: wb_packet.data = {24'b0, mem_rdata[23:16]};
                        2'b11: wb_packet.data = {24'b0, mem_rdata[31:24]};
                    endcase
                end
                // --- LHU ---
                3'b101: begin
                    case (addr_low_s1[1])
                        1'b0: wb_packet.data = {16'b0, mem_rdata[15:0]};
                        1'b1: wb_packet.data = {16'b0, mem_rdata[31:16]};
                    endcase
                end
                default: wb_packet.data = mem_rdata;
            endcase
        end 
        else begin
            wb_packet.data = '0;
        end
    end
    
    // Debug Print
    always_ff @(posedge clk) begin
        if (valid_in && !rst) begin
             $display("[LSU_DBG] t=%0t valid_in=1 rob=%0d prd=%0d op=%h", 
                      $time, instr_in.rob_tag, instr_in.prd_addr, instr_in.opcode);
        end
    end

endmodule