//! sram to axi bridge

`define INST_ID 4'b0000
`define DATA_ID 4'b0001

module sram_axi_bridge(
    input  wire        clk,
    input  wire        resetn,

    // inst sram interface
    input  wire        inst_sram_req,
    input  wire        inst_sram_wr,
    input  wire [1:0]  inst_sram_size,
    input  wire [3:0]  inst_sram_wstrb,
    input  wire [31:0] inst_sram_addr,
    input  wire [31:0] inst_sram_wdata,
    output  wire        inst_sram_addr_ok,
    output  wire        inst_sram_data_ok,
    output  wire [31:0] inst_sram_rdata,

    // data sram interface
    input wire        data_sram_req,
    input wire        data_sram_wr,
    input wire [1:0]  data_sram_size,
    input wire [3:0]  data_sram_wstrb,
    input wire [31:0] data_sram_addr,
    input wire [31:0] data_sram_wdata,
    output  wire        data_sram_addr_ok,
    output  wire        data_sram_data_ok,
    output  wire [31:0] data_sram_rdata,

    ////////////////////////////////////////////

    // AXI read address channel
    output wire [3 :0] arid, // 读请求id，手册定义指令请求为0，数据请求为1
    output wire [31:0] araddr, // 读请求地址
    output wire [7 :0] arlen, // 读请求传输长度，固定为0
    output wire [2 :0] arsize, // 读请求传输大小，即每次请求字节数
    output wire [1 :0] arburst, // 传输类型，固定0b01
    output wire [1 :0] arlock, // 控制信号，原子锁，固定0
    output wire [3 :0] arcache, // 缓存属性，固定0
    output wire [2 :0] arprot,  // 保护属性，固定0
    output wire        arvalid, // 读请求有效信号
    input  wire        arready, // 从方是否准备好接收读请求

    // AXI read data channel
    input  wire [3 :0] rid, // 对应的请求id
    input  wire [31:0] rdata, // 读请求返回的数据
    input  wire [1 :0] rresp, // 可忽略
    input  wire        rlast, // 可忽略
    input  wire        rvalid, // 读出数据有效
    output wire        rready, // 读数据已经被接收

    // AXI write address channel
    output wire [3 :0] awid, // 手册约定固定1
    output wire [31:0] awaddr,
    output wire [7 :0] awlen, // 0
    output wire [2 :0] awsize,
    output wire [1 :0] awburst, // 0b01
    output wire [1 :0] awlock, // 0
    output wire [3 :0] awcache, // 0
    output wire [2 :0] awprot, // 0
    output wire        awvalid,
    input  wire        awready,

    // AXI write data channel
    output wire [3 :0] wid, // 手册约定固定1
    output wire [31:0] wdata,
    output wire [3 :0] wstrb,
    output wire        wlast, // 1
    output wire        wvalid, // 写请求有效
    input  wire        wready,

    // AXI write response channel
    input  wire [3 :0] bid, // 忽略
    input  wire [1 :0] bresp, // 忽略
    input  wire        bvalid, // 写成功
    output wire        bready // 写响应已经被接收
);

    wire reset = !resetn;

    // 请求类型
    wire data_read_req = data_sram_req && !data_sram_wr;
    wire inst_read_req = !data_read_req && inst_sram_req;
    wire read_req = inst_read_req || data_read_req;
    wire data_write_req = data_sram_req && data_sram_wr;

    // 读响应的类型
    wire read_res_is_data = rid == `DATA_ID;



    // 复制自手册
    //
    // 1）除了可以置为常值的信号外，所有 AXI 主方的输出直接来自触发器 Q 端。
    // 2）为读数据预留缓存，从 rdata 端口上收到的数据先保存到这个预留缓存中。
    // 3）AXI 上最多支持几个“已完成读请求握手但数据尚未返回的读事务”，就预留
    // 同样数目的 rdata 缓存。
    // 第 8 章 AXI 总线接口设计 215
    // 4）取指对应的 arid 恒为 0，load 对应的 arid 恒为 1。
    // 5）控制 AXI 读写的状态机分为 4 个独立的状态机：读请求通道一个，读响应通
    // 道一个，写请求和写数据共用一个，写响应一个。
    // 6）类 SRAM 从方接的输入信号不用锁存后再使用。
    // 7）数据端发来的类 SRAM 总线的读请求优先级固定高于取指端发来的类 SRAM
    // 总线的读请求。
    // 8）类 SRAM 从方输出的 addr_ok 和 data_ok 信号若是来自组合逻辑，那么这个
    // 组合逻辑中不要引入 AXI 接口上的 valid 和 ready 信号



    // 读请求
    reg axi_pending_read_req; // 有被桥接收但还未发出到AXI的读请求
    reg [3:0] axi_pending_read_arid;
    reg [31:0] axi_pending_addr;
    reg [1:0] axi_pending_size;

    wire data_sram_read_addr_ok;

    always @(posedge clk) begin
        if (reset) begin
            axi_pending_addr <= 32'b0;
            axi_pending_read_req <= 1'b0;
            axi_pending_read_arid <= 4'b0;
            axi_pending_size <= 2'b0;
        end else if (read_req && !axi_pending_read_req) begin
            // 无未决请求时接收新的请求
            axi_pending_read_req <= 1'b1;
            axi_pending_read_arid <= data_read_req ? `DATA_ID : `INST_ID;
            axi_pending_addr <= data_read_req ? data_sram_addr : inst_sram_addr;
            axi_pending_size <= data_read_req ? data_sram_size : inst_sram_size;
        end else if (arvalid && arready) begin
            // axi允许并发，所以axi握手成功后就可以开始收新请求并发送
            // 不需要等到上次请求得到响应
            axi_pending_read_req <= 1'b0;
        end
    end

    // axi 侧
    assign arvalid = axi_pending_read_req;
    assign arid = axi_pending_read_arid;
    assign araddr = axi_pending_addr;
    assign arsize = {1'b0, axi_pending_size};
    // 固定值
    assign arlen = 8'd0;
    assign arburst = 2'b01;
    assign arlock = 2'b00;
    assign arcache = 4'b0000;
    assign arprot = 3'b000;

    // sram 侧
    wire sram_ready_read = !axi_pending_read_req;
    assign inst_sram_addr_ok = inst_read_req && sram_ready_read;
    assign data_sram_read_addr_ok = data_read_req && sram_ready_read;


    // 读响应
    reg axi_pending_read_res; // 有被桥接收但还未发出到sram的读响应
    reg [31:0] axi_pending_rdata;
    reg axi_pending_read_res_is_data;
    wire axi_pending_read_res_is_inst = !axi_pending_read_res_is_data;

    wire data_sram_read_data_ok;

    always @(posedge clk) begin
        if (reset) begin
            axi_pending_read_res <= 1'b0;
            axi_pending_rdata <= 32'b0;
            axi_pending_read_res_is_data <= 1'b0;
        end else if (rvalid && !axi_pending_read_res) begin
            // 与请求逻辑完全一致
            axi_pending_read_res <= 1'b1;
            axi_pending_rdata <= rdata;
            axi_pending_read_res_is_data <= read_res_is_data;
        end else if (inst_sram_data_ok || data_sram_read_data_ok) begin
            // 由 cpu sram 侧保证 ok 后第一个时钟沿接收数据，从此时又可以接收新的响应
            axi_pending_read_res <= 1'b0;
        end
    end

    // axi 侧
    assign rready = !reset && !axi_pending_read_res;

    // sram 侧
    assign inst_sram_data_ok = axi_pending_read_res && axi_pending_read_res_is_inst;
    assign data_sram_read_data_ok = axi_pending_read_res && axi_pending_read_res_is_data;
    assign inst_sram_rdata = axi_pending_rdata;
    assign data_sram_rdata = axi_pending_rdata;



    // 写请求(和数据)
    reg axi_pending_write_req;
    reg [31:0] axi_pending_write_addr;
    reg [1:0] axi_pending_write_size;
    reg [3:0] axi_pending_write_wstrb;
    reg [31:0] axi_pending_write_wdata;

    wire data_sram_write_addr_ok;

    // 先握手成功的请求
    reg axi_pending_write_addr_req_ok;
    reg axi_pending_write_data_req_ok;
    // 当拍握手成功的请求
    wire axi_write_addr_req_ok = awvalid && awready;
    wire axi_write_data_req_ok = wvalid && wready;
    // 地址和数据请求都握手成功
    // 即存在一个已经存储握手状态的请求和一个本拍握手成功的请求
    // 或同时握手
    wire axi_write_req_ok = (axi_write_addr_req_ok && axi_write_data_req_ok)
                        || (axi_pending_write_addr_req_ok && axi_write_data_req_ok)
                        || (axi_pending_write_data_req_ok && axi_write_addr_req_ok);

    always @(posedge clk) begin
        if (reset) begin
            axi_pending_write_req <= 1'b0;
            axi_pending_write_addr <= 32'b0;
            axi_pending_write_size <= 2'b0;
            axi_pending_write_wstrb <= 4'b0;
            axi_pending_write_wdata <= 32'b0;
            axi_pending_write_addr_req_ok <= 1'b0;
            axi_pending_write_data_req_ok <= 1'b0;
        end else if (data_write_req && !axi_pending_write_req) begin
            // 无未决请求时接收新的请求
            axi_pending_write_req <= 1'b1;
            axi_pending_write_addr <= data_sram_addr;
            axi_pending_write_size <= data_sram_size;
            axi_pending_write_wstrb <= data_sram_wstrb;
            axi_pending_write_wdata <= data_sram_wdata;
        end else if (axi_write_req_ok) begin
            axi_pending_write_req <= 1'b0;
            axi_pending_write_addr_req_ok <= 1'b0;
            axi_pending_write_data_req_ok <= 1'b0;
        end else begin
            // 两套握手可能不同时完成，存储先完成的
            if (axi_write_addr_req_ok) begin
                axi_pending_write_addr_req_ok <= 1'b1;
            end
            if (axi_write_data_req_ok) begin
                axi_pending_write_data_req_ok <= 1'b1;
            end
        end
    end

    // axi 侧
    assign awvalid = axi_pending_write_req && !axi_pending_write_addr_req_ok;
    assign wvalid = axi_pending_write_req && !axi_pending_write_data_req_ok;
    assign wdata = axi_pending_write_wdata;
    assign awaddr = axi_pending_write_addr;
    assign wstrb = axi_pending_write_wstrb;
    assign awsize = {1'b0, axi_pending_write_size};
    // 固定值
    assign wid     = 4'b0001;
    assign awid    = 4'b0001;
    assign awlen   = 8'd0;
    assign awburst = 2'b01;
    assign awlock  = 2'b00;
    assign awcache = 4'b0000;
    assign awprot  = 3'b000;
    assign wlast   = 1'b1;

    // sram 侧
    wire sram_ready_write = !axi_pending_write_req;
    assign data_sram_write_addr_ok = data_write_req && sram_ready_write;


    // 写响应
    reg axi_pending_write_res; // 有被桥接收但还未发出到sram的写响应

    wire data_sram_write_data_ok;

    always @(posedge clk) begin
        if (reset) begin
            axi_pending_write_res <= 1'b0;
        end else if (bvalid && !axi_pending_write_res) begin
            axi_pending_write_res <= 1'b1;
        end else if (axi_pending_write_res) begin
            // ok 在产生后第一个时钟升沿被 cpu 接收
            axi_pending_write_res <= 1'b0;
        end
    end

    // axi 侧
    assign bready = !reset && !axi_pending_write_res;

    // sram 侧
    assign data_sram_write_data_ok = axi_pending_write_res;



    assign data_sram_addr_ok = data_sram_read_addr_ok || data_sram_write_addr_ok;
    assign data_sram_data_ok = data_sram_read_data_ok || data_sram_write_data_ok;

endmodule
