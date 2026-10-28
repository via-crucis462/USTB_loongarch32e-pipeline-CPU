`ifndef MYCPU_DEFINES_VH
`define MYCPU_DEFINES_VH

    //总线位宽：前递 1+32=33
    // 引入 br_stall +1 = 34
    `define BR_BUS_WD       34

    //各级总线位宽：FS->DS 1+6+9+32+32=80
    `define FS_TO_DS_BUS_WD 80
    //DS->ES 原字段323位 + 最高位中断标记
    `define DS_TO_ES_BUS_WD 324
    //ES->MS 原字段234位 + 最高位中断标记
    `define ES_TO_MS_BUS_WD 235
    //MS->WS 原字段198位 + 最高位中断标记
    `define MS_TO_WS_BUS_WD 199
    //WS->RF 1+6+9+1+1+5+32=55
    `define WS_TO_RF_BUS_WD 55
    //WS->CSR 1(csr_ertn)+12+32+1+32 + 32=142
    `define WS_TO_CSR_BUS_WD 142

    //访存字节数
    `define B 2'b01
    `define H 2'b10
    `define W 2'b11

    //异常类型
    `define ECODE_INT 6'h00   // 中断
    `define ECODE_PIL 6'h01   // 读操作页无效
    `define ECODE_PIS 6'h02   // 写操作页无效
    `define ECODE_PIF 6'h03   // 取指页无效
    `define ECODE_PME 6'h04   // 页修改异常


    `define ECODE_PPI 6'h07   // 页特权等级不合规
    `define ECODE_ADE 6'h08   // 地址错误（子码区分取指与访存）
    `define ECODE_ALE 6'h09   // 访存地址错误
    `define ECODE_BCE 6'h0A   // 边界检查异常
    `define ECODE_SYS 6'h0B   // 系统调用异常
    `define ECODE_BRK 6'h0C   // 断点异常
    `define ECODE_INE 6'h0D   // 指令不存在
    `define ECODE_IPE 6'h0E   // 指令特权等级不合规
    `define ECODE_FPE 6'h0F   // 浮点运算异常
    `define ECODE_TLBR 6'h3F  // TLB 重填异常

    `define ESUBCODE_ALE 9'h000
    `define ESUBCODE_INT 9'h000
    `define ESUBCODE_INE 9'h000
    `define ESUBCODE_IPE 9'h000
    `define ESUBCODE_BRK 9'h000
    `define ESUBCODE_SYS 9'h000
    `define ESUBCODE_ADEF 9'h000
    `define ESUBCODE_ADEM 9'h001

    //CSR号及字段位置
    `define CSR_CRMD 12'h0
    `define CSR_CRMD_PLV 1:0
    `define CSR_CRMD_PIE 2

    `define CSR_PRMD 12'h1
    `define CSR_PRMD_PPLV 1:0
    `define CSR_PRMD_PIE 2

    `define CSR_ECFG 12'h4
    `define CSR_ECFG_LIE 12:0

    `define CSR_ESTAT 12'h5
    `define CSR_ESTAT_IS10 1:0
    `define CSR_ESTAT_IS98 9:2
    `define CSR_ESTAT_ECODE 21:16
    `define CSR_ESTAT_ESUBCODE 30:22

    `define CSR_ERA 12'h6
    `define CSR_ERA_PC 31:0

    `define CSR_BADV 12'h7
    `define CSR_BADV_VADDR 31:0

    `define CSR_EENTRY 12'hc
    `define CSR_EENTRY_VA 31:6

    `define CSR_SAVE0 12'h10
    `define CSR_SAVE1 12'h11
    `define CSR_SAVE2 12'h12
    `define CSR_SAVE3 12'h13
    `define CSR_SAVE_DATA 31:0

    `define CSR_TID 12'h40
    `define CSR_TID_TID 31:0

    `define CSR_TCFG 12'h41
    `define CSR_TCFG_EN 0
    `define CSR_TCFG_PERIOD 1
    `define CSR_TCFG_INITV 31:2

    `define CSR_TVAL 12'h42
    `define CSR_TVAL_TIMEVAL 31:0

    `define CSR_TICLR 12'h44
    `define CSR_TICLR_CLR 0
`endif
