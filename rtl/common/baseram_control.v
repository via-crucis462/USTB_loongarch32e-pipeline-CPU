module BaseRAM_control(
    input  wire        clk,
    input  wire        reset,
    // from cpu
    input  wire        data_sram_en,
    input  wire [31:0] data_sram_addr,
    input  wire [31:0] data_sram_wdata,
    output reg  [31:0] data_sram_rdata,
    input  wire [ 3:0] data_sram_we,

    // to base ram
    inout  wire [31:0] base_ram_data,
    output wire [19:0] base_ram_addr,
    output wire [ 3:0] base_ram_be_n,
    output wire        base_ram_ce_n,
    output wire        base_ram_oe_n,
    output wire        base_ram_we_n
);

assign base_ram_be_n = (|data_sram_we && data_sram_en) ? ~data_sram_we : 4'hf
    ;
assign base_ram_ce_n = ~data_sram_en;
assign base_ram_we_n = ~( | data_sram_we && data_sram_en);
assign base_ram_oe_n = ~data_sram_en | (|data_sram_we);

assign base_ram_addr = data_sram_addr[21:2];

assign base_ram_data = ~base_ram_we_n ? data_sram_wdata : 32'hz;

always @(posedge clk) begin
    if (reset) begin
        data_sram_rdata <= 32'b0;
    end else if (data_sram_en && !(|data_sram_we)) begin
        data_sram_rdata <= base_ram_data;
    end
end

endmodule