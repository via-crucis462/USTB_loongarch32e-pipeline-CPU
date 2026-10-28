`include "mycpu_defines.vh"

module IF_stage(
    input wire clk, //时钟
    input wire reset,   //复位
    input wire ds_allowin,  //告知是否下个阶段可以接受数据输入
    input wire [`BR_BUS_WD -1 :0] br_bus, //跳转信号
    output wire fs_to_ds_valid,     //告知下个阶段数据是否有效
    output wire [`FS_TO_DS_BUS_WD-1 :0] fs_to_ds_bus,   //传递给下一级的缓冲区
    // inst sram interface
    output wire        inst_sram_req,
    output wire        inst_sram_wr,
    output wire [1:0]  inst_sram_size,
    output wire [3:0]  inst_sram_wstrb,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire        inst_sram_addr_ok,
    input  wire        inst_sram_data_ok,
    input  wire [31:0] inst_sram_rdata,

    input wire [31:0] ex_pc,
    input wire has_ex,  //无条件例外
    input wire int_flush,
    input wire ertn_flush,
    input wire [31:0] ertn_entry
);

    //异常输出处理
    wire if_ex; //if阶段的异常信号
    wire [5:0] if_ecode; //if阶段的异常码
    wire [8:0] if_esubcode; //if阶段的异常子码

    //if级握手信号
    reg         fs_valid;
    wire        fs_ready_go;
    wire        fs_allowin;
    wire        to_fs_valid;

    wire pre_if_ready_go;


    wire [31:0] seq_pc; //顺序的地址
    wire [31:0] next_pc; //下一个执行的地址，可能会跳转

    wire br_stall; //跳转阻塞信号，id级存在即将跳转正在计算的指令
    wire br_taken; //跳转信号
    wire [31:0] br_target;//跳转地址

    reg br_pending; // 待处理跳转
    reg [31:0] br_target_pending; // 待处理跳转地址
    wire br_active;

    wire [31:0] fs_inst; //fs阶段的inst和pc,往后传递
    reg [31:0] fs_pc;
    // 用于完成取指时 ds 不允许进入的情况，暂存指令
    reg [31:0] fs_inst_cache;
    reg fs_inst_cache_valid; // 缓存中的数据是否应该被使用

    wire any_flush = has_ex || int_flush || ertn_flush;

    reg flush_pending; // 重定向目标尚未完成地址握手
    reg [31:0] flush_pending_pc; // 暂存异常跳转目标
    wire flush_active;
    reg drop_next_inst; // 已取消的取指请求尚未返回，应当在返回时丢弃

    wire is_ADEF;

    assign if_ex = is_ADEF; //暂时没有异常处理
    assign if_ecode = is_ADEF ? `ECODE_ADE : 6'b0;
    assign if_esubcode = is_ADEF ? `ESUBCODE_ADEF : 9'b0;
    assign {br_stall,br_taken,br_target} = br_bus; //跳转信号传递

    //if向id传递的bus
    // fs_to_ds_bus 总位宽 = 1+6+9+32+32 = 80 bit
    assign fs_to_ds_bus = {if_ex,        // [79]
                           if_ecode,     // [78:73]
                           if_esubcode,  // [72:64]
                           fs_inst,      // [63:32]
                           fs_pc};       // [31:0]

    // pre-if stage
    // 当请求完成发送完成时，pre-if的pc(next pc)已经可以向下传递，
    // 但 fs 会在确保数据已经读出时才允许同步接收，期间会阻塞pre-if更新与发送请求。
    // 如果 sram 不出错，一次请求发送总是对应一次数据读取完成。
    // 有个缺点，好像要好几拍才取指一次
    assign pre_if_ready_go = inst_sram_req && inst_sram_addr_ok;
    assign to_fs_valid = ~reset && pre_if_ready_go;

    assign seq_pc = fs_pc + 3'h4; //顺序
    assign next_pc = (has_ex || int_flush) ? ex_pc :
                    (ertn_flush) ? ertn_entry :
                    (flush_pending) ? flush_pending_pc :
                    (br_taken)  ? br_target :
                    (br_pending) ? br_target_pending :
                    seq_pc;

    // 这里稍微修了一下，is_ADEF 通过组合逻辑决定fs_inst，而
    // fs_inst 和 fs_pc 应该是同级数据（之前这里是 next_pc)
    assign is_ADEF = fs_pc[1:0] != 2'b0;

    assign flush_active = any_flush || flush_pending;
    // 异常处理
    // 和下面的跳转逻辑几乎完全一致，或许可以合并
    always @(posedge clk) begin
        if (reset) begin
            flush_pending <= 1'b0;
            flush_pending_pc <= 32'b0;
        end else if (any_flush) begin
            // 这里和书中的实现略有不同，改为了异常发生当拍不发送请求，之后达成条件才发送；
            // 但协议与书中一致，都是等已经发送的请求返回后才发起新的请求。

            // 异常发生时无条件置位，下次握手成功后清零
            flush_pending <= 1'b1;
            flush_pending_pc <= (has_ex || int_flush) ? ex_pc : ertn_entry;
        end else if (to_fs_valid && fs_allowin) begin
            // next pc 更新后首次握手成功
            flush_pending <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (reset || inst_sram_data_ok) begin
            drop_next_inst <= 1'b0;
        end else if (any_flush || br_taken) begin
            // 当拍 inst_sram_data_ok 没置位且收到了异常
            //
            // 这里学习了一下gpt的实现，与参考书略有不同，但比较优雅：
            // 如果上次跳转还没处理又出现了中断，如果drop_next_inst还未清除，说明上次异常等待的那个废信号还没返回；
            // 由于实现保证了“上次请求返回结果后，才能发起下次请求”，这里drop_next_inst就可以直接保持原状态，
            // 其他部分保证 flush target 更新（等到可以发起req时，始终发最新的）即可。
            drop_next_inst <= drop_next_inst // 前一次跳转没处理又发生异常
                        || (fs_valid && !fs_inst_cache_valid);// 普通的首次异常
        end
    end
    wire test_drop = fs_valid && !fs_inst_cache_valid;
    // 缓冲指令
    always @(posedge clk)begin
        if(reset || flush_active || br_active || drop_next_inst)begin
            fs_inst_cache <= 32'b0;
            fs_inst_cache_valid <= 1'b0;
        end else if (inst_sram_data_ok && !ds_allowin) begin
            // 当 ds 不允许进入但有新数据读出，帮其暂存
            // 前一个 if 已经排除了异常、跳转和待丢弃的返回。
            fs_inst_cache <= inst_sram_rdata;
            fs_inst_cache_valid <= 1'b1;
        end else if (ds_allowin) begin
            // 数据被取走
            fs_inst_cache_valid <= 1'b0;
        end
    end


    //IF stage
    // 待丢弃的返回只结束旧事务，不能作为本级的有效指令。
    assign fs_ready_go = !drop_next_inst && (inst_sram_data_ok || fs_inst_cache_valid);

    // 允许进入，需要了解下一级是否可以进入目的是可以实现保持停顿
    // 即使异常已清空 fs_valid，也要等待旧事务返回并丢弃后再接收新 PC。
    assign fs_allowin = !drop_next_inst && (!fs_valid || fs_ready_go && ds_allowin);

    assign br_active = br_pending || br_taken;
    always @(posedge clk) begin
        if (reset || any_flush) begin
            br_pending <= 1'b0;
            br_target_pending <= 32'b0;
        end else if (br_taken) begin
            br_pending <= 1'b1;
            br_target_pending <= br_target;
        end else if (to_fs_valid && fs_allowin) begin
            // next pc 更新后首次握手成功
            br_pending <= 1'b0;
        end
    end

    // fs_valid 应该和可用的[正在取指/已取指]pc绑定
    // 异常和跳转都要丢弃最后一条指令，异常跳转当拍 valid 还未来得及置，在这里组合逻辑临时屏蔽
    assign fs_to_ds_valid = fs_valid && fs_ready_go && !any_flush && !br_taken;

    always@(posedge clk)begin
        if(reset || any_flush || br_taken)begin
            // 见手册，if stage异常处理的四种情况都要把fs_valid置0，
            // 所有流水级均应按此规律。
            // 之前的设计不涉及应该是因为固定单周期延迟内存 + pre if总是有效，
            // 异常发生时通过组合逻辑让next pc立即变化提前取指，
            // 异常的第一个时钟升沿那一拍fs直接就能拿到有效的数据（fs_pc和相应的指令数据）；
            // 引入总线后这一点不成立。
            // （个人理解：把与前级的分界缓冲寄存器当作本级“输入”，[x]s_valid表示该“输入”的数据有效）
            //
            // 省流：这里的 valid 表示 fs_pc 存在一条已经握手还未读出指令的 pc
            // 异常或者跳转应该把旧请求直接取消，所以清 valid
            fs_valid <= 1'b0;
        end else if(fs_allowin)begin
            fs_valid <= to_fs_valid;
        end
    end


    always@(posedge clk)begin
        if(reset)begin
            fs_pc <= 32'h1bfffffc;
        end else if(to_fs_valid && fs_allowin)begin
            fs_pc <= next_pc;
        end
    end

    // 当 fs_allowin == 1 时才发出请求
    // 当 ds 因 load-use 问题阻塞时这里也应阻塞
    // 因为引入总线sram后，!fs_valid 也可能为1，fs_allowin因此为1，
    // pre if会继续发出请求，导致读出跳转前的错误pc的指令
    // 异常当拍不发请求，之后达成条件才发出请求
    assign inst_sram_req = !reset && !any_flush && !br_taken && !br_stall && fs_allowin;

    assign inst_sram_addr = next_pc;
    assign inst_sram_wdata = 32'b0;
    assign inst_sram_wstrb = 4'h0;
    assign inst_sram_size = 2'b10;
    assign fs_inst = is_ADEF ? 32'b0
                    : fs_inst_cache_valid ? fs_inst_cache
                    : inst_sram_rdata;

endmodule
