`include "mycpu_defines.vh"

module csr(
    input wire clk,
    input wire reset,
    input wire csr_re,
    input wire [11:0] csr_raddr,
    input wire [11:0] csr_waddr,
    input wire csr_we,
    input wire [31:0] csr_wmask,
    input wire [31:0] csr_wvalue,
    output wire [31:0] csr_rvalue,

    output wire [31:0] ex_entry,
    output wire [31:0] ertn_entry,
    output wire has_ex,  //无条件例外
    output wire has_int,
    input wire int_flush,  //中断刷新信号
    input wire ertn_flush,
    input wire wb_ex,
    input wire [5:0] wb_ecode,
    input wire [8:0] wb_esubcode,
    input wire [31:0] wb_pc,
    input wire [31:0] wb_vaddr,

    input wire  [7:0] hw_int_in,    //硬中断
    input wire  ipi_int_in,    //IPI中断
    input wire  coreid_in    //核心ID
    );

    reg        csr_ticlr_clr; //定时器清零
    reg [1:0] csr_crmd_plv; //当前特权级
    reg       csr_crmd_ie; //当前中断使能
    wire       csr_crmd_da; //当前地址空间有效
    wire       csr_crmd_pg; //当前页表启用
    wire [1:0] csr_crmd_datf; //当前数据地址空间类型
    wire [1:0] csr_crmd_datm; //当前指令地址空间类型
    reg [1:0] csr_prmd_pplv; //以前特权级
    reg       csr_prmd_pie; //以前中断使能
    reg [12:0] csr_ecfg_lie; //本地中断使能
    reg [12:0] csr_estat_is; //中断状态
    reg [5:0] csr_estat_ecode; //异常码
    reg [8:0] csr_estat_esubcode; //异常子码
    reg  [31:0] timer_cnt;
    reg [31:0] csr_era_pc;
    reg [31:0] csr_badv_vaddr; //坏地址寄存器
    reg [25:0] csr_eentry_va; //异常入口地址
    reg [31:0] csr_save0_data;
    reg [31:0] csr_save1_data;
    reg [31:0] csr_save2_data;
    reg [31:0] csr_save3_data;
    reg [31:0] csr_tid; //定时器编号
    reg        csr_tcfg_en; //定时器使能
    reg        csr_tcfg_period; //定时器周期
    reg [29:0]  csr_tcfg_initval; //定时器初始值(暂定)
    reg [31:0] csr_tval_timeval; //定时器当前值
    wire [31:0] tcfg_next_value;
    wire [31:0] csr_tval;
    reg [31:0] csr_rdata;

// ticlr
    always @(posedge clk) begin
        if (reset)
            csr_ticlr_clr <= 1'b0;
        else if(wb_ex || int_flush)
            csr_ticlr_clr <= 1'b0;
    end


// crmd
    always @(posedge clk) begin
        if (reset)
            csr_crmd_plv <= 2'b0;
        else if (wb_ex || int_flush)
            csr_crmd_plv <= 2'b0;
        else if (ertn_flush)
            csr_crmd_plv <= csr_prmd_pplv;
        else if (csr_we && csr_waddr==`CSR_CRMD)
            csr_crmd_plv <= csr_wmask[`CSR_CRMD_PLV]&csr_wvalue[`CSR_CRMD_PLV]
                        | ~csr_wmask[`CSR_CRMD_PLV]&csr_crmd_plv;
    end

    always @(posedge clk) begin
        if (reset)
            csr_crmd_ie <= 1'b0;
        else if (wb_ex || int_flush)
            csr_crmd_ie <= 1'b0;
        else if (ertn_flush)
            csr_crmd_ie <= csr_prmd_pie;
        else if (csr_we && csr_waddr==`CSR_CRMD)
            csr_crmd_ie <= csr_wmask[`CSR_CRMD_PIE]&csr_wvalue[`CSR_CRMD_PIE]
                        | ~csr_wmask[`CSR_CRMD_PIE]&csr_crmd_ie;
    end

    assign csr_crmd_da   = 1'b1;
    assign csr_crmd_pg   = 1'b0;
    assign csr_crmd_datf = 2'b00;
    assign csr_crmd_datm = 2'b00;


// prmd
    always @(posedge clk) begin
        if (wb_ex || int_flush) begin
            csr_prmd_pplv <= csr_crmd_plv;
            csr_prmd_pie  <= csr_crmd_ie;
        end
        else if (csr_we && csr_waddr==`CSR_PRMD) begin
            csr_prmd_pplv <= csr_wmask[`CSR_PRMD_PPLV]&csr_wvalue[`CSR_PRMD_PPLV]
                        | ~csr_wmask[`CSR_PRMD_PPLV]&csr_prmd_pplv;
            csr_prmd_pie  <= csr_wmask[`CSR_PRMD_PIE]&csr_wvalue[`CSR_PRMD_PIE]
                        | ~csr_wmask[`CSR_PRMD_PIE]&csr_prmd_pie;
        end
    end


// ecfg
    always @(posedge clk) begin
        if (reset)
            csr_ecfg_lie <= 13'b0;
        else if (csr_we && csr_waddr==`CSR_ECFG)
            csr_ecfg_lie <= csr_wmask[`CSR_ECFG_LIE]&13'h1bff&csr_wvalue[`CSR_ECFG_LIE]
                        | ~csr_wmask[`CSR_ECFG_LIE]&13'h1bff&csr_ecfg_lie;
    end

// estat
    always @(posedge clk) begin
        if (reset)
            csr_estat_is[1:0] <= 2'b0;
        else if (csr_we && csr_waddr==`CSR_ESTAT)
            csr_estat_is[1:0] <=  csr_wmask[`CSR_ESTAT_IS10]&csr_wvalue[`CSR_ESTAT_IS10]
                            | ~csr_wmask[`CSR_ESTAT_IS10]&csr_estat_is[1:0];
        csr_estat_is[9:2] <= hw_int_in[7:0];
        csr_estat_is[10] <= 1'b0;
        if (timer_cnt[31:0]==32'b0)
            csr_estat_is[11] <= 1'b1;
        else if (csr_we && csr_waddr==`CSR_TICLR && csr_wmask[`CSR_TICLR_CLR]
                && csr_wvalue[`CSR_TICLR_CLR])
            csr_estat_is[11] <= 1'b0;
        csr_estat_is[12] <= ipi_int_in;
    end

    always @(posedge clk) begin
        if (wb_ex) begin
            csr_estat_ecode    <= wb_ecode;
            csr_estat_esubcode <= wb_esubcode;
        end else if (int_flush) begin
                csr_estat_ecode    <= `ECODE_INT;
                csr_estat_esubcode <= `ESUBCODE_INT;
        end
    end


// era
    always @(posedge clk) begin
        if (wb_ex || int_flush)
            csr_era_pc <= wb_pc;
        else if (csr_we && csr_waddr==`CSR_ERA)
            csr_era_pc <= csr_wmask[`CSR_ERA_PC]&csr_wvalue[`CSR_ERA_PC]
                        | ~csr_wmask[`CSR_ERA_PC]&csr_era_pc;
    end

// badv
    assign wb_ex_addr_err = wb_ecode==`ECODE_ADE || wb_ecode==`ECODE_ALE;

    always @(posedge clk) begin
        if ((wb_ex || int_flush) && wb_ex_addr_err)
            csr_badv_vaddr <= (wb_ecode==`ECODE_ADE &&
                            wb_esubcode==`ESUBCODE_ADEF) ? wb_pc : wb_vaddr;
    end
// eentry
    always @(posedge clk) begin
        if (csr_we && csr_waddr==`CSR_EENTRY)
            csr_eentry_va <= csr_wmask[`CSR_EENTRY_VA]&csr_wvalue[`CSR_EENTRY_VA]
                        | ~csr_wmask[`CSR_EENTRY_VA]&csr_eentry_va;
    end
// save0~3
    always @(posedge clk) begin
        if (csr_we && csr_waddr==`CSR_SAVE0)
            csr_save0_data <= csr_wmask[`CSR_SAVE_DATA]&csr_wvalue[`CSR_SAVE_DATA]
                        | ~csr_wmask[`CSR_SAVE_DATA]&csr_save0_data;
        if (csr_we && csr_waddr==`CSR_SAVE1)
            csr_save1_data <= csr_wmask[`CSR_SAVE_DATA]&csr_wvalue[`CSR_SAVE_DATA]
                        | ~csr_wmask[`CSR_SAVE_DATA]&csr_save1_data;
        if (csr_we && csr_waddr==`CSR_SAVE2)
            csr_save2_data <= csr_wmask[`CSR_SAVE_DATA]&csr_wvalue[`CSR_SAVE_DATA]
                        | ~csr_wmask[`CSR_SAVE_DATA]&csr_save2_data;
        if (csr_we && csr_waddr==`CSR_SAVE3)
            csr_save3_data <= csr_wmask[`CSR_SAVE_DATA]&csr_wvalue[`CSR_SAVE_DATA]
                        | ~csr_wmask[`CSR_SAVE_DATA]&csr_save3_data;
    end

// tid
    always @(posedge clk) begin
        if (reset)
            csr_tid <= coreid_in;
        else if (csr_we && csr_waddr==`CSR_TID)
            csr_tid  <= csr_wmask[`CSR_TID_TID]&csr_wvalue[`CSR_TID_TID]
                        | ~csr_wmask[`CSR_TID_TID]&csr_tid;
    end
// tcfg
    always @(posedge clk) begin
        if (reset)
            csr_tcfg_en <= 1'b0;
        else if (csr_we && csr_waddr==`CSR_TCFG)
            csr_tcfg_en <= csr_wmask[`CSR_TCFG_EN]&csr_wvalue[`CSR_TCFG_EN]
                        | ~csr_wmask[`CSR_TCFG_EN]&csr_tcfg_en;
        if (csr_we && csr_waddr==`CSR_TCFG) begin
            csr_tcfg_period <= csr_wmask[`CSR_TCFG_PERIOD]&csr_wvalue[`CSR_TCFG_PERIOD]
                                | ~csr_wmask[`CSR_TCFG_PERIOD]&csr_tcfg_period;
            csr_tcfg_initval <= csr_wmask[`CSR_TCFG_INITV]&csr_wvalue[`CSR_TCFG_INITV]
                            | ~csr_wmask[`CSR_TCFG_INITV]&csr_tcfg_initval;
        end
    end
// tval
    assign tcfg_next_value =  csr_wmask[31:0]&csr_wvalue[31:0]
                        | ~csr_wmask[31:0]&{csr_tcfg_initval,
                                            csr_tcfg_period, csr_tcfg_en};

    always @(posedge clk) begin
        if (reset)
            timer_cnt <= 32'hffffffff;
        else if (csr_we && csr_waddr==`CSR_TCFG && tcfg_next_value[`CSR_TCFG_EN])
            timer_cnt <= {tcfg_next_value[`CSR_TCFG_INITV], 2'b0};
        else if (csr_tcfg_en && timer_cnt!=32'hffffffff) begin
            if (timer_cnt[31:0]==32'b0 && csr_tcfg_period)
                timer_cnt <= {csr_tcfg_initval, 2'b0};
            else
                timer_cnt <= timer_cnt - 1'b1;
        end
    end

    assign csr_tval = timer_cnt[31:0];

    always @(*) begin
        csr_rdata = 32'b0;
        case (csr_raddr)
            `CSR_CRMD:   csr_rdata = {23'b0, csr_crmd_datm, csr_crmd_datf,
                                      csr_crmd_pg, csr_crmd_da, csr_crmd_ie,
                                      csr_crmd_plv};
            `CSR_PRMD:   csr_rdata = {29'b0, csr_prmd_pie, csr_prmd_pplv};
            `CSR_ECFG:   csr_rdata = {19'b0, csr_ecfg_lie};
            `CSR_ESTAT:  csr_rdata = {1'b0, csr_estat_esubcode, csr_estat_ecode,
                                      3'b0, csr_estat_is};
            `CSR_ERA:    csr_rdata = csr_era_pc;
            `CSR_BADV:   csr_rdata = csr_badv_vaddr;
            `CSR_EENTRY: csr_rdata = {csr_eentry_va, 6'b0};
            `CSR_SAVE0:  csr_rdata = csr_save0_data;
            `CSR_SAVE1:  csr_rdata = csr_save1_data;
            `CSR_SAVE2:  csr_rdata = csr_save2_data;
            `CSR_SAVE3:  csr_rdata = csr_save3_data;
            `CSR_TID:    csr_rdata = csr_tid;
            `CSR_TCFG:   csr_rdata = {csr_tcfg_initval, csr_tcfg_period,
                                      csr_tcfg_en};
            `CSR_TVAL:   csr_rdata = csr_tval;
            `CSR_TICLR:  csr_rdata = 32'b0;
            default:     csr_rdata = 32'b0;
        endcase
    end
    assign ertn_entry = csr_era_pc;
    assign ex_entry = {csr_eentry_va, 6'b0};
    assign csr_rvalue = csr_re ? csr_rdata : 32'b0;
    assign has_int = ((csr_estat_is[12:0] & csr_ecfg_lie[12:0]) != 13'b0) && (csr_crmd_ie == 1'b1);
    assign has_ex = (wb_ecode == `ECODE_SYS) || (wb_ecode == `ECODE_BRK) || (wb_ecode == `ECODE_INE) || (wb_ecode == `ECODE_ADE)
                    || (wb_ecode == `ECODE_IPE) || (wb_ecode == `ECODE_ALE);
endmodule
