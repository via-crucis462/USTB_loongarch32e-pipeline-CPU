//! AXI CPU wrapper: CPU core + SRAM-to-AXI bridge

module mycpu_top(
    input  wire        aclk,
    input  wire        aresetn,   // low active

    // AXI read address channel (master -> slave)
    output wire [3 :0] arid,
    output wire [31:0] araddr,
    output wire [7 :0] arlen,
    output wire [2 :0] arsize,
    output wire [1 :0] arburst,
    output wire [1 :0] arlock,
    output wire [3 :0] arcache,
    output wire [2 :0] arprot,
    output wire        arvalid,
    input  wire        arready,

    // AXI read data channel (slave -> master)
    input  wire [3 :0] rid,
    input  wire [31:0] rdata,
    input  wire [1 :0] rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output wire        rready,

    // AXI write address channel (master -> slave)
    output wire [3 :0] awid,
    output wire [31:0] awaddr,
    output wire [7 :0] awlen,
    output wire [2 :0] awsize,
    output wire [1 :0] awburst,
    output wire [1 :0] awlock,
    output wire [3 :0] awcache,
    output wire [2 :0] awprot,
    output wire        awvalid,
    input  wire        awready,

    // AXI write data channel (master -> slave)
    output wire [3 :0] wid,
    output wire [31:0] wdata,
    output wire [3 :0] wstrb,
    output wire        wlast,
    output wire        wvalid,
    input  wire        wready,

    // AXI write response channel (slave -> master)
    input  wire [3 :0] bid,
    input  wire [1 :0] bresp,
    input  wire        bvalid,
    output wire        bready,

    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [3 :0] debug_wb_rf_we,
    output wire [4 :0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

    // insr
    wire        cpu_inst_req;
    wire        cpu_inst_wr;
    wire [1 :0] cpu_inst_size;
    wire [3 :0] cpu_inst_wstrb;
    wire [31:0] cpu_inst_addr;
    wire [31:0] cpu_inst_wdata;
    wire        cpu_inst_addr_ok;
    wire        cpu_inst_data_ok;
    wire [31:0] cpu_inst_rdata;

    // data
    wire        cpu_data_req;
    wire        cpu_data_wr;
    wire [1 :0] cpu_data_size;
    wire [3 :0] cpu_data_wstrb;
    wire [31:0] cpu_data_addr;
    wire [31:0] cpu_data_wdata;
    wire        cpu_data_addr_ok;
    wire        cpu_data_data_ok;
    wire [31:0] cpu_data_rdata;

    mycpu_sram u_cpu(
        .clk               (aclk             ),
        .resetn            (aresetn          ),

        .inst_sram_req     (cpu_inst_req     ),
        .inst_sram_wr      (cpu_inst_wr      ),
        .inst_sram_size    (cpu_inst_size    ),
        .inst_sram_wstrb   (cpu_inst_wstrb   ),
        .inst_sram_addr    (cpu_inst_addr    ),
        .inst_sram_wdata   (cpu_inst_wdata   ),
        .inst_sram_addr_ok (cpu_inst_addr_ok ),
        .inst_sram_data_ok (cpu_inst_data_ok ),
        .inst_sram_rdata   (cpu_inst_rdata   ),

        .data_sram_req     (cpu_data_req     ),
        .data_sram_wr      (cpu_data_wr      ),
        .data_sram_size    (cpu_data_size    ),
        .data_sram_wstrb   (cpu_data_wstrb   ),
        .data_sram_addr    (cpu_data_addr    ),
        .data_sram_wdata   (cpu_data_wdata   ),
        .data_sram_addr_ok (cpu_data_addr_ok ),
        .data_sram_data_ok (cpu_data_data_ok ),
        .data_sram_rdata   (cpu_data_rdata   ),

        .debug_wb_pc       (debug_wb_pc      ),
        .debug_wb_rf_we    (debug_wb_rf_we   ),
        .debug_wb_rf_wnum  (debug_wb_rf_wnum ),
        .debug_wb_rf_wdata (debug_wb_rf_wdata)
);

    sram_axi_bridge u_bridge(
        .clk               (aclk             ),
        .resetn            (aresetn          ),

        .inst_sram_req     (cpu_inst_req     ),
        .inst_sram_wr      (cpu_inst_wr      ),
        .inst_sram_size    (cpu_inst_size    ),
        .inst_sram_wstrb   (cpu_inst_wstrb   ),
        .inst_sram_addr    (cpu_inst_addr    ),
        .inst_sram_wdata   (cpu_inst_wdata   ),
        .inst_sram_addr_ok (cpu_inst_addr_ok ),
        .inst_sram_data_ok (cpu_inst_data_ok ),
        .inst_sram_rdata   (cpu_inst_rdata   ),

        .data_sram_req     (cpu_data_req     ),
        .data_sram_wr      (cpu_data_wr      ),
        .data_sram_size    (cpu_data_size    ),
        .data_sram_wstrb   (cpu_data_wstrb   ),
        .data_sram_addr    (cpu_data_addr    ),
        .data_sram_wdata   (cpu_data_wdata   ),
        .data_sram_addr_ok (cpu_data_addr_ok ),
        .data_sram_data_ok (cpu_data_data_ok ),
        .data_sram_rdata   (cpu_data_rdata   ),

        .arid              (arid             ),
        .araddr            (araddr           ),
        .arlen             (arlen            ),
        .arsize            (arsize           ),
        .arburst           (arburst          ),
        .arlock            (arlock           ),
        .arcache           (arcache          ),
        .arprot            (arprot           ),
        .arvalid           (arvalid          ),
        .arready           (arready          ),

        .rid               (rid              ),
        .rdata             (rdata            ),
        .rresp             (rresp            ),
        .rlast             (rlast            ),
        .rvalid            (rvalid           ),
        .rready            (rready           ),

        .awid              (awid             ),
        .awaddr            (awaddr           ),
        .awlen             (awlen            ),
        .awsize            (awsize           ),
        .awburst           (awburst          ),
        .awlock            (awlock           ),
        .awcache           (awcache          ),
        .awprot            (awprot           ),
        .awvalid           (awvalid          ),
        .awready           (awready          ),

        .wid               (wid              ),
        .wdata             (wdata            ),
        .wstrb             (wstrb            ),
        .wlast             (wlast            ),
        .wvalid            (wvalid           ),
        .wready            (wready           ),

        .bid               (bid              ),
        .bresp             (bresp            ),
        .bvalid            (bvalid           ),
        .bready            (bready           )
    );
endmodule
