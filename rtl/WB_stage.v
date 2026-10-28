`include "mycpu_defines.vh"

module WB_stage(
    input  wire        clk,
    input  wire        reset,
    //allowin
    output wire        ws_allowin,  //该阶段是否可以接收数据(最后一级, 恒为1)
    //from ms stage
    input  wire        ms_to_ws_valid,
    input  wire [`MS_TO_WS_BUS_WD -1 :0] ms_to_ws_bus,  //上一级缓冲区
    //to rf :write back
    output wire [`WS_TO_RF_BUS_WD -1 :0] ws_to_rf_bus,  //写回缓冲区
    output wire [`WS_TO_CSR_BUS_WD -1 :0] ws_to_csr_bus,  //写回CSR缓冲区
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata,
    output wire        ws_to_rf_valid,
    output wire        ws_int, // 本级寄存的中断标记，仅在 ws_to_rf_valid 时有效

    input wire has_ex,  //无条件例外
    input wire int_flush,
    input wire ertn_flush
);

    //异常处理
    wire ws_ex;
    wire [5:0] ws_excode;
    wire [8:0] ws_esubcode;
    wire [11:0] csr_write_num;
    wire [31:0] csr_wmask;
    wire csr_ertn;
    wire csr_we;
    wire [31:0] csr_wdata;
    reg ws_valid;
    reg [`MS_TO_WS_BUS_WD -1 :0] ms_to_ws_bus_r;
    wire ws_ready_go;
    wire [31:0] wb_pc;
    wire [31:0] wb_vaddr;

    assign wb_pc = ms_to_ws_bus_r[31:0];
    assign ws_int = ms_to_ws_bus_r[198];
    assign wb_vaddr = ms_to_ws_bus_r[197:166];
    assign ws_ready_go     = 1'b1;
    //最后一级, 没有下游 allowin
    assign ws_allowin      = !ws_valid || ws_ready_go;
    // ws_to_rf_bus 总位宽 = 1+6+9+1+1+5+32 = 55 bit
    assign ws_to_rf_bus = {
                        ws_ex,          //[54]
                        ws_excode,      //[53:48]
                        ws_esubcode,    //[47:39]
                        ws_valid && ms_to_ws_bus_r[71],  //[38]    load标志
                        !ws_ex && !ws_int && ws_valid && ms_to_ws_bus_r[70],  //[37]    写寄存器使能
                        ms_to_ws_bus_r[69:65],           //[36:32] 写寄存器地址
                        ms_to_ws_bus_r[63:32]//[31: 0] 写回数据
                        };
    // ws_to_csr_bus 总位宽 = 1(csr_ertn)+12+32+1+32 + 32 = 110 bit
    assign ws_to_csr_bus = {
                            wb_vaddr,       //[141:110] 异常对应的访存地址
                            wb_pc,//[109:78] 写回的PC，当异常发生时用于记录异常发生的地址，因为debug_pc会失效，所以要单独记录
                            ws_valid && csr_ertn, //[77]     ertn指令标志
                            csr_write_num,  //[76:65]
                            csr_wmask,      //[64:33]
                            csr_we,         //[32]
                            csr_wdata       //[31:0]
                            };

    // 这里约定中断比异常优先级更高
    assign ws_ex = ws_valid && !ws_int && ms_to_ws_bus_r[87];
    assign ws_excode = ws_ex ? ms_to_ws_bus_r[86:81] : 6'b0;
    assign ws_esubcode = ws_ex ? ms_to_ws_bus_r[80:72] : 9'b0;

    assign csr_we = ws_valid && ms_to_ws_bus_r[120];
    assign csr_ertn = ms_to_ws_bus_r[165];
    assign csr_wdata = ms_to_ws_bus_r[119:88];
    assign csr_wmask = ms_to_ws_bus_r[152:121];
    assign csr_write_num = ms_to_ws_bus_r[164:153];
    assign ws_to_rf_valid = ws_valid;
    // debug info generate
    assign debug_wb_pc       = ws_valid ? ms_to_ws_bus_r[31:0] : 32'b0;
    assign debug_wb_rf_we    = {4{!ws_ex && !ws_int && ws_valid && ms_to_ws_bus_r[70]}};
    assign debug_wb_rf_wnum  = ws_valid ? ms_to_ws_bus_r[69:65] : 5'b0;
    assign debug_wb_rf_wdata = ws_valid ? ws_to_rf_bus[31:0] : 32'b0;
    always @(posedge clk) begin
        if (reset || has_ex || ertn_flush || int_flush) begin
            ws_valid <= 1'b0;
            ms_to_ws_bus_r <= 0;
        end else begin
            if (ws_allowin)
                ws_valid <= ms_to_ws_valid;
            if (ms_to_ws_valid && ws_allowin)
                ms_to_ws_bus_r <= ms_to_ws_bus;
        end
    end
endmodule
