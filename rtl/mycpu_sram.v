/* fs: fetch stage
 * ds: decode stage
 * es: execute stage
 * ms: memory stage
 * ws: write back stage
 */
`include "mycpu_defines.vh"

/*
    .inst_sram_req    (cpu_inst_req    ),
    .inst_sram_wr     (cpu_inst_wr     ),
    .inst_sram_size   (cpu_inst_size   ),
    .inst_sram_wstrb  (cpu_inst_wstrb  ),
    .inst_sram_addr   (cpu_inst_addr   ),
    .inst_sram_wdata  (cpu_inst_wdata  ),
    .inst_sram_addr_ok(cpu_inst_addr_ok),
    .inst_sram_data_ok(cpu_inst_data_ok),
    .inst_sram_rdata  (cpu_inst_rdata  ),

    .data_sram_req    (cpu_data_req    ),
    .data_sram_wr     (cpu_data_wr     ),
    .data_sram_size   (cpu_data_size   ),
    .data_sram_wstrb  (cpu_data_wstrb  ),
    .data_sram_addr   (cpu_data_addr   ),
    .data_sram_wdata  (cpu_data_wdata  ),
    .data_sram_addr_ok(cpu_data_addr_ok),
    .data_sram_data_ok(cpu_data_data_ok),
    .data_sram_rdata  (cpu_data_rdata  ),
*/
module mycpu_sram(
    input  wire        clk,
    input  wire        resetn,
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
    // data sram interface
    output wire        data_sram_req,
    output wire        data_sram_wr,
    output wire [1:0]  data_sram_size,
    output wire [3:0]  data_sram_wstrb,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire        data_sram_addr_ok,
    input  wire        data_sram_data_ok,
    input  wire [31:0] data_sram_rdata,
    // trace debug interface
    output wire [31:0] debug_wb_pc,         //pc值
    output wire [ 3:0] debug_wb_rf_we,      //写寄存器信号
    output wire [ 4:0] debug_wb_rf_wnum,    //写入的寄存器号
    output wire [31:0] debug_wb_rf_wdata    //写入数据
);

    wire reset;
    wire        ds_allowin, es_allowin, ms_allowin, ws_allowin;
    wire        fs_to_ds_valid, ds_to_es_valid, es_to_ms_valid, ms_to_ws_valid, ws_valid;

    wire [`BR_BUS_WD       -1:0] br_bus;
    wire [`FS_TO_DS_BUS_WD -1:0] fs_to_ds_bus;
    wire [`DS_TO_ES_BUS_WD -1:0] ds_to_es_bus;
    wire [`ES_TO_MS_BUS_WD -1:0] es_to_ms_bus;
    wire [`MS_TO_WS_BUS_WD -1:0] ms_to_ws_bus;
    wire [`WS_TO_RF_BUS_WD -1:0] ws_to_rf_bus;
    wire [`WS_TO_CSR_BUS_WD -1:0] ws_to_csr_bus;

    wire        ms_mem_wait;   // MEM 正在等待 SRAM 数据
    wire        ds_int, es_int, ms_int, ws_int; // 各级中断标记，使用时结合本级有效信号


    // CSR冲突总线格式：{CSR写使能, CSR写地址}
    wire [12:0] es_csr_conflict_bus;
    wire [12:0] ms_csr_conflict_bus;
    wire [12:0] ws_csr_conflict_bus;

    wire        csr_re;     //读使能
    wire [11:0] csr_raddr;  //ID阶段CSR读地址
    wire [11:0] csr_waddr;  //写回阶段CSR写地址
    wire        csr_we;     //写使能
    wire [31:0] csr_wmask;  //写掩码
    wire [31:0] csr_wvalue; //写入值
    wire [31:0] csr_rvalue; //读出值
    wire        wb_csr_we;

    wire [31:0] ex_entry;   //异常入口地址
    wire        has_ex;    //无条件例外
    wire        has_int;
    wire int_flush;

    // 这里“中断插入到有效指令”采用类似 axi 的握手机制
    wire int_ok; // 中断已被附着到有效指令
    reg int_pending; // 收到中断但尚无指令接受其附着
    reg int_r;

    wire        ertn_flush; //异常返回刷新信号
    wire [31:0] ertn_entry;
    wire        wb_ex;      //写回阶段异常信号
    wire [5:0]  wb_ecode;   //写回阶段异常码
    wire [8:0]  wb_esubcode; //写回阶段异常子码
    wire [31:0] wb_pc;      //写回阶段异常发生的PC
    wire [31:0] wb_vaddr;   //写回阶段异常相关虚地址

    wire [7:0]  hw_int_in;  //硬件中断输入
    wire        ipi_int_in; //IPI中断输入 ioctl
    wire        coreid_in;  //核心ID输入

    assign reset = ~resetn; //复位信号
    assign es_csr_conflict_bus = {es_to_ms_bus[156], es_to_ms_bus[200:189]};
    assign ms_csr_conflict_bus = {ms_to_ws_bus[120], ms_to_ws_bus[164:153]};
    assign ws_csr_conflict_bus = {ws_to_csr_bus[32], ws_to_csr_bus[76:65]};

    // 中断处理逻辑
    always @(posedge clk) begin
        if (reset) begin
            int_pending <= 1'b0;
            int_r <= 1'b0;
        end else if (has_int && !int_r) begin
            // 中断升沿设置 pending 标志
            int_pending <= 1'b1;
        end else if (int_ok) begin
            // 中断已被附着到有效指令，清除 pending 标志
            int_pending <= 1'b0;
        end
        int_r <= has_int;
    end

    assign int_flush = ws_int && ws_valid;

    assign {ertn_flush, csr_waddr, csr_wmask, wb_csr_we,
            csr_wvalue} = ws_to_csr_bus;
    assign csr_we = wb_csr_we;
    assign {wb_ex, wb_ecode, wb_esubcode} = ws_to_rf_bus[54:39];
    assign wb_pc = ws_to_csr_bus[109:78];
    assign wb_vaddr = ws_to_csr_bus[141:110];

    assign hw_int_in = 8'b0;//测例这么要求的，本质寄存器也是只读状态
    //暂定
    assign ipi_int_in = 1'b0;
    assign coreid_in = 1'b0;
    csr _csr(
        .clk(clk),
        .reset(reset),
        .csr_re(csr_re),
        .csr_raddr(csr_raddr),
        .csr_waddr(csr_waddr),
        .csr_we(csr_we),
        .csr_wmask(csr_wmask),
        .csr_wvalue(csr_wvalue),
        .csr_rvalue(csr_rvalue),
        .hw_int_in(hw_int_in),
        .ipi_int_in(ipi_int_in),
        .ex_entry(ex_entry),
        .has_ex(has_ex),    //无条件异常
        .has_int(has_int),
        .int_flush(int_flush),  //中断刷新信号
        .ertn_flush(ertn_flush),
        .ertn_entry(ertn_entry),
        .wb_ex(wb_ex),
        .wb_ecode(wb_ecode),
        .wb_esubcode(wb_esubcode),
        .wb_pc(wb_pc),
        .wb_vaddr(wb_vaddr),
        .coreid_in(coreid_in)
    );
    // 取指
    IF_stage if_stage(
        .clk(clk), //时钟
        .reset(reset),   //复位
        .ds_allowin(ds_allowin),  //告知是否下个阶段可以接受数据输入
        .br_bus(br_bus), //
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_bus(fs_to_ds_bus),
        // inst sram interface
        .inst_sram_req    (inst_sram_req),
        .inst_sram_wr     (inst_sram_wr),
        .inst_sram_size   (inst_sram_size   ),
        .inst_sram_wstrb  (inst_sram_wstrb  ),
        .inst_sram_addr   (inst_sram_addr   ),
        .inst_sram_wdata  (inst_sram_wdata  ),
        .inst_sram_addr_ok(inst_sram_addr_ok),
        .inst_sram_data_ok(inst_sram_data_ok),
        .inst_sram_rdata  (inst_sram_rdata  ),
        .ex_pc(ex_entry),
        .has_ex(has_ex),
        .int_flush(int_flush),
        .ertn_flush(ertn_flush),
        .ertn_entry(ertn_entry)
    );

    // 译码
    ID_stage id_stage(
        .clk(clk),
        .reset(reset),
        //allowin
        .es_allowin(es_allowin),  //握手信号
        .ds_allowin(ds_allowin),  //该阶段是否k可以接收数据
        //from if stage
        .fs_to_ds_valid(fs_to_ds_valid),
        .fs_to_ds_bus(fs_to_ds_bus),
        //to ex stage
        .ds_to_es_valid(ds_to_es_valid),
        .ds_to_es_bus(ds_to_es_bus),
        //to if stage
        .br_bus(br_bus),
        .csr_re(csr_re),
        .csr_raddr(csr_raddr),
        .csr_rdata(csr_rvalue),
        //to rf :write back
        .ws_to_rf_bus(ws_to_rf_bus),
        .es_to_ms_bus(es_to_ms_bus),
        .es_dest({es_to_ms_bus[98],es_to_ms_bus[104:99], es_to_ms_bus[63:32]}),
        .ms_dest({ms_to_ws_bus[71],ms_to_ws_bus[70:65], ms_to_ws_bus[63:32]}),
        .es_to_ms_valid(es_to_ms_valid),
        .ms_to_ws_valid(ms_to_ws_valid),
        .ms_mem_wait(ms_mem_wait),
        .ws_to_rf_valid(ws_valid),
        .int_req(int_pending),
        .int_ok(int_ok),
        .ds_int(ds_int),
        .int_flush(int_flush),
        .ertn_flush(ertn_flush),
        .has_ex(has_ex),
        .es_csr_conflict_bus(es_csr_conflict_bus),
        .ms_csr_conflict_bus(ms_csr_conflict_bus),
        .ws_csr_conflict_bus(ws_csr_conflict_bus)
    );

    EX_stage ex_stage(
        .clk(clk),
        .reset(reset),
        //allowin
        .ms_allowin(ms_allowin),  //握手信号
        .es_allowin(es_allowin),  //该阶段是否k可以接收数据
        //from ds stage
        .ds_to_es_valid(ds_to_es_valid),
        .ds_to_es_bus(ds_to_es_bus),  //上一级缓冲区
        //to ms stage
        .es_to_ms_valid(es_to_ms_valid),  //告知下一级数据是否有效
        .es_to_ms_bus(es_to_ms_bus),       //下一级缓冲区
        .es_int(es_int),
        // data sram request interface
        .data_sram_req(data_sram_req),
        .data_sram_wr(data_sram_wr),
        .data_sram_size(data_sram_size),
        .data_sram_wstrb(data_sram_wstrb),
        .data_sram_addr(data_sram_addr),
        .data_sram_wdata(data_sram_wdata),
        .data_sram_addr_ok(data_sram_addr_ok),
        .int_flush(int_flush),
        .ertn_flush(ertn_flush),
        .ms_ex(ms_ex),
        .ms_int(ms_int),
        .ms_ertn(ms_ertn),
        .ms_to_ws_valid(ms_to_ws_valid),
        .wb_ex(wb_ex),
        .ws_int(ws_int),
        .wb_ertn(wb_ertn),
        .ws_to_rf_valid(ws_valid),
        .has_ex(has_ex)
    );
    assign ms_ertn = ms_to_ws_bus[165];
    assign wb_ertn = ws_to_csr_bus[77];

    MEM_stage mem_stage(
        .clk(clk),
        .reset(reset),
        //allowin
        .ws_allowin(ws_allowin),  //握手信号
        .ms_allowin(ms_allowin),  //该阶段是否可以接收数据
        //from es stage
        .es_to_ms_valid(es_to_ms_valid),
        .es_to_ms_bus(es_to_ms_bus),  //上一级缓冲区
        //to ws stage
        .ms_to_ws_valid(ms_to_ws_valid),  //告知下一级数据是否有效
        .ms_to_ws_bus(ms_to_ws_bus),   //写回缓冲区
        // data sram response interface
        .data_sram_rdata(data_sram_rdata),
        .data_sram_data_ok(data_sram_data_ok),
        .has_ex(has_ex),
        .int_flush(int_flush),
        .ertn_flush(ertn_flush),
        .mem_ex(ms_ex),
        .ms_int(ms_int),
        .ms_mem_wait(ms_mem_wait)
    );

    WB_stage wb_stage(
        .clk(clk),
        .reset(reset),
        //allowin
        .ws_allowin(ws_allowin),  //该阶段是否k可以接收数据
        //from ms stage
        .ms_to_ws_valid(ms_to_ws_valid),
        .ms_to_ws_bus(ms_to_ws_bus),  //上一级缓冲区
        //to rf :write back
        .ws_to_rf_bus(ws_to_rf_bus),   //写回缓冲区
        .ws_to_csr_bus(ws_to_csr_bus),
        // trace debug interface
        .debug_wb_pc(debug_wb_pc),
        .debug_wb_rf_we(debug_wb_rf_we),
        .debug_wb_rf_wnum(debug_wb_rf_wnum),
        .debug_wb_rf_wdata(debug_wb_rf_wdata),
        .ws_to_rf_valid(ws_valid),
        .ws_int(ws_int),
        .has_ex(has_ex),
        .int_flush(int_flush),
        .ertn_flush(ertn_flush)
    );
endmodule
