`include "mycpu_defines.vh"

module ID_stage(
    input  wire        clk,
    input  wire        reset,
    //allowin
    input  wire        es_allowin,  //握手信号
    output wire        ds_allowin,  //该阶段是否k可以接收数据
    //from if stage
    input  wire        fs_to_ds_valid,
    input  wire [`FS_TO_DS_BUS_WD -1 :0] fs_to_ds_bus,  //上一级缓冲区
    //to ex stage
    output wire        ds_to_es_valid,      //告知下一级数据是否有效
    output wire [`DS_TO_ES_BUS_WD -1 :0] ds_to_es_bus,  //下一级缓冲区
    //to if stage
    output wire [`BR_BUS_WD -1 : 0 ] br_bus,    //跳转信号
    //to rf :write back
    input  wire [`WS_TO_RF_BUS_WD -1 :0] ws_to_rf_bus,   //写回缓冲区

    //处理冲突
    input wire  [`ES_TO_MS_BUS_WD -1 :0] es_to_ms_bus,   //来自es阶段的冲突信号 // 似乎没有用到，感觉可删
    input wire  [38 : 0] es_dest,   //load_op , gr_we , dest[5] , data[32]
    input wire  [38 : 0] ms_dest,
    input wire  es_to_ms_valid,
    input wire  ms_to_ws_valid,
    input wire  ms_mem_wait,   //MEM级有访存指令但数据还没回来
    input wire  ws_to_rf_valid,

    output wire csr_re,
    output wire [11:0] csr_raddr,
    input  wire [31:0] csr_rdata,

    input wire int_req, // 待插到指令上的中断
    output wire int_ok, // 中断请求本拍被接受
    output wire ds_int, // 本拍交付到 EX 的中断标记

    input wire has_ex,  //无条件例外
    input wire int_flush,
    input wire ertn_flush,
    //csr读写冲突处理,手册上说只用阻塞处理，所以并不需要传写掩码和写数据，只有12位num和1位使能
    input wire [12:0] es_csr_conflict_bus,
    input wire [12:0] ms_csr_conflict_bus,
    input wire [12:0] ws_csr_conflict_bus
);

// 计数器，用于统计时钟周期数
reg [63:0] Counter;

// 异常处理
wire        if_ex;
wire [5:0] if_ecode;
wire [8:0] if_esubcode;
wire        ds_ex;
wire [5:0] ds_excode;
wire [8:0] ds_esubcode;

wire br_stall; //跳转阻塞信号，id级存在即将跳转正在计算的指令
wire br_taken;
wire [31:0] br_target;

wire [31:0] ds_pc;
wire [31:0] ds_inst;

reg         ds_valid;
wire        ds_ready_go;

wire [14:0] alu_op;

wire load_signed;  //加载的数据是否要进行有符号扩展
wire [1:0] mem_size;  //内存写入/读取的数据大小
wire load_op;  //加载信号
wire src1_is_pc; //来自src为pc地址
wire src2_is_imm; //src2为imm
wire res_from_mem; //结果来自mem
wire dst_is_r1;
wire dst_is_rj;
wire gr_we;
wire mem_we;
wire src_reg_is_rd;
wire [4:0]dest;
wire rj_eq_rd;
wire [31:0]rj_value;
wire [31:0]rkd_value;
wire [31:0]imm;
wire [31:0]br_offs;
wire [31:0]jirl_offs;

wire csr_we;
wire [11:0] csr_write_num;
wire [31:0] csr_wmask;
wire csr_ertn;

//分段
wire [5:0] op_31_26;
wire [1:0] op_25_24;
wire [3:0] op_25_22;
wire [ 1:0] op_21_20;
wire [ 4:0] op_19_15;
wire [14:0] op_14_10;
wire [4:0] op_9_5;
wire [4:0] op_4_0;

wire [ 4:0] rd;
wire [ 4:0] rj;
wire [ 4:0] rk;

wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;

wire [63:0] op_31_26_d;
wire [3:0] op_25_24_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;
wire [31:0] op_14_10_d;
wire [31:0] op_9_5_d;
wire [31:0] op_4_0_d;

wire        inst_add_w;
wire        inst_sub_w;
wire        inst_slt;
wire        inst_sltu;
wire        inst_nor;
wire        inst_and;
wire        inst_or;
wire        inst_xor;
wire        inst_slli_w;
wire        inst_srli_w;
wire        inst_srai_w;
wire        inst_addi_w;
wire        inst_ld_w;
wire        inst_st_w;
wire        inst_jirl;
wire        inst_b;
wire        inst_bl;
wire        inst_beq;
wire        inst_bne;
wire        inst_lu12i_w;
wire        inst_pcaddu12i;
wire        inst_slti;
wire        inst_sltui;
wire        inst_andi;
wire        inst_ori;
wire        inst_xori;
wire        inst_sll_w;
wire        inst_sra_w;
wire        inst_srl_w;
wire        inst_blt;
wire        inst_bge;
wire        inst_bltu;
wire        inst_bgeu;
wire        inst_ld_b;
wire        inst_ld_h;
wire        inst_ld_bu;
wire        inst_ld_hu;
wire        inst_st_b;
wire        inst_st_h;
wire        inst_div_w;
wire        inst_div_wu;
wire        inst_mul_w;
wire        inst_mulh_w;
wire        inst_mulh_wu;
wire        inst_mod_w;
wire        inst_mod_wu;
wire        inst_csrwr;
wire        inst_csrrd;
wire        inst_csrxchg;
wire        inst_syscall;
wire        inst_ertn;
wire        inst_break;
wire        inst_rdcntvl_w;
wire        inst_rdcntvh_w;
wire        inst_rdcntid_w;

wire        unsupport_inst;//但你怎么知道指令是不存在还是你没实现呢（？
wire        is_IPE;//权限错误

wire        need_ui5;
wire        need_si12;
wire        need_si16;
wire        need_si20;
wire        need_si26;
wire        src2_is_4;

wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;

wire [31:0] alu_src1 ;
wire [31:0] alu_src2;
wire [31:0] alu_result;

wire [31:0] mem_result;
wire [31:0] final_result;

wire rf_we ; //写使能
wire [4:0] rf_waddr;
wire [31:0] rf_wdata;

wire es_match_rj = es_to_ms_valid && es_dest[37] && (es_dest[36:32] == rf_raddr1) && (rf_raddr1 != 5'd0);
wire es_match_rkd = es_to_ms_valid && es_dest[37] && (es_dest[36:32] == rf_raddr2) && (rf_raddr2 != 5'd0);
wire ms_match_rj = ms_to_ws_valid && ms_dest[37] && (ms_dest[36:32] == rf_raddr1) && (rf_raddr1 != 5'd0);
wire ms_match_rkd = ms_to_ws_valid && ms_dest[37] && (ms_dest[36:32] == rf_raddr2) && (rf_raddr2 != 5'd0);
wire ws_match_rj = ws_to_rf_valid && ws_to_rf_bus[37] && (ws_to_rf_bus[36:32] == rf_raddr1) && (rf_raddr1 != 5'd0);
wire ws_match_rkd = ws_to_rf_valid && ws_to_rf_bus[37] && (ws_to_rf_bus[36:32] == rf_raddr2) && (rf_raddr2 != 5'd0);

reg [`FS_TO_DS_BUS_WD -1 :0] fs_to_ds_bus_r;

wire es_load_hazard = es_dest[38] && (es_match_rj || es_match_rkd);
wire ms_match_rj_raw = (ms_dest[36:32] == rf_raddr1) && (rf_raddr1 != 5'd0);
wire ms_match_rkd_raw = (ms_dest[36:32] == rf_raddr2) && (rf_raddr2 != 5'd0);
// mem_valid = ms_mem_wait | ms_to_ws_valid：
wire ms_load_hazard = (ms_mem_wait || ms_to_ws_valid) && ms_dest[38] && (ms_match_rj_raw || ms_match_rkd_raw);
wire load_data_hazard = es_load_hazard || ms_load_hazard;
wire es_csr_hazard;
wire ms_csr_hazard;
wire ws_csr_hazard;


always @(posedge clk) begin
    if (reset) begin
        Counter <= 64'b0;
    end else if (Counter != 64'hFFFFFFFFFFFFFFFF)begin
        Counter <= Counter + 1'b1;
    end else begin
        Counter <= 64'h0;
    end
end

//如果上一级是异常指令
assign ds_ex = if_ex | inst_syscall | inst_break | unsupport_inst | is_IPE;
assign ds_excode = if_ex ? if_ecode :
                    inst_syscall ? `ECODE_SYS :
                    inst_break ? `ECODE_BRK :
                    unsupport_inst ? `ECODE_INE :
                    is_IPE ? `ECODE_IPE :
                    6'b0;
assign ds_esubcode = if_ex ? if_esubcode : 
                    inst_syscall ? `ESUBCODE_SYS:
                    inst_break ? `ESUBCODE_BRK:
                    unsupport_inst ? `ESUBCODE_INE:
                    is_IPE ? `ESUBCODE_IPE:
                    9'b0;

assign op_31_26  = ds_inst[31:26];
assign op_25_24  = ds_inst[25:24];
assign op_25_22  = ds_inst[25:22];
assign op_21_20  = ds_inst[21:20];
assign op_19_15  = ds_inst[19:15];
assign op_14_10  = ds_inst[14:10];
assign op_9_5   = ds_inst[9:5];
assign op_4_0   = ds_inst[4:0];

assign rd   = ds_inst[ 4: 0];
assign rj   = ds_inst[ 9: 5];
assign rk   = ds_inst[14:10];

assign i12  = ds_inst[21:10];
assign i20  = ds_inst[24: 5];
assign i16  = ds_inst[25:10];
assign i26  = {ds_inst[ 9: 0], ds_inst[25:10]};

decoder_6_64 u_dec0(.in(op_31_26 ), .out(op_31_26_d ));
decoder_2_4  u_dec4(.in(op_25_24 ), .out(op_25_24_d ));
decoder_4_16 u_dec1(.in(op_25_22 ), .out(op_25_22_d ));
decoder_2_4  u_dec2(.in(op_21_20 ), .out(op_21_20_d ));
decoder_5_32 u_dec3(.in(op_19_15 ), .out(op_19_15_d ));
decoder_5_32 u_dec5(.in(op_14_10 ), .out(op_14_10_d ));
decoder_5_32 u_dec6(.in(op_9_5 ), .out(op_9_5_d ));
decoder_5_32 u_dec7(.in(op_4_0 ), .out(op_4_0_d ));

assign inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_jirl   = op_31_26_d[6'h13];
assign inst_b      = op_31_26_d[6'h14];
assign inst_bl     = op_31_26_d[6'h15];
assign inst_beq    = op_31_26_d[6'h16];
assign inst_bne    = op_31_26_d[6'h17];
assign inst_lu12i_w= op_31_26_d[6'h05] & ~ds_inst[25];
assign inst_pcaddu12i = op_31_26_d[6'h07] & ~ds_inst[25];
assign inst_slti = op_31_26_d[6'h00] & op_25_22_d[4'h8];
assign inst_sltui = op_31_26_d[6'h00] & op_25_22_d[4'h9];
assign inst_andi = op_31_26_d[6'h00] & op_25_22_d[4'hd];
assign inst_ori = op_31_26_d[6'h00] & op_25_22_d[4'he];
assign inst_xori = op_31_26_d[6'h00] & op_25_22_d[4'hf];
assign inst_sll_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'he];
assign inst_sra_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
assign inst_srl_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
assign inst_blt = op_31_26_d[6'h18];
assign inst_bge = op_31_26_d[6'h19];
assign inst_bltu   = op_31_26_d[6'h1a];
assign inst_bgeu   = op_31_26_d[6'h1b];
assign inst_ld_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
assign inst_ld_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
assign inst_ld_bu  = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
assign inst_ld_hu  = op_31_26_d[6'h0a] & op_25_22_d[4'h9];
assign inst_st_b   = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
assign inst_st_h   = op_31_26_d[6'h0a] & op_25_22_d[4'h5];
assign inst_div_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h0];
assign inst_div_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h2];
assign inst_mul_w    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
assign inst_mulh_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
assign inst_mulh_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
assign inst_mod_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h1];
assign inst_mod_wu = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h3];
//特权级
assign inst_csrxchg = op_31_26_d[6'h01] & op_25_24_d[2'h0] & ds_inst[9:5] != 5'h0 & ds_inst[9:5] != 5'h1;
assign inst_csrwr = op_31_26_d[6'h01] & op_25_24_d[2'h0] & ds_inst[9:5] == 5'h1;
assign inst_csrrd = op_31_26_d[6'h01] & op_25_24_d[2'h0] & ds_inst[9:5] == 5'h0;
assign inst_syscall = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h16];
assign inst_ertn = op_31_26_d[6'h01] & op_25_22_d[4'h9] & op_21_20_d[2'h0] & op_19_15_d[5'h10] & op_14_10_d[5'he] & op_9_5_d[5'h0] & op_4_0_d[5'h0];
assign inst_break = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h14];
assign inst_rdcntid_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h0] & op_14_10_d[5'h18] & op_4_0_d[5'h0];
assign inst_rdcntvl_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h0] & op_14_10_d[5'h18] & op_9_5_d[5'h0];
assign inst_rdcntvh_w = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h0] & op_19_15_d[5'h0] & op_14_10_d[5'h19] & op_9_5_d[5'h0];

assign unsupport_inst = ds_valid && !(inst_add_w | inst_addi_w | inst_ld_w | inst_ld_b | inst_st_w | inst_st_b | inst_st_h
                        | inst_jirl | inst_bl | inst_b | inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu
                        | inst_pcaddu12i | inst_ld_h | inst_ld_bu | inst_ld_hu
                        | inst_sub_w | inst_slt | inst_slti | inst_sltu | inst_sltui
                        | inst_and | inst_andi | inst_nor | inst_or | inst_ori | inst_xor | inst_xori
                        | inst_slli_w | inst_sll_w | inst_srli_w | inst_srl_w | inst_srai_w | inst_sra_w
                        | inst_lu12i_w | inst_div_w | inst_div_wu | inst_mul_w | inst_mulh_w | inst_mulh_wu
                        | inst_mod_w | inst_mod_wu
                        | inst_csrxchg | inst_csrwr | inst_csrrd | inst_syscall | inst_ertn | inst_break
                        | inst_rdcntvl_w | inst_rdcntvh_w | inst_rdcntid_w);

assign alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_ld_b | inst_st_w | inst_st_b | inst_st_h
                    | inst_jirl | inst_bl | inst_pcaddu12i | inst_ld_h | inst_ld_bu | inst_ld_hu;
assign alu_op[ 1] = inst_sub_w;
assign alu_op[ 2] = inst_slt | inst_slti;
assign alu_op[ 3] = inst_sltu | inst_sltui;
assign alu_op[ 4] = inst_and | inst_andi;
assign alu_op[ 5] = inst_nor;
assign alu_op[ 6] = inst_or | inst_ori;
assign alu_op[ 7] = inst_xor | inst_xori;
assign alu_op[ 8] = inst_slli_w | inst_sll_w ;
assign alu_op[ 9] = inst_srli_w | inst_srl_w;
assign alu_op[10] = inst_srai_w | inst_sra_w ;
assign alu_op[11] = inst_lu12i_w;
assign alu_op[12] = inst_mul_w;
assign alu_op[13] = inst_mulh_w;
assign alu_op[14] = inst_mulh_wu;

//信号
assign need_ui5  = inst_slli_w | inst_srli_w | inst_srai_w;
assign need_u12  = inst_andi | inst_ori | inst_xori;
assign need_si12 = inst_addi_w | inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu | inst_st_w | inst_st_b | inst_st_h 
                                | inst_slti | inst_sltui ;
assign need_si16 = inst_jirl | inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu;
assign need_si20 = inst_lu12i_w | inst_pcaddu12i;
assign need_si26 = inst_b | inst_bl;
assign src2_is_4 = inst_jirl | inst_bl;

assign imm = src2_is_4 ? 32'h4
            : need_si20 ? {i20[19:0], 12'b0}
            : need_u12 ? i12[11:0]
            : need_ui5 ? rk
            : {{20{i12[11]}}, i12[11:0]} ;

assign br_offs = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                            {{14{i16[15]}}, i16[15:0], 2'b0} ;

assign jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

assign src_reg_is_rd = inst_beq | inst_bne | inst_st_w | inst_st_b | inst_st_h | inst_blt | inst_bge | inst_bltu | inst_bgeu
                        | inst_csrxchg | inst_csrwr | inst_csrrd ;
assign src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;

assign src2_is_imm   = inst_slli_w |
                       inst_srli_w |
                       inst_srai_w |
                       inst_addi_w |
                       inst_ld_w   |
                       inst_ld_b   |
                       inst_ld_h   |
                       inst_ld_bu   |
                       inst_ld_hu   |
                       inst_st_w   |
                       inst_st_b   |
                       inst_st_h   |
                       inst_lu12i_w|
                       inst_pcaddu12i |
                       inst_slti   |
                       inst_sltui   |
                       inst_andi   |
                       inst_ori   |
                       inst_xori   |
                       inst_jirl   |
                       inst_bl     ;

assign res_from_mem  = inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu;   //备战未来（？
assign load_op       = inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu;   //加载指令标志
assign load_signed = inst_ld_b | inst_ld_w | inst_ld_h ;
assign mem_size = inst_ld_b ? `B :
                  inst_ld_w ? `W :
                  inst_st_w ? `W :
                  inst_st_b ? `B :
                  inst_st_h ? `H :
                  inst_ld_h ? `H :
                  inst_ld_hu ? `H :
                  inst_ld_bu ? `B :
                  0;
assign dst_is_r1     = inst_bl;
assign dst_is_rj     = inst_rdcntid_w;
assign gr_we         = ~inst_st_w & ~inst_st_b & ~inst_st_h & ~inst_beq & ~inst_bne & ~inst_b & ~inst_blt & ~inst_bge & ~inst_bltu & ~inst_bgeu;
assign mem_we        = inst_st_w | inst_st_b | inst_st_h;
assign dest          = dst_is_r1 ? 5'd1 : 
                    dst_is_rj ? rj :
                    rd;


assign csr_re = inst_csrxchg | inst_csrwr | inst_csrrd | inst_syscall | inst_ertn | inst_rdcntid_w;
assign csr_we = inst_csrxchg | inst_csrwr | inst_csrrd; 
//这里给csrrd写使能是因为，csr_we在ES级用于交换csr和rd的值，读指令也需要写回rd，只是不写csr，因此下文mask置全0即可
assign csr_raddr = inst_ertn ? 12'd0 :
                   inst_rdcntid_w ? `CSR_TID : ds_inst[21:10];
assign csr_write_num = (csr_we || inst_rdcntid_w) ? csr_raddr : 12'd0;
assign csr_wmask = inst_csrxchg ? rj_value :
                   inst_csrwr ? 32'hFFFFFFFF : 32'h0;
assign csr_ertn = inst_ertn;

assign is_IPE = (csr_rdata[`CSR_CRMD_PLV]!=2'b0) && inst_ertn;

assign rf_raddr1 = rj;
assign rf_raddr2 = src_reg_is_rd ? rd :rk;

assign rf_we = !reset && ws_to_rf_bus[37];
assign rf_waddr = ws_to_rf_bus[36:32];
assign rf_wdata = ws_to_rf_bus[31:0];

regfile u_regfile(
    .clk    (clk    ),
    .raddr1 (rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we    ),
    .waddr  (rf_waddr ),
    .wdata  (rf_wdata )
);

//冲突信号
assign rj_value = (es_match_rj && !es_dest[38]) ? es_dest[31:0] :
                  (ms_match_rj && !ms_dest[38]) ? ms_dest[31:0] :
                  ws_match_rj ? ws_to_rf_bus[31:0] : rf_rdata1;
assign rkd_value = (es_match_rkd && !es_dest[38]) ? es_dest[31:0] :
                   (ms_match_rkd && !ms_dest[38]) ? ms_dest[31:0] :
                   ws_match_rkd ? ws_to_rf_bus[31:0] : rf_rdata2;

assign rj_eq_rd = (rj_value == rkd_value);
assign rj_lt_rd = ($signed(rj_value) < $signed(rkd_value));
assign rj_ltu_rd = ($unsigned(rj_value) < $unsigned(rkd_value));

assign br_stall = load_data_hazard && (inst_beq
                                || inst_bne
                                || inst_blt
                                || inst_bge
                                || inst_bltu
                                || inst_bgeu
                                || inst_jirl
                                || inst_bl
                                || inst_b);
assign br_taken = (  inst_beq  &&  rj_eq_rd
                  || inst_bne  && !rj_eq_rd
                  || inst_blt  &&  rj_lt_rd
                  || inst_bge  && !rj_lt_rd
                  || inst_bltu &&  rj_ltu_rd
                  || inst_bgeu && !rj_ltu_rd
                  || inst_jirl
                  || inst_bl
                  || inst_b
                ) && ds_to_es_valid && es_allowin && !ds_int; // 指令在被后递时才应该单次触发跳转，之前的实现似乎有点问题
assign br_target = (inst_beq || inst_bne || inst_blt || inst_bl || inst_b || inst_bge || inst_bltu || inst_bgeu) ? (ds_pc + br_offs) :
                                                   /*inst_jirl*/ (rj_value + jirl_offs);

assign br_bus = {br_stall, br_taken , br_target};

assign {
        if_ex,
        if_ecode,
        if_esubcode,
        ds_inst,
        ds_pc} = fs_to_ds_bus_r;

// ds_to_es_bus 总位宽 = 324 bit，最高位为中断标记
assign ds_to_es_bus = {
                        ds_int,         //[323]      1 bit
                        inst_rdcntvh_w, //[322]      1 bit
                        inst_rdcntvl_w, //[321]      1 bit
                        Counter,        //[320:257] 64 bit
                        inst_rdcntid_w, //[256]      1 bit
                        csr_ertn,     //[255]      1 bit
                        csr_write_num, //[254:243] 12 bit
                        csr_wmask,      //[242:211] 32 bit
                        csr_we        ,  //[210]      1 bit
                        csr_rdata     ,  //[209:178] 32 bit
                        ds_ex,        //[177]     1  bit
                        ds_excode,    //[176:171] 6  bit
                        ds_esubcode,  //[170:162] 9 bit
                        inst_mod_wu,    //[161]     1  bit
                        inst_mod_w,    //[160]     1  bit
                        inst_div_wu,   //[159]     1  bit
                        inst_div_w,   //[158]     1  bit
                        load_signed,  //[157]     1  bit
                        mem_size     ,  //[156:155] 2  bit
                        alu_op       ,  //[154:140] 15 bit
                        load_op      ,  //[139]      1 bit
                        src1_is_pc   ,  //[138]      1 bit
                        src2_is_imm  ,  //[137]      1 bit
                        src2_is_4    ,  //[136]      1 bit
                        gr_we        ,  //[135]      1 bit
                        mem_we       ,  //[134]      1 bit
                        dest         ,  //[133:129]  5 bit
                        imm          ,  //[128: 97] 32 bit
                        rj_value     ,  //[ 96: 65] 32 bit
                        rkd_value    ,  //[ 64: 33] 32 bit
                        ds_pc        ,  //[ 32:  1] 32 bit
                        res_from_mem    //[  0]      1 bit
                      };


assign ds_int = int_req && ds_to_es_valid && es_allowin;
assign int_ok = ds_int;

assign es_csr_hazard = es_to_ms_valid && es_csr_conflict_bus[12] && (es_csr_conflict_bus[11:0] == csr_write_num);
assign ms_csr_hazard = ms_to_ws_valid && ms_csr_conflict_bus[12] && (ms_csr_conflict_bus[11:0] == csr_write_num);
assign ws_csr_hazard = ws_to_rf_valid && ws_csr_conflict_bus[12] && (ws_csr_conflict_bus[11:0] == csr_write_num);
//ex8_obj中有个测试会在syscall后几条指令触发一个load_use，导致会置ds_ready_go为0，使得取指也暂停，
assign ds_ready_go = reset || (!load_data_hazard && !es_csr_hazard && !ms_csr_hazard && !ws_csr_hazard) || int_flush || has_ex || ertn_flush;
// 是否是写指令，且是否寄存器值相等
assign ds_allowin      = !ds_valid || ds_ready_go && es_allowin;
assign ds_to_es_valid  = ds_valid && ds_ready_go && !int_flush;
//这里使用es_allow_in是防止当前为syscall，上一个指令是div等需要等待的指令还在流水线中，导致取指暂停，异常指令被吞掉
// ds_ready_go 防止load_use冒险导致的取指暂停，反正是要确保异常指令能不被刷新，能传到下一级
always @(posedge clk) begin
    if (reset || ertn_flush || has_ex || int_flush) begin
        ds_valid <= 1'b0;
        fs_to_ds_bus_r <= 0;
    end
    else if (ds_allowin) begin
        ds_valid <= fs_to_ds_valid;
        if (fs_to_ds_valid) begin
            fs_to_ds_bus_r <= fs_to_ds_bus;
        end
    end
end

endmodule
