# lab2 手册代码
## module1
module BaseRAM_control(
    input  wire        clk,
    input  wire        reset,
    // from cpu
    input  wire        inst_sram_en,
    input  wire [31:0] inst_sram_addr,
    input  wire [31:0] inst_sram_wdata,
    output reg  [31:0] inst_sram_rdata,
    input  wire [ 3:0] inst_sram_we,

    // to base ram
    inout  wire [31:0] base_ram_data,
    output wire [19:0] base_ram_addr,
    output wire [ 3:0] base_ram_be_n,
    output wire        base_ram_ce_n,
    output wire        base_ram_oe_n,
    output wire        base_ram_we_n
);

assign base_ram_be_n = ( | inst_sram_we && inst_sram_en) ? ~inst_sram_we : 4'h0
    ;
assign base_ram_ce_n = ~inst_sram_en;
assign base_ram_we_n = ~( | inst_sram_we && inst_sram_en);
assign base_ram_oe_n = ( | inst_sram_we && inst_sram_en);

assign base_ram_addr = inst_sram_addr[21:2];

assign base_ram_data = ~base_ram_we_n ? inst_sram_wdata : 32'hz;

always @(posedge clk) begin
    if (reset) begin
        inst_sram_rdata <= 32'hz;
    end else if (~base_ram_oe_n) begin
        inst_sram_rdata <= base_ram_data;
    end
end

endmodule
```