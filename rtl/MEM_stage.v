`include "mycpu_defines.vh"

module MEM_stage(
    input  wire        clk,
    input  wire        reset,
    //allowin
    input  wire        ws_allowin,  //握手信号(来自 ws 级)
    output wire        ms_allowin,  //该阶段是否可以接收数据
    //from es stage
    input  wire        es_to_ms_valid,
    input  wire [`ES_TO_MS_BUS_WD -1 :0] es_to_ms_bus,  //上一级缓冲区
    //to rf :write back
    output wire        ms_to_ws_valid,  //告知下一级数据是否有效
    output wire [`MS_TO_WS_BUS_WD -1 :0] ms_to_ws_bus,  //写回缓冲区
    //内存访问端口
    input  wire [31:0] data_sram_rdata,  //访存数据
    input  wire        data_sram_data_ok,

    input  wire has_ex,
    input  wire int_flush,
    input  wire ertn_flush,

    output wire mem_ex, //用于指示MEM阶段是否发生异常/或有异常指令，用于处理精确异常中访存的冲突
    output wire ms_int, // 本级寄存的中断标记，仅在 mem_valid 时有效
    output wire ms_mem_wait //本级有指令且正在等待SRAM返回数据(data_ok)
);

    wire [5:0] mem_excode;
    wire [8:0] mem_esubcode;
    wire es_ex;
    wire [5:0] es_excode;
    wire [8:0] es_esubcode;
    wire [31:0] ex_badv;

    wire [11:0] csr_write_num;
    wire [31:0] csr_wmask;
    wire csr_ertn;
    wire csr_we;
    wire [31:0] csr_wdata;
    reg mem_valid;
    reg [`ES_TO_MS_BUS_WD -1 :0] es_to_ms_bus_r;
    wire ms_ready_go;

    wire         mem_we, gr_we,res_from_mem, load_op, load_signed;
    wire [1:0] mem_size ,mem_addr_offset;
    wire [4:0] dest;
    wire [31:0] rkd_value, alu_result, ms_pc, sram_wdata;
    wire [3:0] sram_we;
    wire [7:0] sram_rdata_byte0, sram_rdata_byte1, sram_rdata_byte2, sram_rdata_byte3;  //字节选
    wire [15:0] sram_rdata_half0, sram_rdata_half1;  //半字选
    wire [7:0] sram_rdata_byte;
    wire [15:0] sram_rdata_half;
    wire [31:0] sram_rdata;
    wire debug_mem_size = mem_size == `B;
    wire debug_mem_size_H = mem_size == `H;
    wire [31:0] final_result;

    assign mem_ex = es_ex;
    assign mem_excode = es_excode;
    assign mem_esubcode = es_esubcode;
    // ex级某次访存请求发起时，本级 es_to_ms_bus_r 更新条件也满足，
    // 因此这里用 es_to_ms_bus_r 的访存信息字段，刚好可以锁存至内存数据准备好，
    // bus_r 的内容和内存数据同步被送到下一级。
    assign ms_ready_go     = data_sram_data_ok || !(mem_we || load_op || res_from_mem);
    assign ms_allowin      = !mem_valid || ms_ready_go && ws_allowin || has_ex;
    assign ms_to_ws_valid  = mem_valid && ms_ready_go;
    // 本级持有一条访存指令、但数据还没回来
    // ID 应该视为 load use 而等待
    assign ms_mem_wait     = mem_valid && !ms_ready_go;

    always @(posedge clk) begin
        if (reset || has_ex || ertn_flush || int_flush) begin
            mem_valid <= 1'b0;
            es_to_ms_bus_r <= 0;
        end else begin
            if (ms_allowin)
                mem_valid <= es_to_ms_valid;
            if (es_to_ms_valid && ms_allowin)
                es_to_ms_bus_r <= es_to_ms_bus;
        end
    end
    assign {
            ms_int,
            ex_badv,
            csr_ertn,
            csr_write_num,
            csr_wmask,
            csr_we,
            csr_wdata,
            es_ex,
            es_excode,
            es_esubcode,
            load_signed,  //load指令
            mem_size,
            gr_we,  //写寄存器使能
            dest,  //写寄存器地址

            load_op,  //load指令
            res_from_mem,  //结果是否来自内存

            mem_we,  //写内存使能
            rkd_value,  //写内存数据
            alu_result,  //alu计算结果
            ms_pc  //当前指令的pc,用于debug
            } = es_to_ms_bus_r;

    assign mem_addr_offset = alu_result[1:0];

    //load data from sram
    assign sram_rdata_byte0 = data_sram_rdata[7:0];
    assign sram_rdata_byte1 = data_sram_rdata[15:8];
    assign sram_rdata_byte2 = data_sram_rdata[23:16];
    assign sram_rdata_byte3 = data_sram_rdata[31:24];
    assign sram_rdata_half0 = data_sram_rdata[15:0];
    assign sram_rdata_half1 = data_sram_rdata[31:16];

    assign sram_rdata_byte = mem_addr_offset == 2'b00 ? sram_rdata_byte0 :
                             mem_addr_offset == 2'b01 ? sram_rdata_byte1 :
                             mem_addr_offset == 2'b10 ? sram_rdata_byte2 :
                             sram_rdata_byte3;
    assign sram_rdata_half = mem_addr_offset[1] == 1'b0 ? sram_rdata_half0 :
                             sram_rdata_half1;

    assign sram_rdata = (mem_size == `B) ? (load_signed ? {{24{sram_rdata_byte[7]}}, sram_rdata_byte} : {24'b0, sram_rdata_byte}) :
                        (mem_size == `H) ? (load_signed ? {{16{sram_rdata_half[15]}}, sram_rdata_half} : {16'b0, sram_rdata_half}) :
                        data_sram_rdata;


    // ms_to_ws_bus 总位宽 = 199 bit，最高位为中断标记
    assign final_result = (res_from_mem | load_op) ? sram_rdata : alu_result;
    assign ms_to_ws_bus = {
                            ms_int,        //[198] 中断标记
                            ex_badv,       //[197:166] 访存错误地址
                            csr_ertn,      //[165]      1 bit
                            csr_write_num ,  //[164:153] 12 bit  CSR写地址
                            csr_wmask    ,  //[152:121] 32 bit  CSR写掩码
                            csr_we        ,  //[120]      1 bit
                            csr_wdata     ,  //[119:88]  32 bit
                            mem_ex      ,  //[87]     异常标志
                            mem_excode  ,  //[86:81]  异常码
                            mem_esubcode,  //[80:72]  异常子码
                            load_op      ,  //[71]     load标志
                            gr_we        ,  //[70]     写寄存器使能
                            dest         ,  //[69:65]  写寄存器地址
                            res_from_mem ,
                            final_result ,  //[63:32]  写回数据(load/alu 已 mux)
                            ms_pc           //[31: 0]  当前指令的pc, 用于debug
                          };
endmodule
